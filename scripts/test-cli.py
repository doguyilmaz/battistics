#!/usr/bin/env python3
"""Exercise real command processes against isolated IPC; never changes power settings."""
import json
import os
import pty
import select
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
products = root / ".build/xcode/Build/Products/Debug"
assert (products / "BattisticsCore.o").exists(), "Build the app first"


class Server:
    def __init__(self, directory, behavior="normal"):
        self.path = str(Path(directory) / "control.sock")
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.bind(self.path)
        os.chmod(self.path, 0o600)
        self.socket.listen(1)
        self.requests = []
        self.closed = threading.Event()
        self.behavior = behavior
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        connection, _ = self.socket.accept()
        identifier = str(uuid.uuid4())
        try:
            with connection, connection.makefile("rb") as stream:
                for line in stream:
                    request = json.loads(line)
                    self.requests.append(request)
                    operation = request["operation"]
                    if self.behavior == "disconnect" and operation == "heartbeat":
                        return
                    if self.behavior == "busy" or (self.behavior == "expired" and operation == "heartbeat"):
                        reply = {"error": {"code": "busy" if self.behavior == "busy" else "inactive", "message": "Session unavailable"}}
                    else:
                        reply = {"status": {"active": operation != "stop", "sessionID": identifier,
                                            "owner": "this_client", "stopOnThermalPressure": False,
                                            "closedLidAllowed": False}}
                    connection.sendall(json.dumps(reply).encode() + b"\n")
        finally:
            self.closed.set()

    def finish(self):
        assert self.closed.wait(8), "CLI did not release its connection"
        self.thread.join(1)
        self.socket.close()
        os.unlink(self.path)


with tempfile.TemporaryDirectory(prefix="battistics-cli-", dir="/private/tmp") as temporary:
    directory = Path(temporary)
    executable = directory / "command-test"
    subprocess.run([
        "swiftc", "-parse-as-library", "-swift-version", "6", "-I", str(products),
        str(products / "BattisticsCore.o"), "-lsqlite3",
        str(root / "Sources/BattisticsCLI/RunOptions.swift"),
        str(root / "Sources/BattisticsCLI/CommandRunner.swift"),
        str(root / "Sources/BattisticsCLI/CommandProcess.swift"),
        str(root / "Tests/Integration/CommandHarness.swift"), "-o", str(executable),
    ], check=True)

    def start(command, **kwargs):
        return subprocess.Popen([str(executable), temporary, "run", "--", *command], **kwargs)

    server = Server(temporary)
    process = start(["/bin/sh", "-c", 'read value; printf "%s|%s|%s" "$value" "$1" "$CLI_TEST"; exit 7', "sh", "$(not-evaluated)"],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    env={**os.environ, "CLI_TEST": "inherited"}, cwd=temporary)
    out, err = process.communicate(b"stdin works\n", timeout=10)
    assert process.returncode == 7 and out == b"stdin works|$(not-evaluated)|inherited", (process.returncode, out, err)
    server.finish()
    assert [r["operation"] for r in server.requests] == ["start", "stop"]
    assert server.requests[0]["source"] == "command"
    assert server.requests[0]["name"] == "sh"

    server = Server(temporary, "busy")
    marker = directory / "must-not-run"
    process = start(["/usr/bin/touch", str(marker)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    process.communicate(timeout=10)
    assert process.returncode == 69 and not marker.exists()
    server.finish()

    server = Server(temporary)
    process = start(["battistics-nonexistent-command"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    process.communicate(timeout=10)
    assert process.returncode == 127
    server.finish()
    assert server.requests[-1]["operation"] == "stop"

    for number in [signal.SIGINT, signal.SIGTERM, signal.SIGHUP]:
        server = Server(temporary)
        process = start(["/bin/sleep", "60"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert select.select([process.stderr], [], [], 8)[0], "No startup confirmation"
        assert b"started" in process.stderr.readline()
        process.send_signal(number)
        _, err = process.communicate(timeout=10)
        assert process.returncode == 128 + number, (number, process.returncode, err)
        server.finish()
        assert server.requests[-1]["operation"] == "stop"

    server = Server(temporary)
    pid, terminal = pty.fork()
    if pid == 0:
        os.execv(str(executable), [str(executable), temporary, "run", "--", "/bin/sh", "-c",
                                  'printf ready; read value; printf "received:%s" "$value"; exec sleep 60'])
    output = b""
    deadline = time.monotonic() + 8
    try:
        while b"ready" not in output and time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.2)[0]:
                output += os.read(terminal, 4096)
        assert b"ready" in output, output
        os.write(terminal, b"terminal-input\n")
        while b"received:terminal-input" not in output and time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.2)[0]:
                output += os.read(terminal, 4096)
        assert b"received:terminal-input" in output, output
        os.write(terminal, b"\x03")
        while time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.05)[0]:
                try:
                    output += os.read(terminal, 4096)
                except OSError:
                    pass
            waited, status = os.waitpid(pid, os.WNOHANG)
            if waited:
                assert os.waitstatus_to_exitcode(status) == 130, status
                break
            time.sleep(0.05)
        else:
            raise AssertionError("Terminal Ctrl+C did not end command")
    finally:
        os.close(terminal)
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except ProcessLookupError:
            pass
    server.finish()

    for behavior in ["expired", "disconnect"]:
        server = Server(temporary, behavior)
        process = start(["/bin/sh", "-c", "sleep 17; printf completed; exit 3"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = process.communicate(timeout=25)
        assert process.returncode == 3 and out == b"completed", (process.returncode, out, err)
        assert b"Keep Awake ended" in err
        server.finish()
        assert sum(r["operation"] == "start" for r in server.requests) == 1

    print("CLI integration passed: argv, streams, exit codes, startup refusal, signals, lease loss.")
