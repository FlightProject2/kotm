# Blender MCP bridge

Connects a Claude Code session to a running Blender instance so the asset pipeline —
characters, weapons, vehicles, props destined for the Godot build — can be driven and
inspected directly.

`tools/blender_mcp_bridge.py` is a stdio MCP server that relays tool calls to the
official **Blender Lab MCP add-on** over its TCP socket.

## The one hard requirement

**The bridge must run on the same machine as Blender.** The add-on binds to
`localhost:9876`, so a Claude Code session running in a cloud container has no route to
it and every call fails with `ConnectionRefused`. Check where a session is executing
before debugging anything else — a correct Blender setup fails exactly the same way as a
broken one when the session is remote.

## Setup

1. Install the MCP add-on from <https://www.blender.org/lab/mcp-server> (drag the install
   button onto Blender twice: once to add the Blender Lab repository, once to install).
2. In its preferences, confirm **Server is running**. Host `localhost`, port `9876`, and
   Auto Start on is the expected configuration.
3. Register the bridge, from the repository root:

   ```
   claude mcp add blender -- uv run --script tools/blender_mcp_bridge.py
   ```

   `uv run --script` reads the inline dependency block in the script, so nothing needs
   installing first. Requires [uv](https://docs.astral.sh/uv/); on a machine without it,
   `pip install 'mcp>=1.2'` and register `python tools/blender_mcp_bridge.py` instead.
4. Restart Claude Code and check `claude mcp list` shows `blender` connected.

Environment overrides: `BLENDER_HOST` (default `127.0.0.1`), `BLENDER_PORT` (default
`9876`), `BLENDER_TIMEOUT` in seconds (default `30` — raise it for genuinely slow
operations like heavy renders or bakes).

## Tools

| Tool | What it does |
|---|---|
| `blender_execute` | Runs Python inside Blender. The code must assign a dict to `result`; that dict comes back. `bpy` is available. |
| `blender_get_scene` | Scene summary: version, `.blend` path, frame range, render engine, and the first 100 objects with type and location. |

## Do not use the community package

`uvx blender-mcp` (the community [`ahujasid/blender-mcp`](https://github.com/ahujasid/blender-mcp))
targets a *different* add-on that speaks a different wire format. Pointed at the official
Blender Lab add-on it fails, typically with `Incomplete JSON response received`. The
official add-on uses null-byte-framed JSON:

```
-> {"type": "execute", "code": "<python>", "strict_json": true}\0
<- {"status": "ok", "result": {...}}\0
<- {"status": "error", "message": "..."}\0
```

The code is run through `exec()` inside Blender, and whatever it assigns to `result` is
returned. `strict_json` decides whether a non-serialisable `result` is an error or is
coerced with `repr()`.

## Tests

```
uv run --script tools/test_blender_mcp_bridge.py
```

Stands up a stand-in for the add-on — same framing, same `exec`-and-read-`result`
semantics, backed by a fake `bpy` — and drives the bridge through a real MCP stdio
client. Covers the wire framing, the MCP handshake, both tools, the scene code, errors
raised inside Blender, and the connection-refused path. Runs without Blender, and passes
against both `mcp` 1.x and 2.x. Only real `bpy` behaviour is out of scope.
