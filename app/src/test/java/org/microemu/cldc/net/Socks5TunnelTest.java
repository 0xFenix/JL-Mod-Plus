/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

package org.microemu.cldc.net;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public class Socks5TunnelTest {
	@Test
	public void noAuthIpv4TargetTunnels() throws Exception {
		try (FakeProxy proxy = new FakeProxy(false, "", "", 0)) {
			Socket socket = Socks5Tunnel.connect("192.0.2.10", 8080,
					"127.0.0.1", proxy.port(), "", "", 2000, 2000);
			try {
				assertEquals(0x5A, socket.getInputStream().read());
			} finally {
				socket.close();
			}
			proxy.await();
			assertEquals(1, proxy.offeredMethods);
			assertEquals(1, proxy.addressType);
			assertEquals("192.0.2.10", proxy.targetHost);
			assertEquals(8080, proxy.targetPort);
		}
	}

	@Test
	public void usernamePasswordTargetTunnels() throws Exception {
		try (FakeProxy proxy = new FakeProxy(true, "alice", "s3cr3t", 0)) {
			Socket socket = Socks5Tunnel.connect("example.com", 443,
					"127.0.0.1", proxy.port(), "alice", "s3cr3t", 2000, 2000);
			try {
				assertEquals(0x5A, socket.getInputStream().read());
			} finally {
				socket.close();
			}
			proxy.await();
			assertEquals(4, proxy.offeredMethods);
			assertEquals("alice", proxy.authUser);
			assertEquals("s3cr3t", proxy.authPass);
		}
	}

	@Test
	public void hostnameTargetUsesDomainAddressType() throws Exception {
		try (FakeProxy proxy = new FakeProxy(false, "", "", 0)) {
			Socket socket = Socks5Tunnel.connect("example.com", 443,
					"127.0.0.1", proxy.port(), "", "", 2000, 2000);
			try {
				assertEquals(0x5A, socket.getInputStream().read());
			} finally {
				socket.close();
			}
			proxy.await();
			assertEquals(3, proxy.addressType);
			assertEquals("example.com", proxy.targetHost);
			assertEquals(443, proxy.targetPort);
		}
	}

	@Test
	public void refusedConnectCarriesReplyCode() throws Exception {
		try (FakeProxy proxy = new FakeProxy(false, "", "", 5)) {
			IOException failure = assertThrows(IOException.class,
					() -> Socks5Tunnel.connect("192.0.2.10", 80,
							"127.0.0.1", proxy.port(), "", "", 2000, 2000));
			assertEquals("CONNECT refused (5)", failure.getMessage());
			proxy.await();
		}
	}

	@Test
	public void wrongCredentialsAreRejected() throws Exception {
		try (FakeProxy proxy = new FakeProxy(true, "alice", "s3cr3t", 0)) {
			IOException failure = assertThrows(IOException.class,
					() -> Socks5Tunnel.connect("example.com", 443,
							"127.0.0.1", proxy.port(), "alice", "wrong", 2000, 2000));
			assertEquals("bad credentials", failure.getMessage());
			proxy.await();
		}
	}

	private static final class FakeProxy implements AutoCloseable {
		private final ServerSocket server;
		private final boolean requireAuth;
		private final String expectedUser;
		private final String expectedPass;
		private final int replyCode;
		private final CountDownLatch done = new CountDownLatch(1);

		volatile int offeredMethods;
		volatile int addressType = -1;
		volatile String targetHost;
		volatile int targetPort = -1;
		volatile String authUser;
		volatile String authPass;
		volatile Throwable failure;

		FakeProxy(boolean requireAuth, String expectedUser, String expectedPass, int replyCode)
				throws IOException {
			this.requireAuth = requireAuth;
			this.expectedUser = expectedUser;
			this.expectedPass = expectedPass;
			this.replyCode = replyCode;
			this.server = new ServerSocket(0, 1, InetAddress.getLoopbackAddress());
			this.server.setSoTimeout(5000);
			Thread worker = new Thread(this::serve, "fake-socks5");
			worker.setDaemon(true);
			worker.start();
		}

		int port() {
			return server.getLocalPort();
		}

		void await() throws Exception {
			assertTrue(done.await(5, TimeUnit.SECONDS), "fake proxy did not finish");
			if (failure != null) {
				throw new AssertionError("fake proxy failed", failure);
			}
		}

		private void serve() {
			try (Socket socket = server.accept()) {
				DataInputStream in = new DataInputStream(socket.getInputStream());
				DataOutputStream out = new DataOutputStream(socket.getOutputStream());

				assertEquals(5, in.readUnsignedByte());
				int count = in.readUnsignedByte();
				int methods = 0;
				for (int i = 0; i < count; i++) {
					methods |= 1 << in.readUnsignedByte();
				}
				offeredMethods = methods;

				int method;
				if (requireAuth) {
					method = (methods & 4) != 0 ? 2 : 0xFF;
				} else {
					method = (methods & 1) != 0 ? 0 : 0xFF;
				}
				out.writeByte(5);
				out.writeByte(method);
				out.flush();
				if (method == 0xFF) {
					return;
				}

				if (method == 2) {
					assertEquals(1, in.readUnsignedByte());
					byte[] user = new byte[in.readUnsignedByte()];
					in.readFully(user);
					byte[] pass = new byte[in.readUnsignedByte()];
					in.readFully(pass);
					authUser = new String(user, StandardCharsets.UTF_8);
					authPass = new String(pass, StandardCharsets.UTF_8);
					boolean accepted = expectedUser.equals(authUser)
							&& expectedPass.equals(authPass);
					out.writeByte(1);
					out.writeByte(accepted ? 0 : 1);
					out.flush();
					if (!accepted) {
						return;
					}
				}

				assertEquals(5, in.readUnsignedByte());
				assertEquals(1, in.readUnsignedByte());
				in.readUnsignedByte(); // reserved
				addressType = in.readUnsignedByte();
				if (addressType == 1) {
					byte[] address = new byte[4];
					in.readFully(address);
					targetHost = (address[0] & 0xFF) + "." + (address[1] & 0xFF)
							+ "." + (address[2] & 0xFF) + "." + (address[3] & 0xFF);
				} else if (addressType == 3) {
					byte[] name = new byte[in.readUnsignedByte()];
					in.readFully(name);
					targetHost = new String(name, StandardCharsets.UTF_8);
				} else {
					throw new AssertionError("unexpected address type " + addressType);
				}
				targetPort = in.readUnsignedShort();

				out.writeByte(5);
				out.writeByte(replyCode);
				out.writeByte(0);
				out.writeByte(1);
				out.write(new byte[]{127, 0, 0, 1});
				out.writeShort(0);
				out.flush();
				if (replyCode == 0) {
					out.writeByte(0x5A);
					out.flush();
				}
			} catch (Throwable error) {
				failure = error;
			} finally {
				try {
					server.close();
				} catch (IOException ignored) {
					// Test teardown.
				}
				done.countDown();
			}
		}

		@Override
		public void close() throws IOException {
			server.close();
		}
	}
}
