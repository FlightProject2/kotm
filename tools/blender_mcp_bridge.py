#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=1.2"]
# ///
"""stdio MCP bridge to the official Blender Lab MCP add-on.

The add-on (blender.org/lab/mcp-server, "MCP server add-on for LLM interaction")
listens on a TCP socket and speaks null-byte-framed JSON:

    -> {"type": "execute", "code": "<python>", "strict_json": true}\0
    <- {"status": "ok", "result": {...}}\0
    <- {"status": "error", "message": "..."}\0

The code runs through exec() inside Blender and must assign a dict to a name
called `result`; that dict is what comes back. This differs from the community
`blender-mcp` package, which targets a different add-on and fails against this
one with "Incomplete JSON response received".

Usage (from the machine Blender is running on):

    claude mcp add blender -- uv run --script tools/blender_mcp_bridge.py

Environment: BLENDER_HOST (default 127.0.0.1), BLENDER_PORT (default 9876),
BLENDER_TIMEOUT in seconds (default 30).
"""
import json
import os
import socket

try:  # mcp >= 2.0 renamed FastMCP to MCPServer; the decorator API is unchanged.
    from mcp.server.mcpserver import MCPServer as _Server
except ModuleNotFoundError:  # mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

HOST = os.environ.get("BLENDER_HOST", "127.0.0.1")
PORT = int(os.environ.get("BLENDER_PORT", "9876"))
TIMEOUT = float(os.environ.get("BLENDER_TIMEOUT", "30"))

SCENE_CODE = """
import bpy
scene = bpy.context.scene
result = {
    "blender_version": bpy.app.version_string,
    "filepath": bpy.data.filepath,
    "scene_name": scene.name,
    "frame_range": [scene.frame_start, scene.frame_end, scene.frame_current],
    "render_engine": scene.render.engine,
    "object_count": len(scene.objects),
    "objects": [
        {
            "name": o.name,
            "type": o.type,
            "location": [round(c, 4) for c in o.location],
            "visible": o.visible_get(),
        }
        for o in scene.objects
    ][:100],
}
"""


def blender_request(code, strict_json=False):
    """Run one execute request against the add-on. Never raises; errors come
    back in the same {"status": "error"} shape the add-on itself uses."""
    payload = json.dumps(
        {"type": "execute", "code": code, "strict_json": strict_json}
    ).encode("utf-8") + b"\0"
    try:
        sock = socket.create_connection((HOST, PORT), timeout=TIMEOUT)
    except OSError as exc:
        return {
            "status": "error",
            "message": (
                f"Cannot reach Blender at {HOST}:{PORT} ({exc.__class__.__name__}: {exc}). "
                "Check that Blender is open, that the MCP add-on's preferences show "
                "'Server is running', and that this bridge is running on the same "
                "machine as Blender."
            ),
        }
    try:
        sock.settimeout(TIMEOUT)
        sock.sendall(payload)
        buf = bytearray()
        while b"\0" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                return {
                    "status": "error",
                    "message": "Blender closed the connection before sending a complete "
                    f"reply. Partial data: {bytes(buf[:400])!r}",
                }
            buf.extend(chunk)
        raw = bytes(buf[: buf.index(b"\0")])
    except socket.timeout:
        return {
            "status": "error",
            "message": f"Blender did not reply within {TIMEOUT:g}s. Long operations can "
            "exceed this; raise BLENDER_TIMEOUT if the work is genuinely slow.",
        }
    except OSError as exc:
        return {"status": "error", "message": f"Socket error talking to Blender: {exc}"}
    finally:
        sock.close()

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        return {
            "status": "error",
            "message": f"Blender sent a reply that is not valid JSON ({exc}): {raw[:400]!r}",
        }


def format_response(resp):
    """Render an add-on reply as the text an MCP client shows."""
    if resp.get("status") == "error":
        lines = [f"ERROR: {resp.get('message', 'unknown error')}"]
    else:
        result = resp.get("result")
        lines = [json.dumps(result, indent=2) if result else "OK (no result assigned)"]
    for stream in ("stdout", "stderr"):
        if resp.get(stream):
            lines.append(f"\n--- {stream} ---\n{resp[stream]}")
    return "\n".join(lines)


mcp = _Server("blender")


@mcp.tool(
    description=(
        "Run Python inside the running Blender instance. The code must assign a dict "
        "to a variable named `result`; that dict is returned. `bpy` is available. "
        "Example: `import bpy\\nresult = {'objects': [o.name for o in bpy.data.objects]}`"
    )
)
def blender_execute(code: str, strict_json: bool = False) -> str:
    """Execute Python in Blender.

    Args:
        code: Python to exec() in Blender; assign a dict to `result`.
        strict_json: Require `result` to be JSON-serialisable rather than falling
            back to repr().
    """
    if not code:
        return "ERROR: `code` is required."
    return format_response(blender_request(code, strict_json))


@mcp.tool(
    description=(
        "Summarise the current Blender scene: version, .blend path, frame range, "
        "render engine, and the first 100 objects with type and location."
    )
)
def blender_get_scene() -> str:
    """Summarise the current Blender scene."""
    return format_response(blender_request(SCENE_CODE, strict_json=True))


if __name__ == "__main__":
    mcp.run("stdio")
