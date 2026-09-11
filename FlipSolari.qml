import QtQuick

// 01 Solari. The departure board: the old digit's upper half folds down on
// the hinge in perspective, the new digit's lower half drops in behind it
// and lands with a small rebound. Digits with farther to travel chatter
// through the ones in between, the way a station board catches up.
Item {
  id: tile

  property string character: "0"
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property color dim: "#565f89"
  property color line: "#2f3349"
  property color well: "#1a1b26"
  property string fontFamily: "monospace"
  property real speed: 1
  property bool animated: true

  readonly property bool isColon: character === ":"
  readonly property real glyphSize: height * 0.72

  property string current: ""
  property string previous: ""
  property var queue: []
  property bool flipping: false
  property bool topPhase: true
  property bool fast: false
  // Positive x-rotation brings the flap's free edge toward the viewer.
  property real topAngle: 0
  property real bottomAngle: -90

  Component.onCompleted: current = character
  onCharacterChanged: if (!isColon) animateTo(character)

  function animateTo(next) {
    if (current === "" || !animated || !visible) { current = next; queue = []; return }
    var a = parseInt(current, 10), b = parseInt(next, 10)
    var pending = queue.slice()
    if (isNaN(a) || isNaN(b)) {
      pending.push(next)
    } else {
      // Travel downward around the drum, one flap per digit.
      var steps = ((a - b) % 10 + 10) % 10
      var last = pending.length ? parseInt(pending[pending.length - 1], 10) : a
      steps = ((last - b) % 10 + 10) % 10
      for (var i = 1; i <= steps; i++) pending.push(String((last - i + 10) % 10))
    }
    queue = pending
    if (!flipping) startNext()
  }

  function startNext() {
    if (queue.length === 0) { flipping = false; return }
    var pending = queue.slice()
    previous = current
    current = pending.shift()
    queue = pending
    fast = pending.length > 0
    flipping = true
    flip.restart()
  }

  SequentialAnimation {
    id: flip
    ScriptAction { script: { tile.topAngle = 0; tile.bottomAngle = -90; tile.topPhase = true } }
    NumberAnimation {
      target: tile; property: "topAngle"; from: 0; to: 90
      duration: (tile.fast ? 70 : 150) / tile.speed
      easing.type: Easing.InQuad
    }
    ScriptAction { script: tile.topPhase = false }
    NumberAnimation {
      target: tile; property: "bottomAngle"; from: -90; to: 0
      duration: (tile.fast ? 80 : 230) / tile.speed
      easing.type: tile.fast ? Easing.OutQuad : Easing.OutBack
      easing.overshoot: 1.6
    }
    ScriptAction { script: tile.startNext() }
  }

  // Colon: a static accent mark between the two drums.
  Text {
    visible: tile.isColon
    anchors.fill: parent
    text: ":"
    color: tile.accent
    font.family: tile.fontFamily
    font.pixelSize: tile.glyphSize * 0.9
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  Item {
    visible: !tile.isColon
    anchors.fill: parent

    component Half: Item {
      property string glyph: ""
      property bool upper: true
      property alias faceColor: face.color
      clip: true
      Rectangle {
        id: face
        anchors.fill: parent
        color: tile.well
        border.color: tile.line
        border.width: 1
      }
      Text {
        width: tile.width
        height: tile.height
        y: upper ? 0 : -tile.height / 2
        text: glyph
        color: tile.foreground
        font.family: tile.fontFamily
        font.pixelSize: tile.glyphSize
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }

    // Settled faces. The upper one already shows the new digit; the lower
    // one keeps the old digit until the falling flap covers it.
    Half {
      width: parent.width; height: parent.height / 2
      glyph: tile.current
      upper: true
    }
    Half {
      y: parent.height / 2
      width: parent.width; height: parent.height / 2
      glyph: tile.flipping ? tile.previous : tile.current
      upper: false
    }

    // Upper flap: carries the old digit and folds down toward the viewer.
    Half {
      id: upperFlap
      width: parent.width; height: parent.height / 2
      glyph: tile.previous
      upper: true
      visible: tile.flipping && tile.topPhase
      transform: Rotation {
        origin.x: upperFlap.width / 2
        origin.y: upperFlap.height
        axis { x: 1; y: 0; z: 0 }
        angle: tile.topAngle
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
        }
        opacity: Math.abs(tile.topAngle) / 90
      }
    }

    // Lower flap: carries the new digit and falls flat from edge-on.
    Half {
      id: lowerFlap
      y: parent.height / 2
      width: parent.width; height: parent.height / 2
      glyph: tile.current
      upper: false
      visible: tile.flipping && !tile.topPhase
      transform: Rotation {
        origin.x: lowerFlap.width / 2
        origin.y: 0
        axis { x: 1; y: 0; z: 0 }
        angle: tile.bottomAngle
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.6) }
          GradientStop { position: 1; color: "transparent" }
        }
        opacity: Math.abs(tile.bottomAngle) / 90
      }
    }

    // Hinge line and pins. The line flashes accent while the drum moves.
    Rectangle {
      x: -3; width: parent.width + 6
      y: parent.height / 2 - 0.5; height: 1
      color: tile.flipping ? tile.accent : tile.line
      z: 3
    }
    Rectangle { x: -3; y: parent.height / 2 - 3; width: 4; height: 5; color: tile.dim; z: 4 }
    Rectangle { x: parent.width - 1; y: parent.height / 2 - 3; width: 4; height: 5; color: tile.dim; z: 4 }
  }
}
