import QtQuick
import qs.Commons

// Chess piece using filled Unicode chess symbols (same glyph for both colors, color distinguishes).
// Uses the same filled knight glyph (♞) as the bar icon for all pieces.
Item {
    id: root

    property string piece: ""
    property real pieceSize: 40

    // White pieces: pure white
    // Black pieces: theme's darkest background color (Color.background)
    readonly property color fillColor: (piece.length > 0 && piece.toUpperCase() === piece) ? "#ffffff" : Color.background

    width: pieceSize
    height: pieceSize

    // Use filled (black) chess glyphs for both colors - color distinguishes them
    function pieceGlyph(p) {
        if (!p || p === " ") return ""
        switch (p.toUpperCase()) {
            case "K": return "\u265A"  // ♚ Black King
            case "Q": return "\u265B"  // ♛ Black Queen
            case "R": return "\u265C"  // ♜ Black Rook
            case "B": return "\u265D"  // ♝ Black Bishop
            case "N": return "\u265E"  // ♞ Black Knight (matches bar icon)
            case "P": return "\u265F"  // ♟ Black Pawn
        }
        return ""
    }

    readonly property string glyph: pieceGlyph(piece)

    Item {
    anchors.fill: parent
    visible: root.glyph !== ""

    TextMetrics {
        id: metrics
        font.family: "Font Awesome 7 Free"
        font.weight: Font.Black
        font.pixelSize: root.pieceSize * 0.9
        text: root.glyph
    }

    Text {
        id: glyph
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: glyph.implicitWidth / 2 - (metrics.tightBoundingRect.x + metrics.tightBoundingRect.width / 2)
        anchors.verticalCenterOffset: glyph.baselineOffset + metrics.tightBoundingRect.y + metrics.tightBoundingRect.height / 2 - glyph.implicitHeight / 2
        text: root.glyph
        font.family: "Font Awesome 7 Free"
        font.weight: Font.Black
        font.pixelSize: root.pieceSize * 0.9
        color: root.fillColor
        renderType: Text.NativeRendering
    }
}
}