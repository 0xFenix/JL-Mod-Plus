import javax.microedition.lcdui.Command;
import javax.microedition.lcdui.CommandListener;
import javax.microedition.lcdui.Display;
import javax.microedition.lcdui.Displayable;
import javax.microedition.lcdui.Form;
import javax.microedition.midlet.MIDlet;

// Draws a Form with more commands than fit on a handset, so the host has to
// group the extras.
public class CommandProbe extends MIDlet implements CommandListener {
    private Form form;

    protected void startApp() {
        form = new Form("Nhiều lệnh");
        form.append("Sáu lệnh trên màn hình này.");
        String[] labels = {"Chọn", "Quay lại", "Lưu", "Trợ giúp", "Sao lưu", "Thoát"};
        for (int i = 0; i < labels.length; i++) {
            form.addCommand(new Command(labels[i], Command.SCREEN, i + 1));
        }
        form.setCommandListener(this);
        Display.getDisplay(this).setCurrent(form);
        System.out.println("[CMD] ready " + labels.length);
    }

    public void commandAction(Command c, Displayable d) {
        System.out.println("[CMD] fired " + c.getLabel() + " id=" + c.getPriority());
    }

    protected void pauseApp() {}
    protected void destroyApp(boolean unconditional) {}
}
