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

    // --- persisted settings (edited in the dropdown, applied next game) --------
    // Bound to the shell's settings object rather than read once in
    // Component.onCompleted: the bar injects that object a tick after this
    // component completes, so a one-shot read lands on empty settings and
    // silently falls back to every default. Assigning to these would break
    // the binding, so the dropdown handlers persist instead.
    property string humanColorSetting: setting("humanColor", "w")
    property int chessClockSetting: intSetting("chessClock", 30 * 60000)
    property bool pomodoroModeSetting: boolSetting("pomodoroMode", true)
    // pomodoroTime is stored in MINUTES, which is also the unit pomodoroPresets
    // is expressed in (10/15/30/60/120). It was briefly treated as seconds while
    // testing, which left those presets reading as "10s, 15s, 30s..." and put
    // the unit in the settings label as "Every (s)". Everything converting the
    // setting to a duration multiplies by 60 * 1000.
    property int pomodoroTimeSetting: intSetting("pomodoroTime", 10)
    property bool popupsSetting: boolSetting("popups", true)
    property bool settingsDirty: false

    // A Lock In session ending is a sound, not a popup. The freedesktop theme's
    // "complete" cue is the standard task-done sound and is already installed
    // alongside libcanberra on most desktops; the test -f in soundProc keeps a
    // missing theme a silent no-op rather than a logged pw-play error.
    readonly property string focusSound: "/usr/share/sounds/freedesktop/stereo/complete.oga"

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

    // OS account name, resolved once. Results read as "<name> won" rather than
    // "You", so the panel speaks in terms of whoever is actually logged in.
    readonly property string userName: Quickshell.env("USER") || "Player"

    // --- pomodoro (work period between moves) ----------------------------------
    property bool pomodoroMode: false
    property int pomodoroDuration: 10000
    property bool pomodoroActive: false
    property var pomodoroStamp: 0
    property bool aiPendingPanelOpen: false
    // Set when a session reaches zero, cleared once the AI's move lands. Gives
    // the hover something to say in the gap between "session over" and "the AI
    // has actually replied" -- with the panel shut that gap is however long you
    // leave it shut. Distinct from pomodoroActive on purpose: the icon dims off
    // the moment the session ends, so this is hover-only state.
    property bool lockInConcluded: false

    // ---- undo ---------------------------------------------------------------
    // 0 disables undo entirely; 3/5/10 cap it; -1 means unlimited (shown as an
    // infinity sign in SettingsView). Unlimited is the default -- the cap is
    // there for people who want the friction, not as a default.
    property int undoLimitSetting: intSetting("undoLimit", -1)

    // Undo presses spent on the current game. Reset by startGame() and carried
    // through state.json so a shell restart cannot hand back the allowance.
    property int undosUsed: 0

    // One FEN per ply, history[0] being the position the game started from.
    //
    // This deliberately does NOT use ChessEngine's undoMove(). That walks the
    // engine's internal move stack, which lives only in memory -- so a reload
    // would silently drop the ability to undo. Storing positions as FENs makes
    // the history survive a restart (and is cheap: a long game is a few tens of
    // KB) and makes undo a matter of rebuilding the position rather than
    // unwinding internal bookkeeping. stateFromFen/fenOf round-trip exactly,
    // castling rights, en passant square and side to move included, which is
    // what the correctness of this rests on.
    property var history: []

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
        { label: "Off",    base: 0 },
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

    function winnerName(sideColor) {
        return sideColor === humanColor ? userName : "AI"
    }

    function updateStatus() {
        var res = Chess.resultOf(game)
        gameOver = res.type !== "none"
        if (gameOver) {
            if (res.type === "checkmate") {
                statusText = winnerName(res.winner) + " wins by checkmate"
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
            statusText = game.turn === humanColor ? "Your move" : "AI thinking…"
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
        // Pomodoro expiry is checked BEFORE the clock guards, deliberately.
        // startPomodoro() clears clockActive, so `clockActive === ""` holds for
        // the whole focus block and the guards below would skip this function
        // entirely. That left pomodoroTickTimer as the only thing able to end
        // a focus block -- a single missed or delayed tick stranded
        // pomodoroActive = true, which kept the bar icon dimmed until some
        // unrelated path happened to clear the flag. This runs every 100ms off
        // clockTimer, which is unconditionally running, so it does not share
        // that single point of failure.
        if (pomodoroActive) {
            if (pomodoroDuration - (Date.now() - pomodoroStamp) <= 0) {
                pomodoroActive = false
                onPomodoroComplete()
                // onPomodoroComplete may have begun a clock (startAISlice does),
                // so bail rather than account a zero-length slice below.
                return
            }
        }
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
        lockInConcluded = false
        aiPendingPanelOpen = false
        board.selected = -1
        board.targets = []
        board.promotion = null
        var winner = side === "w" ? "b" : "w"
        stopClocks()
        if (!canMateMaterial(winner)) {
            statusText = "Draw — " + (side === "w" ? "White" : "Black") + " ran out of time (insufficient material)"
        } else {
            statusText = winnerName(winner) + " wins on time"
        }
        notifyIfHidden()
    }

    function notifySend(summary, body) {
        notifyProc.running = false
        notifyProc.command = ["notify-send", "-a", "OmaChess", "-t", "6000", summary, body]
        notifyProc.running = true
    }

    function playSound() {
        soundProc.running = false
        soundProc.file = root.focusSound
        soundProc.running = true
    }

    function notifyIfHidden() {
        if (opened) return
        if (!popupsSetting) return
        if (gameOver) notifySend("OmaChess — game over", statusText)
        else if (game.turn === humanColor) notifySend("OmaChess — your move", formatClock(humanClock) + " left")
        else notifySend("OmaChess", "AI is moving…")
    }

    // Settings persist through the shell's own config path rather than an
    // out-of-band write to shell.json: the shell re-reads config here and
    // persists it, so values keep their real JSON types and no other
    // plugin's entry can be clobbered by a racing rewrite.
    function saveSetting(key, val) {
        var entry = { id: root.moduleName }
        for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
        entry[key] = val
        root.settings = entry
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry)
    }

    // Panel.setting() hands back whatever JSON held, so a value written by an
    // older build (or by hand) can still be a string. Coerce explicitly: JS
    // would turn "false" into true, which silently ignores a disabled setting.
    function boolSetting(name, fallback) {
        var v = setting(name, undefined)
        if (v === undefined || v === null) return fallback
        if (typeof v === "boolean") return v
        var s = String(v).trim().toLowerCase()
        if (s === "true" || s === "1" || s === "yes" || s === "on") return true
        if (s === "false" || s === "0" || s === "no" || s === "off") return false
        return fallback
    }

    function intSetting(name, fallback) {
        var v = setting(name, undefined)
        if (v === undefined || v === null || String(v).trim() === "") return fallback
        var n = Number(v)
        return isFinite(n) ? Math.round(n) : fallback
    }

    function buildStatePayload() {
        var p = {
            version: 1,
            fen: Chess.fenOf(game),
            // Undo history. Unconditional (unlike the pomodoro block below,
            // which is only emitted when something in it is live) because the
            // positions are game state in their own right -- dropping them would
            // quietly remove undo after a restart, which is the opposite of what
            // persisting them is for.
            history: history,
            undosUsed: undosUsed,
            humanColor: humanColor,
            gameOver: gameOver,
            statusText: statusText,
            // aiPending/pendingMove used to live inside the `pomodoroActive` ternary,
// which meant the instant onPomodoroComplete() cleared the flag the payload
            // degraded to { active: false } and the deferred AI move was thrown
            // away. applyState() then reset aiPendingPanelOpen to false, so any
            // plugin reload between the timer ending and the panel being opened
            // lost the AI's move entirely and the game sat waiting on a player
            // who was never asked. The whole block is emitted whenever any of
            // the four is live, and `active` is carried as its own field.
            // lockInConcluded is in the condition for the same reason: it is set
            // at the exact moment pomodoroActive goes false, so gating on
            // `active` alone would emit { active: false } and drop the
            // concluded message on the next reload.
            pomodoro: (pomodoroActive || aiPendingPanelOpen || pendingAiMove || lockInConcluded) ? {
                active: pomodoroActive,
                stamp: pomodoroStamp,
                duration: pomodoroDuration,
                mode: pomodoroMode,
                aiPending: aiPendingPanelOpen,
                concluded: lockInConcluded,
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

        // Restore the position history for undo. A save written before undo
        // existed has no history key at all, so fall back to a single-entry
        // history of the current position: undo then simply reads as
        // unavailable, which is honest, rather than rewinding into nowhere.
        history = (payload.history && payload.history.length)
            ? payload.history.slice(0)
            : [Chess.fenOf(game)]
        undosUsed = typeof payload.undosUsed === "number" ? payload.undosUsed : 0

        humanColor = payload.humanColor || "w"
        gameOver = payload.gameOver || false
        statusText = payload.statusText || "Your move"

        if (payload.pomodoro) {
            // `active` is now just one field in the block rather than the
            // condition guarding it, because a pending AI move outlives the
            // focus block that deferred it: onPomodoroComplete() clears
            // pomodoroActive but leaves aiPendingPanelOpen set until the panel
            // is opened. Gating on `active` here would discard that move on
            // every reload.
            pomodoroActive = payload.pomodoro.active === true
            if (pomodoroActive) {
                pomodoroStamp = payload.pomodoro.stamp
                pomodoroDuration = payload.pomodoro.duration
                pomodoroMode = payload.pomodoro.mode !== undefined ? payload.pomodoro.mode : pomodoroModeSetting
            } else {
                pomodoroMode = pomodoroModeSetting
                pomodoroDuration = pomodoroTimeSetting * 60 * 1000
            }
            aiPendingPanelOpen = payload.pomodoro.aiPending === true
            lockInConcluded = payload.pomodoro.concluded === true
            pendingAiMove = payload.pomodoro.pendingMove ? payload.pomodoro.pendingMove : null
        } else {
            pomodoroActive = false
            aiPendingPanelOpen = false
            lockInConcluded = false
            pendingAiMove = null
            pomodoroMode = pomodoroModeSetting
            pomodoroDuration = pomodoroTimeSetting * 60 * 1000
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
                board.blurTitle = "Lock In"
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
        // One entry per ply, for both sides' moves, since the position after
        // this move is exactly what undo may need to return to.
        history = history.concat([Chess.fenOf(game)])
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
        // The AI's move has landed, so a pending "session concluded" message has
        // served its purpose and the hover goes back to reporting whose turn it
        // is. Safe to clear unconditionally: on the player's own move this is
        // already false, since the AI's reply cleared it on the way through.
        lockInConcluded = false
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
        // A new session supersedes any "concluded" message still being shown.
        lockInConcluded = false
        clockActive = ""
        pomodoroStamp = Date.now()
        board.blurActive = true
        board.blurTitle = "Lock In"
        board.blurClockText = formatPomodoro(pomodoroDuration)
        saveGameState()
    }

    function onPomodoroComplete() {
        pomodoroActive = false
        // The icon brightens on the line above (dimmed tracks pomodoroActive),
        // but the game has not moved on yet, so the hover needs its own state
        // to say so. Cleared by onSlideFinished() when the AI's move lands.
        lockInConcluded = true
        if (opened) {
            // startAISlice(true) re-arms the blur itself and retitles it
            // "AI thinking…", so the session overlay is correctly replaced here.
            startAISlice(true)
        } else {
            aiPendingPanelOpen = true
            // The board was left blurred by startPomodoro() and nothing in this
            // branch cleared it: blurActive only ever fell back to false in
            // endAISlice(), which cannot run until the panel is opened. So the
            // board sat there dimmed and frozen on "Lock In 00:00" for as
            // long as the panel stayed shut. The session is over, so drop
            // the blur; handleClick() still refuses input while it is the AI's
            // turn, so this cannot be mistaken for a playable position.
            board.blurActive = false
            board.blurClockText = ""
            playSound()
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
        // Seed the position history with where the game starts, so undo has a
        // position to return to even before the first move is played.
        history = [Chess.fenOf(game)]
        undosUsed = 0
        board.cancelSlide()
        animating = false
        aiThinking = false
        aiSliceTimer.stop()
        board.blurActive = false
        pendingAiMove = null
        pomodoroActive = false
        lockInConcluded = false
        aiPendingPanelOpen = false
        promotionInfo = null
        board.promotion = null
        board.selected = -1
        board.targets = []

        pomodoroDuration = pomodoroTimeSetting * 60 * 1000
        humanColor = humanColorSetting
        pomodoroMode = pomodoroModeSetting
        if (workMs != null) pomodoroDuration = workMs
        // A zero base means no chess clock; the rest of the engine already
        // reads a null timeControl as "untimed" and drops to a plain AI turn.
        timeControl = chessClockSetting > 0 ? { base: chessClockSetting } : null
        clockActive = ""
        clockStamp = 0
        clockW = chessClockSetting
        clockB = chessClockSetting
        settingsDirty = false
        setupOpen = false

        refreshBoardView()
        updateStatus()
        if (game.turn === humanColor) {
            if (timeControl !== null) beginClock(humanColor)
        } else {
            startAISlice(false)
        }
        saveGameState()
    }

    function forfeit() {
        gameOver = true
        aiThinking = false
        animating = false
        aiSliceTimer.stop()
        board.blurActive = false
        pendingAiMove = null
        pomodoroActive = false
        lockInConcluded = false
        aiPendingPanelOpen = false
        board.cancelSlide()
        board.promotion = null
        board.selected = -1
        board.targets = []
        statusText = "AI won"
        stopClocks()
        saveGameState()
    }

    // --- undo ----------------------------------------------------------------
    // Why the button is unavailable, in the player's terms. Silent when undo is
    // simply available, so the tooltip only ever explains a dead button.
    function undoTooltip() {
        if (undoLimitSetting === 0) return "Undo is off — change it in settings"
        if (gameOver) return "Undo — game is over"
        if (undoLimitSetting > 0 && undosUsed >= undoLimitSetting)
            return "Undo limit reached for this game"
        if (pomodoroActive || aiThinking || animating) return "Undo — wait for the AI"
        if (!canUndo()) return "Undo — nothing to take back yet"
        return "Undo your last move"
    }

    // True when an undo would do something. Kept as a function rather than a
    // stored flag so the button's enabled state and the guard inside onClicked
    // can never disagree.
    function canUndo() {
        if (gameOver || pomodoroActive || aiThinking || animating) return false
        if (board.promotion !== null || promotionInfo !== null) return false
        if (undoLimitSetting === 0) return false
        if (undoLimitSetting > 0 && undosUsed >= undoLimitSetting) return false

        // Whose turn it is decides how far back a single undo reaches, because
        // undo always means "the move I just made". If it is the AI's turn, the
        // last ply is the human's own move and one step back undoes exactly
        // that. If it is the human's turn, the last ply is the AI's reply, so
        // stepping back only once would undo the AI rather than the human.
        return game.turn === humanColor ? history.length >= 3 : history.length >= 2
    }

    function undoMove() {
        if (!canUndo()) return

        // Same two cases as canUndo(): reach the position just before the
        // human's last move. In both branches the resulting position has the
        // human to move, which is what makes an undo feel like "my turn again".
        var rewind = game.turn === humanColor ? 2 : 1
        var target = history.length - 1 - rewind
        if (target < 0) return

        // Drop any in-flight AI or focus work first. A pending reply belongs to
        // the position being discarded, so leaving it running would let the AI
        // answer a board that no longer exists.
        aiTimer.stop()
        aiSliceTimer.stop()
        aiThinking = false
        animating = false
        pendingAiMove = null
        aiPendingPanelOpen = false
        pomodoroActive = false
        lockInConcluded = false
        board.blurActive = false
        board.blurClockText = ""
        board.cancelSlide()
        promotionInfo = null
        board.promotion = null
        board.selected = -1
        board.targets = []

        // The undo allowance is spent per press, not per ply: rewind may walk
        // back two plies but it is still the single move the player took back.
        undosUsed++

        // Rebuild rather than unwind, then truncate so the discarded positions
        // cannot be returned to by a second undo.
        game = Chess.stateFromFen(history[target])
        history = history.slice(0, target + 1)

        // Clocks are re-based rather than rewound: the time already spent is
        // gone, and there is no per-ply snapshot to restore it from. The run is
        // stopped so the next onSlideFinished picks the human's clock back up.
        stopClocks()
        clockActive = ""

        refreshBoardView()
        updateStatus()
        notifyIfHidden()
        saveGameState()
    }

    // --- bar button -----------------------------------------------------------
    readonly property color iconTint: barForeground

    // Whose turn it is, for the tooltip only. It deliberately does NOT move
    // the icon: the bar already dots an open panel, and a dim that tracked
    // the turn said "the ball is with the AI", which is a different thing from
    // what the dim now means.
    //
    // Reads board.turnColor rather than game.turn on purpose: `game` is a
    // plain JS object that Chess.makeMove mutates in place, and QML cannot
    // observe property changes on a non-QObject, so a binding on game.turn
    // fires once and never again. turnColor is a real property reassigned by
    // refreshBoardView() after every move, so this stays reactive.
    readonly property bool awaitingPlayer: !gameOver && board.turnColor === humanColor

    Component {
        id: knightIconComponent
        // Hand-rolled metrics, mirroring OpticalGlyph.qml for a typeface that
        // is not the bar's own. The horizontal correction is the same one
        // OpticalGlyph applies. The vertical axis is where this glyph needs a
        // hand, and the reason is measurable.
        //
        // At Style.bar.iconFont -- 13px, and not theme-overridable, since
        // Style.qml:405-410 honors only size-horizontal/size-vertical -- the
        // glyphs compare as follows, by rasterizing each and scanning ink rows:
        //
        //   Nerd Font U+F017/U+F013/U+F2A2   ink 13.0px tall, ink center
        //                                         0.00px from line-box center
        //   Font Awesome 7 U+265E             ink 15.0px tall, ink center
        //                                         1.00px ABOVE line-box center
        //
        // The neighbouring icons and this one are both centered by line box --
        // anchors.centerIn on a Text whose implicitHeight is the line box -- so
        // with no nudge the knight rides exactly 1px high. In both faces
        // leading is 0 and lineSpacing == height == ascent + descent, so this
        // is not a line-spacing artifact.
        //
        // The nudge is a constant rather than a tightBoundingRect derivation
        // like the horizontal one, and that is the point. A derived vertical
        // offset tracks whatever glyph is in place and drifts between them,
        // which is why the earlier attempt was reverted. A literal cannot
        // drift, and this component only ever draws U+265E.
        //
        // Font.Black is kept because it selects Font Awesome's solid chess
        // face -- the unweighted face is a hollow outline that reads far
        // weaker than the rest of the bar. (JetBrainsMono Nerd Font, the
        // bar's own font, has no U+265E at all, so this typeface is not
        // optional.)
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
                anchors.verticalCenterOffset: 1
                text: "\u265E"
                font.family: "Font Awesome 7 Free"
                font.weight: Font.Black
                font.pixelSize: Style.bar.iconFont
                color: root.barForeground
                renderType: Text.NativeRendering
            }
        }
    }

    // The knight dims only while the focus timer is running, through the
    // native WidgetButton.dimmed rather than an opacity binding on the glyph
    // itself: that gets the bar's own dim level (0.45) and its standard 140ms
    // fade for free, and leaves exactly one animation in play instead of the
    // glyph's 160ms stacked on the button's 140ms.
    //
    // pomodoroActive is the right signal rather than "not awaitingPlayer"
    // because those two mostly coincide -- the pomodoro only ever starts from
    // the AI's-turn branch of onSlideFinished(), and the board is inert while
    // it runs -- but keying off the timer is what actually describes the state.
    // The cases where they part company: game over, and AI thinking with
    // pomodoroMode off. Neither dims any more.
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        dimmed: pomodoroActive
        // The countdown reads board.blurClockText rather than recomputing from
        // Date.now(). None of pomodoroActive/pomodoroDuration/pomodoroStamp
        // change while a session runs, so a Date.now() expression would freeze
        // at whatever the tooltip was built with and never tick. blurClockText
        // is rewritten every second by the tick timer, so it stays live -- and
        // the hover shows the identical digits to the board.
        tooltipText: pomodoroActive
            ? "Chess — Lock in " + board.blurClockText
            : (lockInConcluded
               ? "Chess — Lock in session concluded"
               : (awaitingPlayer ? "Chess — your move" : "Chess"))
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
        running: root.pomodoroActive
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
        id: soundProc
        property string file: ""
        // test -f first so a desktop without the freedesktop sound theme
        // stays quiet instead of logging a pw-play failure every focus block
        command: ["sh", "-c", "test -f \"$1\" && exec pw-play \"$1\"", "sh", file]
    }

    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyState(text())
        onLoadFailed: function(err) { root.applyState("") }
    }

    // Appends one trace line per invocation. A Process append beats writing
    // through a FileView because FileView.setText() silently does nothing on a
    // view that was never loaded, which is exactly the case for a log nobody
    // reads back through the view -- state.json only works because the shell
    // loads it on startup. Args go through argv rather than a shell string so
    // the line needs no quoting.


    Process {
        id: mkStateDir
        command: ["mkdir", "-p", root.stateDir]
        onExited: stateFile.reload()
    }

    Component.onCompleted: {
        AI.setEngine(Chess)
        board.slideFinished.connect(onSlideFinished)
        refreshBoardView()
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
        // The board drives the panel's width, and the card is sized to the
        // content column. Scales with the spacing/font scale, so the fit holds
        // at any theme size.
        property int boardSquareSize: Style.space(32)
        // Derived from the card's own padding and border instead of a guessed
        // constant, so the content always exactly fills the card.
        readonly property int contentSideInset: padding + Math.max(1, Style.space(2))
        contentWidth: panel.fittedContentWidth(panel.boardSquareSize * 8 + panel.contentSideInset * 2)
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
            width: parent.width
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
                    id: undoButton
                    text: "Undo"
                    // qs.Ui.Button has no enabled state to lean on, so
                    // availability is carried by the label colour and enforced
                    // again in onClicked. Muted rather than hidden: an absent
                    // button reads as a layout bug, a greyed one reads as "off".
                    foreground: canUndo() ? Color.foreground : Color.muted
                    tooltipText: undoTooltip()
                    onClicked: function() { if (canUndo()) undoMove() }
                }

                // One slot that offers whichever action still applies. While the
                // game is live the only thing left to do to it is forfeit; once it
                // is decided, the same slot becomes the prompt to start another.
                Button {
                    id: endGameButton
                    text: gameOver ? "New" : "Forfeit"
                    tooltipText: gameOver ? "New game" : "Forfeit the game"
                    onClicked: {
                        if (gameOver) { setupOpen = true; settingsOpen = false }
                        else forfeit()
                    }
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

            // Clock strip
            ClockStrip {
                id: clockStrip
                Layout.fillWidth: true
                boardWidth: panel.boardSquareSize * 8
                timeControl: root.timeControl
                humanClock: root.humanClock
                aiClock: root.aiClock
                clockActive: root.clockActive
                humanColor: root.humanColor
                aiColor: root.aiColor
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
                    blurOverlay: setupOpen || settingsOpen
                    interactive: !animating && !aiThinking && !gameOver && !setupOpen && !pomodoroActive && !settingsOpen
                    onClicked: function(sq) { root.handleClick(sq) }
                    onPromotionChosen: function(piece) { root.promoChosen(piece) }
                    onPromotionCancelled: root.promoCancelled()
                    clip: true
                }

                // Settings overlay. Sits on the board like the setup overlay
                // rather than pushing the panel taller. No scroller: a
                // Flickable grabs the pointer to prepare for dragging, which
                // swallowed clicks on the buttons underneath whenever the hand
                // moved even a pixel between press and release. It fits because
                // SettingsView keeps its labels inline and its presets to bare
                // numbers -- see the note at the top of that file.
                Item {
                    id: settingsOverlay
                    anchors.fill: parent
                    visible: settingsOpen
                    z: 10

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.88)
                        border.width: 1
                        border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.3)
                    }

                    SettingsView {
                        id: settingsView
                        width: parent.width - Style.space(12)
                        x: Style.space(6)
                        // Centre the controls in the board, but never above the
                        // top edge: a taller font scale overflows downward, and
                        // keeping the first sections on screen matters more than
                        // the balance.
                        y: Math.max(Style.space(6),
                                    (settingsOverlay.height - implicitHeight) / 2)

                        foreground: Color.popups.text
                        fontFamily: Style.font.family

                        humanColorSetting: root.humanColorSetting
                        chessClockSetting: root.chessClockSetting
                        pomodoroModeSetting: root.pomodoroModeSetting
                        pomodoroTimeSetting: root.pomodoroTimeSetting
                        popupsSetting: root.popupsSetting
                        undoLimitSetting: root.undoLimitSetting
                        settingsDirty: root.settingsDirty
                        clockPresets: root.clockPresets

                        onHumanColorChanged: function(color) { root.saveSetting("humanColor", color); root.settingsDirty = true }
                        onChessClockChanged: function(ms) { root.saveSetting("chessClock", ms); root.settingsDirty = true }
                        onPomodoroModeChanged: function(enabled) { root.saveSetting("pomodoroMode", enabled); root.settingsDirty = true }
                        onPomodoroTimeChanged: function(minutes) { root.saveSetting("pomodoroTime", minutes); root.settingsDirty = true }
                        onPopupsChanged: function(enabled) { root.saveSetting("popups", enabled); root.settingsDirty = true }
                        onUndoLimitChanged: function(value) { root.saveSetting("undoLimit", value); root.settingsDirty = true }
                    }
                }

                // Setup overlay
                SetupOverlay {
                    id: setupOverlay
                    anchors.fill: parent
                    visible: setupOpen
                    z: 10
                    onStartRequested: { root.startGame(null); setupOpen = false }
                }
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

    }