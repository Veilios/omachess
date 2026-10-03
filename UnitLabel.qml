import QtQuick
import qs.Commons

// A settings row label split into a word and a smaller, dimmer unit suffix --
// "Clock" + "(min)". Two Texts rather than one string, so the unit can drop a
// step in size without shrinking the word it qualifies.
Item {
    id: root

    property string text: ""
    property string unitText: ""
    property color textColor: Color.popups.text
    property color unitColor: Color.muted
    property string fontFamily: Style.font.family

    // 0.8 of the label size, floored at 7px so it stays legible and never
    // inverts against a very small caption token.
    readonly property int unitPx: Math.max(7, Math.round(Style.font.caption * 0.8))

    // The real rendered width, so the settings column can be sized from what is
    // drawn. Two TextMetrics mirroring these two strings used to stand in for
    // this, which meant the measurement had to be kept in sync by hand.
    readonly property real contentWidth: main.implicitWidth + unit.implicitWidth

    implicitWidth: contentWidth
    implicitHeight: main.implicitHeight

    Text {
        id: main

        anchors.left: parent.left
        anchors.top: parent.top

        text: root.text
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
    }

    Text {
        id: unit

        anchors.left: main.right
        // The reason this is not a Row: a Row top-aligns its children, and the
        // unit is 2px smaller, so its baseline lands that much above the word's
        // and the pair reads as floating rather than as one label. Anchoring to
        // the word's own baseline is what actually puts them on one line --
        // vertically centring the pair instead would still separate them,
        // because a smaller line box centres its baseline higher.
        anchors.baseline: main.baseline

        text: root.unitText
        color: root.unitColor
        font.family: root.fontFamily
        font.pixelSize: root.unitPx
        font.letterSpacing: 1
    }
}