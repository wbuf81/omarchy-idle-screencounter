# Arrivals Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a departure-board list of running coding agents under the idle countdown, flipping in the active board style, holdable by hover, with click-to-focus.

**Architecture:** A bash scan script summarizes agent processes as JSON; pure Logic.js turns records into rows with status; a pure-QtQuick `ArrivalsBoard.qml` renders rows with the existing `FlipBoard`; `Service.qml` runs the scan, merges Hyprland toplevels, and implements hold and focus.

**Tech Stack:** Quickshell QML (Quickshell.Io Process, Quickshell.Hyprland), bash + coreutils + grep, Node for tests, jq for the script test.

**Spec:** `docs/superpowers/specs/2026-09-13-arrivals-board-design.md`

## Global Constraints

- Version becomes `2.1.0` in `manifest.json` and `scripts/static-check.sh` together.
- `FlipBoard.qml`, `Flip*.qml`, and `ArrivalsBoard.qml` import only `QtQuick`; theme values arrive as properties.
- The board shows tool names, folder names, branch names, and window titles. Never message text.
- The scan runs only while the popup is visible, every 5 seconds.
- `Style.cornerRadius` is used as-is. Captions are uppercase with letter spacing. Hairline rules, no cards inside the card.
- Commit after every task with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- After editing `Service.qml`, run `./scripts/dev-sync.sh`, wait at least 3 seconds, then `omarchy-restart-shell`. Never restart within 3 seconds of a sync.

## Research facts the code relies on

- Claude Code writes `~/.claude/sessions/<pid>.json`: `{ pid, sessionId, cwd, startedAt (ms), name, status: "busy"|"idle", updatedAt (ms) }`. The transcript is `~/.claude/projects/<cwd with / and . replaced by ->/<sessionId>.jsonl`.
- Claude Code sets the terminal title to a status glyph plus a summary. Spinner glyphs `◐◓◑◒` mean busy; `✳` means waiting for input. The summary text also appears inside the transcript, which lets the scan attribute a title to a session by `grep -F`.
- Ghostty runs every window in one process, so Hyprland's client `pid` is the same for all terminals. `HyprlandToplevel.lastIpcObject.pid` gives it; a Claude process's ancestry is `claude → bash → ghostty`.
- Codex rollouts live at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`; the first line is `session_meta` with `payload.cwd`.
- Prototype scan of four agents took 150 ms reading 400 KB tails.

---

### Task 1: Settings for the board

**Files:**
- Modify: `Logic.js` (normalizedSettings, editedSettings, exports)
- Test: `tests/logic.test.js`

**Interfaces:**
- Produces: settings keys `agentsBoard: boolean` (default `true`) and `agentsExtra: string` (default `""`, normalized to lowercase comma-separated process names without spaces); `Logic.normalizedAgentsExtra(value) -> string`.

- [ ] **Step 1: Write the failing tests**

Append before `console.log("logic tests passed")` in `tests/logic.test.js`:

```js
// Arrivals board settings.
assert.equal(Logic.normalizedSettings({}, id).agentsBoard, true)
assert.equal(Logic.normalizedSettings({ agentsBoard: false }, id).agentsBoard, false)
assert.equal(Logic.normalizedSettings({}, id).agentsExtra, "")
assert.equal(Logic.normalizedAgentsExtra(" Aider, opencode ,,GOOSE "), "aider,opencode,goose")
assert.equal(Logic.normalizedAgentsExtra("bad name;rm -rf"), "")
assert.equal(Logic.editedSettings({}, {}, "agentsBoard", false, id).agentsBoard, false)
assert.equal(Logic.editedSettings({}, {}, "agentsExtra", "Aider, goose", id).agentsExtra, "aider,goose")
```

- [ ] **Step 2: Run to verify failure**

Run: `node tests/logic.test.js`
Expected: `TypeError: Logic.normalizedAgentsExtra is not a function` (or an assertion on `agentsBoard`).

- [ ] **Step 3: Implement**

In `Logic.js`, add after `normalizedPlacement`:

```js
// Extra process names the user wants treated as agents. Only plain
// executable names survive: letters, digits, dot, dash, underscore.
function normalizedAgentsExtra(value) {
  var parts = String(value || "").toLowerCase().split(",")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var name = parts[i].replace(/^\s+|\s+$/g, "")
    if (name !== "" && /^[a-z0-9._-]+$/.test(name) && out.indexOf(name) === -1) out.push(name)
  }
  return out.join(",")
}
```

In `normalizedSettings`, add defaults `agentsBoard: true, agentsExtra: ""` to the `Object.assign` object and, after the `flipStyle` line:

```js
  normalized.agentsBoard = normalized.agentsBoard !== false
  normalized.agentsExtra = normalizedAgentsExtra(normalized.agentsExtra)
```

In `editedSettings`, change the assignment line to:

```js
  var stringKeys = ["placement", "flipStyle", "agentsExtra"]
  var boolKeys = ["enabled", "agentsBoard"]
  next[key] = boolKeys.indexOf(key) !== -1 ? !!value : (stringKeys.indexOf(key) !== -1 ? String(value) : Math.round(Number(value)))
```

Export `normalizedAgentsExtra`.

- [ ] **Step 4: Run tests**

Run: `node tests/logic.test.js` → `logic tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Logic.js tests/logic.test.js
git commit -m "Add agentsBoard and agentsExtra settings" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Row and status helpers

**Files:**
- Modify: `Logic.js`
- Test: `tests/logic.test.js`

**Interfaces:**
- Consumes: a scan record `{ pid, agent, label, strategy, cwd, started (s), lastActivity (s), branch, tools: string[], sessionStatus: "busy"|"idle"|"", cpuTicks: number, windowTitle: string }` and a toplevel merge `{ title, address }`.
- Produces:
  - `Logic.AGENT_WAIT_MARKERS = ["✳", "?"]`
  - `Logic.agentStatus(record, nowMs, previousCpuTicks) -> "working"|"needs-you"|"idle"`
  - `Logic.agentNow(record, status, nowMs) -> string` (≤ 11 chars, uppercase)
  - `Logic.elapsedLabel(fromMs, nowMs) -> string` (`MM:SS`, `H:MM`, `Nd`)
  - `Logic.agentRow(record, top, nowMs, previousCpuTicks) -> { id, agent, agentLabel, project, branch, now, tools, status, elapsed, title, address, pid }`
  - `Logic.sortedAgentRows(rows) -> rows`

- [ ] **Step 1: Write the failing tests**

```js
// Agent status.
var now = Date.parse("2026-09-13T18:40:00Z")
var busy = { pid: 1, agent: "claude", label: "Claude Code", strategy: "claude", cwd: "/home/wes/Projects/omarchy-idle-screencounter", started: 1789157806, lastActivity: Math.floor(now / 1000) - 20, branch: "main", tools: ["Bash", "Write"], sessionStatus: "busy", cpuTicks: 100, windowTitle: "◐ Vestaboard flipper animations" }
assert.equal(Logic.agentStatus(busy, now), "working")
var waiting = Object.assign({}, busy, { sessionStatus: "idle", lastActivity: Math.floor(now / 1000) - 300, windowTitle: "✳ Health stuff weekly updates" })
assert.equal(Logic.agentStatus(waiting, now), "needs-you")
var stale = Object.assign({}, waiting, { lastActivity: Math.floor(now / 1000) - 3 * 3600, windowTitle: "" })
assert.equal(Logic.agentStatus(stale, now), "idle")
var asked = Object.assign({}, busy, { sessionStatus: "idle", tools: ["Bash", "AskUserQuestion"] })
assert.equal(Logic.agentStatus(asked, now), "needs-you")
var generic = { pid: 2, agent: "aider", label: "Aider", strategy: "generic", cwd: "/home/wes/x", started: 1, lastActivity: 0, branch: "", tools: [], sessionStatus: "", cpuTicks: 500, windowTitle: "aider" }
assert.equal(Logic.agentStatus(generic, now, 480), "working")
assert.equal(Logic.agentStatus(generic, now, 500), "idle")
assert.equal(Logic.agentStatus(Object.assign({}, generic, { windowTitle: "? aider needs input" }), now, 500), "needs-you")

// NOW column and elapsed.
assert.equal(Logic.agentNow(busy, "working", now), "WRITE")
assert.equal(Logic.agentNow(waiting, "needs-you", now), "WAITING")
assert.equal(Logic.agentNow(stale, "idle", now), "IDLE 3H")
assert.equal(Logic.agentNow(generic, "working", now), "RUNNING")
assert.equal(Logic.agentNow(Object.assign({}, busy, { tools: ["mcp__plugin_playwright__browser_navigate"] }), "working", now), "MCP PLUGIN")
assert.equal(Logic.elapsedLabel(now - 65 * 1000, now), "01:05")
assert.equal(Logic.elapsedLabel(now - 2 * 3600 * 1000 - 5 * 60000, now), "2:05")
assert.equal(Logic.elapsedLabel(now - 3 * 86400 * 1000, now), "3d")

// Rows and ordering.
var row = Logic.agentRow(busy, { title: "◐ Vestaboard flipper animations", address: "0x1" }, now)
assert.equal(row.agentLabel, "Claude Code")
assert.equal(row.project, "omarchy-idle-screencounter")
assert.equal(row.status, "working")
assert.equal(row.address, "0x1")
assert.equal(row.title, "Vestaboard flipper animations")
var rows = Logic.sortedAgentRows([
  Logic.agentRow(stale, null, now),
  Logic.agentRow(busy, null, now),
  Logic.agentRow(waiting, null, now)
])
assert.deepEqual(rows.map(function(r) { return r.status }), ["needs-you", "working", "idle"])
```

- [ ] **Step 2: Run to verify failure**

Run: `node tests/logic.test.js` → `TypeError: Logic.agentStatus is not a function`.

- [ ] **Step 3: Implement**

Add to `Logic.js` after `flipStyleForShow`:

```js
var AGENT_WAIT_MARKERS = ["✳", "?"]
var AGENT_BUSY_GLYPHS = ["◐", "◓", "◑", "◒", "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
var WORKING_WINDOW_MS = 2 * 60 * 1000
var WAITING_WINDOW_MS = 30 * 60 * 1000

function titleMarker(title) {
  var text = String(title || "").replace(/^\s+/, "")
  return text === "" ? "" : text.charAt(0)
}

function stripTitleGlyph(title) {
  return String(title || "").replace(/^[^A-Za-z0-9]+\s*/, "")
}

// One of "working", "needs-you", "idle". Transcript-backed agents lean on the
// session status file; generic agents lean on CPU movement and the title.
function agentStatus(record, nowMs, previousCpuTicks) {
  var r = record || {}
  var marker = titleMarker(r.windowTitle)
  var lastMs = numberOr(r.lastActivity, 0) * 1000
  var recent = lastMs > 0 && nowMs - lastMs <= WORKING_WINDOW_MS
  var tools = Array.isArray(r.tools) ? r.tools : []
  var lastTool = tools.length ? String(tools[tools.length - 1]) : ""
  if (r.sessionStatus === "busy") return "working"
  if (AGENT_BUSY_GLYPHS.indexOf(marker) !== -1) return "working"
  if (lastTool === "AskUserQuestion") return "needs-you"
  if (AGENT_WAIT_MARKERS.indexOf(marker) !== -1 && (lastMs === 0 || nowMs - lastMs <= WAITING_WINDOW_MS)) return "needs-you"
  if (r.sessionStatus === "idle" && lastMs > 0 && nowMs - lastMs <= WAITING_WINDOW_MS) return "needs-you"
  if (r.strategy === "generic" || !r.strategy) {
    var prev = numberOr(previousCpuTicks, -1)
    if (prev >= 0 && numberOr(r.cpuTicks, 0) > prev) return "working"
    return "idle"
  }
  return recent ? "working" : "idle"
}

function compactAge(fromMs, nowMs) {
  var s = Math.max(0, Math.floor((nowMs - fromMs) / 1000))
  if (s < 60) return s + "S"
  if (s < 3600) return Math.floor(s / 60) + "M"
  if (s < 86400) return Math.floor(s / 3600) + "H"
  return Math.floor(s / 86400) + "D"
}

// The NOW column: at most 11 uppercase characters.
function agentNow(record, status, nowMs) {
  var r = record || {}
  if (status === "needs-you") return "WAITING"
  if (status === "idle") {
    var lastMs = numberOr(r.lastActivity, 0) * 1000
    return lastMs > 0 ? ("IDLE " + compactAge(lastMs, nowMs)).slice(0, 11) : "IDLE"
  }
  var tools = Array.isArray(r.tools) ? r.tools : []
  if (tools.length) {
    var name = String(tools[tools.length - 1]).replace(/^mcp__/, "MCP ").replace(/__.*$/, "").replace(/[_-]+/g, " ")
    return name.toUpperCase().slice(0, 11)
  }
  return "RUNNING"
}

function elapsedLabel(fromMs, nowMs) {
  var s = Math.max(0, Math.floor((nowMs - fromMs) / 1000))
  if (s >= 86400) return Math.floor(s / 86400) + "d"
  if (s >= 3600) return Math.floor(s / 3600) + ":" + (Math.floor((s % 3600) / 60) < 10 ? "0" : "") + Math.floor((s % 3600) / 60)
  return (Math.floor(s / 60) < 10 ? "0" : "") + Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
}

function agentRow(record, top, nowMs, previousCpuTicks) {
  var r = record || {}
  var t = top || {}
  var status = agentStatus(r, nowMs, previousCpuTicks)
  var lastMs = numberOr(r.lastActivity, 0) * 1000
  var startMs = numberOr(r.started, 0) * 1000
  var cwd = String(r.cwd || "")
  var project = cwd.replace(/\/+$/, "").split("/").pop() || cwd || "?"
  return {
    id: String(r.agent || "") + ":" + String(r.pid || ""),
    pid: numberOr(r.pid, 0),
    agent: String(r.agent || ""),
    agentLabel: String(r.label || r.agent || "Agent"),
    project: project,
    branch: String(r.branch || ""),
    now: agentNow(r, status, nowMs),
    tools: Array.isArray(r.tools) ? r.tools.slice(-4) : [],
    status: status,
    lastActivity: lastMs,
    elapsed: elapsedLabel(lastMs > 0 ? lastMs : startMs, nowMs),
    title: stripTitleGlyph(t.title || r.windowTitle || ""),
    address: String(t.address || "")
  }
}

function sortedAgentRows(rows) {
  var order = { "needs-you": 0, working: 1, idle: 2 }
  return (rows || []).slice().sort(function(a, b) {
    var byStatus = order[a.status] - order[b.status]
    if (byStatus !== 0) return byStatus
    return numberOr(b.lastActivity, 0) - numberOr(a.lastActivity, 0)
  })
}
```

Export: `AGENT_WAIT_MARKERS, agentStatus, agentNow, elapsedLabel, agentRow, sortedAgentRows, stripTitleGlyph`.

- [ ] **Step 4: Run tests** → `logic tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Logic.js tests/logic.test.js
git commit -m "Add agent status and row helpers" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Scan script

**Files:**
- Create: `scripts/agents-scan.sh`
- Create: `tests/agents-scan.test.sh`
- Modify: `scripts/static-check.sh` (run the new test, `bash -n` the script)

**Interfaces:**
- Produces: `scripts/agents-scan.sh` prints a JSON array of records `{ pid, agent, label, strategy, cwd, started, lastActivity, branch, tools, sessionStatus, cpuTicks, windowTitle }`. Environment: `AGENTS_EXTRA` (comma list of extra process names), `AGENTS_TITLES` (newline-separated `pid<TAB>title` candidate titles to attribute), `AGENTS_SCAN_HOME` (overrides `$HOME`, for tests), `AGENTS_SCAN_LIBRARY=1` (define functions only, for tests).

- [ ] **Step 1: Write the failing test**

`tests/agents-scan.test.sh`:

```bash
#!/usr/bin/env bash
# Exercises the record builders against a fixture home. Process enumeration
# needs a live agent, so this covers parsing, not pgrep.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/.claude/sessions" "$fixture/.claude/projects/-home-wes-Projects-demo.app" "$fixture/.codex/sessions/2026/09/13"
cat > "$fixture/.claude/sessions/4242.json" <<'JSON'
{"pid":4242,"sessionId":"abc-123","cwd":"/home/wes/Projects/demo.app","startedAt":1789324406662,"name":"demo-app-1","status":"idle","updatedAt":1789324720849}
JSON
transcript="$fixture/.claude/projects/-home-wes-Projects-demo.app/abc-123.jsonl"
printf '%s\n' \
  '{"type":"user","cwd":"/home/wes/Projects/demo.app","gitBranch":"feature/x","message":{"role":"user","content":"Fix the thing"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{}}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. Title hint: Demo app cleanup"}]}}' > "$transcript"
cat > "$fixture/.codex/sessions/2026/09/13/rollout-2026-09-13T10-00-00-xyz.jsonl" <<'JSON'
{"timestamp":"2026-09-13T10:00:00Z","type":"session_meta","payload":{"session_id":"xyz","cwd":"/home/wes/Projects/ledger"}}
{"timestamp":"2026-09-13T10:00:05Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}
{"timestamp":"2026-09-13T10:00:09Z","type":"response_item","payload":{"type":"function_call","name":"apply_patch","arguments":"{}"}}
JSON

export AGENTS_SCAN_HOME="$fixture" AGENTS_SCAN_LIBRARY=1
# shellcheck source=../scripts/agents-scan.sh
source "$here/../scripts/agents-scan.sh"

record=$(AGENTS_TITLES=$'4242\t✳ Demo app cleanup\n4242\t✳ Other window' summarize_claude 4242 /home/wes/Projects/demo.app 1789324406 12345)
echo "$record" | jq -e '.agent == "claude" and .strategy == "claude" and .branch == "feature/x" and .sessionStatus == "idle" and .cpuTicks == 12345 and (.tools == ["Read","Edit"]) and .windowTitle == "✳ Demo app cleanup"' >/dev/null

record=$(summarize_codex 777 /home/wes/Projects/ledger 1789324406 5)
echo "$record" | jq -e '.agent == "codex" and .strategy == "codex" and (.tools == ["shell","apply_patch"]) and .lastActivity > 0' >/dev/null

record=$(summarize_generic 888 aider Aider /home/wes/Projects/anything 1789324406 9)
echo "$record" | jq -e '.agent == "aider" and .label == "Aider" and .strategy == "generic" and .tools == [] and .cpuTicks == 9' >/dev/null

# No processes match in the fixture, so the full scan prints an empty array.
out=$(AGENTS_SCAN_LIBRARY= bash "$here/../scripts/agents-scan.sh")
test "$out" = "[]" || { echo "expected [] from an idle scan, got: $out" >&2; exit 1; }

echo "agents-scan tests passed"
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/agents-scan.test.sh` → fails, `scripts/agents-scan.sh: No such file or directory`.

- [ ] **Step 3: Write the script**

`scripts/agents-scan.sh`:

```bash
#!/usr/bin/env bash
# Summarize running coding agents as JSON for the Arrivals board.
#
# Output: one JSON array. Each record:
#   pid, agent (process name), label, strategy (claude|codex|generic), cwd,
#   started (epoch s), lastActivity (epoch s, 0 unknown), branch, tools
#   (last four tool names), sessionStatus (busy|idle|""), cpuTicks
#   (utime+stime from /proc), windowTitle (attributed from AGENTS_TITLES).
#
# Environment:
#   AGENTS_EXTRA       comma-separated extra process names, treated as generic
#   AGENTS_TITLES      newline-separated "pid<TAB>title" candidates; a title is
#                      attributed to a Claude session when its text appears in
#                      the transcript tail
#   AGENTS_SCAN_HOME   overrides $HOME (tests)
#   AGENTS_SCAN_LIBRARY  when non-empty, only define functions (tests)
#
# The script never reads message text into its output: only tool names,
# branch, cwd, timestamps, and the caller-supplied titles leave this file.
set -uo pipefail

home="${AGENTS_SCAN_HOME:-$HOME}"
tail_bytes=400000

# process name | label | strategy
AGENT_TABLE="claude|Claude Code|claude
codex|Codex|codex
opencode|OpenCode|generic
aider|Aider|generic
gemini|Gemini CLI|generic
goose|Goose|generic
amp|Amp|generic
cursor-agent|Cursor|generic
copilot|Copilot CLI|generic"

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}

json_string_array() {
  local out="" item
  for item in "$@"; do
    [[ -z $item ]] && continue
    out+="${out:+,}\"$(json_escape "$item")\""
  done
  printf '[%s]' "$out"
}

cpu_ticks_for() {
  local stat
  stat=$(cat "/proc/$1/stat" 2>/dev/null) || { printf '0'; return; }
  stat=${stat##*) }
  set -- $stat
  printf '%s' $(( ${12:-0} + ${13:-0} ))
}

# Claude's title summary appears inside the transcript. Return the first
# candidate title for this pid whose text (glyph stripped) is in the tail.
attribute_title() {
  local pid=$1 transcript=$2 line tpid title text
  [[ -z ${AGENTS_TITLES:-} || -z $transcript || ! -r $transcript ]] && return
  while IFS=$'\t' read -r tpid title; do
    [[ $tpid != "$pid" && $tpid != any ]] && continue
    text=$(printf '%s' "$title" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//')
    [[ -z $text ]] && continue
    if tail -c "$tail_bytes" "$transcript" | grep -qF -- "$text"; then
      printf '%s' "$title"
      return
    fi
  done <<< "$AGENTS_TITLES"
}

emit_record() {
  # pid agent label strategy cwd started lastActivity branch sessionStatus cpuTicks windowTitle tools...
  local pid=$1 agent=$2 label=$3 strategy=$4 cwd=$5 started=$6 last=$7 branch=$8 status=$9 cpu=${10} title=${11}
  shift 11
  printf '{"pid":%s,"agent":"%s","label":"%s","strategy":"%s","cwd":"%s","started":%s,"lastActivity":%s,"branch":"%s","tools":%s,"sessionStatus":"%s","cpuTicks":%s,"windowTitle":"%s"}' \
    "${pid:-0}" "$(json_escape "$agent")" "$(json_escape "$label")" "$strategy" "$(json_escape "$cwd")" \
    "${started:-0}" "${last:-0}" "$(json_escape "$branch")" "$(json_string_array "$@")" "$status" "${cpu:-0}" "$(json_escape "$title")"
}

summarize_claude() {
  local pid=$1 cwd=$2 started=$3 cpu=$4
  local session="$home/.claude/sessions/$pid.json" sid status transcript last="" branch="" title=""
  local tools=()
  if [[ -r $session ]]; then
    sid=$(grep -oE '"sessionId":"[^"]+"' "$session" | head -1 | cut -d'"' -f4)
    status=$(grep -oE '"status":"[^"]+"' "$session" | head -1 | cut -d'"' -f4)
  fi
  local projdir="$home/.claude/projects/$(printf '%s' "$cwd" | sed 's#[/.]#-#g')"
  if [[ -n ${sid:-} && -r "$projdir/$sid.jsonl" ]]; then
    transcript="$projdir/$sid.jsonl"
  else
    transcript=$(ls -t "$projdir"/*.jsonl 2>/dev/null | head -1)
  fi
  if [[ -n $transcript ]]; then
    last=$(stat -c %Y "$transcript" 2>/dev/null)
    mapfile -t tools < <(tail -c "$tail_bytes" "$transcript" | grep -oE '"type":"tool_use","id":"[^"]+","name":"[A-Za-z0-9_]+"' | grep -oE '"name":"[A-Za-z0-9_]+"' | tail -4 | cut -d'"' -f4)
    branch=$(tail -c 20000 "$transcript" | grep -oE '"gitBranch":"[^"]*"' | tail -1 | cut -d'"' -f4)
    title=$(attribute_title "$pid" "$transcript")
  fi
  emit_record "$pid" claude "Claude Code" claude "$cwd" "$started" "${last:-0}" "$branch" "${status:-}" "$cpu" "$title" "${tools[@]}"
}

summarize_codex() {
  local pid=$1 cwd=$2 started=$3 cpu=$4 transcript="" last="" f
  local tools=()
  for f in $(ls -t "$home"/.codex/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -40); do
    if head -c 4000 "$f" | grep -qF "\"cwd\":\"$cwd\""; then transcript=$f; break; fi
  done
  if [[ -n $transcript ]]; then
    last=$(stat -c %Y "$transcript" 2>/dev/null)
    mapfile -t tools < <(tail -c "$tail_bytes" "$transcript" | grep -oE '"type":"function_call"[^}]{0,300}"name":"[A-Za-z0-9_]+"' | grep -oE '"name":"[A-Za-z0-9_]+"' | tail -4 | cut -d'"' -f4)
  fi
  emit_record "$pid" codex Codex codex "$cwd" "$started" "${last:-0}" "" "" "$cpu" "" "${tools[@]}"
}

summarize_generic() {
  local pid=$1 agent=$2 label=$3 cwd=$4 started=$5 cpu=$6
  emit_record "$pid" "$agent" "$label" generic "$cwd" "$started" 0 "" "" "$cpu" ""
}

scan() {
  local table="$AGENT_TABLE" extra name records=() line proc label strategy pid cwd started cpu
  for name in ${AGENTS_EXTRA//,/ }; do
    [[ $name =~ ^[a-z0-9._-]+$ ]] || continue
    grep -q "^$name|" <<< "$table" || table+=$'\n'"$name|$name|generic"
  done
  while IFS='|' read -r proc label strategy; do
    [[ -z $proc ]] && continue
    for pid in $(pgrep -x -- "$proc" 2>/dev/null); do
      cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null) || continue
      started=$(stat -c %Y "/proc/$pid" 2>/dev/null || printf 0)
      cpu=$(cpu_ticks_for "$pid")
      case $strategy in
        claude) records+=("$(summarize_claude "$pid" "$cwd" "$started" "$cpu")") ;;
        codex) records+=("$(summarize_codex "$pid" "$cwd" "$started" "$cpu")") ;;
        *) records+=("$(summarize_generic "$pid" "$proc" "$label" "$cwd" "$started" "$cpu")") ;;
      esac
    done
  done <<< "$table"
  local joined="" r
  for r in "${records[@]}"; do joined+="${joined:+,}$r"; done
  printf '[%s]\n' "$joined"
}

if [[ -z ${AGENTS_SCAN_LIBRARY:-} ]]; then
  scan
fi
```

Then `chmod +x scripts/agents-scan.sh tests/agents-scan.test.sh`.

- [ ] **Step 4: Run the test** → `agents-scan tests passed`. Also run the real scan: `./scripts/agents-scan.sh | jq .` and confirm records for the live agents, each with `cpuTicks > 0`.

- [ ] **Step 5: Wire into static-check**

In `scripts/static-check.sh`: add `scripts/agents-scan.sh` and `tests/agents-scan.test.sh` to the `for entrypoint in` list; change the `bash -n` line to include `scripts/agents-scan.sh tests/agents-scan.test.sh`; add `bash tests/agents-scan.test.sh` after `node tests/logic.test.js`. Run `./scripts/static-check.sh`.

- [ ] **Step 6: Commit**

```bash
git add scripts/agents-scan.sh tests/agents-scan.test.sh scripts/static-check.sh
git commit -m "Add the agents scan script with adapters and a generic fallback" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Letters in every board style

**Files:**
- Modify: `FlipBoard.qml`, `FlipSolari.qml`, `FlipBits.qml`, `FlipDrum.qml`
- Test: visual, via a harness under the scratchpad (not shipped)

**Interfaces:**
- Produces: `FlipBoard.glyphSet: "digits"|"alnum"` (default `"digits"`), forwarded to every tile as `glyphSet`. Tiles accept any character; `"alnum"` boards render `A–Z 0–9 space . - · ! ? / ×`.

- [ ] **Step 1: FlipBoard forwards the glyph set**

Add `property string glyphSet: "digits"` and, in the `onLoaded` bindings, `item.glyphSet = Qt.binding(function() { return board.glyphSet })`. Also pass it as an initial property in `load()`: `setSource(board.styleSource, { character: character, glyphSet: board.glyphSet })`.

- [ ] **Step 2: Solari chatters along the glyph ring**

In `FlipSolari.qml`, add `property string glyphSet: "digits"` and replace the digit-only step computation in `animateTo` with:

```qml
  readonly property string ring: glyphSet === "alnum" ? " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-·!?/×" : "0123456789"

  function stepsBetween(from, to) {
    var a = ring.indexOf(from), b = ring.indexOf(to)
    if (a === -1 || b === -1) return [to]
    var n = ring.length
    var forward = ((b - a) % n + n) % n
    var backward = ((a - b) % n + n) % n
    // Digits travel downward like a real drum; letters take the short way,
    // capped so a word change never chatters for long.
    var cap = glyphSet === "alnum" ? 3 : 10
    var out = []
    if (glyphSet !== "alnum") {
      for (var i = 1; i <= backward; i++) out.push(ring.charAt((a - i + n) % n))
    } else if (forward <= backward) {
      var count = Math.min(forward, cap)
      for (var f = 1; f < count; f++) out.push(ring.charAt((a + f) % n))
      out.push(to)
    } else {
      var count2 = Math.min(backward, cap)
      for (var g = 1; g < count2; g++) out.push(ring.charAt((a - g + n) % n))
      out.push(to)
    }
    return out
  }
```

and in `animateTo`, replace the `if (isNaN(a) || isNaN(b)) … else { … }` block with:

```qml
    var last = pending.length ? pending[pending.length - 1] : current
    var steps = stepsBetween(last, next)
    for (var i = 0; i < steps.length; i++) pending.push(steps[i])
```

- [ ] **Step 3: Bits gets an alphabet**

In `FlipBits.qml`, add `property string glyphSet: "digits"` and extend `glyphs` with:

```qml
    "A": ["01110","10001","10001","11111","10001","10001","10001"],
    "B": ["11110","10001","10001","11110","10001","10001","11110"],
    "C": ["01110","10001","10000","10000","10000","10001","01110"],
    "D": ["11100","10010","10001","10001","10001","10010","11100"],
    "E": ["11111","10000","10000","11110","10000","10000","11111"],
    "F": ["11111","10000","10000","11110","10000","10000","10000"],
    "G": ["01110","10001","10000","10111","10001","10001","01111"],
    "H": ["10001","10001","10001","11111","10001","10001","10001"],
    "I": ["01110","00100","00100","00100","00100","00100","01110"],
    "J": ["00111","00010","00010","00010","00010","10010","01100"],
    "K": ["10001","10010","10100","11000","10100","10010","10001"],
    "L": ["10000","10000","10000","10000","10000","10000","11111"],
    "M": ["10001","11011","10101","10101","10001","10001","10001"],
    "N": ["10001","10001","11001","10101","10011","10001","10001"],
    "O": ["01110","10001","10001","10001","10001","10001","01110"],
    "P": ["11110","10001","10001","11110","10000","10000","10000"],
    "Q": ["01110","10001","10001","10001","10101","10010","01101"],
    "R": ["11110","10001","10001","11110","10100","10010","10001"],
    "S": ["01111","10000","10000","01110","00001","00001","11110"],
    "T": ["11111","00100","00100","00100","00100","00100","00100"],
    "U": ["10001","10001","10001","10001","10001","10001","01110"],
    "V": ["10001","10001","10001","10001","10001","01010","00100"],
    "W": ["10001","10001","10001","10101","10101","10101","01010"],
    "X": ["10001","10001","01010","00100","01010","10001","10001"],
    "Y": ["10001","10001","10001","01010","00100","00100","00100"],
    "Z": ["11111","00001","00010","00100","01000","10000","11111"],
    ".": ["00000","00000","00000","00000","00000","01100","01100"],
    "-": ["00000","00000","00000","11111","00000","00000","00000"],
    "·": ["00000","00000","00000","01100","01100","00000","00000"],
    "!": ["00100","00100","00100","00100","00100","00000","00100"],
    "/": ["00001","00010","00010","00100","01000","01000","10000"],
    "×": ["00000","10001","01010","00100","01010","10001","00000"],
```

Uppercase lookups: change `readonly property var glyph: glyphs[character] || glyphs["?"]` to `glyphs[String(character).toUpperCase()] || glyphs["?"]`.

- [ ] **Step 4: Drum gets a letter strip**

In `FlipDrum.qml`, add `property string glyphSet: "digits"` and:

```qml
  readonly property string ring: glyphSet === "alnum" ? " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-·!?/×" : "0123456789"
  readonly property int ringLength: ring.length
  readonly property bool isDigit: ring.indexOf(character) !== -1 && !isColon
```

Replace every `10 +`, `% 10`, and `parseInt(character, 10)` in the roll logic with ring arithmetic: `index = ringLength + ring.indexOf(character)`, `if (index % ringLength === d) return`, and pick the nearest direction:

```qml
    var d = ring.indexOf(character)
    var cur = index % ringLength
    var down = ((cur - d) % ringLength + ringLength) % ringLength
    var up = ((d - cur) % ringLength + ringLength) % ringLength
    var target = glyphSet === "alnum" && up < down ? index + up : index - down
```

The Repeater model becomes `tile.copies * tile.ringLength`, each cell's text `ring.charAt(index % ringLength)`, and the recenter line `tile.index = tile.ringLength + tile.index % tile.ringLength`.

- [ ] **Step 5: Visual check**

Create a scratch harness (outside the repo) that loads `FlipBoard.qml` five times with `glyphSet: "alnum"`, `tileWidth: 14`, `tileHeight: 20`, cycling `value` through `"WRITE PANEL"`, `"BASH ×4"`, `"WAITING"`, `"IDLE 3H"` every 1.5 s, grabbing a PNG per second. Confirm letters render in all five styles and the Solari chatter is ≤ 3 steps.

- [ ] **Step 6: Run `./scripts/static-check.sh` and commit**

```bash
git add FlipBoard.qml FlipSolari.qml FlipBits.qml FlipDrum.qml
git commit -m "Let every flip board render letters" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: ArrivalsBoard.qml

**Files:**
- Create: `ArrivalsBoard.qml`

**Interfaces:**
- Consumes: rows from `Logic.sortedAgentRows` (`{ id, agentLabel, project, branch, now, tools, status, elapsed, title, address }`), `FlipBoard` with `glyphSet`.
- Produces: `ArrivalsBoard { rows, style, held, maxRows, foreground, accent, alert, dim, line, well, fontFamily, captionSize, bodySize, animated }` with `signal focusRequested(string address)`; `implicitHeight` is 0 when `rows` is empty.

- [ ] **Step 1: Write the component**

```qml
import QtQuick

// The Arrivals board: one departure-board row per running coding agent.
// Pure QtQuick. Rows come in already sorted; every theme value is a property.
Item {
  id: board

  property var rows: []
  property string style: "solari"
  property bool held: false
  property int maxRows: 5
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property color alert: "#f776c6"
  property color dim: "#565f89"
  property color line: "#2f3349"
  property color well: "#1a1b26"
  property string fontFamily: "monospace"
  property real captionSize: 10
  property real bodySize: 11
  property bool animated: true

  signal focusRequested(string address)

  readonly property int shown: rows.length > maxRows ? maxRows - 1 : rows.length
  readonly property int hidden: rows.length - shown
  readonly property int working: rows.filter(function(r) { return r.status === "working" }).length
  readonly property int needing: rows.filter(function(r) { return r.status === "needs-you" }).length
  readonly property real rowHeight: Math.round(bodySize * 2.9)
  readonly property real cell: Math.round(bodySize * 1.8)

  implicitWidth: 460
  implicitHeight: rows.length === 0 ? 0 : column.implicitHeight

  component Caption: Text {
    textFormat: Text.PlainText
    color: board.dim
    font.family: board.fontFamily
    font.pixelSize: board.captionSize
    font.letterSpacing: 1.4
    font.capitalization: Font.AllUppercase
    elide: Text.ElideRight
  }

  component Chip: Rectangle {
    property string status: "idle"
    readonly property bool isWorking: status === "working"
    readonly property bool isNeeds: status === "needs-you"
    implicitWidth: chipText.implicitWidth + 12
    implicitHeight: chipText.implicitHeight + 4
    color: isWorking ? board.accent : "transparent"
    border.color: isWorking ? board.accent : (isNeeds ? board.alert : board.line)
    border.width: 1
    Row {
      anchors.centerIn: parent
      spacing: 4
      Rectangle {
        visible: chip.isWorking || chip.isNeeds
        width: 5; height: chipText.implicitHeight * 0.7
        anchors.verticalCenter: parent.verticalCenter
        color: chip.isWorking ? board.well : board.alert
        SequentialAnimation on opacity {
          running: board.visible && (chip.isWorking || chip.isNeeds)
          loops: Animation.Infinite
          PropertyAction { value: 1 }
          PauseAnimation { duration: chip.isNeeds ? 350 : 500 }
          PropertyAction { value: 0 }
          PauseAnimation { duration: chip.isNeeds ? 350 : 500 }
        }
      }
      Caption {
        id: chipText
        text: chip.isWorking ? "Working" : (chip.isNeeds ? "Needs you" : "Idle")
        color: chip.isWorking ? board.well : (chip.isNeeds ? board.alert : board.dim)
        font.letterSpacing: 1.0
        font.pixelSize: board.captionSize - 1
      }
    }
    property alias chip: chipSelf
    id: chipSelf
  }

  Column {
    id: column
    width: parent.width
    spacing: 4
    visible: board.rows.length > 0

    Item {
      width: parent.width
      height: headLeft.implicitHeight
      Row {
        id: headLeft
        spacing: 6
        Rectangle { width: 5; height: 5; anchors.verticalCenter: parent.verticalCenter; color: board.accent }
        Caption { text: "Arrivals"; color: board.foreground; font.bold: true }
      }
      Caption {
        anchors.right: parent.right
        text: board.rows.length + (board.rows.length === 1 ? " agent" : " agents") + " · " + board.working + " working" + (board.needing > 0 ? " · " + board.needing + " waiting" : "")
      }
    }

    // Column captions share the row grid below.
    Item {
      width: parent.width
      height: colHead.implicitHeight + 3
      Row {
        id: colHead
        width: parent.width
        spacing: 8
        Caption { width: board.width * 0.15; text: "Agent" }
        Caption { width: board.width * 0.27; text: "Project" }
        Caption { width: board.cell * 0.62 * 11 + 10; text: "Now" }
        Caption { width: board.cell * 0.62 * 5 + 4; text: "Elapsed" }
        Caption { text: "Status" }
      }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: board.line }
    }

    Repeater {
      model: board.shown
      delegate: Item {
        id: rowItem
        required property int index
        readonly property var row: board.rows[index]
        readonly property bool hovered: hover.hovered && board.held
        width: column.width
        height: board.rowHeight + (hovered ? detail.implicitHeight + 6 : 0)

        HoverHandler { id: hover }
        TapHandler {
          enabled: board.held && rowItem.row.address !== ""
          onTapped: board.focusRequested(rowItem.row.address)
        }

        Row {
          id: cells
          width: parent.width
          height: board.rowHeight
          spacing: 8
          Text {
            width: board.width * 0.15
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.row.agentLabel
            color: board.foreground
            font.family: board.fontFamily
            font.pixelSize: board.bodySize
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: board.width * 0.27
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: rowItem.row.project + (rowItem.row.branch !== "" ? " · " + rowItem.row.branch : "")
            color: board.dim
            font.family: board.fontFamily
            font.pixelSize: board.bodySize
            elide: Text.ElideRight
          }
          FlipBoard {
            anchors.verticalCenter: parent.verticalCenter
            value: rowItem.row.now.padEnd(11, " ")
            style: board.style
            glyphSet: "alnum"
            tileWidth: Math.round(board.cell * 0.62)
            tileHeight: board.cell
            gap: 1
            colonWidth: tileWidth
            foreground: board.foreground
            accent: board.accent
            dim: board.dim
            line: board.line
            well: board.well
            fontFamily: board.fontFamily
            animated: board.animated
          }
          FlipBoard {
            anchors.verticalCenter: parent.verticalCenter
            value: rowItem.row.elapsed.padStart(5, " ")
            style: board.style
            glyphSet: "alnum"
            tileWidth: Math.round(board.cell * 0.62)
            tileHeight: board.cell
            gap: 1
            colonWidth: Math.round(tileWidth * 0.5)
            foreground: board.foreground
            accent: board.accent
            dim: board.dim
            line: board.line
            well: board.well
            fontFamily: board.fontFamily
            animated: board.animated
          }
          Chip { anchors.verticalCenter: parent.verticalCenter; status: rowItem.row.status }
        }

        Caption {
          id: detail
          visible: rowItem.hovered
          anchors.top: cells.bottom
          width: parent.width
          font.capitalization: Font.MixedCase
          font.letterSpacing: 0.2
          text: (rowItem.row.tools.length ? "Last: " + rowItem.row.tools.join(" › ") : "No tool calls seen")
            + (rowItem.row.title !== "" ? "  ·  “" + rowItem.row.title + "”" : "")
            + (rowItem.row.address !== "" ? "  ·  click to focus" : "")
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: board.line }
        Rectangle { anchors.fill: parent; color: board.accent; opacity: rowItem.hovered ? 0.06 : 0; z: -1 }
      }
    }

    Caption {
      visible: board.hidden > 0
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "+" + board.hidden + " more"
    }
  }
}
```

Note: the `Chip` component's `id`/alias dance above is awkward; simplify to `id: chip` at the top of the component body and drop the alias line. Inline components allow `id` inside.

- [ ] **Step 2: Visual check**

Scratch harness: `FloatingWindow` 560×360 with a `Loader` of `ArrivalsBoard.qml`, `rows` set to the mockup's four sample rows (statuses working, working, needs-you, idle), `held: true`, `style` cycling through the five boards every 3 s, one PNG per cycle. Confirm columns align, chips read, NOW letters flip in each style, empty `rows` gives height 0.

- [ ] **Step 3: Commit**

```bash
git add ArrivalsBoard.qml
git commit -m "Add the ArrivalsBoard component" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Service integration: scan, merge, hold, focus

**Files:**
- Modify: `Service.qml`

**Interfaces:**
- Consumes: `scripts/agents-scan.sh` JSON, `Logic.agentRow`, `Logic.sortedAgentRows`, `ArrivalsBoard`, `Hyprland.toplevels`, `Hyprland.dispatch`.
- Produces: `root.agentRows` (sorted list), `root.hasAgents`, `root.held`, status IPC fields `agents`, `held`.

- [ ] **Step 1: Settings and state**

After `flipStyle`:

```qml
  readonly property bool agentsBoardEnabled: setting("agentsBoard", true) !== false
  readonly property string agentsExtra: Logic.normalizedAgentsExtra(setting("agentsExtra", ""))
  property var agentRecords: []
  property var agentRows: []
  property var previousCpu: ({})
  readonly property bool hasAgents: agentsBoardEnabled && agentRows.length > 0
  // Hovering the card keeps the popup up after activity ends idle.
  property bool held: false
```

Change `popupVisible` to:

```qml
  readonly property bool popupVisible: !screensaverActive && !sessionLocked
    && (warningVisible || previewVisible || held)
```

and add `onHeldChanged: if (!held && !previewVisible && !idleMonitor.isIdle) endCountdown("released")`.

Because `warningVisible` requires `idleMonitor.isIdle`, moving the mouse onto the card ends idle and the countdown; `held` keeps the surface visible. `displaySeconds` while held and not counting must not read 0: add

```qml
  property int heldSeconds: 0
  onHeldChanged: { if (held) heldSeconds = displaySeconds }  // merge with the handler above
  readonly property int displaySeconds: previewVisible ? previewSeconds : (held && remainingSeconds === 0 ? heldSeconds : remainingSeconds)
```

Write the two `onHeldChanged` bodies as one handler.

- [ ] **Step 2: The scan process**

```qml
  Process {
    id: agentScan
    command: ["bash", Qt.resolvedUrl("scripts/agents-scan.sh").toString().replace("file://", "")]
    environment: ({
      AGENTS_EXTRA: root.agentsExtra,
      AGENTS_TITLES: root.candidateTitles()
    })
    stdout: StdioCollector {
      onStreamFinished: root.applyScan(text)
    }
  }

  Timer {
    id: agentScanTimer
    interval: 5000
    repeat: true
    running: root.popupVisible && root.agentsBoardEnabled
    triggeredOnStart: true
    onTriggered: if (!agentScan.running) agentScan.running = true
  }

  // Titles of terminal toplevels, one "pid<TAB>title" per line, so the scan
  // can attribute a title to a session by finding its text in the transcript.
  function candidateTitles() {
    var lines = []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < tops.length; i++) {
      var ipc = tops[i].lastIpcObject || {}
      var pid = Number(ipc.pid || 0)
      var title = String(tops[i].title || "")
      if (pid > 0 && title !== "") lines.push("any\t" + title)
    }
    return lines.join("\n")
  }

  function applyScan(text) {
    var records
    try { records = JSON.parse(String(text || "[]")) } catch (e) { console.warn("idle-screen-counter agents-scan parse failed"); records = [] }
    if (!Array.isArray(records)) records = []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var now = Date.now()
    var rows = []
    var nextCpu = ({})
    for (var i = 0; i < records.length; i++) {
      var r = records[i]
      var key = String(r.agent) + ":" + String(r.pid)
      nextCpu[key] = Number(r.cpuTicks || 0)
      rows.push(Logic.agentRow(r, root.toplevelFor(r, tops), now, previousCpu[key]))
    }
    previousCpu = nextCpu
    agentRecords = records
    agentRows = Logic.sortedAgentRows(rows)
  }

  // A toplevel belongs to a record when its client pid is the agent or one of
  // its ancestors (claude → bash → terminal). Single-process terminals share
  // one pid across windows; then only a title the scan attributed disambiguates.
  function toplevelFor(record, tops) {
    var pids = [Number(record.pid)]
    var ancestors = Array.isArray(record.ancestors) ? record.ancestors : []
    for (var a = 0; a < ancestors.length; a++) pids.push(Number(ancestors[a]))
    var candidates = []
    for (var i = 0; i < tops.length; i++) {
      var ipc = tops[i].lastIpcObject || {}
      if (pids.indexOf(Number(ipc.pid || -1)) !== -1) candidates.push(tops[i])
    }
    if (candidates.length === 1) return { title: String(candidates[0].title || ""), address: String(candidates[0].address || "") }
    var wanted = String(record.windowTitle || "")
    for (var c = 0; c < candidates.length; c++) {
      if (wanted !== "" && String(candidates[c].title || "") === wanted)
        return { title: wanted, address: String(candidates[c].address || "") }
    }
    return { title: wanted, address: "" }
  }

  function focusAgent(address) {
    if (!address) return
    Hyprland.dispatch("focuswindow address:" + address)
    held = false
  }
```

The script must also emit `ancestors`: in Task 3's `scan()`, compute up to three parent pids by reading field 4 of `/proc/<pid>/stat` and pass them into `emit_record` as a new `"ancestors":[...]` field. Add that to the script and its test (`.ancestors | type == "array"`). Do this as part of this task and amend the Task 3 test.

- [ ] **Step 3: Hold on the window**

On the `PanelWindow`, replace `mask: Region {}` with:

```qml
      // Click-through everywhere except the card, and only while the board
      // has something to hold open. Otherwise the surface stays fully passive.
      mask: root.hasAgents ? cardRegion : emptyRegion
      Region { id: emptyRegion }
      Region { id: cardRegion; item: card }
```

Inside `card` add:

```qml
        HoverHandler {
          enabled: root.hasAgents
          onHoveredChanged: {
            if (hovered) { root.held = true; heldSafety.restart() }
            else root.held = false
          }
        }
        Timer { id: heldSafety; interval: 45000; onTriggered: root.held = false }
```

Header text while held: change the right-hand `Caption` texts to
`root.held ? "Held" : (root.previewVisible ? "Preview" : "Live")` with color `root.held ? card.alert : root.countdownAccent`, where `readonly property color alert: Color.urgent` on the card. The "starts in" caption becomes `root.held ? "Countdown paused while you look" : …` and the footer `root.held ? "Move off the board to dismiss · click a row to focus its terminal" : …`.

- [ ] **Step 4: Place the board**

After the board `Item` (the countdown) and before the footer `Rule`, add:

```qml
          ArrivalsBoard {
            visible: root.hasAgents || (root.previewVisible && root.agentsBoardEnabled)
            width: parent.width
            rows: root.hasAgents ? root.agentRows : root.sampleRows
            style: root.activeStyle
            held: root.held
            foreground: card.ink
            accent: root.countdownAccent
            alert: card.alert
            dim: card.dim
            line: card.line
            well: card.well
            fontFamily: Style.font.family
            captionSize: Style.font.caption
            bodySize: Style.font.bodySmall
            animated: popupWindow.visible
            onFocusRequested: function(address) { root.focusAgent(address) }
          }
```

with, on `root`:

```qml
  readonly property var sampleRows: previewVisible && agentRows.length === 0 ? Logic.sortedAgentRows([
    Logic.agentRow({ pid: 0, agent: "sample", label: "Claude Code", strategy: "claude", cwd: "/home/you/Projects/your-app", started: Math.floor(Date.now() / 1000) - 620, lastActivity: Math.floor(Date.now() / 1000) - 12, branch: "main", tools: ["Read", "Edit"], sessionStatus: "busy", cpuTicks: 0, windowTitle: "" }, null, Date.now()),
    Logic.agentRow({ pid: 0, agent: "sample", label: "Codex", strategy: "codex", cwd: "/home/you/Projects/ledger", started: Math.floor(Date.now() / 1000) - 3000, lastActivity: Math.floor(Date.now() / 1000) - 400, branch: "", tools: ["shell"], sessionStatus: "idle", cpuTicks: 0, windowTitle: "" }, null, Date.now())
  ]) : []
```

Sample rows carry `agentLabel` suffixed with " · sample" so they are never mistaken for live data: post-process with `.map(function(r) { r.agentLabel += " · sample"; return r })`.

- [ ] **Step 5: Status IPC**

Add to the `status()` JSON: `agents: root.agentRows.length, held: root.held, agentsBoard: root.agentsBoardEnabled`.

- [ ] **Step 6: Deploy and verify**

```bash
./scripts/static-check.sh && ./scripts/dev-sync.sh && sleep 4 && omarchy-restart-shell
```

Then: `qs -p /usr/share/omarchy/shell ipc call idle-screen-counter previewStyle solari`, wait 2 s, `status` shows `agents` ≥ 1 on this machine; `grim` a screenshot and crop the card; check the shell log for warnings from the plugin (`qs log … | grep WARN | grep idle-screencounter`). Move the pointer onto the card during a preview and confirm the header reads HELD and the card stays after the 10 s preview would have ended; move off and confirm it dismisses.

- [ ] **Step 7: Commit**

```bash
git add Service.qml scripts/agents-scan.sh tests/agents-scan.test.sh
git commit -m "Show the Arrivals board under the countdown with hold and focus" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Settings panel controls

**Files:**
- Modify: `Panel.qml`

**Interfaces:**
- Consumes: settings keys `agentsBoard`, `agentsExtra`; `root.save(key, value)`.

- [ ] **Step 1: Add the row under the flip-style picker**

After the picker `Row` and before the next `Rule {}`:

```qml
      Item {
        width: parent.width
        height: Math.max(arrivalsLabels.implicitHeight, arrivalsToggle.implicitHeight)
        Column {
          id: arrivalsLabels
          anchors.left: parent.left
          anchors.right: arrivalsToggle.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Caption { text: "Arrivals board"; color: root.ink; font.bold: true }
          Caption {
            width: parent.width
            text: "Lists running coding agents under the countdown. Hover to hold, click a row to focus."
            font.capitalization: Font.MixedCase
            font.letterSpacing: 0.2
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
          }
        }
        ToggleSwitch {
          id: arrivalsToggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.agentsBoard
          foreground: root.barForeground
          accent: Color.accent
          onToggled: root.save("agentsBoard", !root.agentsBoard)
        }
      }

      Item {
        visible: root.agentsBoard
        width: parent.width
        height: extraField.implicitHeight
        Caption { id: extraLabel; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Also watch" }
        TextField {
          id: extraField
          anchors.left: extraLabel.right
          anchors.leftMargin: Style.space(12)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.agentsExtra
          placeholderText: "process names, comma separated · aider, goose"
          foreground: root.barForeground
          accent: Color.accent
          onAccepted: root.save("agentsExtra", text)
          onEditingFinished: root.save("agentsExtra", text)
        }
      }
```

with `readonly property bool agentsBoard: setting("agentsBoard", true) !== false` and `readonly property string agentsExtra: String(setting("agentsExtra", ""))` on `root`. Check `qs.Ui/TextField.qml` for its property names (`text`, `placeholderText`, `foreground`, `accent`, signals `accepted`, `editingFinished`) and adapt to what exists.

- [ ] **Step 2: Deploy and verify**

`./scripts/dev-sync.sh`, open the panel via IPC, screenshot, confirm the row renders and toggling writes `agentsBoard` into `shell.json`.

- [ ] **Step 3: Commit**

```bash
git add Panel.qml
git commit -m "Add Arrivals board controls to the settings panel" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Manifest, docs, release prep

**Files:**
- Modify: `manifest.json`, `scripts/static-check.sh`, `README.md`, `CHANGELOG.md`, `MAINTAINER_NOTES.md`

- [ ] **Step 1: Manifest**

Version `2.1.0`. Defaults: `"agentsBoard": true, "agentsExtra": ""`. Schema entries:

```json
{"key": "agentsBoard", "type": "boolean", "label": "Arrivals board (running coding agents)", "defaultValue": true},
{"key": "agentsExtra", "type": "string", "label": "Extra agent process names (comma separated)", "defaultValue": ""}
```

Description: "Five theme-aware flip-board countdowns before Omarchy starts the screensaver, with an arrivals board of your running coding agents." Keywords add `agents`, `claude-code`, `codex`.

- [ ] **Step 2: Static check**

`.version == "2.1.0"`; `ArrivalsBoard.qml` in the file list; `grep -Fq 'agents-scan.sh' Service.qml`.

- [ ] **Step 3: Docs**

README: new section "Arrivals board" after "Make it yours": what it shows, hold and focus, the adapter table, the privacy statement, and "Adding an agent" (one table line plus one `summarize_*` function; the record fields). Settings table gains `agentsBoard` and `agentsExtra`. CHANGELOG `## 2.1.0`. Maintainer notes: pid-ancestry matching, the single-process-terminal limitation and the title attribution trick, the hold mask, the 3-second sync-to-restart rule.

- [ ] **Step 4: Full verification**

`./scripts/static-check.sh`, `./scripts/dev-sync.sh`, wait 4 s, `omarchy-restart-shell`, zero plugin warnings in the log, preview screenshot showing live rows, panel screenshot showing the toggle.

- [ ] **Step 5: Commit and push**

```bash
git add -A -- . ':!omasnap'
git commit -m "Release v2.1.0: Arrivals board" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push origin main
```

Tagging and the marketplace update issue are separate decisions for the maintainer.

---

## Self-review

- Spec coverage: scan script and adapters (Task 3, 6 for ancestors), Logic helpers and settings (1, 2), letters in all styles (4), ArrivalsBoard layout, chips, collapse, detail, focus signal (5), Service scan cadence, toplevel matching, hold mask and copy, focus dispatch, sample preview rows, IPC (6), panel toggle and extra field (7), manifest, static check, docs (8). Error handling: parse failure → empty rows (6); no toplevel → no address (6); screensaver/lock suppression already wins because `popupVisible` keeps those guards (6).
- Names are consistent: `agentsBoard`, `agentsExtra`, `agentRow`, `sortedAgentRows`, `agentStatus`, `glyphSet`, `held`, `focusRequested`, `agents-scan.sh`, `AGENTS_TITLES`, `AGENTS_EXTRA`.
- Known soft spot: `qs.Ui/TextField.qml` property names are to be confirmed at Task 7.
