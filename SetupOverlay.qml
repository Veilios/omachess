import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    visible: false

    signal startRequested()

    Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.55)
        border.width: 1
        border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.3)
    }

    Column {
        anchors.centerIn: parent
        spacing: Style.space(10)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Color.popups.text
            font.pixelSize: Style.font.title
            font.bold: true
            text: "New game"
        }

        Button {
            text: "Start game"
            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: root.startRequested()
        }
    }
}