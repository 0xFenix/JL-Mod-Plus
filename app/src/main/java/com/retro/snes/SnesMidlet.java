package com.retro.snes;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import javax.microedition.lcdui.Display;
import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;
import javax.microedition.shell.AppClassLoader;

public class SnesMidlet extends MIDlet {
    private SnesCanvas canvas;

    @Override
    public void startApp() throws MIDletStateChangeException {
        if (canvas != null) {
            canvas.start();
            return;
        }

        InputStream romStream = null;
        try {
            romStream = getClass().getResourceAsStream("/rom.snes");
            if (romStream == null) {
                romStream = getClass().getResourceAsStream("/rom.smc");
            }
            if (romStream == null) {
                romStream = AppClassLoader.getResourceAsStream(getClass(), "rom.snes");
            }
            if (romStream == null) {
                romStream = AppClassLoader.getResourceAsStream(getClass(), "rom.smc");
            }
            if (romStream == null) {
                String dataDir = AppClassLoader.getDataDir();
                if (dataDir != null) {
                    File file = new File(dataDir, "rom.snes");
                    if (!file.isFile()) file = new File(dataDir, "rom.smc");
                    if (file.isFile()) {
                        romStream = new FileInputStream(file);
                    }
                }
            }

            if (romStream == null) {
                throw new Exception("SNES ROM file 'rom.snes' or 'rom.smc' not found");
            }

            canvas = new SnesCanvas(romStream);
            Display.getDisplay(this).setCurrent(canvas);
            canvas.start();
        } catch (Exception e) {
            e.printStackTrace();
            throw new MIDletStateChangeException("Failed to initialize SNES emulator: " + e.getMessage());
        }
    }

    @Override
    public void pauseApp() {
        if (canvas != null) {
            canvas.stop();
        }
    }

    @Override
    public void destroyApp(boolean unconditional) throws MIDletStateChangeException {
        if (canvas != null) {
            canvas.stop();
            canvas = null;
        }
    }
}
