import QtQuick
import QtQuick.Effects
import qs.Commons

// Interactive 8x8 chess board. Pure view: all game logic lives in Main.qml.
// State comes in through `position` (64-char board slice), selection,
// targets, last move and check highlight; user intent leaves through
// `clicked`, `promotionChosen` and `promotionCancelled` signals. Move animation is
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
  property bool blurOverlay: false        // blur requested by an overlay, with no label
  readonly property bool blurred: blurActive || blurOverlay
  property string blurClockText: ""       // live countdown to show over the blur
  property string blurTitle: "AI thinking…"  // label shown over the blur
  property bool useRealBlur: true
  property bool flipped: false            // true when playing as black (board rotated 180°)

  signal clicked(int sq)
  signal promotionChosen(string piece)
  signal promotionCancelled()
  signal slideFinished()

  width: square * 8
  height: square * 8

  // Two square tones derived from the theme so they behave on light and dark
  // alike. Qt.lighter/Qt.darker scale channels multiplicatively, which barely
  // moves luminance on a near-black background -- a 2.2x lift of #0c0b0c lands
  // at #1a181a, only 1.15:1, so the board pattern itself became unreadable,
  // and the highlight lifts were worse: 1.45x of the dark square is 1.03:1.
  // Blending a fixed step toward a target colour instead yields a predictable
  // luminance ramp, and because it interpolates toward whatever the theme's
  // text is, the tones separate properly on light themes too.
  function mixToward(from, to, f) {
    return Qt.rgba(from.r + (to.r - from.r) * f,
                   from.g + (to.g - from.g) * f,
                   from.b + (to.b - from.b) * f,
                   1.0)
  }

  readonly property color sqDark: Color.popups.background
  readonly property color sqLight: mixToward(sqDark, Color.popups.text, 0.30)
  readonly property color sqSelected: mixToward(sqDark, Color.popups.text, 0.58)
  readonly property color sqLastMove: Color.accent

  // Piece box as a fraction of the square. Single source of truth: the static
  // pieces, the two slide overlays and beginSlide's centring offset all derive
  // from it, so shrinking the pieces can't leave the animation offset behind.
  // 0.85 crowded the square's edges; 0.68 overcorrected once the square
  // itself shrank, so this is a middle setting that keeps clear margins at
  // the panel's default size.
  readonly property real pieceScale: 0.75
  readonly property real pieceBox: square * pieceScale

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
    if (i === selected) return sqSelected
    return (f + r) % 2 ? sqDark : sqLight
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
    var off = (root.square - root.pieceBox) / 2
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

  // How far the blur stage extends past the board on every side. It only has to
  // exceed the blur radius (about 2px at blur 1.0 / blurMax 32); 4 leaves
  // headroom if the blur is ever strengthened.
  readonly property int blurPad: 4

  // ---- board visuals (grouped so the blur can capture them) ----------------
  Item {
    // Deliberately larger than the board. ShaderEffectSource captures its
    // sourceItem's own bounds, so growing the *source* is the only way to give
    // the blur kernel real texels past the board's edge. Growing the
    // ShaderEffectSource instead just adds transparent padding the kernel never
    // reaches, and the boundary clamps: measured on screen, the board's outer
    // edge carried a 21.8 single-pixel gradient against an interior 99.5th
    // percentile of 9.7, i.e. a visible 1px rim.
    //
    // boardVisual sits inset by blurPad inside this stage and keeps the board's
    // own coordinate space, so every child below (squares, markers, pieces,
    // sliders) still positions itself with root.sqX()/sqY() unchanged. The pad
    // is filled with the dark square tone so the blur has something to sample;
    // blurred and dimmed, it reads as a soft edge rather than a frame.
    id: boardStage
    x: -root.blurPad
    y: -root.blurPad
    width: parent.width + root.blurPad * 2
    height: parent.height + root.blurPad * 2

    Rectangle {
      anchors.fill: parent
      color: root.sqDark
    }

    Item {
      id: boardVisual
      x: root.blurPad
      y: root.blurPad
      width: parent.width - root.blurPad * 2
      height: parent.height - root.blurPad * 2

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

    // ---- last-move markers ---------------------------------------------------
    // A border rather than a fill: recolouring the square itself would have to
    // fight the piece sitting on it. Tinting toward the accent collapses on
    // light themes, where the accent sits close to the text colour and a white
    // piece on a tinted square drops to ~1.0:1. An outline leaves the square's
    // luminance untouched, so the piece keeps full contrast, and it cannot be
    // confused with the selection, which is a fill. A square that is both gets
    // only the selection, so each highlighted square reads as exactly one state
    // (the accent border is invisible against the bright selection fill).
    Repeater {
      model: [root.lastFrom, root.lastTo]
      Rectangle {
        required property int modelData
        readonly property bool on: modelData >= 0 && modelData !== root.selected
        visible: on
        x: root.sqX(modelData) + 1
        y: root.sqY(modelData) + 1
        width: Math.max(0, root.square - 2)
        height: Math.max(0, root.square - 2)
        color: "transparent"
        border.width: Math.max(1, Math.round(root.square * 0.06))
        border.color: root.sqLastMove
        radius: border.width
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
      border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.75)
      radius: root.square * 0.12
    }

    // ---- pieces ---------------------------------------------------------------
    Repeater {
      model: 64
      Piece {
        anchors.centerIn: undefined
        x: root.sqX(index) + (root.square - width) / 2
        y: root.sqY(index) + (root.square - height) / 2
        width: root.pieceBox
        height: root.pieceBox
        pieceSize: root.pieceBox
        visible: root.pieceAt(index) !== " " && !root.isSliding(index)
        piece: root.pieceAt(index)
      }
    }

    // ---- sliding overlays (drawn above the static pieces) -----------------------
    Piece {
      id: slider
      z: 20
      visible: false
      width: root.pieceBox
      height: root.pieceBox
      pieceSize: root.pieceBox
    }

    Piece {
      id: rookSlider
      z: 20
      visible: false
      width: root.pieceBox
      height: root.pieceBox
      pieceSize: root.pieceBox
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
  }

  // ---- AI-thinking blur overlay ------------------------------------------------
  // captureSource and blurFx both track boardStage, not the board: the blur has
  // to cover the padded stage, and keeping the two the same size keeps them 1:1
  // so the board is not scaled to fit. blurPad only has to exceed the blur
  // radius, which at blur 1.0 / blurMax 32 is about 2px; 4 leaves headroom for
  // a stronger blur.
  ShaderEffectSource {
    id: captureSource
    x: boardStage.x
    y: boardStage.y
    width: boardStage.width
    height: boardStage.height
    sourceItem: boardStage
    live: true
    hideSource: root.blurred
    visible: root.blurred
  }

  MultiEffect {
    id: blurFx
    x: boardStage.x
    y: boardStage.y
    width: boardStage.width
    height: boardStage.height
    source: captureSource
    visible: root.blurred
    blurEnabled: root.blurred && root.useRealBlur
    blur: 1.0
    blurMax: 32
    brightness: root.useRealBlur ? -0.12 : -0.52
    saturation: root.blurred ? 0.85 : 1.0
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
        color: Color.popups.text
        font.pixelSize: root.square * 0.3
        font.bold: true
        text: root.blurTitle
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: Color.popups.text
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
    onPressed: root.promotionCancelled()

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
              onClicked: root.promotionChosen(String(modelData))
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