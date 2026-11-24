#!/bin/bash
# Local network fixtures for the J2ME networking probe (host side, macOS/Linux).
# The iOS simulator shares the host network stack, so 127.0.0.1 inside the app
# reaches these listeners.
#   TCP echo  on 127.0.0.1:9099  (newline-delimited; replies "ECHO <line>")
#   HTTP      on 127.0.0.1:9098  (replies 200 with a short body)
# Usage: ./net-fixtures.sh [start|stop|foreground]
set -e
PIDFILE="${TMPDIR:-/tmp}/jlmodplus-net-fixtures.pid"
PY="${PYTHON:-python3}"

case "${1:-foreground}" in
stop)
    if [ -f "$PIDFILE" ]; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; fi
    pkill -f 'jlmodplus-net-fixtures' 2>/dev/null || true
    echo "fixtures stopped"
    ;;
start)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "already running pid $(cat "$PIDFILE")"; exit 0
    fi
    bash "$0" foreground >"${TMPDIR:-/tmp}/jlmodplus-net-fixtures.log" 2>&1 &
    echo $! > "$PIDFILE"
    sleep 0.5
    echo "fixtures started pid $(cat "$PIDFILE")"
    ;;
foreground)
    exec "$PY" - <<'PYEOF'
import socket, threading

def echo_conn(c, a):
    try:
        buf = b""
        while True:
            d = c.recv(4096)
            if not d:
                break
            buf += d
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                c.sendall(b"ECHO " + line + b"\n")
    except Exception as e:
        print("echo error", e, flush=True)
    finally:
        c.close()

def tcp_echo():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 9099)); s.listen(8)
    print("echo listening 9099", flush=True)
    while True:
        c, a = s.accept()
        threading.Thread(target=echo_conn, args=(c, a), daemon=True).start()

def http_srv():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 9098)); s.listen(8)
    print("http listening 9098", flush=True)
    body = b"OK-FROM-FIXTURE\n"
    while True:
        c, a = s.accept()
        try:
            req = b""
            while b"\r\n\r\n" not in req:
                d = c.recv(4096)
                if not d: break
                req += d
            req_line = req.split(b"\r\n")[0].decode("latin-1")
            print("http request:", req_line, flush=True)
            resp = (b"HTTP/1.1 200 OK\r\n"
                    b"Content-Type: text/plain\r\n"
                    b"Content-Length: " + str(len(body)).encode() + b"\r\n"
                    b"Connection: close\r\n\r\n" + body)
            c.sendall(resp)
        finally:
            c.close()

threading.Thread(target=tcp_echo, daemon=True).start()
threading.Thread(target=http_srv, daemon=True).start()
threading.Event().wait()
PYEOF
    ;;
*)
    echo "usage: $0 [start|stop|foreground]" >&2; exit 1 ;;
esac
