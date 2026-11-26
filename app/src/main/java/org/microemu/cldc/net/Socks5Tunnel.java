/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.microemu.cldc.net;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/**
 * Minimal SOCKS5 CONNECT tunnel (RFC 1928) with optional username/password
 * authentication (RFC 1929).
 *
 * <p>The proxy resolves host names because the request carries a domain name
 * when the target is not a dotted IPv4 literal. The returned socket is a
 * transparent byte stream; on any failure it is closed before the exception
 * escapes, so callers never receive a half-open tunnel.
 */
public final class Socks5Tunnel {
	private static final int VERSION = 0x05;
	private static final int AUTH_VERSION = 0x01;
	private static final int CMD_CONNECT = 0x01;
	private static final int METHOD_NO_AUTH = 0x00;
	private static final int METHOD_USER_PASS = 0x02;
	private static final int METHOD_NONE_ACCEPTABLE = 0xFF;
	private static final int ATYP_IPV4 = 0x01;
	private static final int ATYP_DOMAIN = 0x03;
	private static final int ATYP_IPV6 = 0x04;

	private Socks5Tunnel() {
	}

	/**
	 * Opens a SOCKS5 tunnel to {@code host:port} through {@code proxyHost:proxyPort}.
	 *
	 * @param connectTimeoutMs proxy TCP connect timeout; 0 waits indefinitely
	 * @param readTimeoutMs    negotiation read timeout; 0 waits indefinitely.
	 *                         It is cleared before the tunnel is returned so the
	 *                         guest sees the same read behaviour as a direct socket.
	 */
	public static Socket connect(String host, int port, String proxyHost, int proxyPort,
			String user, String pass, int connectTimeoutMs, int readTimeoutMs) throws IOException {
		if (proxyHost == null || proxyHost.isEmpty()) {
			throw new IOException("proxy host is required");
		}
		if (proxyPort < 1 || proxyPort > 65535) {
			throw new IOException("invalid proxy port");
		}
		if (port < 1 || port > 65535) {
			throw new IOException("invalid target port");
		}
		String username = user == null ? "" : user;
		String password = pass == null ? "" : pass;

		Socket socket = new Socket();
		try {
			socket.connect(new InetSocketAddress(proxyHost, proxyPort), connectTimeoutMs);
			socket.setSoTimeout(readTimeoutMs);
			DataInputStream in = new DataInputStream(socket.getInputStream());
			DataOutputStream out = new DataOutputStream(socket.getOutputStream());

			negotiate(in, out, username, password);
			requestConnect(in, out, host, port);

			socket.setSoTimeout(0);
			return socket;
		} catch (IOException | RuntimeException ex) {
			closeQuietly(socket);
			throw ex;
		}
	}

	private static void negotiate(DataInputStream in, DataOutputStream out,
			String user, String pass) throws IOException {
		out.writeByte(VERSION);
		out.writeByte(1);
		out.writeByte(user.isEmpty() ? METHOD_NO_AUTH : METHOD_USER_PASS);
		out.flush();

		int version = in.readUnsignedByte();
		int method = in.readUnsignedByte();
		if (version != VERSION) {
			throw new IOException("proxy protocol error");
		}
		if (method == METHOD_NONE_ACCEPTABLE) {
			throw new IOException(user.isEmpty()
					? "proxy requires authentication"
					: "proxy rejected authentication methods");
		}
		if (method == METHOD_USER_PASS) {
			if (user.isEmpty()) {
				throw new IOException("proxy requires authentication");
			}
			authenticate(in, out, user, pass);
		} else if (method != METHOD_NO_AUTH) {
			throw new IOException("proxy selected unsupported auth method " + method);
		}
	}

	private static void authenticate(DataInputStream in, DataOutputStream out,
			String user, String pass) throws IOException {
		byte[] userBytes = user.getBytes(StandardCharsets.UTF_8);
		byte[] passBytes = pass.getBytes(StandardCharsets.UTF_8);
		if (userBytes.length > 255 || passBytes.length > 255) {
			throw new IOException("credentials too long");
		}
		out.writeByte(AUTH_VERSION);
		out.writeByte(userBytes.length);
		out.write(userBytes);
		out.writeByte(passBytes.length);
		out.write(passBytes);
		out.flush();

		int version = in.readUnsignedByte();
		int status = in.readUnsignedByte();
		if (version != AUTH_VERSION) {
			throw new IOException("proxy protocol error");
		}
		if (status != 0) {
			throw new IOException("bad credentials");
		}
	}

	private static void requestConnect(DataInputStream in, DataOutputStream out,
			String host, int port) throws IOException {
		if (host == null || host.isEmpty()) {
			throw new IOException("target host is required");
		}
		out.writeByte(VERSION);
		out.writeByte(CMD_CONNECT);
		out.writeByte(0);
		byte[] ipv4 = parseIpv4(host);
		if (ipv4 != null) {
			out.writeByte(ATYP_IPV4);
			out.write(ipv4);
		} else {
			byte[] name = host.getBytes(StandardCharsets.UTF_8);
			if (name.length > 255) {
				throw new IOException("target host name is too long");
			}
			out.writeByte(ATYP_DOMAIN);
			out.writeByte(name.length);
			out.write(name);
		}
		out.writeShort(port);
		out.flush();

		int version = in.readUnsignedByte();
		int reply = in.readUnsignedByte();
		in.readUnsignedByte(); // reserved
		int addressType = in.readUnsignedByte();
		if (version != VERSION) {
			throw new IOException("proxy protocol error");
		}
		if (reply != 0) {
			throw new IOException("CONNECT refused (" + reply + ")");
		}
		consumeBoundAddress(in, addressType);
		in.readUnsignedShort(); // bound port
	}

	private static void consumeBoundAddress(DataInputStream in, int addressType) throws IOException {
		switch (addressType) {
			case ATYP_IPV4:
				in.readFully(new byte[4]);
				break;
			case ATYP_DOMAIN:
				in.readFully(new byte[in.readUnsignedByte()]);
				break;
			case ATYP_IPV6:
				in.readFully(new byte[16]);
				break;
			default:
				throw new IOException("proxy sent unsupported address type " + addressType);
		}
	}

	/** Returns the four address octets, or null when the host is not a dotted IPv4 literal. */
	private static byte[] parseIpv4(String host) {
		String[] parts = host.split("\\.", -1);
		if (parts.length != 4) {
			return null;
		}
		byte[] address = new byte[4];
		for (int i = 0; i < 4; i++) {
			String part = parts[i];
			if (part.isEmpty() || part.length() > 3) {
				return null;
			}
			int value = 0;
			for (int j = 0; j < part.length(); j++) {
				char c = part.charAt(j);
				if (c < '0' || c > '9') {
					return null;
				}
				value = value * 10 + (c - '0');
			}
			if (value > 255) {
				return null;
			}
			address[i] = (byte) value;
		}
		return address;
	}

	private static void closeQuietly(Socket socket) {
		try {
			socket.close();
		} catch (IOException ignored) {
			// Preserve the original failure.
		}
	}
}
