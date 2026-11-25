import javax.microedition.lcdui.Command;
import javax.microedition.lcdui.CommandListener;
import javax.microedition.lcdui.Display;
import javax.microedition.lcdui.Displayable;
import javax.microedition.lcdui.List;
import javax.microedition.midlet.MIDlet;

// A List long enough that the command buttons used to be pushed off screen.
public class ListProbe extends MIDlet implements CommandListener {
    protected void startApp() {
        List list = new List("Danh sách dài", List.IMPLICIT);
        for (int i = 1; i <= 30; i++) {
            list.append("Mục " + i, null);
        }
        list.setSelectedIndex(3, true); // Mục 4 must show as selected
        list.addCommand(new Command("Chọn", Command.OK, 1));
        list.addCommand(new Command("Quay lại", Command.BACK, 2));
        list.setCommandListener(this);
        Display.getDisplay(this).setCurrent(list);
        System.out.println("[LIST] ready 30");
    }

    public void commandAction(Command c, Displayable d) {
        System.out.println("[LIST] fired " + c.getLabel());
    }

    protected void pauseApp() {}
    protected void destroyApp(boolean unconditional) {}
}
