#!/usr/bin/env python3
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time


KEYS = {
    "Enter": b"\r",
    "Space": b" ",
    "Esc": b"\x1b",
    "Left": b"\x1b[D",
    "Right": b"\x1b[C",
    "Up": b"\x1b[A",
    "Down": b"\x1b[B",
    "s": b"s",
    "S": b"S",
}


def set_winsize(fd, rows, cols):
    size = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, size)


def read_available(fd):
    while True:
        ready, _, _ = select.select([fd], [], [], 0)
        if not ready:
            return
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return
        if not chunk:
            return
        os.write(sys.stdout.fileno(), chunk)


def main():
    if len(sys.argv) < 2:
        print("usage: drive-demo.py EXE [delay:key ...]", file=sys.stderr)
        return 2

    exe = sys.argv[1]
    actions = sys.argv[2:]
    rows = int(os.environ.get("MIAOU_CAPTURE_ROWS", "28"))
    cols = int(os.environ.get("MIAOU_CAPTURE_COLS", "88"))
    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    env["MIAOU_DRIVER"] = env.get("MIAOU_DRIVER", "matrix")

    master, slave = pty.openpty()
    set_winsize(slave, rows, cols)
    proc = subprocess.Popen(
        [exe],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        cwd=os.getcwd(),
        env=env,
        close_fds=True,
    )
    os.close(slave)

    try:
        time.sleep(1.2)
        read_available(master)
        for action in actions:
            if ":" in action:
                delay, key = action.split(":", 1)
                time.sleep(float(delay))
            else:
                key = action
            os.write(master, KEYS.get(key, key.encode("utf-8")))
            time.sleep(0.45)
            read_available(master)

        deadline = time.time() + 2.0
        while time.time() < deadline:
            read_available(master)
            time.sleep(0.1)
    finally:
        if proc.poll() is None:
            proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                proc.kill()
        read_available(master)
        os.close(master)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
