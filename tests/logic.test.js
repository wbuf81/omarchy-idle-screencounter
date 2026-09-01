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

console.log("logic tests passed")
