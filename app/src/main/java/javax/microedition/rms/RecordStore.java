/*
 *  MicroEmulator
 *  Copyright (C) 2001 Bartek Teodorczyk <barteo@barteo.net>
 *  Copyright (C) 2017-2018 Nikita Shakarun
 *
 *  It is licensed under the following two licenses as alternatives:
 *    1. GNU Lesser General Public License (the "LGPL") version 2.1 or any newer version
 *    2. Apache License (the "AL") Version 2.0
 *
 *  You may not use this file except in compliance with at least one of
 *  the above two licenses.
 *
 *  You may obtain a copy of the LGPL at
 *      http://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
 *
 *  You may obtain a copy of the AL at
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the LGPL or the AL for the specific language governing permissions and
 *  limitations.
 */
package javax.microedition.rms;

import java.util.concurrent.ConcurrentHashMap;

import javax.microedition.rms.impl.AndroidRecordStoreManager;
import javax.microedition.shell.MidletTabRouter;

public class RecordStore {
	public static final int AUTHMODE_PRIVATE = 0;
	public static final int AUTHMODE_ANY = 1;

	/**
	 * Per-tab RMS managers. RecordStore names are only unique within a suite, so each tab
	 * keeps its own name-to-store cache; the on-disk files were already separated per suite
	 * by the tab-dispatched data dir. Tab 0 is the implicit single-suite fallback.
	 */
	private static final ConcurrentHashMap<Integer, AndroidRecordStoreManager> MANAGERS =
			new ConcurrentHashMap<>();

	static AndroidRecordStoreManager managerForCurrentThread() {
		int tab = MidletTabRouter.tabForThread(Thread.currentThread());
		if (tab == MidletTabRouter.NO_TAB) {
			tab = MidletTabRouter.selectedTabId();
		}
		if (tab == MidletTabRouter.NO_TAB) {
			tab = 0;
		}
		AndroidRecordStoreManager manager = MANAGERS.get(tab);
		if (manager == null) {
			AndroidRecordStoreManager created = new AndroidRecordStoreManager();
			AndroidRecordStoreManager raced = MANAGERS.putIfAbsent(tab, created);
			manager = raced != null ? raced : created;
		}
		return manager;
	}

	/** Drops the cached manager of a torn-down tab; the on-disk stores are untouched. */
	public static void removeManagerForTab(int tabId) {
		MANAGERS.remove(tabId);
	}

	public static void deleteRecordStore(String recordStoreName) throws RecordStoreException {
		managerForCurrentThread().deleteRecordStore(recordStoreName);
	}

	public static String[] listRecordStores() {
		return managerForCurrentThread().listRecordStores();
	}

	public static RecordStore openRecordStore(String recordStoreName, boolean createIfNecessary)
			throws RecordStoreException {
		return managerForCurrentThread().openRecordStore(recordStoreName, createIfNecessary);
	}

	public static RecordStore openRecordStore(String recordStoreName, boolean createIfNecessary,
											  int authmode, boolean writable)
			throws RecordStoreException {
		// TODO Not yet implemented
		return openRecordStore(recordStoreName, createIfNecessary);
	}

	public static RecordStore openRecordStore(String recordStoreName,
											  String vendorName,
											  String suiteName)
			throws RecordStoreException {
		// TODO Not yet implemented
		return openRecordStore(recordStoreName, false);
	}

	public void closeRecordStore() throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public String getName() throws RecordStoreNotOpenException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int getVersion() throws RecordStoreNotOpenException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int getNumRecords() throws RecordStoreNotOpenException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int getSize() throws RecordStoreNotOpenException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int getSizeAvailable() throws RecordStoreNotOpenException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public long getLastModified() throws RecordStoreNotOpenException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public void addRecordListener(RecordListener listener) {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public void removeRecordListener(RecordListener listener) {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int getNextRecordID() throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int addRecord(byte[] data, int offset, int numBytes) throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public void deleteRecord(int recordId) throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int getRecordSize(int recordId) throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public int getRecord(int recordId, byte[] buffer, int offset) throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public byte[] getRecord(int recordId) throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public void setMode(int authmode, boolean writable) throws RecordStoreException {
		// TODO Not yet implemented
	}

	public void setRecord(int recordId, byte[] newData, int offset, int numBytes)
			throws RecordStoreException {
		throw new UnsupportedOperationException("Not implemented method");
	}

	public RecordEnumeration enumerateRecords(RecordFilter filter,
											  RecordComparator comparator,
											  boolean keepUpdated)
			throws RecordStoreNotOpenException {
		throw new UnsupportedOperationException("Not implemented method");
	}
}
