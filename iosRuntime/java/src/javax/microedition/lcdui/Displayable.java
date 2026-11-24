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

/**
 * Base class for all J2ME UI screens.
 */
public abstract class Displayable {
    private String title;
    public int width = 240;
    public int height = 320;
    private ArrayList<Command> commands = new ArrayList<Command>();
    private CommandListener commandListener;
    private Ticker ticker;

    public void setTitle(String title) { this.title = title; }
    public String getTitle() { return title != null ? title : ""; }

    public int getWidth() { return width; }
    public int getHeight() { return height; }

    public void addCommand(Command cmd) {
        if (cmd != null && !commands.contains(cmd)) {
            commands.add(cmd);
            if (isShown()) onCommandsChanged();
        }
    }

    public void removeCommand(Command cmd) {
        if (commands.remove(cmd)) {
            if (isShown()) onCommandsChanged();
        }
    }

    protected void onCommandsChanged() { }

    public void setCommandListener(CommandListener listener) {
        this.commandListener = listener;
    }

    public ArrayList<Command> getCommands() { return commands; }
    public CommandListener getCommandListener() { return commandListener; }

    public void setTicker(Ticker ticker) { this.ticker = ticker; }
    public Ticker getTicker() { return ticker; }

    public boolean isShown() {
        Display d = Display.getDisplay(null);
        return d != null && d.getCurrent() == this;
    }

    protected void sizeChanged(int w, int h) { }

    /** Fire command action. Called from Display event loop when a command event is received. */
    public void fireCommandAction(int commandIndex) {
        if (commandListener != null && commandIndex >= 0 && commandIndex < commands.size()) {
            commandListener.commandAction(commands.get(commandIndex), this);
        }
    }
}
