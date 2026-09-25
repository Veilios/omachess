import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ChessEngine.js" as Chess
import "ChessAI.js" as AI

Panel {
    id: root
    moduleName: "veilios.omachess"
    ipcTarget: "veilios.omachess"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // --- UI state --------------------------------------------------------------
    property bool settingsOpen: false
    property bool setupOpen: false
    property bool opened: false

    // --- persisted settings (edited in the dropdown, applied next game) --------
    property string humanColorSetting: "w"
    property int chessClockSetting: 30 * 60000
    property bool pomodoroModeSetting: true
    property int pomodoroTimeSetting: 10
    property bool settingsDirty: false

    // --- persistence -----------------------------------------------------------
    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: home + "/.local/state/omarchy-omachess"
    readonly property string statePath: stateDir + "/state.json"
    property bool stateLoaded: false

    // --- current game state ----------------------------------------------------
    property var game: Chess.stateFromFen(Chess.START_FEN)
    property string humanColor: "w"
    readonly property string aiColor: humanColor === "w" ? "b" : "w"
    property bool aiThinking: false
    property bool animating: false
    property bool gameOver: false
    property string statusText: "Your move"
    property var promotionInfo: null

    // --- pomodoro (work period between moves) ----------------------------------
    property bool pomodoroMode: false
    property int pomodoroDuration: 10000
    property bool pomodoroActive: false
    property var pomodoroStamp: 0
    property bool aiPendingPanelOpen: false

    // --- timed games -----------------------------------------------------------
    property var timeControl: null
    property int clockW: 0
    property int clockB: 0
    property string clockActive: ""
    property var clockStamp: 0
    property var pendingAiMove: null
    property int sliceMs: 0

    readonly property int humanClock: humanColor === "w" ? clockW : clockB
    readonly property int aiClock: humanColor === "w" ? clockB : clockW

    property var clockPresets: [
        { label: "10 min", base: 10 * 60000 },
        { label: "15 min", base: 15 * 60000 },
        { label: "30 min", base: 30 * 60000 },
        { label: "90 min", base: 90 * 60000 }
    ]
    property var workPresets: [
        { label: "15 min",  base: 15  * 60000 },
        { label: "30 min",  base: 30  * 60000 },
        { label: "60 min",  base: 60  * 60000 },
        { label: "120 min", base: 120 * 60000 }
    ]

    function kingSquareOf(color) {
        var target = color === "w" ? "K" : "k"
        for (var i = 0; i < 64; i++) if (game.board[i] === target) return i
        return -1
    }

    function refreshBoardView() {
        board.position = game.board.join("")
        board.turnColor = game.turn
        var ks = kingSquareOf(game.turn)
        board.checkSq = Chess.inCheck(game, game.turn) ? ks : -1
        var last = game.moves.length ? game.moves[game.moves.length - 1] : null
        board.lastFrom = last ? last.from : -1
        board.lastTo = last ? last.to : -1
    }

    function updateStatus() {
        var res = Chess.resultOf(game)
        gameOver = res.type !== "none"
        if (gameOver) {
            if (res.type === "checkmate") {
                statusText = (res.winner === "w" ? "White" : "Black") + " wins by checkmate"
            } else if (res.type === "stalemate") {
                statusText = "Draw — stalemate"
            } else if (res.type === "drawRepetition") {
                statusText = "Draw — repetition"
            } else if (res.type === "draw50") {
                statusText = "Draw — 50-move rule"
            } else {
                statusText = "Draw — insufficient material"
            }
        } else {
            statusText = game.turn === humanColor ? "Your move" : "Thinking…"
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

    function formatPomodoro(ms) {
        var total = Math.max(0, Math.round(ms / 1000))
        function pad(n) { return n < 10 ? "0" + n : String(n) }
        var m = Math.floor(total / 60)
        var s = total % 60
        return (m < 10 ? "0" + m : String(m)) + ":" + pad(s)
    }

    function clockShouldRun(side) {
        return timeControl !== null && !gameOver && clockActive === side &&
               !pomodoroActive &&
               (side === humanColor ? opened : true)
    }

    function accountElapsed() {
        if (timeControl === null || clockActive === "") return
        if (!clockShouldRun(clockActive)) return
        var now = Date.now()
        var by = Math.max(0, now - clockStamp)
        clockStamp = now
        if (clockActive === "w") clockW = Math.max(0, clockW - by)
        else clockB = Math.max(0, clockB - by)
        if (aiThinking) board.blurClockText = formatClock(aiClock)
        if ((clockActive === "w" ? clockW : clockB) <= 0) flagfallClock(clockActive)
    }

    function beginClock(side) {
        clockActive = side
        clockStamp = Date.now()
    }

    function clockPause() { accountElapsed() }

    function clockResume() {
        if (timeControl !== null && clockActive !== "") clockStamp = Date.now()
    }

    function stopClocks() {
        accountElapsed()
        clockActive = ""
        clockStamp = 0
    }

    function canMateMaterial(color) {
        var nonKing = 0
        var singleMinor = false
        for (var i = 0; i < 64; i++) {
            var p = game.board[i]
            if (p === " " || Chess.pieceColor(p) !== color) continue
            var u = p.toUpperCase()
            if (u === "K") continue
            if (u === "B" || u === "N") {
                nonKing++
                if (nonKing === 1) singleMinor = true
            } else {
                nonKing += 2
            }
        }
        if (nonKing === 0) return false
        if (nonKing === 1 && singleMinor) return false
        return true
    }

    function flagfallClock(side) {
        if (gameOver) return
        gameOver = true
        aiThinking = false
        aiSliceTimer.stop()
        board.blurActive = false
        pendingAiMove = null
        pomodoroActive = false
        pomodoroTickTimer.stop()
        aiPendingPanelOpen = false
        board.selected = -1
        board.targets = []
        board.promotion = null
        var winner = side === "w" ? "b" : "w"
        stopClocks()
        if (!canMateMaterial(winner)) {
            statusText = "Draw — " + (side === "w" ? "White" : "Black") + " ran out of time (insufficient material)"
        } else {
            statusText = (winner === "w" ? "White" : "Black") + " wins on time"
        }
        notifyIfHidden()
    }

    function notifySend(summary, body) {
        notifyProc.running = false
        notifyProc.command = ["notify-send", "-a", "OmaChess", "-t", "6000", summary, body]
        notifyProc.running = true
    }

    function notifyIfHidden() {
        if (opened) return
        if (gameOver) notifySend("OmaChess — game over", statusText)
        else if (game.turn === humanColor) notifySend("OmaChess — your move", formatClock(humanClock) + " left")
        else notifySend("OmaChess", "AI is moving…")
    }

    function saveSetting(key, val) {
        saveSettingsProc.key = key
        saveSettingsProc.value = String(val)
        saveSettingsProc.running = true
    }

    function buildStatePayload() {
        var p = {
            version: 1,
            fen: Chess.fenOf(game),
            humanColor: humanColor,
            gameOver: gameOver,
            statusText: statusText,
            pomodoro: pomodoroActive ? {
                active: true,
                stamp: pomodoroStamp,
                duration: pomodoroDuration,
                mode: pomodoroMode,
                aiPending: aiPendingPanelOpen,
                pendingMove: pendingAiMove ? { from: pendingAiMove.from, to: pendingAiMove.to, flags: pendingAiMove.flags || [] } : null
            } : { active: false },
            clocks: timeControl ? {
                base: timeControl.base,
                w: clockW,
                b: clockB,
                active: clockActive,
                stamp: clockStamp
            } : null
        }
        return JSON.stringify(p, null, 2) + "\n"
    }

    function saveGameState() {
        if (!stateLoaded) return
        saveTimer.restart()
    }

    function applyState(raw) {
        var payload = null
        try { payload = JSON.parse(String(raw || "").trim()) } catch (e) {}

        if (!payload || typeof payload !== "object") {
            stateLoaded = true
            startGame(null)
            return
        }

        if (payload.version !== 1) {
            stateLoaded = true
            startGame(null)
            return
        }

        if (payload.fen) {
            game = Chess.stateFromFen(payload.fen)
        }

        humanColor = payload.humanColor || "w"
        gameOver = payload.gameOver || false
        statusText = payload.statusText || "Your move"

        if (payload.pomodoro && payload.pomodoro.active) {
            pomodoroActive = true
            pomodoroStamp = payload.pomodoro.stamp
            pomodoroDuration = payload.pomodoro.duration
            pomodoroMode = payload.pomodoro.mode !== undefined ? payload.pomodoro.mode : pomodoroModeSetting
            aiPendingPanelOpen = payload.pomodoro.aiPending || false
            if (payload.pomodoro.pendingMove) {
                pendingAiMove = payload.pomodoro.pendingMove
            }
        } else {
            pomodoroActive = false
            aiPendingPanelOpen = false
            pendingAiMove = null
        }

        if (payload.clocks) {
            timeControl = { base: payload.clocks.base }
            clockW = payload.clocks.w
            clockB = payload.clocks.b
            clockActive = payload.clocks.active || ""
            clockStamp = payload.clocks.stamp
        } else {
            timeControl = null
            clockW = 0
            clockB = 0
            clockActive = ""
            clockStamp = 0
        }

        if (pomodoroActive) {
            var remaining = pomodoroDuration - (Date.now() - pomodoroStamp)
            if (remaining <= 0) {
                pomodoroActive = false
                onPomodoroComplete()
            } else {
                board.blurActive = true
                board.blurTitle = "Focus time"
                board.blurClockText = formatPomodoro(remaining)
            }
        }

        refreshBoardView()
        updateStatus()
        stateLoaded = true
    }

    function applyMove(move) {
        if (gameOver) return
        if (timeControl !== null) {
            accountElapsed()
            clockActive = ""
            if (gameOver) return
        }
        var prev = board.position
        var fromChar = prev.charAt(move.from)
        var rookFrom = -1
        var rookTo = -1
        var rookChar = ""
        if (fromChar.toUpperCase() === "K" && Math.abs(move.to - move.from) === 2) {
            var kingside = move.to > move.from
            rookFrom = kingside ? move.from + 3 : move.from - 4
            rookTo = kingside ? move.to - 1 : move.to + 1
            rookChar = prev.charAt(rookFrom)
        }
        Chess.makeMove(game, move)
        board.selected = -1
        board.targets = []
        if (board.promotion) board.promotion = null
        animating = true
        board.beginSlide({
            from: move.from,
            to: move.to,
            fromChar: fromChar,
            rookFrom: rookFrom,
            rookTo: rookTo,
            rookChar: rookChar
        })
    }

    function onSlideFinished() {
        animating = false
        refreshBoardView()
        updateStatus()
        if (!gameOver) {
            if (game.turn === humanColor) {
                if (timeControl !== null) beginClock(humanColor)
            } else {
                if (pomodoroMode) startPomodoro()
                else if (timeControl !== null) startAISlice(false)
                else scheduleAITurn()
            }
        }
        notifyIfHidden()
        saveGameState()
    }

    function scheduleAITurn() {
        aiTimer.restart()
    }

    function runAITurn() {
        if (gameOver) return
        if (game.turn === humanColor) return
        aiThinking = true
        var move = AI.chooseMove(game, { depth: 3, timeMs: 200 })
        aiThinking = false
        if (move) {
            applyMove(move)
        } else {
            updateStatus()
        }
    }

    function startAISlice(withBlur) {
        if (gameOver || aiThinking) return
        aiThinking = true
        if (timeControl !== null) beginClock(aiColor)
        sliceMs = 3000 + Math.floor(Math.random() * 2000)
        board.blurActive = withBlur === true
        board.blurTitle = "AI thinking…"
        pendingAiMove = AI.chooseMove(game, { depth: 3, timeMs: 200 })
        if (!pendingAiMove) {
            endAISlice()
        } else {
            aiSliceTimer.interval = sliceMs
            aiSliceTimer.restart()
        }
    }

    function endAISlice() {
        aiSliceTimer.stop()
        aiThinking = false
        board.blurActive = false
        var mv = pendingAiMove
        pendingAiMove = null
        if (mv) {
            applyMove(mv)
        } else {
            updateStatus()
        }
    }

    function startPomodoro() {
        if (gameOver || pomodoroActive) return
        pomodoroActive = true
        clockActive = ""
        pomodoroStamp = Date.now()
        board.blurActive = true
        board.blurTitle = "Focus time"
        board.blurClockText = formatPomodoro(pomodoroDuration)
        saveGameState()
    }

    function onPomodoroComplete() {
        pomodoroActive = false
        if (opened) {
            startAISlice(true)
        } else {
            aiPendingPanelOpen = true
            notifySend("OmaChess — Focus time over", "Your move is ready. Open the game to see it.")
        }
        saveGameState()
    }

    function handleClick(sq) {
        if (gameOver || aiThinking || animating || sq < 0) return
        if (game.turn !== humanColor) return

        var selected = board.selected
        if (selected === sq) {
            board.selected = -1
            board.targets = []
            return
        }

        var pieceHere = game.board[sq]
        if (pieceHere !== " " && Chess.pieceColor(pieceHere) === humanColor) {
            board.selected = sq
            var ms = Chess.movesFrom(game, sq)
            var ts = []
            for (var t = 0; t < ms.length; t++) ts.push(ms[t].to)
            board.targets = ts
            return
        }

        if (selected >= 0) {
            var cands = Chess.movesFrom(game, selected)
            for (var i = 0; i < cands.length; i++) {
                if (cands[i].to !== sq) continue
                var f = cands[i].flags || []
                if (f.indexOf("promo") >= 0) {
                    var moving = game.board[selected]
                    promotionInfo = { from: selected, to: sq, color: moving === "P" ? "w" : "b" }
                    board.promotion = promotionInfo
                    return
                }
                applyMove(cands[i])
                return
            }
        }

        board.selected = -1
        board.targets = []
    }

    function promoChosen(piece) {
        if (!promotionInfo) return
        var info = promotionInfo
        var p = info.color === "w" ? piece : piece.toLowerCase()
        promotionInfo = null
        board.promotion = null
        var cands = Chess.movesFrom(game, info.from)
        for (var i = 0; i < cands.length; i++) {
            if (cands[i].to === info.to && (cands[i].promo || "") === p) {
                applyMove(cands[i])
                return
            }
        }
        board.selected = -1
        board.targets = []
    }

    function promoCancelled() {
        promotionInfo = null
        board.promotion = null
        board.selected = -1
        board.targets = []
    }

    function startGame(workMs) {
        game = Chess.stateFromFen(Chess.START_FEN)
        board.cancelSlide()
        animating = false
        aiThinking = false
        aiSliceTimer.stop()
        board.blurActive = false
        pendingAiMove = null
        pomodoroActive = false
        pomodoroTickTimer.stop()
        aiPendingPanelOpen = false
        promotionInfo = null
        board.promotion = null
        board.selected = -1
        board.targets = []

        pomodoroDuration = pomodoroTimeSetting * 1000
        humanColor = humanColorSetting
        pomodoroMode = pomodoroModeSetting
        if (workMs != null) pomodoroDuration = workMs
        timeControl = { base: chessClockSetting }
        clockActive = ""
        clockStamp = 0
        clockW = chessClockSetting
        clockB = chessClockSetting
        settingsDirty = false
        setupOpen = false

        refreshBoardView()
        updateStatus()
        if (game.turn === humanColor) {
            beginClock(humanColor)
        } else {
            startAISlice(false)
        }
        saveGameState()
    }

    function resign() {
        gameOver = true
        aiThinking = false
        animating = false
        aiSliceTimer.stop()
        board.blurActive = false
        pendingAiMove = null
        pomodoroActive = false
        pomodoroTickTimer.stop()
        aiPendingPanelOpen = false
        board.cancelSlide()
        board.promotion = null
        board.selected = -1
        board.targets = []
        statusText = "You resigned"
        stopClocks()
        saveGameState()
    }

    // --- bar button -----------------------------------------------------------
    readonly property color iconTint: barForeground

    Component {
        id: knightIconComponent
        Item {
            width: Style.bar.iconCanvas
            height: Style.bar.iconCanvas
            TextMetrics {
                id: km
                font.family: "Font Awesome 7 Free"
                font.weight: Font.Black
                font.pixelSize: Style.bar.iconFont
                text: "\u265E"
            }
            Text {
                id: glyph
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: glyph.implicitWidth / 2 - (km.tightBoundingRect.x + km.tightBoundingRect.width / 2)
                anchors.verticalCenterOffset: glyph.baselineOffset + km.tightBoundingRect.y + km.tightBoundingRect.height / 2 - glyph.implicitHeight / 2
                text: "\u265E"
                font.family: "Font Awesome 7 Free"
                font.weight: Font.Black
                font.pixelSize: Style.bar.iconFont
                color: root.barForeground
                renderType: Text.NativeRendering
            }
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        tooltipText: "Chess"
        iconComponent: knightIconComponent
        onPressed: function(b) {
            if (b === Qt.LeftButton) root.toggle()
        }
    }

    // --- timers / processes ----------------------------------------------------
    Timer {
        id: aiTimer
        interval: 300
        repeat: false
        onTriggered: runAITurn()
    }

    Timer {
        id: aiSliceTimer
        interval: 4000
        repeat: false
        onTriggered: endAISlice()
    }

    Timer {
        id: clockTimer
        interval: 100
        repeat: true
        running: true
        onTriggered: accountElapsed()
    }

    Timer {
        id: pomodoroTickTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (!pomodoroActive) return
            var remaining = pomodoroDuration - (Date.now() - pomodoroStamp)
            if (remaining <= 0) {
                board.blurClockText = "0:00"
                onPomodoroComplete()
            } else {
                board.blurClockText = formatPomodoro(remaining)
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!stateLoaded) return
            var payload = buildStatePayload()
            stateFile.setText(payload)
        }
    }

    Process {
        id: notifyProc
        command: ["notify-send", "-a", "OmaChess", "-t", "6000", "OmaChess", ""]
    }

    Process {
        id: saveSettingsProc
        property string key: ""
        property string value: ""
        command: {
            var py = [
                'import json,sys',
                'p=sys.argv[1];vid=sys.argv[2];key=sys.argv[3];val=sys.argv[4]',
                'd=json.load(open(p))',
                'for sec in d.get("bar",{}).get("layout",{}).values():',
                '    if isinstance(sec,list):',
                '        for e in sec:',
                '            if isinstance(e,dict) and e.get("id")==vid:',
                '                e[key]=val',
                'json.dump(d,open(p,"w"),indent=2)',
                'open(p,"a").write("\\n")'
            ]
            return ["python3", "-c", py.join("\n"),
                    home + "/.config/omarchy/shell.json",
                    "veilios.omachess", key, value]
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyState(text())
        onLoadFailed: function(err) { root.applyState("") }
    }

    Process {
        id: mkStateDir
        command: ["mkdir", "-p", root.stateDir]
        onExited: stateFile.reload()
    }

    Component.onCompleted: {
        AI.setEngine(Chess)
        board.slideFinished.connect(onSlideFinished)
        refreshBoardView()
        humanColorSetting = setting("humanColor", "w")
        chessClockSetting = setting("chessClock", 30 * 60000)
        pomodoroModeSetting = setting("pomodoroMode", true)
        pomodoroTimeSetting = setting("pomodoroTime", 10)
        humanColor = humanColorSetting
        pomodoroMode = pomodoroModeSetting
        pomodoroDuration = pomodoroTimeSetting * 1000
        mkStateDir.running = true
    }

    // --- popup panel -----------------------------------------------------------
    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        property int boardSquareSize: 24
        contentWidth: panel.fittedContentWidth(Style.space(360))
        contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            Keys.onPressed: function(event) {
                if (blocked) return
                if (event.key === Qt.Key_Escape) {
                    if (settingsOpen) settingsOpen = false
                    else if (setupOpen) setupOpen = false
                    else if (board.promotion) board.promotion = null
                    else root.close()
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
                    startGame(null)
                    event.accepted = true
                }
            }
        }

ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            clip: true
            spacing: Style.space(4)

            // Header row - RowLayout handles spacing/alignment automatically
            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Style.space(6)

                Text {
                    id: statusLabel
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: gameOver ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.75)
                                         : Color.popups.text
                    font.pixelSize: Style.font.body
                    text: statusText
                    verticalAlignment: Text.AlignVCenter
                }

                // Spacer pushes buttons to the right
                Item { Layout.fillWidth: true }

                Button {
                    id: newButton
                    text: "New"
                    tooltipText: "New game"
                    onClicked: { setupOpen = true; settingsOpen = false }
                }

                Button {
                    id: resignButton
                    text: "Resign"
                    tooltipText: "Resign the game"
                    onClicked: resign()
                }

                Rectangle {
                    id: settingsButton
                    Layout.alignment: Qt.AlignRight
                    width: Style.space(24)
                    height: Style.space(24)
                    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(4)
                    color: settingsOpen
                        ? Qt.rgba(iconTint.r, iconTint.g, iconTint.b, 0.32)
                        : (settingsMouse.containsMouse || settingsMouse.pressed
                        ? Style.hoverFillFor(iconTint, Color.accent)
                        : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "\uF013"
                        font.family: "Font Awesome 7 Free"
                        font.weight: Font.Black
                        font.pixelSize: 11
                        color: settingsOpen ? Color.accent : iconTint
                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { settingsOpen = !settingsOpen; if (settingsOpen) setupOpen = false }
                    }
                }
            }

            // Settings dropdown
            SettingsView {
                id: settingsView
                Layout.fillWidth: true
                visible: settingsOpen
                clip: true

                foreground: Color.popups.text
                fontFamily: Style.font.family

                humanColorSetting: humanColorSetting
                chessClockSetting: chessClockSetting
                pomodoroModeSetting: pomodoroModeSetting
                pomodoroTimeSetting: pomodoroTimeSetting
                settingsDirty: settingsDirty
                clockPresets: clockPresets

                onHumanColorChanged: { humanColorSetting = color; saveSetting("humanColor", color); settingsDirty = true }
                onChessClockChanged: { chessClockSetting = ms; saveSetting("chessClock", ms); settingsDirty = true }
                onPomodoroModeChanged: { pomodoroModeSetting = enabled; saveSetting("pomodoroMode", enabled); settingsDirty = true }
                onPomodoroTimeChanged: { pomodoroTimeSetting = seconds; saveSetting("pomodoroTime", seconds); settingsDirty = true }
            }

            // Clock strip
            ClockStrip {
                id: clockStrip
                Layout.fillWidth: true
                timeControl: timeControl
                humanClock: humanClock
                aiClock: aiClock
                clockActive: clockActive
                humanColor: humanColor
                aiColor: aiColor
                foreground: Color.popups.text
            }

            // Chess board
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: panel.boardSquareSize * 8
                Layout.preferredHeight: panel.boardSquareSize * 8
                Board {
                    id: board
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: panel.boardSquareSize * 8
                    height: panel.boardSquareSize * 8
                    square: panel.boardSquareSize
                    flipped: humanColor === "b"
                    interactive: !animating && !aiThinking && !gameOver && !setupOpen && !pomodoroActive
                    onClicked: handleClick(sq)
                    onPromoChosen: promoChosen(piece)
                    onPromoCancelled: promoCancelled()
                    clip: true
                }
            }

            // Setup overlay
            SetupOverlay {
                id: setupOverlay
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: panel.boardSquareSize * 8
                Layout.preferredHeight: panel.boardSquareSize * 8
                visible: setupOpen
                onStartGame: { startGame(null); setupOpen = false }
            }
        }
    }

    Connections {
        target: root
        function onOpenedChanged() {
            if (opened) {
                clockResume()
                if (aiPendingPanelOpen) {
                    aiPendingPanelOpen = false
                    startAISlice(false)
                }
            } else {
                clockPause()
                saveGameState()
            }
        }
    }

    function toggle() {
        if (opened) close()
        else open()
    }

    function open() {
        opened = true
        controller.show()
    }

    function close() {
        controller.hide()
        opened = false
    }
}