import QtQuick

// 03 Drum. A rotating digit drum seen through a window. Neighboring digits
// ghost in above and below in the dim color, the active one stops between
// two accent ticks. The roll overshoots a hair and settles into its detent.
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
  readonly property bool isDigit: /^[0-9]$/.test(character)
  readonly property real glyphSize: height * 0.72
  readonly property real cell: height * 0.68
  readonly property real inset: (height - cell) / 2
  readonly property int copies: 3
  property int index: -1

  clip: true

  function yFor(i) { return -i * cell + inset }

  Component.onCompleted: if (isDigit) { index = 10 + parseInt(character, 10); strip.y = yFor(index) }
  onCharacterChanged: {
    if (!isDigit) return
    var d = parseInt(character, 10)
    if (index === -1) { index = 10 + d; strip.y = yFor(index); return }
    if (index % 10 === d) return
    if (!animated || !visible) { roll.stop(); index = 10 + d; strip.y = yFor(index); return }
    // Counting down rolls the drum toward lower values; find the nearest one.
    var target = index - ((index % 10 - d + 10) % 10)
    if (target < 0) target += 10
    index = target
    roll.stop()
    roll.to = yFor(target)
    roll.distance = Math.abs(strip.y - roll.to) / cell
    roll.restart()
  }

  Rectangle {
    visible: !tile.isColon
    anchors.fill: parent
    color: tile.well
    border.color: tile.line
    border.width: 1
  }

  Item {
    id: strip
    visible: tile.isDigit
    width: tile.width
    Column {
      Repeater {
        model: tile.copies * 10
        Text {
          required property int index
          width: tile.width
          height: tile.cell
          text: String(index % 10)
          color: index === tile.index ? tile.foreground : tile.dim
          font.family: tile.fontFamily
          font.pixelSize: tile.glyphSize
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }

  SequentialAnimation {
    id: roll
    property real to: 0
    property real distance: 1
    NumberAnimation {
      target: strip; property: "y"; to: roll.to
      duration: (320 + roll.distance * 40) / tile.speed
      easing.type: Easing.OutBack
      easing.overshoot: 0.7
    }
    // Recenter silently into the middle copy so the next roll has room.
    ScriptAction { script: { tile.index = 10 + tile.index % 10; strip.y = tile.yFor(tile.index) } }
  }

  // Non-digit characters (the colon, a placeholder) sit still.
  Text {
    visible: !tile.isDigit
    anchors.fill: parent
    text: tile.character
    color: tile.isColon ? tile.accent : tile.foreground
    font.family: tile.fontFamily
    font.pixelSize: tile.glyphSize * (tile.isColon ? 0.9 : 1)
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    SequentialAnimation on opacity {
      running: tile.isColon && tile.visible
      loops: Animation.Infinite
      PropertyAction { value: 1 }
      PauseAnimation { duration: 500 }
      PropertyAction { value: 0 }
      PauseAnimation { duration: 500 }
    }
  }

  // Window shading: the drum fades into the well at the top and bottom.
  Rectangle {
    visible: tile.isDigit
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    height: parent.height * 0.34
    gradient: Gradient {
      GradientStop { position: 0; color: tile.well }
      GradientStop { position: 1; color: Qt.rgba(tile.well.r, tile.well.g, tile.well.b, 0) }
    }
  }
  Rectangle {
    visible: tile.isDigit
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: parent.height * 0.34
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(tile.well.r, tile.well.g, tile.well.b, 0) }
      GradientStop { position: 1; color: tile.well }
    }
  }
  Rectangle { visible: tile.isDigit; x: 6; width: parent.width - 12; y: Math.round(parent.height * 0.11); height: 1; color: tile.line }
  Rectangle { visible: tile.isDigit; x: 6; width: parent.width - 12; y: Math.round(parent.height * 0.89); height: 1; color: tile.line }

  // Detent ticks.
  Rectangle { visible: tile.isDigit; x: 0; y: parent.height / 2 - 0.5; width: 5; height: 1; color: tile.accent }
  Rectangle { visible: tile.isDigit; x: parent.width - 5; y: parent.height / 2 - 0.5; width: 5; height: 1; color: tile.accent }
}
