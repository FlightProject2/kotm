#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=1.2"]
# ///
"""Exercise tools/blender_mcp_bridge.py end to end without Blender.

Stands up a TCP server that mimics the official Blender Lab add-on — same
null-byte-framed JSON, same exec()-and-read-`result` semantics, backed by a
fake `bpy` — then drives the bridge through a real MCP stdio client session.
That covers the wire framing, the MCP handshake, both tools, the scene code
itself, and the failure paths. Only real bpy behaviour is out of scope.

    uv run --script tools/test_blender_mcp_bridge.py
"""
import asyncio
import json
import os
import socketserver
import sys
import threading
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

BRIDGE = Path(__file__).resolve().parent / "blender_mcp_bridge.py"


# --- a fake bpy, just deep enough for the bridge's scene code ----------------
class FakeObject:
    def __init__(self, name, type_, location):
        self.name, self.type, self.location = name, type_, location

    def visible_get(self):
        return True


class FakeScene:
    name = "Scene"
    frame_start, frame_end, frame_current = 1, 250, 7
    render = type("Render", (), {"engine": "BLENDER_EEVEE_NEXT"})()
    objects = [
        FakeObject("Cube", "MESH", [0.0, 0.0, 0.0]),
        FakeObject("Light", "LIGHT", [4.076, 1.005, 5.904]),
        FakeObject("Camera", "CAMERA", [7.358, -6.926, 4.958]),
    ]


class FakeBpy:
    app = type("App", (), {"version_string": "5.2.0"})()
    data = type("Data", (), {"filepath": "/tmp/kotm_assets.blend", "objects": FakeScene.objects})()
    context = type("Context", (), {"scene": FakeScene()})()


sys.modules["bpy"] = FakeBpy()  # so `import bpy` inside exec() finds the fake


def run_code(code, strict_json):
    """Mimic the add-on: exec the code, hand back whatever `result` holds."""
    namespace = {}
    try:
        exec(code, namespace)
    except Exception as exc:
        return {"status": "error", "message": f"{type(exc).__name__}: {exc}"}
    result = namespace.get("result")
    if result is None:
        return {"status": "ok", "result": {}}
    try:
        json.dumps(result)
    except TypeError:
        if strict_json:
            return {"status": "error", "message": "result is not JSON-serialisable"}
        result = repr(result)
    return {"status": "ok", "result": result}


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        buf = bytearray()
        while b"\0" not in buf:
            chunk = self.request.recv(65536)
            if not chunk:
                return
            buf.extend(chunk)
        req = json.loads(bytes(buf[: buf.index(b"\0")]))
        if req.get("type") != "execute":
            resp = {"status": "error", "message": f"unknown type {req.get('type')!r}"}
        else:
            resp = run_code(req.get("code", ""), req.get("strict_json", False))
        self.request.sendall(json.dumps(resp).encode() + b"\0")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


# --- the checks -------------------------------------------------------------
FAILURES = []


def as_json(text):
    """Parse a tool payload, or {} so the check fails with the text in view."""
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {}


def check(label, condition, detail=""):
    print(f"  {'PASS' if condition else 'FAIL'}  {label}")
    if not condition:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        if detail:
            print(f"        {detail}")


async def session_for(port):
    env = dict(os.environ, BLENDER_HOST="127.0.0.1", BLENDER_PORT=str(port), BLENDER_TIMEOUT="10")
    return stdio_client(StdioServerParameters(command=sys.executable, args=[str(BRIDGE)], env=env))


async def main():
    server = Server(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"stand-in add-on listening on 127.0.0.1:{port}\n")

    print("connected to a running add-on:")
    async with await session_for(port) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            names = sorted(t.name for t in (await session.list_tools()).tools)
            check("handshake + tool listing", names == ["blender_execute", "blender_get_scene"], str(names))

            text = (await session.call_tool("blender_get_scene")).content[0].text
            scene = as_json(text)
            check("blender_get_scene reports the version", scene.get("blender_version") == "5.2.0", text[:200])
            check("blender_get_scene lists objects",
                  [o.get("name") for o in scene.get("objects", [])] == ["Cube", "Light", "Camera"], text[:200])
            check("blender_get_scene reports frame range", scene.get("frame_range") == [1, 250, 7], text[:200])

            text = (await session.call_tool(
                "blender_execute",
                {"code": "import bpy\nresult = {'n': len(bpy.data.objects)}"},
            )).content[0].text
            check("blender_execute returns the result dict", as_json(text) == {"n": 3}, text[:200])

            text = (await session.call_tool(
                "blender_execute", {"code": "result = 1 / 0"}
            )).content[0].text
            check("errors inside Blender surface as errors",
                  text.startswith("ERROR:") and "ZeroDivisionError" in text, text[:200])

            text = (await session.call_tool("blender_execute", {"code": ""})).content[0].text
            check("empty code is rejected", text.startswith("ERROR:"), text[:200])

    server.shutdown()

    print("\nwhen Blender is not reachable:")
    async with await session_for(1) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            text = (await session.call_tool("blender_get_scene")).content[0].text
            check("refused connection explains itself",
                  text.startswith("ERROR:") and "Cannot reach Blender" in text
                  and "same machine" in text, text[:200])

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) failed:")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
