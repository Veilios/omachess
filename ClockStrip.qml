import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

RowLayout {
    id: root
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredHeight: Style.space(22)
    spacing: Style.space(6)
    visible: root.timeControl !== null

    property var timeControl: null
    property int humanClock: 0
    property int aiClock: 0
    property string clockActive: ""
    property string humanColor: "w"
    property string aiColor: "b"
    property color foreground: Color.popups.text
    property int boardWidth: 0

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: (root.boardWidth - Style.space(6)) / 2
        Layout.fillHeight: true
        radius: Style.space(4)
        color: root.clockActive === root.humanColor
               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
               : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

        Text {
            anchors.centerIn: parent
            color: root.clockActive === root.humanColor && root.humanClock <= 10000 ? Color.urgent : root.foreground
            font.pixelSize: Style.font.body
            font.bold: root.clockActive === root.humanColor
            text: "You " + root.formatClock(root.humanClock)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: (root.boardWidth - Style.space(6)) / 2
        Layout.fillHeight: true
        radius: Style.space(4)
        color: root.clockActive === root.aiColor
               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
               : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

        Text {
            anchors.centerIn: parent
            color: root.clockActive === root.aiColor && root.aiClock <= 10000 ? Color.urgent : root.foreground
            font.pixelSize: Style.font.body
            font.bold: root.clockActive === root.aiColor
            text: "AI " + root.formatClock(root.aiClock)
        }
    }

    function formatClock(ms) {
        var total = Math.max(0, Math.round(ms / 1000))
        function pad(n) { return n < 10 ? "0" + n : String(n) }
        if (total >= 3600) {
            return Math.floor(total / 3600) + ":" + pad(Math.floor((total % 3600) / 60)) + ":" + pad(total % 60)
        }
        return Math.floor(total / 60) + ":" + pad(total % 60)
    }
}