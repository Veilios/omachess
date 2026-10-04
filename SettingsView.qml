import QtQuick
import QtQuick.Layouts
import qs.Commons

// Settings shown as an overlay on the board.
//
// The board is only ~296px tall, and the previous stacked layout (a caption
// line above every group) needed ~336px, so it could not fit without
// scrolling. Two changes fixed that: labels sit inline to the left of their
// control instead of on their own line, and the controls are segmented bars
// rather than separate buttons, which are both shorter and narrower. Numeric
// Numeric presets drop their "min" suffix to keep the segmented bar on one
    // row -- "10 min" x5 was 377px wide against 282px available and wrapped to two
// rows. Repeating the unit on all five would be worse, so it goes on the row
// label instead: "Clock (min)" and "Focus timer (min)", both drawn by UnitLabel
// so the word and its unit share a baseline and stay consistent with each other.
Column {
    id: root
    Layout.fillWidth: true
    spacing: Style.space(10)

    property color foreground: Color.popups.text
    property string fontFamily: Style.font.family

    property string humanColorSetting: "w"
    property int chessClockSetting: 30 * 60000
    property bool pomodoroModeSetting: true
    property int pomodoroTimeSetting: 10
    property bool popupsSetting: true
    property int undoLimitSetting: -1
    property bool settingsDirty: false
    property var clockPresets: []

    signal humanColorChanged(string color)
    signal chessClockChanged(int ms)
    signal pomodoroModeChanged(bool enabled)
    signal pomodoroTimeChanged(int minutes)
    signal popupsChanged(bool enabled)
    signal undoLimitChanged(int value)

    readonly property color faint: Qt.darker(foreground, 1.1)
    readonly property var pomodoroPresets: [10, 15, 30, 60, 120]

    // 0 is Off, -1 is unlimited. The unlimited option is labelled with the
    // infinity sign rather than the word, purely to keep the bar narrow enough
    // not to wrap -- same reasoning as dropping the "min" suffix from the
    // numeric presets.
    readonly property var undoModel: [
        { label: "Off", value: 0 },
        { label: "3", value: 3 },
        { label: "5", value: 5 },
        { label: "10", value: 10 },
        // widthChars gives the infinity sign the same room as the two-digit
        // "10" beside it; a lone narrow glyph otherwise sits in a pill that is
        // visibly tighter than its neighbours.
        { label: "∞", value: -1, widthChars: 2 }
    ]

    // Every label shares one width so the controls line up on the right. The
    // widest plain-text label is named here and measured once: TextMetrics.width
    // is a property rather than a callable, so it cannot measure each string on
    // demand without mutating the element inside a binding. A new plain label
    // longer than this must be renamed here too, or it gets clipped.
    //
    // The two unit rows ("Clock (min)", "Focus timer (min)") are not measured
    // here at all -- UnitLabel reports its own real implicitWidth, so those rows
    // contribute what they actually render rather than a hand-mirrored estimate.
    //
    // "Notifications" at 12 characters is the longest of the plain labels:
    // "Play as" and "Lock In" are 7 each.
    readonly property string widestLabel: "Notifications"

    TextMetrics {
        id: labelMetrics
        text: root.widestLabel
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
    }

    // Widest of: the measured plain label, and the two UnitLabel rows.
    readonly property int labelWidth: Math.max(labelMetrics.width, clockRow.contentWidth, focusRow.contentWidth) + Style.space(6)

    function indexOfValue(list, value) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].value === value) return i
        }
        return 0
    }

    // Clock presets carry minutes in `base` (ms). Off is base 0.
    readonly property var clockModel: {
        var out = []
        for (var i = 0; i < clockPresets.length; i++) {
            var p = clockPresets[i]
            out.push({ label: p.base === 0 ? "Off" : String(Math.round(p.base / 60000)), value: p.base })
        }
        return out
    }

    readonly property var sideModel: [
        { label: "White", value: "w" },
        { label: "Black", value: "b" }
    ]

    readonly property var onOffModel: [
        { label: "On", value: true },
        { label: "Off", value: false }
    ]

    readonly property var timeModel: {
        var out = []
        for (var i = 0; i < pomodoroPresets.length; i++) {
            out.push({ label: String(pomodoroPresets[i]), value: pomodoroPresets[i] })
        }
        return out
    }

    // ---- title -------------------------------------------------------------
    Item {
        width: parent.width
        height: titleText.implicitHeight

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            text: "Settings"
        }

        // Unsaved indicator. A chip rather than its own line, so it costs no
        // extra height when it appears.
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.settingsDirty
            implicitWidth: unsavedText.implicitWidth + Style.space(5) * 2
            implicitHeight: unsavedText.implicitHeight + Style.space(2) * 2
            width: implicitWidth
            height: implicitHeight
            radius: height / 2
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)

            Text {
                id: unsavedText
                anchors.centerIn: parent
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                text: "Unsaved"
            }
        }
    }

    // ---- Play as -----------------------------------------------------------
    Item {
        width: parent.width
        height: sideSeg.implicitHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.labelWidth - Style.space(6)
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            text: "Play as"
        }

        SegmentedControl {
            id: sideSeg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: root.sideModel
            currentIndex: root.indexOfValue(root.sideModel, root.humanColorSetting)
            onActivated: function(index) { root.humanColorChanged(root.sideModel[index].value) }
        }
    }

    // ---- Time per player ---------------------------------------------------
    Item {
        width: parent.width
        height: clockSeg.implicitHeight

        UnitLabel {
            id: clockRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Clock"
            unitText: "(min)"
            textColor: root.faint
        }

        SegmentedControl {
            id: clockSeg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: root.clockModel
            currentIndex: root.indexOfValue(root.clockModel, root.chessClockSetting)
            onActivated: function(index) { root.chessClockChanged(root.clockModel[index].value) }
        }
    }

    // ---- Lock In ------------------------------------------------------------
    Item {
        width: parent.width
        height: pomoSeg.implicitHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.labelWidth - Style.space(6)
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            text: "Lock In"
        }

        SegmentedControl {
            id: pomoSeg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: root.onOffModel
            currentIndex: root.indexOfValue(root.onOffModel, root.pomodoroModeSetting)
            onActivated: function(index) { root.pomodoroModeChanged(root.onOffModel[index].value) }
        }
    }

    // Focus timer length, hidden with the mode. There is height budget for it
    // either way, so this only removes clutter. Values are minutes.
    Item {
        width: parent.width
        height: timeSeg.implicitHeight
        visible: root.pomodoroModeSetting

        UnitLabel {
            id: focusRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Focus timer"
            unitText: "(min)"
            textColor: root.faint
        }

        SegmentedControl {
            id: timeSeg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: root.timeModel
            currentIndex: root.indexOfValue(root.timeModel, root.pomodoroTimeSetting)
            onActivated: function(index) { root.pomodoroTimeChanged(root.timeModel[index].value) }
        }
    }

    // ---- Notifications -----------------------------------------------------
    Item {
        width: parent.width
        height: alertSeg.implicitHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.labelWidth - Style.space(6)
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            text: "Notifications"
        }

        SegmentedControl {
            id: alertSeg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: root.onOffModel
            currentIndex: root.indexOfValue(root.onOffModel, root.popupsSetting)
            onActivated: function(index) { root.popupsChanged(root.onOffModel[index].value) }
        }
    }

    // ---- Undo ---------------------------------------------------------------
    // How many moves the player may take back in one game.
    Item {
        width: parent.width
        height: undoSeg.implicitHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.labelWidth - Style.space(6)
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            text: "Undo"
        }

        SegmentedControl {
            id: undoSeg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: root.undoModel
            currentIndex: root.indexOfValue(root.undoModel, root.undoLimitSetting)
            onActivated: function(index) { root.undoLimitChanged(root.undoModel[index].value) }
        }
    }
}
