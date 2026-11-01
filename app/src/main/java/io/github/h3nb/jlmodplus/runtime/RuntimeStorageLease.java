/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
package io.github.h3nb.jlmodplus.runtime;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.channels.OverlappingFileLockException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/** A process-lifetime reservation for one installed MIDlet's private storage namespace. */
public final class RuntimeStorageLease implements AutoCloseable {
    private static final char[] HEX = "0123456789abcdef".toCharArray();
    private final FileChannel channel;
    private final FileLock lock;
    /**
     * In-process shares for multi-MIDlet tabs of the same suite. The OS file lock cannot be
     * acquired twice in one process, so tabs running the same installed suite share one
     * underlying lease with a reference count. The last close releases the real lease.
     */
    private static final java.util.Map<String, SharedLease> SHARED = new java.util.HashMap<>();

    private static final class SharedLease {
        final RuntimeStorageLease lease;
        int refs;

        SharedLease(RuntimeStorageLease lease) {
            this.lease = lease;
            this.refs = 1;
        }
    }

    private final String sharedKey;

    private RuntimeStorageLease(FileChannel channel, FileLock lock) {
        this(channel, lock, null);
    }

    private RuntimeStorageLease(FileChannel channel, FileLock lock, String sharedKey) {
        this.channel = channel;
        this.lock = lock;
        this.sharedKey = sharedKey;
    }

    /** Returns null when another runtime already owns this path. */
    public static RuntimeStorageLease acquire(File filesDir, File installedDir) throws IOException {
        FileChannel channel = openChannel(filesDir, installedDir);
        try {
            FileLock lock = channel.tryLock();
            if (lock == null) {
                channel.close();
                return null;
            }
            return new RuntimeStorageLease(channel, lock);
        } catch (OverlappingFileLockException occupied) {
            channel.close();
            return null;
        } catch (IOException | RuntimeException failure) {
            channel.close();
            throw failure;
        }
    }

    /**
     * Shares one OS lease between tabs running the same installed suite in this process.
     * Returns null only when another process owns the path. Each returned handle must be
     * closed; the underlying lease is released when the last share closes.
     */
    public static RuntimeStorageLease acquireShared(File filesDir, File installedDir)
            throws IOException {
        String key = digest(installedDir.getCanonicalPath());
        RuntimeStorageLease joined = joinShared(key);
        if (joined != null) {
            return joined;
        }
        RuntimeStorageLease exclusive = acquire(filesDir, installedDir);
        if (exclusive == null) {
            // A sibling tab may have published its share between the two checks.
            return joinShared(key);
        }
        synchronized (RuntimeStorageLease.class) {
            SharedLease shared = SHARED.get(key);
            if (shared != null) {
                shared.refs++;
                try {
                    exclusive.close();
                } catch (IOException ignored) {
                    // The pre-existing share stays authoritative.
                }
                return new RuntimeStorageLease(null, null, key);
            }
            SHARED.put(key, new SharedLease(exclusive));
            return new RuntimeStorageLease(null, null, key);
        }
    }

    private static RuntimeStorageLease joinShared(String key) {
        synchronized (RuntimeStorageLease.class) {
            SharedLease shared = SHARED.get(key);
            if (shared == null) {
                return null;
            }
            shared.refs++;
            return new RuntimeStorageLease(null, null, key);
        }
    }

    /** Probes the OS lock without waiting; an abandoned lock file is not an active lease. */
    public static boolean isActive(File filesDir, File installedDir) throws IOException {
        try (FileChannel channel = openChannel(filesDir, installedDir)) {
            try (FileLock probe = channel.tryLock()) {
                return probe == null;
            } catch (OverlappingFileLockException occupied) {
                return true;
            }
        }
    }

    private static FileChannel openChannel(File filesDir, File installedDir) throws IOException {
        File directory = new File(new File(filesDir, "runtime"), "leases");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Cannot create runtime lease directory: " + directory);
        }
        File lockFile = new File(directory, digest(installedDir.getCanonicalPath()) + ".lock");
        return new FileOutputStream(lockFile, true).getChannel();
    }

    private static String digest(String identity) {
        final byte[] bytes;
        try {
            bytes = MessageDigest.getInstance("SHA-256")
                    .digest(identity.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException impossible) {
            throw new AssertionError(impossible);
        }
        char[] text = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int value = bytes[i] & 0xff;
            text[i * 2] = HEX[value >>> 4];
            text[i * 2 + 1] = HEX[value & 0xf];
        }
        return new String(text);
    }

    @Override
    public void close() throws IOException {
        if (sharedKey != null) {
            releaseShared(sharedKey);
            return;
        }
        synchronized (this) {
            try {
                if (lock.isValid()) lock.release();
            } finally {
                channel.close();
            }
        }
    }

    private static void releaseShared(String key) throws IOException {
        RuntimeStorageLease last;
        synchronized (RuntimeStorageLease.class) {
            SharedLease shared = SHARED.get(key);
            if (shared == null) {
                return;
            }
            if (--shared.refs > 0) {
                return;
            }
            SHARED.remove(key);
            last = shared.lease;
        }
        last.close();
    }
}
