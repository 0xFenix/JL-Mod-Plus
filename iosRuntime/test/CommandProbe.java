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
        // The four soft-key types a handset keeps on screen, plus two extras
        // that have to hide behind the options menu.
        form.addCommand(new Command("Chọn", Command.OK, 1));
        form.addCommand(new Command("Quay lại", Command.BACK, 2));
        form.addCommand(new Command("Huỷ", Command.CANCEL, 3));
        form.addCommand(new Command("Thoát", Command.EXIT, 4));
        form.addCommand(new Command("Trợ giúp", Command.SCREEN, 5));
        form.addCommand(new Command("Sao lưu", Command.SCREEN, 6));
        form.setCommandListener(this);
        Display.getDisplay(this).setCurrent(form);
        System.out.println("[CMD] ready " + form.size());
    }

    public void commandAction(Command c, Displayable d) {
        System.out.println("[CMD] fired " + c.getLabel() + " id=" + c.getPriority());
    }

    protected void pauseApp() {}
    protected void destroyApp(boolean unconditional) {}
}
