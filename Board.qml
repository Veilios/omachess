import QtQuick
import QtQuick.Effects
import qs.Commons

// Interactive 8x8 chess board. Pure view: all game logic lives in Main.qml.
// State comes in through `position` (64-char board slice), selection,
// targets, last move and check highlight; user intent leaves through
// `clicked`, `promoChosen` and `promoCancelled` signals. Move animation is
// driven by `beginSlide`; the AI "thinking" state by `blurActive`/`blurClockText`.
Item {
  id: root

  property string position: ""            // 64 chars, index = rank*8 + file (a1=0)
  property string turnColor: "w"          // "w" | "b"
  property int selected: -1
  property var targets: []                // destination squares for `selected`
  property int lastFrom: -1
  property int lastTo: -1
  property int checkSq: -1
  property bool interactive: true
  property int square: 39
  property var promotion: null            // { to, color } when a picker is up
  property int slideDuration: 200
  property var slide: null                // active slide spec { from,to,fromChar,rookFrom,... }
  property bool blurActive: false         // board blurred + countdown
  property string blurClockText: ""       // live countdown to show over the blur
  property string blurTitle: "AI thinking…"  // label shown over the blur
  property bool useRealBlur: true
  property bool flipped: false            // true when playing as black (board rotated 180°)

  signal clicked(int sq)
  signal promoChosen(string piece)
  signal promoCancelled()
  signal slideFinished()

  width: square * 8
  height: square * 8

  readonly property color sqLight: Qt.lighter(Color.popups.background, 1.5)
  readonly property color sqDark: Qt.darker(Color.popups.background, 2.2)

  function pieceAt(i) {
    if (i < 0 || i > 63 || position.length !== 64) return " "
    return position.charAt(i)
  }

  function sqX(i) {
    var f = flipped ? 7 - (i & 7) : (i & 7)
    return f * square
  }

  function sqY(i) {
    var r = flipped ? (i >> 3) : 7 - (i >> 3)
    return r * square
  }

  function sqAt(px, py) {
    var f = Math.floor(px / square)
    var r = 7 - Math.floor(py / square)
    if (flipped) { f = 7 - f; r = 7 - r; }
    if (f < 0 || f > 7 || r < 0 || r > 7) return -1
    return (r << 3) | f
  }

  function squareColor(i) {
    var f = i & 7
    var r = i >> 3
    var base = (f + r) % 2 ? sqDark : sqLight
    if (i === selected) return Qt.lighter(base, 1.45)
    if (i === lastFrom || i === lastTo) return Qt.lighter(base, 1.12)
    return base
  }

  function isSliding(i) {
    if (!slide) return false
    if (i === slide.from) return true
    if (slide.rookFrom !== undefined && slide.rookFrom >= 0 && i === slide.rookFrom) return true
    return false
  }

  function beginSlide(spec) {
    if (slide) cancelSlide()
    slide = spec
    var off = (root.square - root.square * 0.85) / 2
    slider.piece = spec.fromChar
    slider.x = sqX(spec.from) + off
    slider.y = sqY(spec.from) + off
    slider.visible = true
    slideAnimX.from = slider.x
    slideAnimX.to = sqX(spec.to) + off
    slideAnimY.from = slider.y
    slideAnimY.to = sqY(spec.to) + off
    slideAnim.start()
    if (spec.rookFrom >= 0) {
      rookSlider.piece = spec.rookChar
      rookSlider.x = sqX(spec.rookFrom) + off
      rookSlider.y = sqY(spec.rookFrom) + off
      rookSlider.visible = true
      rookAnimX.from = rookSlider.x
      rookAnimX.to = sqX(spec.rookTo) + off
      rookAnimY.from = rookSlider.y
      rookAnimY.to = sqY(spec.rookTo) + off
      rookAnim.start()
    }
  }

  function finishSlide() {
    slider.visible = false
    rookSlider.visible = false
    rookAnim.stop()
    slide = null
    root.slideFinished()
  }

  function cancelSlide() {
    slideAnim.stop()
    rookAnim.stop()
    slider.visible = false
    rookSlider.visible = false
    slide = null
  }

  // ---- board visuals (grouped so the blur can capture them) ----------------
  Item {
    id: boardVisual
    anchors.fill: parent

    // ---- squares -----------------------------------------------------------
    Repeater {
      model: 64
      Rectangle {
        x: root.sqX(index)
        y: root.sqY(index)
        width: root.square
        height: root.square
        color: root.squareColor(index)
      }
    }

    // ---- legal-move markers -------------------------------------------------
    Repeater {
      model: root.targets
      Rectangle {
        readonly property bool capture: root.pieceAt(modelData) !== " "
        x: root.sqX(modelData) + (root.square - (capture ? root.square * 0.44 : root.square * 0.26)) / 2
        y: root.sqY(modelData) + (root.square - (capture ? root.square * 0.44 : root.square * 0.26)) / 2
        width: capture ? root.square * 0.44 : root.square * 0.26
        height: capture ? root.square * 0.44 : root.square * 0.26
        radius: width / 2
        color: capture ? "transparent"
                       : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.28)
        border.width: capture ? Math.max(2, root.square * 0.055) : 0
        border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.5)
      }
    }

    // ---- check ring ----------------------------------------------------------
    Rectangle {
      visible: root.checkSq >= 0 && root.checkSq <= 63
      x: root.sqX(root.checkSq)
      y: root.sqY(root.checkSq)
      width: root.square
      height: root.square
      color: "transparent"
      border.width: Math.max(2, root.square * 0.06)
      border.color: Qt.rgba(0.9, 0.13, 0.1, 0.75)
      radius: root.square * 0.12
    }

    // ---- pieces ---------------------------------------------------------------
    Repeater {
      model: 64
      Piece {
        anchors.centerIn: undefined
        x: root.sqX(index) + (root.square - width) / 2
        y: root.sqY(index) + (root.square - height) / 2
        width: root.square * 0.85
        height: root.square * 0.85
        pieceSize: root.square * 0.85
        visible: root.pieceAt(index) !== " " && !root.isSliding(index)
        piece: root.pieceAt(index)
      }
    }

    // ---- sliding overlays (drawn above the static pieces) -----------------------
    Piece {
      id: slider
      z: 20
      visible: false
      width: root.square * 0.85
      height: root.square * 0.85
      pieceSize: root.square * 0.85
    }

    Piece {
      id: rookSlider
      z: 20
      visible: false
      width: root.square * 0.85
      height: root.square * 0.85
      pieceSize: root.square * 0.85
    }

    ParallelAnimation {
      id: slideAnim
      NumberAnimation { id: slideAnimX; target: slider; property: "x"; duration: root.slideDuration; easing.type: Easing.InOutCubic }
      NumberAnimation { id: slideAnimY; target: slider; property: "y"; duration: root.slideDuration; easing.type: Easing.InOutCubic }
      onFinished: root.finishSlide()
    }

    ParallelAnimation {
      id: rookAnim
      NumberAnimation { id: rookAnimX; target: rookSlider; property: "x"; duration: root.slideDuration; easing.type: Easing.InOutCubic }
      NumberAnimation { id: rookAnimY; target: rookSlider; property: "y"; duration: root.slideDuration; easing.type: Easing.InOutCubic }
    }
  }

  // ---- AI-thinking blur overlay ------------------------------------------------
  ShaderEffectSource {
    id: captureSource
    anchors.fill: parent
    sourceItem: boardVisual
    live: true
    hideSource: root.blurActive
    visible: root.blurActive
  }

  MultiEffect {
    id: blurFx
    anchors.fill: parent
    source: captureSource
    visible: root.blurActive
    blurEnabled: root.blurActive && root.useRealBlur
    blur: 1.0
    blurMax: 32
    brightness: root.useRealBlur ? -0.12 : -0.52
    saturation: root.blurActive ? 0.85 : 1.0
  }

  Item {
    id: blurInfo
    anchors.fill: parent
    visible: root.blurActive

    Column {
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "#ffffff"
        font.pixelSize: root.square * 0.3
        font.bold: true
        text: root.blurTitle
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "#ffffff"
        font.pixelSize: root.square * 0.62
        font.bold: true
        text: root.blurClockText
      }
    }
  }

  // ---- clicks ----------------------------------------------------------------
  MouseArea {
    anchors.fill: parent
    enabled: root.interactive && root.promotion === null
    onClicked: function(mouse) { root.clicked(root.sqAt(mouse.x, mouse.y)) }
  }

  // ---- promotion picker ------------------------------------------------------
  MouseArea {
    anchors.fill: parent
    visible: root.promotion !== null && root.interactive
    onPressed: root.promoCancelled()

    Column {
      anchors.verticalCenter: parent.verticalCenter
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 2

      Row {
        spacing: 2
        Repeater {
          model: ["Q", "N", "R", "B"]
          Rectangle {
            id: promoCell
            readonly property string promoChar: {
              if (!root.promotion) return ""
              return root.promotion.color === "w" ? String(modelData) : String(modelData).toLowerCase()
            }
            width: root.square * 0.94
            height: root.square * 0.94
            radius: width * 0.14
            color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.95)
            border.width: 1
            border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.35)

            Piece {
              anchors.centerIn: parent
              width: parent.width - 8
              height: parent.height - 8
              pieceSize: parent.width - 8
              piece: promoCell.promoChar
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.promoChosen(String(modelData))
            }
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.7)
        font.pixelSize: root.square * 0.32
        text: "Promote to"
      }
    }
  }
}