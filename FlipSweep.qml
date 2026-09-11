import QtQuick

// 04 Sweep. Borrowed from the radar: an accent scan bar sweeps down the tile,
// erasing the old digit above it and painting the new one in behind. Fresh
// paint lands as accent raster first and hardens into solid foreground once
// the bar has passed. A faint dot grid sits behind every tile.
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
  readonly property real band: 0.22

  property string current: ""
  property string incoming: ""
  // 0 = at rest, 0..1 = bar travelling, 1..1+band = last raster hardening.
  property real progress: 0
  readonly property real barPos: Math.min(1, progress)
  readonly property real hardPos: Math.max(0, Math.min(1, barPos - band + Math.max(0, progress - 1)))
  readonly property real barY: barPos * height
  readonly property real hardY: hardPos * height

  Component.onCompleted: current = character
  onCharacterChanged: {
    if (isColon) return
    if (current === "" || !animated || !visible) { sweep.stop(); current = character; progress = 0; return }
    incoming = character
    sweep.restart()
  }

  SequentialAnimation {
    id: sweep
    ScriptAction { script: tile.progress = 0 }
    NumberAnimation { target: tile; property: "progress"; from: 0; to: 1; duration: 480 / tile.speed; easing.type: Easing.InOutQuad }
    NumberAnimation { target: tile; property: "progress"; from: 1; to: 1 + tile.band; duration: 160 / tile.speed; easing.type: Easing.Linear }
    ScriptAction { script: { tile.current = tile.incoming; tile.progress = 0 } }
  }

  Rectangle {
    anchors.fill: parent
    color: tile.well
    border.color: tile.line
    border.width: 1
    visible: !tile.isColon
  }

  // Raster ground behind the digit.
  Canvas {
    id: ground
    visible: !tile.isColon
    anchors.fill: parent
    anchors.margins: 1
    opacity: 0.5
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections { target: tile; function onLineChanged() { ground.requestPaint() } }
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = tile.line
      for (var y = 3; y < height; y += 6)
        for (var x = 3; x < width; x += 6) ctx.fillRect(x - 0.5, y - 0.5, 1.2, 1.2)
    }
  }

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
    SequentialAnimation on opacity {
      running: tile.isColon && tile.visible
      loops: Animation.Infinite
      PropertyAction { value: 1 }
      PauseAnimation { duration: 500 }
      PropertyAction { value: 0 }
      PauseAnimation { duration: 500 }
    }
  }

  component Glyph: Text {
    width: tile.width
    height: tile.height
    color: tile.foreground
    font.family: tile.fontFamily
    font.pixelSize: tile.glyphSize
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  Item {
    visible: !tile.isColon
    anchors.fill: parent

    // Old digit: still visible below the bar.
    Item {
      y: tile.barY
      width: parent.width
      height: Math.max(0, parent.height - tile.barY)
      clip: true
      Glyph { y: -tile.barY; text: tile.current }
    }

    // New digit, hardened: above the raster band.
    Item {
      width: parent.width
      height: tile.hardY
      clip: true
      Glyph { text: tile.incoming }
    }

    // New digit, wet: accent raster between the hardened edge and the bar.
    Item {
      id: wet
      y: tile.hardY
      width: parent.width
      height: Math.max(0, tile.barY - tile.hardY)
      clip: true
      Glyph { y: -wet.y; text: tile.incoming; color: tile.accent }
      Canvas {
        id: mesh
        y: -wet.y
        width: tile.width
        height: tile.height
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: tile; function onWellChanged() { mesh.requestPaint() } }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.fillStyle = tile.well
          for (var y = 0; y < height; y += 3) ctx.fillRect(0, y, width, 1)
          for (var x = 0; x < width; x += 3) ctx.fillRect(x, 0, 1, height)
        }
      }
    }

    // The scan bar and its glow.
    Rectangle {
      visible: tile.progress > 0
      x: 0; width: parent.width
      y: tile.barY - 3; height: 6
      color: tile.accent
      opacity: (tile.progress <= 1 ? 0.28 : 0.28 * (1 - (tile.progress - 1) / tile.band))
    }
    Rectangle {
      visible: tile.progress > 0
      x: 0; width: parent.width
      y: tile.barY - 1; height: 2
      color: tile.accent
      opacity: tile.progress <= 1 ? 1 : 1 - (tile.progress - 1) / tile.band
    }
  }
}
