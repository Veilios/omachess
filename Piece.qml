import QtQuick
import qs.Commons

// Chess piece using filled Unicode chess symbols (same glyph for both colors, color distinguishes).
// Uses the same filled knight glyph (♞) as the bar icon for all pieces.
Item {
    id: root

    property string piece: ""
    property real pieceSize: 40

    readonly property bool isWhite: piece.length > 0 && piece.toUpperCase() === piece

    // A flat fill cannot work on a two-tone board: with only two square
    // shades, anything sitting between them is close to both, and the
    // background tone sits almost exactly between. So each piece pairs its
    // fill with an edge in the opposite tone — the standard chess-UI
    // solution. White reads by its fill, black by its light edge, and both
    // tones come from the palette so this survives a theme change.
    readonly property color fillColor: isWhite ? Color.popups.text : Color.background
    readonly property color outlineColor: isWhite ? Color.background : Color.popups.text

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
        style: Text.Outline
        styleColor: root.outlineColor
        renderType: Text.NativeRendering
    }
}
}