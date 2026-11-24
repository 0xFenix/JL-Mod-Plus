import javax.microedition.lcdui.Canvas;
import javax.microedition.lcdui.Display;
import javax.microedition.lcdui.Graphics;
import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;

/**
 * Prints every key and pointer event it receives, and draws the last one, so a
 * host run can prove the input path reaches Canvas callbacks.
 */
public class InputProbe extends MIDlet {

    private ProbeCanvas canvas;

    protected void startApp() throws MIDletStateChangeException {
        canvas = new ProbeCanvas();
        Display.getDisplay(this).setCurrent(canvas);
        System.out.println("[PROBE] ready");
    }

    protected void pauseApp() {
    }

    protected void destroyApp(boolean unconditional) {
    }

    static class ProbeCanvas extends Canvas {

        private String last = "none";
        private int count = 0;

        ProbeCanvas() {
            setFullScreenMode(true);
        }

        protected void paint(Graphics g) {
            g.setColor(0x102030);
            g.fillRect(0, 0, getWidth(), getHeight());
            g.setColor(0xFFFFFF);
            g.drawString("events: " + count, 4, 4, Graphics.TOP | Graphics.LEFT);
            g.drawString(last, 4, 24, Graphics.TOP | Graphics.LEFT);
        }

        private void record(String what) {
            last = what;
            count++;
            System.out.println("[PROBE] " + what);
            repaint();
        }

        protected void keyPressed(int keyCode) {
            record("keyPressed " + keyCode + " action=" + getGameAction(keyCode));
        }

        protected void keyReleased(int keyCode) {
            record("keyReleased " + keyCode);
        }

        protected void keyRepeated(int keyCode) {
            record("keyRepeated " + keyCode);
        }

        protected void pointerPressed(int x, int y) {
            record("pointerPressed " + x + "," + y);
        }

        protected void pointerDragged(int x, int y) {
            record("pointerDragged " + x + "," + y);
        }

        protected void pointerReleased(int x, int y) {
            record("pointerReleased " + x + "," + y);
        }
    }
}
