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
 * Class for holding User and Device Data related information.
 * This class contains valid data if the status returned in the userAndDeviceDataReceived() callback has value OK.
 * This provides get methods to retrieve each of the  User and Device data related information.
 */
public class IAPClientUserAndDeviceData extends Object {

	/**
	 * Returns the Nokia User Account information in hashed form.
	 */
	public String getAccount() {
		return "dummy_account";
	}

	/**
	 * Returns the device IMEI code in hashed form.
	 */
	public String getImei() {
		return "dummy_imei";
	}

	/**
	 * Returns the subscriber's IMSI code in hashed form.
	 */
	public String getImsi() {
		return "dummy_imsi";
	}

	/**
	 * Returns the home network country according to the SIM card in the device.
	 */
	public String getCountry() {
		return "dummy_country";
	}

	/**
	 * Returns the device language according to the device settings.
	 */
	public String getLanguage() {
		return "dummy_language";
	}

	/**
	 * Returns the name of the device in use.
	 */
	public String getDeviceModel() {
		return "dummy_device_model";
	}
}
