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
    placement: "center"
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
  return normalized
}

function editedSettings(input, current, key, value, pluginId) {
  var next = Object.assign({}, input || {})
  var live = current || {}
  next.warningSeconds = numberOr(live.warningSeconds, numberOr(next.warningSeconds, 120))
  next.screensaverSeconds = numberOr(live.screensaverSeconds, numberOr(next.screensaverSeconds, 600))
  next.lockSeconds = numberOr(live.lockSeconds, numberOr(next.lockSeconds, 1200))
  next[key] = key === "enabled" ? !!value : (key === "placement" ? String(value) : Math.round(Number(value)))

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
    seconds: seconds,
    normalizedPlacement: normalizedPlacement,
    normalizedSettings: normalizedSettings,
    editedSettings: editedSettings,
    timeline: timeline,
    format: format
  }
}
