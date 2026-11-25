#!/usr/bin/env bash
# Local SOCKS5 servers used to verify the per-tab proxy on a simulator or a
# phone. Port 1080 accepts anonymous clients, 1081 requires user "game" with
# password "secret". Every CONNECT is printed so a run can prove the socket
# really went through the proxy.
#   ./scripts/socks-fixture.sh start|stop
#   ./scripts/socks-fixture.sh foreground      # keeps running in the terminal
set -u

PYTHON="${PYTHON:-python3}"
PIDFILE="${TMPDIR:-/tmp}/rt-socks-fixture.pid"

start() {
    bash "$0" foreground >"${TMPDIR:-/tmp}/rt-socks-fixture.log" 2>&1 &
    echo $! >"$PIDFILE"
    sleep 0.5
    echo "socks fixture: 127.0.0.1:1080 (no auth), 127.0.0.1:1081 (game/secret)"
    echo "log: ${TMPDIR:-/tmp}/rt-socks-fixture.log"
}

stop() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
    pkill -f 'socks-fixture.sh foreground' 2>/dev/null
    echo "socks fixture stopped"
}

if [ "${1:-}" = "start" ]; then
    start
    exit 0
fi
if [ "${1:-}" = "stop" ]; then
    stop
    exit 0
fi

exec "$PYTHON" - <<'PY'
import socket, select, struct, sys, threading

AUTH = {1080: None, 1081: ("game", "secret")}

def read_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("closed")
        data += chunk
    return data

def relay(a, b):
    try:
        while True:
            r, _, _ = select.select([a, b], [], [], 30)
            if not r:
                break
            for src in r:
                dst = b if src is a else a
                data = src.recv(65536)
                if not data:
                    return
                dst.sendall(data)
    except OSError:
        pass
    finally:
        try: a.close()
        except OSError: pass
        try: b.close()
        except OSError: pass

def handle(client, port):
    try:
        ver, nmethods = read_exact(client, 2)
        methods = read_exact(client, nmethods)
        need = AUTH.get(port)
        if need and 2 in methods:
            client.sendall(b"\x05\x02")
            ver, ulen = read_exact(client, 2)
            user = read_exact(client, ulen).decode()
            plen = read_exact(client, 1)[0]
            password = read_exact(client, plen).decode()
            if (user, password) != need:
                print("[SOCKS] auth failed", flush=True)
                client.sendall(b"\x01\x01")
                return
            client.sendall(b"\x01\x00")
        elif 0 in methods:
            client.sendall(b"\x05\x00")
        else:
            client.sendall(b"\x05\xff")
            return
        ver, cmd, rsv, atyp = read_exact(client, 4)
        if atyp == 1:
            host = socket.inet_ntoa(read_exact(client, 4))
        elif atyp == 3:
            length = read_exact(client, 1)[0]
            host = read_exact(client, length).decode()
        else:
            client.sendall(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        target_port = struct.unpack(">H", read_exact(client, 2))[0]
        print("[SOCKS] CONNECT %s:%d via %d" % (host, target_port, port), flush=True)
        try:
            upstream = socket.create_connection((host, target_port), timeout=10)
        except OSError as error:
            print("[SOCKS] failed", error, flush=True)
            client.sendall(b"\x05\x05\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        client.sendall(b"\x05\x00\x00\x01" + socket.inet_aton("127.0.0.1") + b"\x00\x00")
        relay(client, upstream)
    except OSError as error:
        print("[SOCKS] error", error, flush=True)
    finally:
        try: client.close()
        except OSError: pass

def serve(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(16)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle, args=(client, port), daemon=True).start()

for p in AUTH:
    threading.Thread(target=serve, args=(p,), daemon=True).start()
print("[SOCKS] fixture listening on 1080 and 1081", flush=True)
threading.Event().wait()
PY
