// Pure configuration and timeline helpers shared by the QML service and UI.
// Keep this file free of Qt APIs so the release suite can execute it in Node.

function numberOr(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function seconds(value, fallback) {
  var number = numberOr(value, fallback)
  return number < 0 ? fallback : Math.floor(number)
}

function boundedSeconds(value, fallback, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, Math.round(numberOr(value, fallback))))
}

var FLIP_STYLES = ["solari", "bits", "drum", "sweep", "step"]
var FLIP_STYLE_LABELS = {
  solari: "Solari",
  bits: "Vestaboard",
  drum: "Drum",
  sweep: "Sweep",
  step: "Stepped",
  random: "Random"
}

function normalizedFlipStyle(value) {
  var candidate = String(value || "random")
  return FLIP_STYLES.indexOf(candidate) !== -1 ? candidate : "random"
}

function flipStyleLabel(value) {
  return FLIP_STYLE_LABELS[normalizedFlipStyle(value)]
}

// The style after `previous` in board order, wrapping. Previews under
// "random" walk this so a click tour shows every board exactly once.
function nextFlipStyle(previous) {
  var index = FLIP_STYLES.indexOf(String(previous || ""))
  return FLIP_STYLES[(index + 1) % FLIP_STYLES.length]
}

// Which board plays for one popup appearance. `roll` is a number in [0, 1)
// supplied by the caller so this stays pure and testable. Random mode never
// repeats the board that just played.
function flipStyleForShow(configured, previous, roll) {
  var style = normalizedFlipStyle(configured)
  if (style !== "random") return style
  var pool = FLIP_STYLES.filter(function(candidate) { return candidate !== String(previous || "") })
  var unit = Math.min(0.999999, Math.max(0, numberOr(roll, 0)))
  return pool[Math.floor(unit * pool.length)]
}

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
    return name.toUpperCase().slice(0, 11).replace(/\s+$/, "")
  }
  return "RUNNING"
}

function elapsedLabel(fromMs, nowMs) {
  var s = Math.max(0, Math.floor((nowMs - fromMs) / 1000))
  if (s >= 86400) return Math.floor(s / 86400) + "d"
  var minutes = Math.floor((s % 3600) / 60)
  if (s >= 3600) return Math.floor(s / 3600) + ":" + (minutes < 10 ? "0" : "") + minutes
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

// A window title claimed by more than one record identifies neither of them.
// Returns a shallow copy of the records with such titles cleared.
function dedupeAgentTitles(records) {
  var count = {}
  var list = Array.isArray(records) ? records : []
  for (var i = 0; i < list.length; i++) {
    var title = String(list[i] && list[i].windowTitle || "")
    if (title !== "") count[title] = (count[title] || 0) + 1
  }
  return list.map(function(record) {
    var copy = Object.assign({}, record)
    if (count[String(copy.windowTitle || "")] > 1) copy.windowTitle = ""
    return copy
  })
}

function sortedAgentRows(rows) {
  var order = { "needs-you": 0, working: 1, idle: 2 }
  return (rows || []).slice().sort(function(a, b) {
    var byStatus = order[a.status] - order[b.status]
    if (byStatus !== 0) return byStatus
    return numberOr(b.lastActivity, 0) - numberOr(a.lastActivity, 0)
  })
}

function normalizedPlacement(value) {
  var candidate = String(value || "center")
  var allowed = ["top-left", "top", "top-right", "center", "bottom-left", "bottom", "bottom-right"]
  return allowed.indexOf(candidate) !== -1 ? candidate : "center"
}

function normalizedSettings(input, pluginId) {
  var normalized = Object.assign({
    id: String(pluginId || "io.github.wbuf81.idle-screencounter"),
    enabled: true,
    warningSeconds: 120,
    screensaverSeconds: 600,
    lockSeconds: 1200,
    snapSeconds: 30,
    placement: "center",
    flipStyle: "random",
    agentsBoard: true,
    agentsExtra: ""
  }, input || {})

  normalized.id = String(pluginId || normalized.id)
  normalized.enabled = normalized.enabled !== false
  normalized.warningSeconds = boundedSeconds(normalized.warningSeconds, 120, 15, 900)
  normalized.screensaverSeconds = boundedSeconds(normalized.screensaverSeconds, 600, 30, 1800)
  normalized.lockSeconds = boundedSeconds(normalized.lockSeconds, 1200, 45, 3600)
  normalized.screensaverSeconds = Math.max(normalized.screensaverSeconds, normalized.warningSeconds + 15)
  normalized.lockSeconds = Math.max(normalized.lockSeconds, normalized.screensaverSeconds + 15)
  normalized.snapSeconds = [15, 30, 60].indexOf(Number(normalized.snapSeconds)) !== -1 ? Number(normalized.snapSeconds) : 30
  normalized.placement = normalizedPlacement(normalized.placement)
  normalized.flipStyle = normalizedFlipStyle(normalized.flipStyle)
  normalized.agentsBoard = normalized.agentsBoard !== false
  normalized.agentsExtra = normalizedAgentsExtra(normalized.agentsExtra)
  return normalized
}

function editedSettings(input, current, key, value, pluginId) {
  var next = Object.assign({}, input || {})
  var live = current || {}
  next.warningSeconds = numberOr(live.warningSeconds, numberOr(next.warningSeconds, 120))
  next.screensaverSeconds = numberOr(live.screensaverSeconds, numberOr(next.screensaverSeconds, 600))
  next.lockSeconds = numberOr(live.lockSeconds, numberOr(next.lockSeconds, 1200))
  var stringKeys = ["placement", "flipStyle", "agentsExtra"]
  var boolKeys = ["enabled", "agentsBoard"]
  next[key] = boolKeys.indexOf(key) !== -1 ? !!value : (stringKeys.indexOf(key) !== -1 ? String(value) : Math.round(Number(value)))

  if (key === "warningSeconds") {
    next.screensaverSeconds = Math.max(next.screensaverSeconds, next.warningSeconds + 15)
    next.lockSeconds = Math.max(next.lockSeconds, next.screensaverSeconds + 15)
  } else if (key === "screensaverSeconds") {
    next.warningSeconds = Math.min(next.warningSeconds, next.screensaverSeconds - 15)
    next.lockSeconds = Math.max(next.lockSeconds, next.screensaverSeconds + 15)
  } else if (key === "lockSeconds") {
    next.screensaverSeconds = Math.min(next.screensaverSeconds, next.lockSeconds - 15)
    next.warningSeconds = Math.min(next.warningSeconds, next.screensaverSeconds - 15)
  }

  next.warningSeconds = Math.max(15, next.warningSeconds)
  next.screensaverSeconds = Math.max(30, next.screensaverSeconds)
  next.lockSeconds = Math.max(45, next.lockSeconds)
  return normalizedSettings(next, pluginId)
}

function timeline(warningValue, screensaverValue, lockValue) {
  var requestedWarning = seconds(warningValue, 120)
  var screensaver = seconds(screensaverValue, 600)
  var lock = seconds(lockValue, 1200)
  var deadline = Math.min(screensaver, lock)
  var effectiveWarning = Math.min(requestedWarning, Math.max(0, deadline - 1))
  return {
    requestedWarning: requestedWarning,
    effectiveWarning: effectiveWarning,
    screensaver: screensaver,
    lock: lock,
    deadline: deadline,
    nextEvent: lock <= screensaver ? "lock" : "screensaver",
    countdownSeconds: Math.max(0, deadline - effectiveWarning)
  }
}

function format(secondsLeft) {
  var safe = Math.max(0, Math.floor(numberOr(secondsLeft, 0)))
  var minutes = Math.floor(safe / 60)
  var secondsPart = safe % 60
  return (minutes < 10 ? "0" : "") + minutes + ":" + (secondsPart < 10 ? "0" : "") + secondsPart
}

if (typeof module !== "undefined") {
  module.exports = {
    FLIP_STYLES: FLIP_STYLES,
    normalizedFlipStyle: normalizedFlipStyle,
    flipStyleLabel: flipStyleLabel,
    nextFlipStyle: nextFlipStyle,
    flipStyleForShow: flipStyleForShow,
    normalizedAgentsExtra: normalizedAgentsExtra,
    AGENT_WAIT_MARKERS: AGENT_WAIT_MARKERS,
    agentStatus: agentStatus,
    agentNow: agentNow,
    elapsedLabel: elapsedLabel,
    agentRow: agentRow,
    sortedAgentRows: sortedAgentRows,
    dedupeAgentTitles: dedupeAgentTitles,
    stripTitleGlyph: stripTitleGlyph,
    seconds: seconds,
    normalizedPlacement: normalizedPlacement,
    normalizedSettings: normalizedSettings,
    editedSettings: editedSettings,
    timeline: timeline,
    format: format
  }
}
