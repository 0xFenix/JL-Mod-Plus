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
/**
 * Java docs licensed under the Apache License, Version 2.0
 * http://www.apache.org/licenses/LICENSE-2.0
 * (c) Copyright 2001, 2002 Motorola, Inc.  ALL RIGHTS RESERVED.
 *
 * @version $Id$
 */
package javax.obex;

/**
 * This class holds user name and password combinations.
 *
 * @version 1.0 February 11, 2002
 */
public class PasswordAuthentication {

	/**
	 * Creates a new <code>PasswordAuthentication</code> with the user name
	 * and password provided.
	 *
	 * @param userName the user name to include; this may be <code>null</code>
	 * @param password the password to include in the response
	 * @throws NullPointerException if <code>password</code> is <code>null</code>
	 */
	public PasswordAuthentication(byte[] userName, byte[] password) {
		if (password == null) {
			throw new NullPointerException("password is null");
		}
	}

	/**
	 * Retrieves the user name that was specified in the constructor. The user
	 * name may be <code>null</code>.
	 *
	 * @return the user name
	 */
	public byte[] getUserName() {
		return null;
	}

	/**
	 * Retrieves the password.
	 *
	 * @return the password
	 */
	public byte[] getPassword() {
		return null;
	}
}
