package com.retro.nes;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import javax.microedition.lcdui.Display;
import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;
import javax.microedition.shell.AppClassLoader;

public class NesMidlet extends MIDlet {
    private NesCanvas canvas;

    @Override
    public void startApp() throws MIDletStateChangeException {
        if (canvas != null) {
            canvas.start();
            return;
        }

        InputStream romStream = null;
        try {
            // First attempt to load from resources inside res.jar
            romStream = getClass().getResourceAsStream("/rom.nes");
            if (romStream == null) {
                romStream = AppClassLoader.getResourceAsStream(getClass(), "rom.nes");
            }
            if (romStream == null) {
                // Look for rom.nes in app directory
                String dataDir = AppClassLoader.getDataDir();
                if (dataDir != null) {
                    File file = new File(dataDir, "rom.nes");
                    if (file.isFile()) {
                        romStream = new FileInputStream(file);
                    }
                }
            }

            if (romStream == null) {
                throw new Exception("NES ROM file 'rom.nes' not found");
            }

            canvas = new NesCanvas(romStream);
            Display.getDisplay(this).setCurrent(canvas);
            canvas.start();
        } catch (Exception e) {
            e.printStackTrace();
            throw new MIDletStateChangeException("Failed to initialize NES emulator: " + e.getMessage());
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
