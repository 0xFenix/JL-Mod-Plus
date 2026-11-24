/*
 * Derived from J2ME-Decade (iOS Edition) <https://github.com/darkrose00x-ux/j2me-ios>,
 * licensed under the Apache License, Version 2.0. That project states its J2ME API
 * layer is ported from J2ME-Loader <https://github.com/nikita36078/J2ME-Loader>,
 * whose javax.microedition sources are Copyright 2012 Kulikov Dmitriy,
 * 2017-2020 Nikita Shakarun, 2019-2023 Yury Kharchenko, Apache License 2.0.
 *
 * JL-Mod Plus modifications: removed the M3G (javax.microedition.m3g), MascotCapsule
 * micro3D, JBlend/Vodafone J3D, Bluetooth, Location and AMMS packages, which are
 * outside the iOS runtime scope.
 */
package javax.microedition.io;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

public class Connector {

	public static final int READ = 1;
	public static final int WRITE = 2;
	public static final int READ_WRITE = 3;

	private Connector() { }

	public static Connection open(String name) throws IOException {
		throw new IOException("Connector.open() not supported: " + name);
	}

	public static Connection open(String name, int mode) throws IOException {
		throw new IOException("Connector.open() not supported: " + name);
	}

	public static Connection open(String name, int mode, boolean timeouts) throws IOException {
		throw new IOException("Connector.open() not supported: " + name);
	}

	public static DataInputStream openDataInputStream(String name) throws IOException {
		throw new IOException("Connector.openDataInputStream() not supported: " + name);
	}

	public static DataOutputStream openDataOutputStream(String name) throws IOException {
		throw new IOException("Connector.openDataOutputStream() not supported: " + name);
	}

	public static InputStream openInputStream(String name) throws IOException {
		throw new IOException("Connector.openInputStream() not supported: " + name);
	}

	public static OutputStream openOutputStream(String name) throws IOException {
		throw new IOException("Connector.openOutputStream() not supported: " + name);
	}
}
