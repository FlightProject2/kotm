# UI layout tool

The front-end includes a live layout editor for the menu screens. It edits the actual controls
that the game renders, so a layout can be reviewed at the target resolution without replacing the
coded menu with a screenshot.

Open it from **Settings → OPEN UI LAYOUT TOOL**, or press **F10** while a front-end screen is open.
Use the **SCREEN** selector to switch between the lobby, customize, marketplace, leaderboards,
settings, pause and results screens. The **REGION** selector chooses a top-level panel. Drag a
region to move it, drag its solid lower-right corner to resize it, or use the X/Y/width/height and
scale fields for exact values. The visibility checkbox can temporarily hide a region while laying
out another one.

**SAVE LAYOUT** stores all screen layouts in `user://kotm_ui_layout.json`, using normalized
coordinates so the same preset scales with the window. **RESET CODE DEFAULTS** resets only the
currently selected screen. **COPY LAYOUT JSON** and **APPLY PASTED JSON** make it possible to
share a screen preset with another developer or check it into the project later. Existing
`user://kotm_lobby_layout.json` presets are imported automatically as the main-screen layout.
