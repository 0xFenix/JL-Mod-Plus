import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.util.Enumeration;

import javax.microedition.io.Connector;
import javax.microedition.io.file.FileConnection;
import javax.microedition.io.file.FileSystemRegistry;
import javax.microedition.midlet.MIDlet;

/** Exercise the JSR-75 file protocol: roots, create, read, rename, list, delete. */
public class FileProbe extends MIDlet {

    protected void startApp() {
        new Thread() {
            public void run() {
                probe();
                notifyDestroyed();
            }
        }.start();
    }

    private void probe() {
        try {
            System.out.println("[FILE] loadProtocol=" + load("org.mini.net.file.Protocol"));
            System.out.println("[FILE] loadLcdui=" + load("javax.microedition.lcdui.Form"));
            Enumeration roots = FileSystemRegistry.listRoots();
            while (roots.hasMoreElements()) {
                System.out.println("[FILE] root=" + roots.nextElement());
            }

            FileConnection conn = (FileConnection) Connector.open("file:///root/probe.txt", Connector.READ_WRITE);
            System.out.println("[FILE] url=" + conn.getURL() + " exists=" + conn.exists());
            if (conn.exists()) {
                conn.delete();
            }
            conn.create();
            DataOutputStream out = conn.openDataOutputStream();
            out.writeUTF("hello-file");
            out.close();
            System.out.println("[FILE] size=" + conn.fileSize() + " path=" + conn.getPath());

            DataInputStream in = conn.openDataInputStream();
            String text = in.readUTF();
            in.close();
            System.out.println("[FILE] read=" + text);

            conn.rename("probe2.txt");
            System.out.println("[FILE] renamed name=" + conn.getName() + " exists=" + conn.exists());

            FileConnection rootDir = (FileConnection) Connector.open("file:///root/", Connector.READ_WRITE);
            System.out.println("[FILE] rootDir=" + rootDir.getURL() + " isDir=" + rootDir.isDirectory());
            System.out.println("[FILE] listing=" + names(rootDir.list()));

            FileConnection dir = (FileConnection) Connector.open("file:///root/probe-dir/", Connector.READ_WRITE);
            if (!dir.exists()) {
                dir.mkdir();
            }
            System.out.println("[FILE] mkdir exists=" + dir.exists() + " isDir=" + dir.isDirectory());
            dir.setFileConnection("..");
            System.out.println("[FILE] parent=" + dir.getURL());
            dir.setFileConnection("probe-dir");
            dir.delete();

            conn.delete();
            System.out.println("[FILE] cleaned exists=" + conn.exists());
            System.out.println("[FILE] done");
        } catch (Throwable failure) {
            System.out.println("[FILE] FAILED " + failure);
        }
    }

    private static String load(String name) {
        try {
            Class type = Class.forName(name);
            return "ok " + type.getName();
        } catch (Throwable failure) {
            return "failed " + failure;
        }
    }

    private static String names(Enumeration entries) {
        StringBuffer buffer = new StringBuffer();
        while (entries != null && entries.hasMoreElements()) {
            buffer.append(entries.nextElement()).append(' ');
        }
        return buffer.toString();
    }

    protected void pauseApp() {
    }

    protected void destroyApp(boolean unconditional) {
    }
}
