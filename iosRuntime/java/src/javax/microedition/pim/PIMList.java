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
/*
 *  Copyright 2021 Yury Kharchenko
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

package javax.microedition.pim;

import java.util.Enumeration;

public interface PIMList {
	String UNCATEGORIZED = null;

	String getName();

	void close() throws PIMException;

	Enumeration items() throws PIMException;

	Enumeration items(PIMItem matchingItem) throws PIMException;

	Enumeration items(String matchingValue) throws PIMException;

	Enumeration itemsByCategory(String category) throws PIMException;

	String[] getCategories() throws PIMException;

	boolean isCategory(String category) throws PIMException;

	void addCategory(String category) throws PIMException;

	void deleteCategory(String category, boolean deleteUnassignedItems) throws PIMException;

	void renameCategory(String currentCategory, String newCategory) throws PIMException;

	int maxCategories();

	boolean isSupportedField(int field);

	int[] getSupportedFields();

	boolean isSupportedAttribute(int field, int attribute);

	int[] getSupportedAttributes(int field);

	boolean isSupportedArrayElement(int stringArrayField, int arrayElement);

	int[] getSupportedArrayElements(int stringArrayField);

	int getFieldDataType(int field);

	String getFieldLabel(int field);

	String getAttributeLabel(int attribute);

	String getArrayElementLabel(int stringArrayField, int arrayElement);

	int maxValues(int field);

	int stringArraySize(int stringArrayField);
}
