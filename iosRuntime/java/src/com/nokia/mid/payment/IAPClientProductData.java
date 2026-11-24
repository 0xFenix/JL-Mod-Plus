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
package com.nokia.mid.payment;

/**
 * Class for holding purchaseable or restorable product specific data.
 * This class contains valid data if the status returned in the productDataReceived() callback has value OK.
 * This provides get methods to retrieve each of the product related information.
 */
public class IAPClientProductData extends Object {

	/**
	 * The DRM protection type is other than Nokia DRM, or it is not available.
	 * The publisher has the responsibility for the access control and restriction mechanisms of use.
	 */
	public static final int OTHER_DRM = 0;

	/**
	 * The item is DRM protected by Nokia. The item can be restored using IAP API.
	 */
	public static final int NOKIA_DRM = 1;

	/**
	 * Returns the productID of the purchaseable item.
	 */
	public String getProductId() {
		return "dummy_product_id";
	}

	/**
	 * Returns the name of the product in 16 characters.
	 */
	public String getTitle() {
		return "dummy_title";
	}

	/**
	 * Returns the short description of the product in 30 characters.
	 */
	public String getShortDescription() {
		return "dummy_short_description";
	}

	/**
	 * Returns the long description of the product in 500 characters.
	 */
	public String getLongDescription() {
		return "dummy_long_description";
	}

	/**
	 * Returns the price of the product including currency, string to be used as is.
	 */
	public String getPrice() {
		return "DUMMY_STRING";
	}

	/**
	 * Returns the type of Drm protection.
	 *
	 * @return OTHER_DRM - Indicates non-Nokia DRM or not available.
	 * NOKIA_DRM - The item is DRM protected by Nokia.
	 */
	public int getDrmProtection() {
		return 0;
	}
}
