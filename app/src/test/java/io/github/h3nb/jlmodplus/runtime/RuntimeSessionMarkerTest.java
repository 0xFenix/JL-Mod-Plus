/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
package io.github.h3nb.jlmodplus.runtime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;

public class RuntimeSessionMarkerTest {
    @Test public void roundTripsEscapedSuiteIdentity() {
        String json = RuntimeSessionMarker.encode(
                3,
                "/data/user/0/app/files/work/converted/My \"Game\"\\x",
                "Line\nOne\t\"Tên\" ゲーム",
                1763000000000L);
        RuntimeSessionMarker.Session session = RuntimeSessionMarker.decode(json);

        assertEquals(3, session.getTabs());
        assertEquals("/data/user/0/app/files/work/converted/My \"Game\"\\x",
                session.getAppPath());
        assertEquals("Line\nOne\t\"Tên\" ゲーム", session.getAppName());
        assertEquals(1763000000000L, session.getUpdated());
    }

    @Test public void toleratesMissingOptionalFieldsAndExtraFields() {
        RuntimeSessionMarker.Session session = RuntimeSessionMarker.decode(
                "{\"tabs\":1,\"unknown\":true}");

        assertEquals(1, session.getTabs());
        assertNull(session.getAppPath());
        assertNull(session.getAppName());
        assertEquals(0L, session.getUpdated());
    }

    @Test public void rejectsMalformedOrEmptyState() {
        assertNull(RuntimeSessionMarker.decode(null));
        assertNull(RuntimeSessionMarker.decode(""));
        assertNull(RuntimeSessionMarker.decode("{}"));
        assertNull(RuntimeSessionMarker.decode("{\"tabs\":0}"));
        assertNull(RuntimeSessionMarker.decode("{\"tabs\":\"many\"}"));
    }
}
