import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Column {
    id: root
    Layout.fillWidth: true
    spacing: Style.space(8)

    property color foreground: Color.popups.text
    property string fontFamily: Style.font.family

    property string humanColorSetting: "w"
    property int chessClockSetting: 30 * 60000
    property bool pomodoroModeSetting: true
    property int pomodoroTimeSetting: 10
    property bool settingsDirty: false
    property var clockPresets: []

    signal humanColorChanged(string color)
    signal chessClockChanged(int ms)
    signal pomodoroModeChanged(bool enabled)
    signal pomodoroTimeChanged(int seconds)

    readonly property color muted: Qt.darker(foreground, 1.5)
    readonly property color faint: Qt.darker(foreground, 1.9)

    Column {
        width: parent.width
        spacing: Style.space(4)

        Text {
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
            text: "Play as"
        }

        Row {
            spacing: Style.space(4)

            Button {
                text: (root.humanColorSetting === "w" ? "• " : "") + "White"
                onClicked: root.humanColorChanged("w")
            }
            Button {
                text: (root.humanColorSetting === "b" ? "• " : "") + "Black"
                onClicked: root.humanColorChanged("b")
            }
        }
    }

    Column {
        width: parent.width
        spacing: Style.space(4)

        Text {
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
            text: "Time per player"
        }

        Row {
            spacing: Style.space(4)
            Repeater {
                model: root.clockPresets
                Button {
                    text: (root.chessClockSetting === modelData.base ? "• " : "") + modelData.label
                    onClicked: root.chessClockChanged(modelData.base)
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Style.space(4)

        Text {
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
            text: "Pomodoro"
        }

        Text {
            visible: root.settingsDirty
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            text: "Changes apply on next game."
        }

        Row {
            spacing: Style.space(4)

            Button {
                text: (root.pomodoroModeSetting ? "• " : "") + "On"
                onClicked: root.pomodoroModeChanged(true)
            }
            Button {
                text: (!root.pomodoroModeSetting ? "• " : "") + "Off"
                onClicked: root.pomodoroModeChanged(false)
            }
        }

        Row {
            visible: root.pomodoroModeSetting
            spacing: Style.space(4)

            Repeater {
                model: [10, 15, 30, 60, 120]
                Button {
                    text: (root.pomodoroTimeSetting === modelData ? "• " : "") + modelData + "s"
                    onClicked: root.pomodoroTimeChanged(modelData)
                }
            }
        }
    }
}