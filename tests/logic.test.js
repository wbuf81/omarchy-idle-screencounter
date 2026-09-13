const assert = require("node:assert/strict")
const Logic = require("../Logic.js")

const id = "io.github.wbuf81.idle-screencounter"

assert.deepEqual(Logic.timeline(120, 600, 1200), {
  requestedWarning: 120,
  effectiveWarning: 120,
  screensaver: 600,
  lock: 1200,
  deadline: 600,
  nextEvent: "screensaver",
  countdownSeconds: 480
})

assert.equal(Logic.timeline(120, 600, 90).nextEvent, "lock")
assert.equal(Logic.timeline(120, 600, 90).effectiveWarning, 89)
assert.equal(Logic.timeline(120, 600, 90).countdownSeconds, 1)
assert.equal(Logic.timeline(-1, "oops", null).requestedWarning, 120)

const malformed = Logic.normalizedSettings({
  id: "wrong",
  warningSeconds: -9,
  screensaverSeconds: "nope",
  lockSeconds: 1,
  snapSeconds: 17,
  placement: "somewhere"
}, id)
assert.equal(malformed.id, id)
assert.equal(malformed.warningSeconds, 15)
assert.equal(malformed.screensaverSeconds, 600)
assert.equal(malformed.lockSeconds, 615)
assert.equal(malformed.snapSeconds, 30)
assert.equal(malformed.placement, "center")

const earlyLock = Logic.editedSettings(
  { warningSeconds: 120, screensaverSeconds: 600, lockSeconds: 1200 },
  { warningSeconds: 120, screensaverSeconds: 600, lockSeconds: 1200 },
  "lockSeconds",
  45,
  id
)
assert.equal(earlyLock.warningSeconds, 15)
assert.equal(earlyLock.screensaverSeconds, 30)
assert.equal(earlyLock.lockSeconds, 45)

const laterWarning = Logic.editedSettings(
  {},
  { warningSeconds: 120, screensaverSeconds: 600, lockSeconds: 1200 },
  "warningSeconds",
  900,
  id
)
assert.equal(laterWarning.warningSeconds, 900)
assert.equal(laterWarning.screensaverSeconds, 915)
assert.equal(laterWarning.lockSeconds, 1200)

assert.equal(Logic.normalizedPlacement("bottom-right"), "bottom-right")
assert.equal(Logic.normalizedPlacement("banana"), "center")
assert.equal(Logic.format(480), "08:00")
assert.equal(Logic.format(7), "00:07")

// Flip styles: five boards plus "random"; anything else falls back to random.
assert.deepEqual(Logic.FLIP_STYLES, ["solari", "bits", "drum", "sweep", "step"])
assert.equal(Logic.normalizedFlipStyle("drum"), "drum")
assert.equal(Logic.normalizedFlipStyle("random"), "random")
assert.equal(Logic.normalizedFlipStyle("banana"), "random")
assert.equal(Logic.normalizedFlipStyle(undefined), "random")
assert.equal(Logic.normalizedSettings({}, id).flipStyle, "random")
assert.equal(Logic.normalizedSettings({ flipStyle: "bits" }, id).flipStyle, "bits")
assert.equal(Logic.editedSettings({}, {}, "flipStyle", "sweep", id).flipStyle, "sweep")
assert.equal(Logic.editedSettings({}, {}, "flipStyle", "nope", id).flipStyle, "random")

// A fixed style always plays itself.
assert.equal(Logic.flipStyleForShow("step", "solari", 0.99), "step")
// Random never repeats the previous style when it has a choice, and honors the roll.
assert.equal(Logic.flipStyleForShow("random", "", 0), "solari")
assert.equal(Logic.flipStyleForShow("random", "", 0.999), "step")
assert.equal(Logic.flipStyleForShow("random", "solari", 0), "bits")
assert.equal(Logic.flipStyleForShow("random", "step", 0.999), "sweep")
assert.notEqual(Logic.flipStyleForShow("random", "drum", 0.5), "drum")
// Cycling is deterministic so a preview can tour the set in order.
assert.equal(Logic.nextFlipStyle(""), "solari")
assert.equal(Logic.nextFlipStyle("solari"), "bits")
assert.equal(Logic.nextFlipStyle("step"), "solari")
assert.equal(Logic.flipStyleLabel("solari"), "Solari")
assert.equal(Logic.flipStyleLabel("random"), "Random")

// Arrivals board settings.
assert.equal(Logic.normalizedSettings({}, id).agentsBoard, true)
assert.equal(Logic.normalizedSettings({ agentsBoard: false }, id).agentsBoard, false)
assert.equal(Logic.normalizedSettings({}, id).agentsExtra, "")
assert.equal(Logic.normalizedAgentsExtra(" Aider, opencode ,,GOOSE "), "aider,opencode,goose")
assert.equal(Logic.normalizedAgentsExtra("bad name;rm -rf"), "")
assert.equal(Logic.editedSettings({}, {}, "agentsBoard", false, id).agentsBoard, false)
assert.equal(Logic.editedSettings({}, {}, "agentsExtra", "Aider, goose", id).agentsExtra, "aider,goose")

// Agent status.
var now = Date.parse("2026-09-13T18:40:00Z")
var busy = { pid: 1, agent: "claude", label: "Claude Code", strategy: "claude", cwd: "/home/wes/Projects/omarchy-idle-screencounter", started: 1789157806, lastActivity: Math.floor(now / 1000) - 20, branch: "main", tools: ["Bash", "Write"], sessionStatus: "busy", cpuTicks: 100, windowTitle: "◐ Vestaboard flipper animations" }
assert.equal(Logic.agentStatus(busy, now), "working")
var waiting = Object.assign({}, busy, { sessionStatus: "idle", lastActivity: Math.floor(now / 1000) - 300, windowTitle: "✳ Health stuff weekly updates" })
assert.equal(Logic.agentStatus(waiting, now), "needs-you")
var stale = Object.assign({}, waiting, { lastActivity: Math.floor(now / 1000) - 3 * 3600, windowTitle: "" })
assert.equal(Logic.agentStatus(stale, now), "idle")
var asked = Object.assign({}, busy, { sessionStatus: "idle", tools: ["Bash", "AskUserQuestion"], windowTitle: "✳ Vestaboard flipper animations" })
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

console.log("logic tests passed")
