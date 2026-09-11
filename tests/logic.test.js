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

console.log("logic tests passed")
