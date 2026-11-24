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
 * MicroEmulator
 * Copyright (C) 2006-2007 Bartek Teodorczyk <barteo@barteo.net>
 * Copyright (C) 2006-2007 Vlad Skarzhevskyy
 * <p>
 * It is licensed under the following two licenses as alternatives:
 * 1. GNU Lesser General Public License (the "LGPL") version 2.1 or any newer version
 * 2. Apache License (the "AL") Version 2.0
 * <p>
 * You may not use this file except in compliance with at least one of
 * the above two licenses.
 * <p>
 * You may obtain a copy of the LGPL at
 * http://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
 * <p>
 * You may obtain a copy of the AL at
 * http://www.apache.org/licenses/LICENSE-2.0
 * <p>
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the LGPL or the AL for the specific language governing permissions and
 * limitations.
 *
 * @version $Id$
 */
package javax.microedition.io.file;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Enumeration;

import javax.microedition.io.StreamConnection;

public interface FileConnection extends StreamConnection {

	public abstract boolean isOpen();

	@Override
	public abstract InputStream openInputStream() throws IOException;

	@Override
	public abstract DataInputStream openDataInputStream() throws IOException;

	@Override
	public abstract OutputStream openOutputStream() throws IOException;

	@Override
	public abstract DataOutputStream openDataOutputStream() throws IOException;

	public abstract OutputStream openOutputStream(long byteOffset) throws IOException;

	public abstract long totalSize();

	public abstract long availableSize();

	public abstract long usedSize();

	public abstract long directorySize(boolean includeSubDirs) throws IOException;

	public abstract long fileSize() throws IOException;

	public abstract boolean canRead();

	public abstract boolean canWrite();

	public abstract boolean isHidden();

	public abstract void setReadable(boolean readable) throws IOException;

	public abstract void setWritable(boolean writable) throws IOException;

	public abstract void setHidden(boolean hidden) throws IOException;

	public abstract Enumeration list() throws IOException;

	public abstract Enumeration list(String filter, boolean includeHidden) throws IOException;

	public abstract void create() throws IOException;

	public abstract void mkdir() throws IOException;

	public abstract boolean exists();

	public abstract boolean isDirectory();

	public abstract void delete() throws IOException;

	public abstract void rename(String newName) throws IOException;

	public abstract void truncate(long byteOffset) throws IOException;

	public abstract void setFileConnection(String s) throws IOException;

	public abstract String getName();

	public abstract String getPath();

	public abstract String getURL();

	public abstract long lastModified();
}
