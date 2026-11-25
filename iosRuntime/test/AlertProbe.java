import javax.microedition.lcdui.*;
import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;

/**
 * Probe for Alert commands: a confirmation alert with two real commands, then
 * an alert that only has the implicit DISMISS command, then a plain form.
 * Prints which command the runtime fired and what became current.
 */
public class AlertProbe extends MIDlet implements CommandListener {
    private Display display;
    private Form result;
    private Alert silent;

    protected void startApp() throws MIDletStateChangeException {
        display = Display.getDisplay(this);
        result = new Form("Kết quả");
        result.append(new StringItem("Trạng thái", "Đã xử lý alert"));
        result.addCommand(new Command("Đóng", Command.EXIT, 1));
        result.setCommandListener(this);

        Alert confirm = new Alert("Thông báo", "Bạn có muốn tiếp tục?", null,
                AlertType.CONFIRMATION);
        confirm.setTimeout(Alert.FOREVER);
        confirm.addCommand(new Command("Đồng ý", Command.OK, 1));
        confirm.addCommand(new Command("Để sau", Command.BACK, 1));
        confirm.setCommandListener(this);

        silent = new Alert("Nhắc nhở", "Alert không có lệnh riêng.", null,
                AlertType.INFO);
        silent.setTimeout(Alert.FOREVER);

        System.out.println("[ALERT] confirm commands=" + confirm.getCommands().size());
        System.out.println("[ALERT] silent commands=" + silent.getCommands().size());
        display.setCurrent(confirm, result);
    }

    public void commandAction(Command c, Displayable d) {
        System.out.println("[ALERT] commandAction label=" + c.getLabel()
                + " on=" + d.getClass().getName());
        if (d == result) {
            notifyDestroyed();
            return;
        }
        // A guest listener owns what happens next; show the implicit-dismiss
        // alert so the next probe step can exercise the default listener.
        display.setCurrent(silent, result);
    }

    protected void pauseApp() { }
    protected void destroyApp(boolean unconditional) { }
}
