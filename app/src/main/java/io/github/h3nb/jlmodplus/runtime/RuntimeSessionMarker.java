/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package io.github.h3nb.jlmodplus.runtime;

import android.app.ActivityManager;
import android.content.Context;
import android.util.AtomicFile;

import androidx.annotation.Nullable;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Cross-process marker describing the isolated runtime's live tab count, so the Library process
 * can offer a way back to a game it cannot inspect directly.
 *
 * <p>A hard process kill leaves the marker behind, so {@link #read} verifies that the runtime
 * process is still running before trusting it. Writes happen only on tab changes and Activity
 * lifecycle callbacks, never per frame.</p>
 */
public final class RuntimeSessionMarker {
    private static final String FILE_NAME = "runtime_sessions.json";
    private static final Pattern TABS_PATTERN = Pattern.compile("\"tabs\"\\s*:\\s*(-?\\d+)");
    private static final Pattern UPDATED_PATTERN = Pattern.compile("\"updated\"\\s*:\\s*(\\d+)");
    private static final Pattern APP_PATH_PATTERN =
            Pattern.compile("\"appPath\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
    private static final Pattern APP_NAME_PATTERN =
            Pattern.compile("\"appName\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");

    private RuntimeSessionMarker() {
    }

    /** Records the live tab count. A non-positive count clears the marker instead. */
    public static void write(@Nullable Context context, int tabs, @Nullable String appPath,
            @Nullable String appName) {
        if (context == null) {
            return;
        }
        if (tabs <= 0) {
            clear(context);
            return;
        }
        // A write can be cut short by a hard kill; read() checks the runtime process before
        // trusting what survived.
        AtomicFile atomic = new AtomicFile(stateFile(context));
        FileOutputStream output = null;
        try {
            byte[] json = encode(tabs, appPath, appName, System.currentTimeMillis())
                    .getBytes(StandardCharsets.UTF_8);
            output = atomic.startWrite();
            output.write(json);
            output.flush();
            atomic.finishWrite(output);
        } catch (IOException | RuntimeException ignored) {
            if (output != null) {
                atomic.failWrite(output);
            }
        }
    }

    /** Returns the last published marker, or null when absent, unreadable, or malformed. */
    @Nullable
    public static Session read(@Nullable Context context) {
        if (context == null) {
            return null;
        }
        ByteArrayOutputStream buffer = new ByteArrayOutputStream(256);
        try (FileInputStream input = new AtomicFile(stateFile(context)).openRead()) {
            byte[] chunk = new byte[512];
            int length;
            while ((length = input.read(chunk)) > 0) {
                buffer.write(chunk, 0, length);
            }
        } catch (IOException | RuntimeException ignored) {
            return null;
        }
        Session session = decode(new String(buffer.toByteArray(), StandardCharsets.UTF_8));
        if (session != null && !runtimeProcessRunning(context)) {
            // A hard kill leaves the marker behind; drop it instead of offering a dead session.
            clear(context);
            return null;
        }
        return session;
    }

    private static boolean runtimeProcessRunning(Context context) {
        ActivityManager manager =
                (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        List<ActivityManager.RunningAppProcessInfo> processes =
                manager == null ? null : manager.getRunningAppProcesses();
        if (processes == null || processes.isEmpty()) {
            // Cannot inspect processes here; keep the marker rather than hide a live game.
            return true;
        }
        String runtimeProcess = context.getPackageName() + ":midlet";
        for (ActivityManager.RunningAppProcessInfo process : processes) {
            if (runtimeProcess.equals(process.processName)) {
                return true;
            }
        }
        return false;
    }

    public static void clear(@Nullable Context context) {
        if (context == null) {
            return;
        }
        try {
            new AtomicFile(stateFile(context)).delete();
        } catch (RuntimeException ignored) {
            // Best effort: a stale marker is tolerated by readers.
        }
    }

    private static File stateFile(Context context) {
        return new File(context.getApplicationContext().getFilesDir(), FILE_NAME);
    }

    static String encode(int tabs, @Nullable String appPath, @Nullable String appName,
            long updated) {
        StringBuilder json = new StringBuilder(128);
        json.append("{\"tabs\":").append(tabs).append(",\"appPath\":");
        appendString(json, appPath);
        json.append(",\"appName\":");
        appendString(json, appName);
        json.append(",\"updated\":").append(updated).append('}');
        return json.toString();
    }

    @Nullable
    static Session decode(@Nullable String json) {
        if (json == null) {
            return null;
        }
        Matcher tabsMatcher = TABS_PATTERN.matcher(json);
        if (!tabsMatcher.find()) {
            return null;
        }
        int tabs;
        try {
            tabs = Integer.parseInt(tabsMatcher.group(1));
        } catch (NumberFormatException ignored) {
            return null;
        }
        if (tabs <= 0) {
            return null;
        }
        Matcher updatedMatcher = UPDATED_PATTERN.matcher(json);
        long updated = 0L;
        if (updatedMatcher.find()) {
            try {
                updated = Long.parseLong(updatedMatcher.group(1));
            } catch (NumberFormatException ignored) {
                updated = 0L;
            }
        }
        return new Session(tabs, stringValue(APP_PATH_PATTERN, json),
                stringValue(APP_NAME_PATTERN, json), updated);
    }

    private static void appendString(StringBuilder json, @Nullable String value) {
        if (value == null) {
            json.append("null");
            return;
        }
        json.append('"');
        for (int i = 0; i < value.length(); i++) {
            char character = value.charAt(i);
            switch (character) {
                case '"' -> json.append("\\\"");
                case '\\' -> json.append("\\\\");
                case '\n' -> json.append("\\n");
                case '\r' -> json.append("\\r");
                case '\t' -> json.append("\\t");
                default -> {
                    if (character < 0x20) {
                        json.append(String.format("\\u%04x", (int) character));
                    } else {
                        json.append(character);
                    }
                }
            }
        }
        json.append('"');
    }

    @Nullable
    private static String stringValue(Pattern pattern, String json) {
        Matcher matcher = pattern.matcher(json);
        return matcher.find() ? unescape(matcher.group(1)) : null;
    }

    private static String unescape(String value) {
        StringBuilder out = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i++) {
            char character = value.charAt(i);
            if (character != '\\' || i + 1 >= value.length()) {
                out.append(character);
                continue;
            }
            char escape = value.charAt(++i);
            switch (escape) {
                case 'n' -> out.append('\n');
                case 'r' -> out.append('\r');
                case 't' -> out.append('\t');
                case 'b' -> out.append('\b');
                case 'f' -> out.append('\f');
                case 'u' -> {
                    if (i + 4 < value.length()) {
                        try {
                            out.append((char) Integer.parseInt(value.substring(i + 1, i + 5), 16));
                            i += 4;
                        } catch (NumberFormatException ignored) {
                            out.append('u');
                        }
                    } else {
                        out.append('u');
                    }
                }
                default -> out.append(escape);
            }
        }
        return out.toString();
    }

    /** Immutable parsed marker state. */
    public static final class Session {
        private final int tabs;
        private final String appPath;
        private final String appName;
        private final long updated;

        Session(int tabs, @Nullable String appPath, @Nullable String appName, long updated) {
            this.tabs = tabs;
            this.appPath = appPath;
            this.appName = appName;
            this.updated = updated;
        }

        public int getTabs() {
            return tabs;
        }

        @Nullable
        public String getAppPath() {
            return appPath;
        }

        @Nullable
        public String getAppName() {
            return appName;
        }

        /** Epoch milliseconds of the last runtime lifecycle write. */
        public long getUpdated() {
            return updated;
        }
    }
}
