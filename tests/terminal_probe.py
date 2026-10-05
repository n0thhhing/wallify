"""Run after building: python3 tests/terminal_probe.py [path/to/wallify]."""
import os
import pty
import re
import select
import subprocess
import sys
import termios
import time


def check(response, tmux=False):
    master, slave = pty.openpty()
    original = termios.tcgetattr(slave)
    environment = dict(os.environ, TERM="xterm-256color")
    environment.pop("KITTY_WINDOW_ID", None)
    environment.pop("TMUX", None)
    if tmux:
        environment["TMUX"] = "test"
    child = subprocess.Popen(
        [sys.argv[1] if len(sys.argv) > 1 else "build/bin/wallify", "--cli"],
        stdin=slave, stdout=slave, stderr=subprocess.DEVNULL, env=environment)
    output = bytearray()
    answered = quit_sent = False
    try:
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if select.select([master], [], [], .05)[0]:
                output.extend(os.read(master, 65536))
            query = re.search(rb"i=(\d+),s=1,v=1,a=q,t=d,f=24;AAAA", output)
            if query and not answered:
                answered = True
                if response == "OK":
                    os.write(master, b"\x1b_Gi=0;OK\x1b\\")
                    os.write(master, b"\x1b_Gi=" + query[1] + b";")
                    os.write(master, b"OK\x1b\\\x1b[?62;4c")
                elif response == "attributes":
                    os.write(master, b"\x1b[?62;4c")
                elif response == "error":
                    os.write(master, b"\x1b_Gi=" + query[1] + b";ENOTSUP\x1b\\")
            if b"a=T,f=100" in output and not quit_sent:
                quit_sent = True
                os.write(master, b"q")
            if child.poll() is not None:
                break
        child.wait(timeout=1)
        assert answered, "graphics query was not sent"
        assert child.returncode == (0 if response == "OK" else 1)
        restored = termios.tcgetattr(slave)
        assert restored == original, f"terminal flags were not restored ({response}): {original} -> {restored}"
        assert quit_sent == (response == "OK"), "incorrect capability result"
        assert (b"\x1b[?1049h" in output) == (response == "OK")
        if tmux:
            assert b"\x1bPtmux;\x1b\x1b_G" in output
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        os.close(master)
        os.close(slave)


for reply in ["OK", "attributes", "error", "timeout"]:
    check(reply)
check("OK", tmux=True)
print("Terminal capability probe checks passed")
