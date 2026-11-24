import javax.microedition.lcdui.*;
import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;

/**
 * Probe for non-Canvas UI: a Form with the item types online games use for
 * login, then a TextBox, then a List. Prints what the runtime does; the
 * screenshots show whether anything renders at all.
 */
public class FormProbe extends MIDlet implements CommandListener {
    private Display display;
    private Form form;
    private TextBox textBox;
    private List list;
    private Alert alert;

    public FormProbe() {
        System.out.println("[FORM] constructor");
    }

    protected void startApp() throws MIDletStateChangeException {
        display = Display.getDisplay(this);
        System.out.println("[FORM] display=" + (display != null ? "ok" : "null"));

        form = new Form("Đăng nhập");
        form.append(new StringItem("Tài khoản", "avatar01"));
        TextField tf = new TextField("Mật khẩu", "", 20, TextField.PASSWORD);
        form.append(tf);
        form.append(new ChoiceGroup("Server", Choice.EXCLUSIVE,
                new String[]{"Server 1", "Server 2"}, null));
        form.addCommand(new Command("OK", Command.OK, 1));
        form.setCommandListener(this);

        textBox = new TextBox("Nhập tên", "abc", 20, TextField.ANY);
        list = new List("Chọn", Choice.IMPLICIT);
        list.append("Mục một", null);
        list.append("Mục hai", null);
        alert = new Alert("Thông báo", "Mất kết nối máy chủ", null, AlertType.WARNING);
        alert.setTimeout(Alert.FOREVER);

        display.setCurrent(form);
        System.out.println("[FORM] setCurrent(form)");

        Thread t = new Thread(new Runnable() {
            public void run() {
                sleep(6000);
                System.out.println("[FORM] -> textBox");
                display.setCurrent(textBox);
                sleep(6000);
                System.out.println("[FORM] -> list");
                display.setCurrent(list);
                sleep(6000);
                System.out.println("[FORM] -> alert");
                display.setCurrent(alert);
                sleep(6000);
                System.out.println("[FORM] -> form");
                display.setCurrent(form);
            }
        });
        t.start();
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            // probe only
        }
    }

    public void commandAction(Command c, Displayable d) {
        System.out.println("[FORM] command " + c.getLabel());
    }

    protected void pauseApp() {}

    protected void destroyApp(boolean unconditional) throws MIDletStateChangeException {}
}
