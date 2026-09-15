# Changelog

## 2.1.0

- Arrivals board: a departure-board list of the coding agents running on this
  machine under the countdown. Agent, project and branch, what it is doing
  now as flip letters in the active board style, elapsed time, and a status
  chip: WORKING, NEEDS YOU, or IDLE.
- Hold: moving the pointer onto the card keeps the popup open with the
  countdown paused. Move off to dismiss. Clicking a row focuses that agent's
  terminal.
- Adapters for Claude Code and Codex read session state and transcripts for
  tool names only. OpenCode, Aider, Gemini CLI, Goose, Amp, Cursor, and
  Copilot CLI are recognised generically by CPU activity and window title, and
  any other process name can be added in the panel.
- New settings `agentsBoard` (default on, hides when nothing is running) and
  `agentsExtra`.
- Every flip board now renders letters, not only digits.
- Fix: on Omarchy 4.0.3 the popup could appear over a running screensaver after
  a shell reload, because the plugin no longer receives the idle service proxy.
  The screensaver window is now detected directly from Hyprland's window events
  and the popup hides within a moment of it opening.

## 2.0.0

- Five flip boards to choose from: Solari, Vestaboard, Drum, Sweep, and Stepped.
- New `flipStyle` setting; the default `random` plays a different board each time
  the warning appears, and previews tour the boards in order.
- Popup redrawn as a flat station board: hairline rules, no extra radius, a
  darker well behind the tiles, blinking status marks, board name in the header.
- Settings panel redesigned in the same language: status readout in the header,
  a live miniature board that previews on click, a flip-style picker, lean
  timeline rows with inline presets, and a footer row for placement and preview.
- Hovering a style in the picker shows it on the miniature board after a short
  dwell, with a crossfade between boards; clicking it selects it. The
  miniature and the Preview button run the desktop preview.
- Work with Omarchy 4.0.3's scoped plugin API: read the bar entry from
  `shell.barConfig`, fall back to the entry-only settings write when the shell
  refuses whole-config mutation. Without this the countdown never armed and
  settings never saved on 4.0.3.

## 1.0.1

- Stop and suppress the countdown as soon as Omarchy starts the screensaver.
- Suppress countdown and preview surfaces while the session is locking or locked.
- Defer to Omarchy's authoritative idle lifecycle after plugin reloads mid-cycle.

## 1.0.0

- Theme-aware mechanical split-flap countdown popup.
- Native Omarchy bar widget and settings panel.
- Configurable warning, screensaver, and lock deadlines.
- 15-second, 30-second, and one-minute slider snapping.
- One-click timing presets and interactive placement picker.
- Live ten-second preview using the real flap animation.
- Passive click-through overlay that disappears on activity.
- Stay Awake and idle-inhibitor support.
- Focused-monitor targeting with safe placement on smaller displays.
- Defensive handling for malformed and lock-before-screensaver timelines.
- Shared, executable configuration logic tests and release checks.
