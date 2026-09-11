# Changelog

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
  dwell, with a crossfade between boards; clicking it previews it on the desktop.
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
