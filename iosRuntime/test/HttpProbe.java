import javax.microedition.io.Connector;
import javax.microedition.io.HttpConnection;
import javax.microedition.midlet.MIDlet;
import java.io.InputStream;
import java.io.InputStreamReader;

public class HttpProbe extends MIDlet {
    private static final String URL = "http://upxu.net";

    protected void startApp() {
        System.out.println("[HTTP] probing " + URL);
        HttpConnection c = null;
        try {
            c = (HttpConnection) Connector.open(URL, Connector.READ_WRITE, true);
            int code = c.getResponseCode();
            String type = c.getType();
            long len = c.getLength();
            System.out.println("[HTTP] code=" + code + " type=" + type + " len=" + len);
            InputStream in = c.openInputStream();
            StringBuilder sb = new StringBuilder();
            int ch;
            while ((ch = in.read()) != -1 && sb.length() < 200) {
                sb.append((char) ch);
            }
            in.close();
            System.out.println("[HTTP] body=" + sb);
        } catch (Throwable t) {
            System.out.println("[HTTP] FAILED " + t);
        } finally {
            try { if (c != null) c.close(); } catch (Exception ignored) {}
        }
        System.out.println("[HTTP] done");
        notifyDestroyed();
    }

    protected void pauseApp() {}
    protected void destroyApp(boolean unconditional) {}
}
