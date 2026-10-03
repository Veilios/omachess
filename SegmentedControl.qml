import QtQuick
import qs.Commons

// A joined segmented control: every option lives in one rounded bar and the
// active one is filled, instead of N separate buttons.
//
// The shell's own qs.Ui.Button already paints a selected fill, but each button
// brings its own border and padding, so N of them read as N loose chips and
// cost ~5px more height each. Here the segments share a single surface, which
// is both the more conventional settings look and the more compact one.
Item {
    id: root

    // [{ label: "White", value: "w" }, ...]
    property var model: []
    property int currentIndex: 0

    // Reuse the shell's selected fill so this stays consistent with every other
    // selected control in the shell, on any theme.
    //
    // selectedFillFor, NOT selectedStateColor. Both read the same
    // `selected-color` token, but the Color variant hands back the solid
    // foreground while the Fill variant wraps it in the shell's selected-fill
    // alpha (0.18). The token defaults to "foreground", so the solid variant
    // painted a #cacccc pill directly behind a #cacccc label: 1.00:1, which
    // meant the selected option was the one you could not read, and only the
    // unselected ones were legible. This is what qs.Ui.Button uses; see
    // Button.qml.
    property color selectedFill: Style.selectedFillFor(Color.popups.text, Color.accent)
    property color baseFill: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.06)
    property color borderColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.18)
    property color dividerColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)
    property color textColor: Color.popups.text

    signal activated(int index)

    readonly property real padH: Style.space(5)
    readonly property real padV: Style.space(4)
    // Measure off a real Text's implicitHeight. fontMetrics.height on an
    // offscreen/invisible Text is not reliably populated, which collapsed the
    // bar to its padding and let the labels overflow it.
    readonly property real innerH: Math.max(Math.round(Style.font.bodySmall * 1.2),
                                           label0.implicitHeight)

    implicitHeight: innerH + padV * 2 + 2
    implicitWidth: row.implicitWidth + 2
    height: implicitHeight

    Text {
        id: label0
        visible: false
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        text: "Ag"
    }

    Rectangle {
        id: bar
        anchors.fill: parent
        radius: height / 2
        color: root.baseFill
        border.width: 1
        border.color: root.borderColor

        Row {
            id: row
            x: 1
            y: 1
            height: bar.height - 2

            Repeater {
                model: root.model

                Item {
                    id: segment
                    required property int index
                    required property var modelData

                    readonly property bool active: index === root.currentIndex
                    readonly property real labelW: segText.implicitWidth

                    width: segText.implicitWidth + root.padH * 2
                    height: row.height

                    // Active fill, inset by 2px so the bar's own border and
                    // radius stay visible around it.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: height / 2
                        color: root.selectedFill
                        visible: segment.active
                    }

                    // Divider between segments, suppressed on the first.
                    Rectangle {
                        x: 0
                        y: segment.height * 0.22
                        width: 1
                        height: segment.height * 0.56
                        color: root.dividerColor
                        visible: !segment.active && index > 0
                    }

                    Text {
                        id: segText
                        anchors.centerIn: parent
                        text: segment.modelData.label
                        color: root.textColor
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: segment.active
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activated(segment.index)
                    }
                }
            }
        }
    }
}
