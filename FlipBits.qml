import QtQuick

// 02 Vestaboard. Each digit is a 5x7 grid of flip bits. A change runs a
// diagonal wave across the tile: every bit turns over on its own hinge and
// changes color at the half-turn. No text is drawn, so it stays crisp at any
// size and reads as the pixel language of the shell.
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
  property string glyphSet: "digits"

  readonly property bool isColon: character === ":"
  readonly property int columns: 5
  readonly property int rows: 7
  readonly property real padX: Math.round(width * 0.08)
  readonly property real padY: Math.round(height * 0.07)
  readonly property real gap: Math.max(1, Math.round(width * 0.03))
  readonly property real cellW: (width - padX * 2 - gap * (columns - 1)) / columns
  readonly property real cellH: (height - padY * 2 - gap * (rows - 1)) / rows

  readonly property var glyphs: ({
    "0": ["01110","10001","10011","10101","11001","10001","01110"],
    "1": ["00100","01100","00100","00100","00100","00100","01110"],
    "2": ["01110","10001","00001","00010","00100","01000","11111"],
    "3": ["11111","00010","00100","00010","00001","10001","01110"],
    "4": ["00010","00110","01010","10010","11111","00010","00010"],
    "5": ["11111","10000","11110","00001","00001","10001","01110"],
    "6": ["00110","01000","10000","11110","10001","10001","01110"],
    "7": ["11111","00001","00010","00100","01000","01000","01000"],
    "8": ["01110","10001","10001","01110","10001","10001","01110"],
    "9": ["01110","10001","10001","01111","00001","00010","01100"],
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
    "?": ["01110","10001","00001","00010","00100","00000","00100"],
    " ": ["00000","00000","00000","00000","00000","00000","00000"]
  })
  readonly property var glyph: glyphs[String(character).toUpperCase()] || glyphs["?"]
  property bool settled: false

  Rectangle {
    anchors.fill: parent
    color: tile.well
    border.color: tile.line
    border.width: 1
    visible: !tile.isColon
  }

  // Colon: two accent bits that blink once a second.
  Item {
    visible: tile.isColon
    anchors.fill: parent
    Repeater {
      model: 2
      Rectangle {
        required property int index
        width: tile.cellW; height: tile.cellH
        x: (tile.width - width) / 2
        y: tile.padY + (index === 0 ? 2 : 4) * (tile.cellH + tile.gap)
        color: tile.accent
      }
    }
    SequentialAnimation on opacity {
      running: tile.isColon && tile.visible
      loops: Animation.Infinite
      PropertyAction { value: 1 }
      PauseAnimation { duration: 500 }
      PropertyAction { value: 0 }
      PauseAnimation { duration: 500 }
    }
  }

  Repeater {
    model: tile.isColon ? 0 : tile.columns * tile.rows

    Item {
      id: bit
      required property int index
      readonly property int row: Math.floor(index / tile.columns)
      readonly property int col: index % tile.columns
      readonly property bool target: tile.glyph[row].charAt(col) === "1"
      property bool on: false
      property real angle: 0

      x: tile.padX + col * (tile.cellW + tile.gap)
      y: tile.padY + row * (tile.cellH + tile.gap)
      width: tile.cellW
      height: tile.cellH

      Component.onCompleted: on = target
      onTargetChanged: {
        if (!tile.animated || !tile.visible) { turn.stop(); on = target; angle = 0; return }
        turn.restart()
      }

      Rectangle {
        anchors.fill: parent
        color: bit.on ? tile.foreground : tile.line
        opacity: bit.on ? 1 : 0.55
      }
      transform: Rotation {
        origin.x: bit.width / 2
        origin.y: bit.height / 2
        axis { x: 1; y: 0; z: 0 }
        angle: bit.angle
      }

      SequentialAnimation {
        id: turn
        PauseAnimation { duration: (bit.row * 0.6 + bit.col) * 26 / tile.speed }
        NumberAnimation { target: bit; property: "angle"; from: 0; to: 90; duration: 120 / tile.speed; easing.type: Easing.InQuad }
        ScriptAction { script: bit.on = bit.target }
        NumberAnimation { target: bit; property: "angle"; from: -90; to: 0; duration: 120 / tile.speed; easing.type: Easing.OutQuad }
      }
    }
  }
}
