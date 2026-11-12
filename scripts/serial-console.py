#!/usr/bin/env python3
"""Drive the Edge 610 serial console without a serial port on this machine.

The board's console is a CP210x on someone else's desk. scripts/serial-bridge.ps1
turns that COM port into plain TCP; when the two machines sit on different
subnets an HTTP proxy can reach it (CONNECT host:7001).

    # the bridge is on 10.1.2.222:7001, reached through a proxy on localhost
    python scripts/serial-console.py --host 10.1.2.222 --port 7001 \
        --proxy 127.0.0.1:7897 --command "uptime" --command "mwan3 status"

Every command is followed by `echo __RC__$?` and the exit status is checked, so
a half-typed line or a console stuck in grub does not look like success. Pass
--raw to read the line stream instead of running commands.
"""

import argparse
import re
import socket
import sys
import time

MARK = "__RC__"


def connect(host, port, proxy, timeout=15):
    sock = socket.create_connection(proxy, timeout=timeout)
    sock.sendall(f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode())
    head = b""
    while b"\r\n\r\n" not in head:
        chunk = sock.recv(1024)
        if not chunk:
            raise OSError("proxy closed the connection")
        head += chunk
    status = head.split(b"\r\n", 1)[0]
    if b" 200 " not in status:
        raise OSError(status.decode("ascii", "replace"))
    return sock


def drain(sock, quiet=0.8, limit=90.0):
    data = b""
    start = last = time.time()
    while time.time() - start < limit:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            if time.time() - last > quiet:
                break
            continue
        if not chunk:
            break
        data += chunk
        last = time.time()
    return data


def run(sock, command, wait=60.0):
    sock.sendall((command + "\r\n").encode())
    sock.sendall((f"echo {MARK}$?\r\n").encode())
    buf = b""
    deadline = time.time() + wait
    while time.time() < deadline:
        try:
            chunk = sock.recv(8192)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += chunk
        if re.search(rb"__RC__\d", buf):
            time.sleep(0.25)
            sock.settimeout(0.3)
            try:
                while True:
                    chunk = sock.recv(8192)
                    if not chunk:
                        break
                    buf += chunk
            except socket.timeout:
                pass
            sock.settimeout(5)
            break
    text = buf.decode("utf-8", "replace").replace("\r", "")
    ok = bool(re.search(r"__RC__0", text))
    return ok, text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True, help="host running serial-bridge.ps1")
    ap.add_argument("--port", type=int, default=7001, help="bridge port (default 7001)")
    ap.add_argument("--proxy", default="", help="HTTP proxy host:port for a CONNECT tunnel")
    ap.add_argument("--command", action="append", default=[], help="shell command, repeatable")
    ap.add_argument("--raw", action="store_true", help="just read the stream for --seconds")
    ap.add_argument("--seconds", type=float, default=5.0, help="read window for --raw")
    ap.add_argument("--no-echo-off", action="store_true", help="keep the tty echo (useful for puzzles)")
    args = ap.parse_args()

    if args.proxy:
        phost, _, pport = args.proxy.partition(":")
        proxy = (phost, int(pport or 8080))
    else:
        proxy = (args.host, args.port)

    sock = connect(args.host, args.port, proxy)
    sock.settimeout(5)
    drain(sock, quiet=0.5, limit=3)

    if args.raw:
        data = drain(sock, quiet=1.5, limit=args.seconds)
        sys.stdout.write(data.decode("utf-8", "replace").replace("\r", ""))
        return 0

    if not args.no_echo_off:
        run(sock, "stty -echo", wait=10)

    failed = 0
    for command in args.command:
        ok, text = run(sock, command)
        print(f"$ {command}")
        print(text.rstrip())
        print("---")
        if not ok:
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
