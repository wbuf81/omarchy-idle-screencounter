# Arrivals board: agent activity under the idle countdown

Status: draft for review · Target release: 2.1.0 · Written 2026-09-13

## Goal

When the idle warning comes up, show a departure-board style list of the coding
agents currently running on this machine underneath the countdown: which agent,
which project, what it is doing right now, how long it has been at it, and
whether it is waiting on the user. The rows flip in the same board style the
countdown chose, so the popup stays one instrument. The board can be held open
by hovering it, and clicking a row focuses that agent's terminal.

Mockup approved on 2026-09-13: "01 Arrivals" from the agents board mockups.

## Decisions already made

- Row letters flip in the **active board style**. Bits gains a 5×7 alphabet and
  Drum gains a letter strip so every style can render text.
- **On by default**, hidden when no agent session exists. A toggle lives in the
  settings panel.
- **Clicking a held row focuses that terminal** through Hyprland and dismisses
  the popup.
- Privacy: the board shows tool names, project folder names, branch names, and
  the agent's own window title. It never reads or shows message text.

## Architecture

```
scripts/agents-scan.sh ──JSON──▶ Service.qml (AgentsModel) ◀── Hyprland.toplevels
                                        │  agents[]                 (title, address, pid)
                                        ▼
                                 ArrivalsBoard.qml ──▶ FlipBoard (letters + digits)
                                        │
                                  popup card (hold, click)
```

Four units, each testable on its own:

1. **`scripts/agents-scan.sh`** enumerates agent processes and summarizes their
   sessions as JSON. Pure bash plus coreutils and grep. No Qt.
2. **`Logic.js` additions** turn a raw scan record plus a window title into a
   row: status, labels, elapsed text. Pure JS, covered by the Node tests.
3. **`ArrivalsBoard.qml`** renders rows from a plain list. Pure QtQuick like the
   `Flip*.qml` tiles, so the harness can drive it with sample data.
4. **`Service.qml`** owns the scan `Process`, merges toplevel titles, exposes the
   list, and implements hold and focus on the popup.

## 1. Scan script

`scripts/agents-scan.sh` prints one JSON array. For every process named `claude`
or `codex`:

| Field | Source |
| --- | --- |
| `pid`, `agent` | `pgrep -x`, `/proc/<pid>/comm` |
| `cwd` | `readlink /proc/<pid>/cwd` |
| `started` | mtime of `/proc/<pid>` (epoch seconds) |
| `transcript` | Claude: newest `*.jsonl` in `~/.claude/projects/<cwd with / and . as ->/`. Codex: newest rollout under `~/.codex/sessions/` whose `cwd` matches. |
| `lastActivity` | transcript mtime |
| `branch` | last `"gitBranch"` in the transcript tail |
| `tools` | last four `tool_use` names from the transcript tail (Claude) or `function_call` names (Codex) |
| `lastType` | `type` field of the transcript's final line (`assistant`, `user`, `system`, `progress`, …) |
| `lastHadToolUse` | whether that final assistant message contained a `tool_use` block |

Only the last 400 KB of a transcript is read, so a 15 MB session costs the same
as a fresh one. The prototype ran in 150 ms for four agents. The script prints
`[]` when nothing is running and never fails the caller: a missing directory or
unreadable transcript yields empty fields, not an exit code.

The script lives in the plugin directory so `omarchy plugin add` ships it. It is
invoked with an absolute path resolved from `Qt.resolvedUrl`.

### Other agents: adapters and a generic fallback

The plugin will be shared, so the scan must not assume Claude Code and Codex.
Two layers:

**Adapter table.** The script declares one line per known agent:
`process name · label · session strategy`. Shipping entries:

| Process | Label | Strategy |
| --- | --- | --- |
| `claude` | Claude Code | `claude`: transcript under `~/.claude/projects/<cwd>` |
| `codex` | Codex | `codex`: rollout under `~/.codex/sessions/` matching `cwd` |
| `opencode` | OpenCode | `generic` |
| `aider` | Aider | `generic` |
| `gemini` | Gemini CLI | `generic` |
| `goose` | Goose | `generic` |
| `amp` | Amp | `generic` |
| `cursor-agent` | Cursor | `generic` |
| `copilot` | Copilot CLI | `generic` |

Adding an agent with a transcript format is one strategy function in the
script and one table line. The README carries a short "Adding an agent"
section that says exactly that, plus what the JSON record must contain.

**Generic strategy.** For any agent without a transcript adapter, the record
still carries `pid`, `agent`, `cwd`, `started`, and two fields every process
has: `cpuTicks` (utime + stime from `/proc/<pid>/stat`) and `windowTitle`
(merged later from the toplevel). `Logic.agentStatus` uses them when
transcript fields are absent: `working` if `cpuTicks` grew since the previous
scan, `idle` otherwise, and `needs-you` when the window title carries a
known waiting marker (Claude Code's `✳`, or a `?` prefix). The NOW column shows
the title's first word for generic agents, or `RUNNING`/`IDLE`.

**User-added processes.** A setting `agentsExtra` (comma-separated process
names, default empty) is passed to the script as `AGENTS_EXTRA`. Each name is
treated as a generic agent labelled after itself. The settings panel exposes
it as a text field under the ARRIVALS BOARD toggle.

The script gets one more field, `strategy`, so the row can say how it was
observed, and the Node tests cover status derivation for both transcript and
generic records.

## 2. Logic.js

New pure helpers, all covered in `tests/logic.test.js`:

- `agentStatus(record, nowMs)` returns `"working"`, `"needs-you"`, or `"idle"`.
  - `needs-you`: the last transcript line is an `assistant` message without a
    tool call, or the last tool is `AskUserQuestion`. The agent finished its
    turn and is waiting.
  - `working`: last activity within the last two minutes.
  - `idle`: everything else.
- `agentRow(record, title, nowMs)` returns `{ id, agent, agentLabel, project,
  branch, now, tools, status, elapsed, title }`.
  - `agentLabel`: `"Claude"` or `"Codex"`.
  - `project`: basename of `cwd`.
  - `now`: the last tool name uppercased, at most 11 characters, or
    `"WAITING"` for needs-you, or `"IDLE"` with a compact age (`"IDLE 2D"`).
  - `elapsed`: `MM:SS` since last activity when under an hour, else `H:MM`,
    else `Nd`.
- `sortedAgentRows(rows)` orders needs-you first, then working, then idle, and
  within a group by most recent activity.
- `agentStatus` handles generic records: `cpuTicks` growth against
  `previousCpuTicks` means working; a waiting marker in the title means
  needs-you.
- `normalizedSettings` gains `agentsBoard` (boolean, default `true`) and
  `agentsExtra` (string, default `""`, trimmed, lowercase, comma-separated
  process names); `editedSettings` accepts both.

## 3. ArrivalsBoard.qml

Pure QtQuick. Inputs: `rows` (list of row objects), `style`, the same color and
font properties as `FlipBoard`, `held` (bool), `maxRows` (default 5). Signals:
`focusRequested(string address)`.

Layout, top to bottom:

- Header row: `▪ ARRIVALS` left; `N agents · M working` right, caption size.
- Column captions: AGENT · PROJECT · NOW · ELAPSED · STATUS.
- One row per agent, separated by hairlines:
  - AGENT: agent label in ink, bold.
  - PROJECT: project name, branch dim after a `·`, elided.
  - NOW: `FlipBoard` with `glyphSet: "alnum"`, 11 tiles, small size, in the
    active style.
  - ELAPSED: `FlipBoard` digits, small size, in the active style.
  - STATUS: chip. `working` is accent fill with a blinking block; `needs-you`
    is pink outline with a blinking `!`; `idle` is dim outline.
- More than `maxRows` agents collapses to `maxRows - 1` rows and a `+N more`
  line.
- Held and hovering a row expands a detail line: the last four tools with
  relative ages, and the window title. A row with an `address` shows a pointer
  cursor; clicking emits `focusRequested`.
- Empty `rows` renders nothing and reports `implicitHeight: 0`, so the popup
  falls back to today's height.

## 4. Letter support in the tiles

`FlipBoard` gains `glyphSet: "digits" | "alnum"` and passes it to tiles.

- **FlipSolari**: the chatter ring becomes the glyph set. Letters travel at most
  three steps through the ring before landing, so a word change stays quick.
- **FlipBits**: add 5×7 glyphs for A–Z, `.`, `-`, `·`, `!`, `?`, `/`, `×`, and
  space. Unknown characters render as `?`.
- **FlipDrum**: with `glyphSet: "alnum"` the strip is three copies of
  `A–Z0–9 -.·` and rolls to the nearest occurrence in either direction. Digit
  boards keep the current ten-digit strip.
- **FlipSweep**, **FlipStep**: already glyph-agnostic. No change.

Small tiles (the row cells) use the same components at `tileHeight` around
`Style.space(18)`. The glyph size formula is already proportional.

## 5. Service.qml: model, hold, focus

- `agentsBoard` setting read like `flipStyle`.
- A `Process` runs `agents-scan.sh` when the popup becomes visible and then
  every 5 seconds while it stays visible. It is not run while hidden, so an
  idle desktop costs nothing. `stdout` is collected through `SplitParser`/
  `StdioCollector` and parsed once per run.
- `Hyprland.toplevels` is scanned for a toplevel whose `lastIpcObject.pid`
  equals the record's pid (or whose pid is an ancestor within two hops via
  `/proc/<pid>/stat`, since Claude Code runs under the terminal's shell). The
  match contributes `title` and `address`.
- `agentRows` is the sorted list from Logic. `hasAgents` is `agentRows.length > 0`.
- **Hold.** When the board is showing, the window's `mask` becomes
  `Region { item: card }` so the card receives pointer events and everything
  else stays click-through. A `HoverHandler` on the card sets `held`. While
  held: `popupVisible` stays true even though `IdleMonitor.isIdle` went false,
  the countdown timer stops, the header shows `HELD` in the countdown accent's
  pink counterpart, the "starts in" line reads "Countdown paused while you
  look", and the footer reads "Move off the board to dismiss". Leaving the card
  clears `held`; the popup hides on the next binding pass. A 45-second safety
  timer clears `held` if the pointer parks on the card.
- **Focus.** `focusRequested(address)` runs
  `Hyprland.dispatch("focuswindow address:" + address)` and clears `held`.
- Preview shows the same rows. With no agents running, preview shows two sample
  rows labelled `SAMPLE` in the status column so the setting is discoverable.

## 6. Settings panel

A new row under FLIP STYLE, styled like the timeline rows:

`ARRIVALS BOARD` · caption "Shows running Claude Code and Codex sessions under
the countdown" · a `ToggleSwitch` on the right. The hero miniature does not
render the board; the panel stays compact.

## 7. Manifest, docs, checks

- `manifest.json`: version `2.1.0`, `agentsBoard` and `agentsExtra` defaults
  and schema entries.
- `scripts/static-check.sh`: version bump, `ArrivalsBoard.qml` and
  `scripts/agents-scan.sh` in the file list, `bash -n` on the scan script, and
  a `grep` that `Service.qml` references `agents-scan.sh`.
- README: a section "Arrivals board" with what it shows, what it reads, and the
  privacy statement. CHANGELOG entry. Maintainer notes: the pid-to-toplevel
  matching rule and the hold mask.

## Error handling

- Scan script failure or malformed JSON: `agentRows` becomes empty, the board
  hides, the countdown is unaffected. Logged once per failure.
- A toplevel with no matching pid: row still shows, without focus affordance.
- Hyprland absent (`Hyprland.toplevels` empty): rows show, no focus.
- Hold while the screensaver or lock activates: the existing suppression wins;
  `held` is cleared.

## Testing

- `tests/logic.test.js`: status derivation for each branch, row formatting,
  sorting, elapsed formats, settings normalization.
- `tests/agents-scan.test.sh`: runs the script against a fixture `HOME` with a
  fake transcript and asserts the JSON shape with `jq`. Process enumeration is
  exercised only when a `claude` or `codex` process exists; the fixture test
  covers the parsing paths.
- Harness: `scripts/harness/` (not shipped) drives `ArrivalsBoard.qml` with the
  mockup's sample rows in all five styles for a visual check.
- Manual: hold and release, click to focus, needs-you ordering, five-plus
  agents collapse, preview with and without agents, toggle off.

## Out of scope

Keyboard navigation on the overlay, model names per session (not reliably
available without reading message content), transcript adapters for agents
other than Claude Code and Codex (they get the generic strategy), and showing
the board in the settings panel miniature.
