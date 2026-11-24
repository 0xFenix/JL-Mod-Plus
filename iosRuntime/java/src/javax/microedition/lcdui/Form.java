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
package javax.microedition.lcdui;

import java.util.ArrayList;

public class Form extends Screen {
    private ArrayList<Item> items = new ArrayList<Item>();
    private ItemStateListener itemStateListener;

    public Form(String title) {
        setTitle(title);
    }

    public Form(String title, Item[] itemArray) {
        setTitle(title);
        if (itemArray != null) {
            for (Item item : itemArray) append(item);
        }
    }

    public int append(Item item) {
        if (item == null) throw new NullPointerException();
        item.owner = this;
        items.add(item);
        if (isShown()) showNative();
        return items.size() - 1;
    }

    public int append(String str) {
        return append(new StringItem(null, str));
    }

    public int append(Image img) {
        return append(new ImageItem(null, img, ImageItem.LAYOUT_DEFAULT, ""));
    }

    public void insert(int index, Item item) {
        item.owner = this;
        items.add(index, item);
        if (isShown()) showNative();
    }

    public void set(int index, Item item) {
        item.owner = this;
        items.set(index, item);
        if (isShown()) showNative();
    }

    public void delete(int index) {
        items.remove(index);
        if (isShown()) showNative();
    }

    public void deleteAll() {
        items.clear();
        if (isShown()) showNative();
    }
    public int size() { return items.size(); }
    public Item get(int index) { return items.get(index); }
    public void setItemStateListener(ItemStateListener listener) { itemStateListener = listener; }

    public void syncFromNative() {
        for (int i = 0; i < items.size(); i++) {
            Item item = items.get(i);
            if (item instanceof TextField) {
                String val = NativeBridge.getFormItemText(i);
                if (val != null) {
                    ((TextField) item).setString(val);
                    notifyItemStateChanged(item);
                }
            } else if (item instanceof ChoiceGroup) {
                ChoiceGroup cg = (ChoiceGroup) item;
                String val = NativeBridge.getFormItemText(i);
                if (val != null && val.length() > 0) {
                    try {
                        String[] parts = val.split("\n");
                        if (cg.choiceType == Choice.MULTIPLE) {
                            if (parts.length >= 3) {
                                String[] flags = parts[2].split(",");
                                for (int f = 0; f < flags.length && f < cg.size(); f++) {
                                    cg.setSelectedIndex(f, "1".equals(flags[f].trim()));
                                }
                            }
                        } else if (parts.length >= 1) {
                            int selIdx = Integer.parseInt(parts[0].trim());
                            if (selIdx >= 0 && selIdx < cg.size()) {
                                cg.setSelectedIndex(selIdx, true);
                            }
                        }
                        notifyItemStateChanged(item);
                    } catch (Throwable t) {
                    }
                }
            }
        }
    }

    void notifyItemStateChanged(Item item) {
        if (itemStateListener != null) itemStateListener.itemStateChanged(item);
    }

    @Override
    protected void onCommandsChanged() {
        showNative();
    }

    /** Serialize form to native bridge and show it. */
    public void showNative() {
        NativeBridge.formBegin(getTitle(), 0); // type 0 = form
        for (Item item : items) {
            int type = item.getItemType();
            if (type == 0) { // StringItem
                NativeBridge.formAddStringItem(item.getItemLabel(), item.getItemText(), 0);
            } else if (type == 1) { // TextField
                TextField tf = (TextField) item;
                NativeBridge.formAddTextField(item.getItemLabel(), item.getItemText(),
                        tf.getMaxSize(), tf.getConstraints());
            } else if (type == 2 && item instanceof ChoiceGroup) { // ChoiceGroup
                ChoiceGroup cg = (ChoiceGroup) item;
                StringBuilder sb = new StringBuilder();
                sb.append(cg.getSelectedIndex()).append("\n");
                for (int j = 0; j < cg.size(); j++) {
                    if (j > 0) sb.append("\t");
                    sb.append(cg.getString(j));
                }
                sb.append("\n");
                for (int j = 0; j < cg.size(); j++) {
                    if (j > 0) sb.append(",");
                    sb.append(cg.isSelected(j) ? "1" : "0");
                }
                NativeBridge.formAddTextField(item.getItemLabel(), sb.toString(), 2, cg.choiceType);
            } else {
                // Fallback: show as string
                NativeBridge.formAddStringItem(item.getItemLabel(), item.getItemText(), 0);
            }
        }
        // Commands
        ArrayList<Command> cmds = getCommands();
        for (int i = 0; i < cmds.size(); i++) {
            Command c = cmds.get(i);
            String lbl = c.getLabel() != null ? c.getLabel().toLowerCase() : "";
            if (cmds.size() > 1 && (lbl.indexOf("mrquyet") >= 0 || lbl.indexOf("mr.quyet") >= 0)) {
                continue;
            }
            NativeBridge.formAddCommand(c.getLabel(), c.getCommandType(), c.getPriority(), i);
        }
        NativeBridge.formShow();
    }
}
