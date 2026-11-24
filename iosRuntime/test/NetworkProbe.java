import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

import javax.microedition.io.Connector;
import javax.microedition.io.HttpConnection;
import javax.microedition.io.SocketConnection;
import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;

/**
 * Networking probe: verifies the J2ME socket and HTTP paths that online games use.
 * Prints one [NET] line per check, then exits.
 */
public class NetworkProbe extends MIDlet {

    private static final String HOST = "127.0.0.1";
    private static final int ECHO_PORT = 9099;
    private static final int HTTP_PORT = 9098;

    protected void startApp() throws MIDletStateChangeException {
        new Thread(new Runnable() {
            public void run() {
                probeSocket();
                probeHttp();
                probePublicSocket();
                probeHttps();
                System.out.println("[NET] done");
                notifyDestroyed();
            }
        }).start();
    }

    private void probeSocket() {
        SocketConnection sc = null;
        try {
            sc = (SocketConnection) Connector.open("socket://" + HOST + ":" + ECHO_PORT);
            System.out.println("[NET] socket connected local=" + sc.getLocalAddress() + ":"
                    + sc.getLocalPort() + " remote=" + sc.getAddress() + ":" + sc.getPort());
            OutputStream out = sc.openOutputStream();
            out.write("PING\n".getBytes());
            out.flush();
            DataInputStream in = sc.openDataInputStream();
            StringBuffer sb = new StringBuffer();
            int c;
            while ((c = in.read()) != -1) {
                if (c == '\n') break;
                sb.append((char) c);
            }
            System.out.println("[NET] socket echo=" + sb);
        } catch (Throwable t) {
            System.out.println("[NET] socket FAILED " + t);
        } finally {
            closeQuietly(sc);
        }
    }

    private void probeHttp() {
        HttpConnection hc = null;
        try {
            hc = (HttpConnection) Connector.open("http://" + HOST + ":" + HTTP_PORT + "/probe?a=1");
            hc.setRequestMethod(HttpConnection.GET);
            hc.setRequestProperty("X-Probe", "jlmodplus");
            int code = hc.getResponseCode();
            String type = hc.getType();
            System.out.println("[NET] http code=" + code + " type=" + type
                    + " len=" + hc.getLength());
            InputStream in = hc.openInputStream();
            byte[] buf = new byte[64];
            int n = in.read(buf);
            System.out.println("[NET] http body=" + (n > 0 ? new String(buf, 0, n) : "<empty>"));
        } catch (Throwable t) {
            System.out.println("[NET] http FAILED " + t);
        } finally {
            closeQuietly(hc);
        }
    }

    /**
     * Raw socket to a public host, which is what a game server connection looks
     * like. Proves the socket path works over the internet; the LAN probe above
     * only works when iOS allows local network access.
     */
    private void probePublicSocket() {
        SocketConnection sc = null;
        try {
            sc = (SocketConnection) Connector.open("socket://example.com:80");
            OutputStream out = sc.openOutputStream();
            out.write("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n".getBytes());
            out.flush();
            DataInputStream in = sc.openDataInputStream();
            StringBuffer sb = new StringBuffer();
            int c;
            while ((c = in.read()) != -1) {
                if (c == '\n') break;
                sb.append((char) c);
            }
            System.out.println("[NET] public socket status=" + sb.toString().trim());
        } catch (Throwable t) {
            System.out.println("[NET] public socket FAILED " + t);
        } finally {
            closeQuietly(sc);
        }
    }

    private void probeHttps() {
        HttpConnection hc = null;
        try {
            hc = (HttpConnection) Connector.open("https://example.com/");
            int code = hc.getResponseCode();
            System.out.println("[NET] https code=" + code + " len=" + hc.getLength());
        } catch (Throwable t) {
            System.out.println("[NET] https FAILED " + t);
        } finally {
            closeQuietly(hc);
        }
    }

    private static void closeQuietly(Object c) {
        try {
            if (c instanceof SocketConnection) ((SocketConnection) c).close();
            else if (c instanceof HttpConnection) ((HttpConnection) c).close();
        } catch (Throwable ignored) {
        }
    }

    protected void pauseApp() {
    }

    protected void destroyApp(boolean unconditional) throws MIDletStateChangeException {
    }
}
