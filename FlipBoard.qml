import QtQuick

// A row of flip tiles that renders `value` in one of the five board styles.
// Pure QtQuick on purpose: the popup, the settings panel, and the standalone
// harness in scripts/ all feed it theme colors from outside.
Item {
  id: board

  property string value: "00:00"
  property string style: "solari"
  property real tileWidth: 62
  property real tileHeight: 80
  property real gap: 7
  property real colonWidth: Math.round(tileWidth * 0.32)
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property color dim: "#565f89"
  property color line: "#2f3349"
  property color well: "#1a1b26"
  property string fontFamily: "monospace"
  property real speed: 1
  property bool animated: true
  // "digits" boards roll like a counter; "alnum" boards carry letters too.
  property string glyphSet: "digits"

  readonly property var styleFiles: ({
    solari: "FlipSolari.qml",
    bits: "FlipBits.qml",
    drum: "FlipDrum.qml",
    sweep: "FlipSweep.qml",
    step: "FlipStep.qml"
  })
  readonly property url styleSource: Qt.resolvedUrl(styleFiles[style] || styleFiles.solari)

  implicitWidth: row.implicitWidth
  implicitHeight: tileHeight

  Row {
    id: row
    spacing: board.gap

    Repeater {
      model: board.value.length

      Loader {
        id: slot
        required property int index
        readonly property string character: board.value.charAt(index)
        width: character === ":" ? board.colonWidth : board.tileWidth
        height: board.tileHeight

        // The character rides along as an initial property so a freshly built
        // tile settles silently instead of flipping in from its default.
        function load() { setSource(board.styleSource, { character: character, glyphSet: board.glyphSet }) }
        Component.onCompleted: load()
        Connections { target: board; function onStyleSourceChanged() { slot.load() } }

        onCharacterChanged: if (item) item.character = character
        onLoaded: {
          item.foreground = Qt.binding(function() { return board.foreground })
          item.accent = Qt.binding(function() { return board.accent })
          item.dim = Qt.binding(function() { return board.dim })
          item.line = Qt.binding(function() { return board.line })
          item.well = Qt.binding(function() { return board.well })
          item.fontFamily = Qt.binding(function() { return board.fontFamily })
          item.speed = Qt.binding(function() { return board.speed })
          item.animated = Qt.binding(function() { return board.animated })
          item.glyphSet = Qt.binding(function() { return board.glyphSet })
        }
      }
    }
  }
}
