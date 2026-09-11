import QtQuick

// 05 Stepped. A split flap drawn in five hard frames with no easing: full,
// squashed, a single accent hinge line, squashed new, full new. The flap as a
// terminal would animate it. The colon is a blinking block cursor.
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
  readonly property real frame: 60 / speed

  property string shown: ""
  // 0 rest · 1 squash old · 2 hinge line · 3 squash new · 4 full new
  property int phase: 0

  Component.onCompleted: shown = character
  onCharacterChanged: {
    if (isColon) return
    if (shown === "" || !animated || !visible) { step.stop(); shown = character; phase = 0; return }
    step.restart()
  }

  SequentialAnimation {
    id: step
    ScriptAction { script: tile.phase = 1 }
    PauseAnimation { duration: tile.frame }
    ScriptAction { script: tile.phase = 2 }
    PauseAnimation { duration: tile.frame }
    ScriptAction { script: { tile.shown = tile.character; tile.phase = 3 } }
    PauseAnimation { duration: tile.frame }
    ScriptAction { script: tile.phase = 4 }
    PauseAnimation { duration: tile.frame }
    ScriptAction { script: tile.phase = 0 }
  }

  Rectangle {
    anchors.fill: parent
    color: tile.well
    border.color: tile.line
    border.width: 1
    visible: !tile.isColon
  }

  // Colon: the block cursor.
  Rectangle {
    visible: tile.isColon
    width: Math.round(tile.width * 0.6)
    height: Math.round(tile.height * 0.34)
    anchors.centerIn: parent
    color: tile.accent
    SequentialAnimation on opacity {
      running: tile.isColon && tile.visible
      loops: Animation.Infinite
      PropertyAction { value: 1 }
      PauseAnimation { duration: 500 }
      PropertyAction { value: 0 }
      PauseAnimation { duration: 500 }
    }
  }

  Text {
    id: glyph
    visible: !tile.isColon && tile.phase !== 2
    anchors.fill: parent
    text: tile.shown
    color: (tile.phase === 1 || tile.phase === 3) ? tile.dim : tile.foreground
    font.family: tile.fontFamily
    font.pixelSize: tile.glyphSize
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    transform: Scale {
      origin.x: glyph.width / 2
      origin.y: glyph.height / 2
      yScale: (tile.phase === 1 || tile.phase === 3) ? 0.5 : 1
    }
  }

  // Frame 2: the flap seen edge-on is a single accent line.
  Rectangle {
    visible: !tile.isColon && tile.phase === 2
    x: Math.round(tile.width * 0.12)
    width: tile.width - x * 2
    y: tile.height / 2 - height / 2
    height: Math.max(2, Math.round(tile.height * 0.04))
    color: tile.accent
  }

  // Hinge shows only while the flap is moving.
  Rectangle {
    visible: !tile.isColon && tile.phase > 0 && tile.phase !== 2
    x: 1; width: tile.width - 2
    y: tile.height / 2 - 0.5; height: 1
    color: tile.line
  }
}
