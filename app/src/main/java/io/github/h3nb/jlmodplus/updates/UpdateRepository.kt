package io.github.h3nb.jlmodplus.updates

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.preference.PreferenceManager
import io.github.h3nb.jlmodplus.BuildConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

internal sealed interface UpdateStatus {
    data object NotChecked : UpdateStatus
    data object Checking : UpdateStatus
    data object Current : UpdateStatus
    data object NoRelease : UpdateStatus
    data class Available(val candidate: UpdateCandidate) : UpdateStatus
    data object NotInstallable : UpdateStatus
    data object Failed : UpdateStatus
}

internal class UpdateRepository private constructor(context: Context) {
    private val preferences: SharedPreferences =
        PreferenceManager.getDefaultSharedPreferences(context.applicationContext)
    private val mutex = Mutex()

    var automaticChecks by mutableStateOf(preferences.getBoolean(KEY_ENABLED, true))
        private set

    // The last valid result survives a failed refresh; refresh activity is independent.
    var status by mutableStateOf<UpdateStatus>(restoredStatus())
        private set
    var checking by mutableStateOf(false)
        private set
    var refreshFailed by mutableStateOf(false)
        private set
    var lastChecked by mutableStateOf(preferences.getLong(KEY_SUCCESS, 0L))
        private set

    init {
        val identity = BuildConfig.VERSION_NAME + "#" + BuildConfig.VERSION_CODE
        val legacyChannelKey = "jlmod_updates_channel"
        if (preferences.getString(KEY_INSTALLED, null) != identity ||
            preferences.contains(legacyChannelKey)) {
            preferences.edit {
                putString(KEY_INSTALLED, identity)
                remove(legacyChannelKey)
                remove(KEY_SUCCESS).remove(KEY_ATTEMPT).remove(KEY_RESULT)
                remove(KEY_VERSION).remove(KEY_CODE).remove(KEY_URL).remove(KEY_DOWNLOAD_URL)
                remove(KEY_HANDLED).remove(KEY_HANDLED + "_Stable").remove(KEY_HANDLED + "_Preview")
            }
            lastChecked = 0L
            status = UpdateStatus.NotChecked
        }
    }

    fun configureAutomaticChecks(enabled: Boolean) {
        automaticChecks = enabled
        preferences.edit { putBoolean(KEY_ENABLED, enabled) }
    }

    fun candidateKey(candidate: UpdateCandidate): String =
        candidate.versionName + "|" + candidate.versionCode

    fun isHandled(candidate: UpdateCandidate): Boolean =
        preferences.getString(KEY_HANDLED, null) == candidateKey(candidate)

    fun handle(candidate: UpdateCandidate) {
        preferences.edit { putString(KEY_HANDLED, candidateKey(candidate)) }
    }

    /** Polling is active only while the Library is resumed. No background worker is needed. */
    fun nextAutomaticDelayMillis(): Long {
        val now = System.currentTimeMillis()
        fun remaining(last: Long, interval: Long): Long =
            if (last <= 0L || now < last) 0L else (interval - (now - last)).coerceAtLeast(0L)
        return maxOf(
            remaining(lastChecked, CHECK_INTERVAL_MS),
            remaining(preferences.getLong(KEY_ATTEMPT, 0L), RETRY_DELAY_MS),
            MIN_POLL_DELAY_MS,
        )
    }

    suspend fun check(manual: Boolean) = mutex.withLock {
        if (!manual && !automaticChecks) return@withLock
        val now = System.currentTimeMillis()
        if (!manual && now - lastChecked in 0 until CHECK_INTERVAL_MS) return@withLock
        val attempted = preferences.getLong(KEY_ATTEMPT, 0L)
        if (!manual && now - attempted in 0 until RETRY_DELAY_MS) return@withLock

        preferences.edit { putLong(KEY_ATTEMPT, now) }
        val previous = status
        checking = true
        refreshFailed = false
        if (previous == UpdateStatus.NotChecked || previous == UpdateStatus.Failed) {
            status = UpdateStatus.Checking
        }
        try {
            val result = withContext(Dispatchers.IO) { fetchLatest() }
            lastChecked = System.currentTimeMillis()
            status = result
            val editor = preferences.edit()
                .putLong(KEY_SUCCESS, lastChecked)
                .putString(KEY_RESULT, when (result) {
                    is UpdateStatus.Available -> "available"
                    UpdateStatus.Current -> "current"
                    UpdateStatus.NotInstallable -> "incompatible"
                    else -> "none"
                })
            if (result is UpdateStatus.Available) {
                editor.putString(KEY_VERSION, result.candidate.versionName)
                    .putInt(KEY_CODE, result.candidate.versionCode)
                    .putString(KEY_URL, result.candidate.releaseUrl)
                    .putString(KEY_DOWNLOAD_URL, result.candidate.downloadUrl)
            } else {
                editor.remove(KEY_VERSION).remove(KEY_CODE).remove(KEY_URL)
                    .remove(KEY_DOWNLOAD_URL)
            }
            editor.apply()
        } catch (cancelled: CancellationException) {
            status = previous
            // Lifecycle cancellation is not a network failure; allow a prompt retry on resume.
            if (preferences.getLong(KEY_ATTEMPT, 0L) == now) {
                preferences.edit { remove(KEY_ATTEMPT) }
            }
            throw cancelled
        } catch (_: IOException) {
            status = if (previous == UpdateStatus.NotChecked || previous == UpdateStatus.Failed) {
                UpdateStatus.Failed
            } else previous
            refreshFailed = true
        } catch (_: JSONException) {
            status = if (previous == UpdateStatus.NotChecked || previous == UpdateStatus.Failed) {
                UpdateStatus.Failed
            } else previous
            refreshFailed = true
        } finally {
            checking = false
        }
    }

    private fun restoredStatus(): UpdateStatus {
        return when (preferences.getString(KEY_RESULT, null)) {
            "available" -> {
                val version = preferences.getString(KEY_VERSION, null)
                val url = preferences.getString(KEY_URL, null)
                val download = preferences.getString(KEY_DOWNLOAD_URL, null)
                val code = preferences.getInt(KEY_CODE, 0)
                val candidate = if (version != null && url != null && code > 0) {
                    UpdateCandidate(version, code, url, download)
                } else null
                if (candidate != null && eligibleUpdate(
                        BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, candidate)) {
                    UpdateStatus.Available(candidate)
                } else UpdateStatus.NotChecked
            }
            "current" -> UpdateStatus.Current
            "none" -> UpdateStatus.NoRelease
            "incompatible" -> UpdateStatus.NotInstallable
            else -> UpdateStatus.NotChecked
        }
    }

    /**
     * Reads this fork's GitHub releases directly, so no hosted manifest is needed.
     * GitHub releases carry no versionCode; one is derived from the version core
     * (major * 1_000_000 + minor * 1_000 + patch) purely for update comparison.
     */
    private fun fetchLatest(): UpdateStatus {
        val connection = URL(RELEASES_API_URL).openConnection() as HttpURLConnection
        connection.connectTimeout = 5000
        connection.readTimeout = 5000
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        connection.setRequestProperty("User-Agent", "JL-Mod-Plus-Updater")
        val payload = try {
            if (connection.responseCode != 200) {
                throw IOException("Update releases HTTP " + connection.responseCode)
            }
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }

        val installed = ReleaseVersion.parse(BuildConfig.VERSION_NAME)
            ?: return UpdateStatus.NoRelease
        val entries = JSONArray(payload)
        var best: Pair<ReleaseVersion, UpdateCandidate>? = null
        var hasNewerIncompatible = false
        var hasPublished = false
        for (i in 0 until entries.length()) {
            val release = entries.optJSONObject(i) ?: continue
            if (release.optBoolean("draft")) continue
            val version = release.optString("tag_name").removePrefix("v")
            val parsed = ReleaseVersion.parse(version) ?: continue
            hasPublished = true
            if (parsed <= installed) continue
            val code = versionCodeFor(version)
            val download = selectApkAsset(release.optJSONArray("assets"))
            if (code <= BuildConfig.VERSION_CODE || download == null) {
                hasNewerIncompatible = true
                continue
            }
            val candidate = UpdateCandidate(
                versionName = version,
                versionCode = code,
                releaseUrl = release.optString("html_url", RELEASES_PAGE_URL),
                downloadUrl = download,
            )
            if (eligibleUpdate(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, candidate) &&
                (best == null || parsed > best.first)) {
                best = parsed to candidate
            }
        }
        return when {
            best != null -> UpdateStatus.Available(best.second)
            hasNewerIncompatible -> UpdateStatus.NotInstallable
            hasPublished -> UpdateStatus.Current
            else -> UpdateStatus.NoRelease
        }
    }

    private fun versionCodeFor(version: String): Int {
        val match = VERSION_CORE.matchEntire(version) ?: return 0
        val (major, minor, patch) = match.destructured
        return major.toInt() * 1_000_000 + minor.toInt() * 1_000 + patch.toInt()
    }

    private fun selectApkAsset(assets: JSONArray?): String? {
        if (assets == null) return null
        val urls = mutableListOf<Pair<String, String>>()
        for (index in 0 until assets.length()) {
            val asset = assets.optJSONObject(index) ?: continue
            val name = asset.optString("name")
            val url = asset.optString("browser_download_url")
            if (!name.endsWith(".apk") || !url.startsWith(ASSET_URL_PREFIX)) continue
            urls.add(name to url)
        }
        if (urls.isEmpty()) return null
        for (abi in Build.SUPPORTED_ABIS) {
            urls.firstOrNull { (name, _) -> abi in name }?.let { return it.second }
        }
        return urls.firstOrNull { (name, _) -> "universal" in name.lowercase() }?.second
            ?: urls.first().second
    }

    companion object {
        private const val RELEASES_API_URL =
            "https://api.github.com/repos/0xFenix/JL-Mod-Plus/releases"
        private const val RELEASES_PAGE_URL = "https://github.com/0xFenix/JL-Mod-Plus/releases"
        private const val ASSET_URL_PREFIX =
            "https://github.com/0xFenix/JL-Mod-Plus/releases/download/"
        private val VERSION_CORE = Regex("""(\d+)\.(\d+)\.(\d+).*""")
        private const val KEY_INSTALLED = "jlmod_updates_installed_identity"
        private const val KEY_ENABLED = "jlmod_updates_enabled"
        private const val KEY_ATTEMPT = "jlmod_updates_last_attempt"
        private const val KEY_SUCCESS = "jlmod_updates_last_success"
        private const val KEY_RESULT = "jlmod_updates_result"
        private const val KEY_VERSION = "jlmod_updates_version"
        private const val KEY_CODE = "jlmod_updates_code"
        private const val KEY_URL = "jlmod_updates_url"
        private const val KEY_DOWNLOAD_URL = "jlmod_updates_download_url"
        private const val KEY_HANDLED = "jlmod_updates_handled_version"
        private const val CHECK_INTERVAL_MS = 60 * 60 * 1000L
        private const val RETRY_DELAY_MS = 30 * 60 * 1000L
        private const val MIN_POLL_DELAY_MS = 60_000L

        @Volatile private var instance: UpdateRepository? = null
        fun get(context: Context): UpdateRepository =
            instance ?: synchronized(this) {
                instance ?: UpdateRepository(context).also { instance = it }
            }
    }
}
