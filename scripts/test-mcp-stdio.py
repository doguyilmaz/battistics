#!/usr/bin/env python3
"""Smoke-test the bundled stdio protocol without requesting any power change."""
import json
import os
import selectors
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]) if len(sys.argv) > 1 else root / ".build/xcode/Build/Products/Debug/Battistics.app/Contents/MacOS/battistics-mcp"
process = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
buffer = bytearray()


def send(message):
    process.stdin.write(json.dumps(message).encode() + b"\n")
    process.stdin.flush()


def request(identifier, method, params):
    send({"jsonrpc": "2.0", "id": identifier, "method": method, "params": params})
    while True:
        while b"\n" not in buffer:
            assert selector.select(timeout=10), f"Timed out waiting for {method}"
            chunk = os.read(process.stdout.fileno(), 65536)
            assert chunk, f"Server closed during {method}"
            buffer.extend(chunk)
        line, _, rest = buffer.partition(b"\n")
        buffer[:] = rest
        response = json.loads(line)
        if response.get("id") == identifier:
            assert "error" not in response, response
            return response["result"]


try:
    initialized = request(1, "initialize", {
        "protocolVersion": "2025-11-25", "capabilities": {},
        "clientInfo": {"name": "battistics-contract-test", "version": "1"},
    })
    assert initialized["serverInfo"]["name"] == "battistics"
    assert "tools" in initialized["capabilities"]
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    tools = request(2, "tools/list", {})["tools"]
    assert {tool["name"] for tool in tools} == {"battistics_status", "battistics_start", "battistics_stop"}
    start_schema = next(tool["inputSchema"] for tool in tools if tool["name"] == "battistics_start")
    assert start_schema["properties"]["duration_minutes"]["enum"] == [15, 30, 60, 120, 240, 360, 720]
    invalid = request(3, "tools/call", {"name": "battistics_start", "arguments": {"name": "Invalid task", "duration_minutes": 0}})
    assert invalid["isError"] is True
    assert json.loads(invalid["content"][0]["text"])["error"]["code"] == "invalid_request"
    process.stdin.close()
    assert process.wait(timeout=10) == 0
    print("PASS: bundled MCP initialize, discovery, input schema, error result, and EOF shutdown")
finally:
    selector.close()
    if process.poll() is None:
        process.kill()
        process.wait()
