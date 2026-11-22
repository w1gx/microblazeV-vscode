#!/usr/bin/env python3
# Author: w1gx
# Date:   2026-11-22

"""Minimal serial terminal (stdlib only, no flow control).

    scripts/console.py [device] [baud]      default: Arty USB-UART, 115200

Quit with Ctrl-].  The Arty's FTDI chip shows up as two ports: the first is
JTAG, the second is the UART, so the default is the second Digilent port.
"""
import glob
import os
import select
import sys
import termios
import tty

BAUDS = {9600: termios.B9600, 19200: termios.B19200, 38400: termios.B38400,
         57600: termios.B57600, 115200: termios.B115200, 230400: termios.B230400,
         460800: termios.B460800, 921600: termios.B921600}


def default_device():
    ports = sorted(glob.glob("/dev/serial/by-id/*Digilent*"))
    uarts = [p for p in ports if p.endswith("-if01-port0")]
    if uarts:
        return uarts[0]
    if ports:
        return ports[-1]
    ttys = sorted(glob.glob("/dev/ttyUSB*"))
    return ttys[1] if len(ttys) > 1 else (ttys[0] if ttys else None)


def open_port(dev, baud):
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attr = termios.tcgetattr(fd)
    attr[0] = 0                                                   # iflag: raw
    attr[1] = 0                                                   # oflag: raw
    attr[2] = termios.CS8 | termios.CREAD | termios.CLOCAL       # 8N1, no RTS/CTS
    attr[3] = 0                                                   # lflag: raw
    attr[4] = attr[5] = BAUDS[baud]
    attr[6][termios.VMIN], attr[6][termios.VTIME] = 0, 0
    termios.tcsetattr(fd, termios.TCSANOW, attr)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def main():
    dev = sys.argv[1] if len(sys.argv) > 1 else default_device()
    baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
    if not dev:
        sys.exit("console: no USB serial port found - is the Arty plugged in?")
    port = open_port(dev, baud)
    print(f"console: {dev} @ {baud} 8N1 - quit with Ctrl-]", file=sys.stderr)

    stdin = sys.stdin.fileno()
    interactive = os.isatty(stdin)
    saved = termios.tcgetattr(stdin) if interactive else None
    try:
        if interactive:
            tty.setraw(stdin)
        watch = [port, stdin] if interactive else [port]
        while True:
            ready, _, _ = select.select(watch, [], [])
            if port in ready:
                data = os.read(port, 4096)
                if data:
                    os.write(sys.stdout.fileno(), data)
            if stdin in ready:
                data = os.read(stdin, 1024)
                if b"\x1d" in data:                               # Ctrl-]
                    break
                os.write(port, data)
    except KeyboardInterrupt:
        pass
    finally:
        if saved:
            termios.tcsetattr(stdin, termios.TCSADRAIN, saved)
        os.close(port)
        print("\nconsole: closed", file=sys.stderr)


if __name__ == "__main__":
    main()
