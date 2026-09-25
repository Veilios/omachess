// ChessAI.js — basic engine for veilios.omachess.
//
// Negamax with alpha-beta pruning, MVV-LVA ordering and a small material +
// piece-square evaluation. Search runs synchronously on the calling thread,
// so a node budget is used to keep the QML UI thread responsive.
//
// Plain JS with a module.exports guard so the same source runs in QML
// (import "ChessAI.js" as AI) and under node for tests.

var WHITE = "w"
var BLACK = "b"

var VALUE = { P: 100, N: 320, B: 330, R: 500, Q: 900, K: 20000 }
var MATE = 50000
var INF = 1e9

// Piece-square tables, classic "simple evaluation" shape. Row 0 = rank 8,
// table index = mirrorV(square) so "up" is always the promotion direction.
var PST = {
  P: [
    0,0,0,0,0,0,0,0,
    50,50,50,50,50,50,50,50,
    10,10,20,30,30,20,10,10,
    5,5,10,25,25,10,5,5,
    0,0,0,20,20,0,0,0,
    5,-5,-10,0,0,-10,-5,5,
    5,10,10,-20,-20,10,10,5,
    0,0,0,0,0,0,0,0
  ],
  N: [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,0,0,0,0,-20,-40,
    -30,0,10,15,15,10,0,-30,
    -30,5,15,20,20,15,5,-30,
    -30,0,15,20,20,15,0,-30,
    -30,5,10,15,15,10,5,-30,
    -40,-20,0,5,5,0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50
  ],
  B: [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,0,0,0,0,0,0,-10,
    -10,0,5,10,10,5,0,-10,
    -10,5,5,10,10,5,5,-10,
    -10,0,10,10,10,10,0,-10,
    -10,10,10,10,10,10,10,-10,
    -10,5,0,0,0,0,5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20
  ],
  R: [
    0,0,0,0,0,0,0,0,
    5,10,10,10,10,10,10,5,
    -5,0,0,0,0,0,0,-5,
    -5,0,0,0,0,0,0,-5,
    -5,0,0,0,0,0,0,-5,
    -5,0,0,0,0,0,0,-5,
    -5,0,0,0,0,0,0,-5,
    0,0,0,5,5,0,0,0
  ],
  Q: [
    -20,-10,-10,-5,-5,-10,-10,-20,
    -10,0,0,0,0,0,0,-10,
    -10,0,5,5,5,5,0,-10,
    -5,0,5,5,5,5,0,-5,
    0,0,5,5,5,5,0,-5,
    -10,5,5,5,5,5,0,-10,
    -10,0,5,0,0,0,0,-10,
    -20,-10,-10,-5,-5,-10,-10,-20
  ],
  K: [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
    20,20,0,0,0,0,20,20,
    20,30,10,0,0,10,30,20
  ],
  Ke: [
    -50,-40,-30,-20,-20,-30,-40,-50,
    -30,-20,-10,0,0,-10,-20,-30,
    -30,-10,20,30,30,20,-10,-30,
    -30,-10,30,40,40,30,-10,-30,
    -30,-10,30,40,40,30,-10,-30,
    -30,-10,20,30,30,20,-10,-30,
    -30,-30,0,0,0,0,-30,-30,
    -50,-30,-30,-30,-30,-30,-30,-50
  ]
}

function kingPiece(p) { return p === " " ? null : p.toUpperCase() }
function mirrorV(sq) { return ((7 - (sq >> 3)) << 3) | (sq & 7) }

// Game phase 0..24 (0 = nothing left, 24 = full non-pawn material) for
// blending the king tables toward the endgame table.
function gamePhase(state) {
  var q = 0, r = 0, b = 0, n = 0
  for (var i = 0; i < 64; i++) {
    switch (kingPiece(state.board[i])) {
      case "Q": q++; break
      case "R": r++; break
      case "B": b++; break
      case "N": n++; break
    }
  }
  return Math.min(24, 4 * q + 2 * r + b + n)
}

function evaluate(state) {
  var score = 0
  var phase = gamePhase(state)
  for (var i = 0; i < 64; i++) {
    var p = state.board[i]
    if (p === " ") continue
    var t = kingPiece(p)
    var idx = p === t ? mirrorV(i) : i
    var pos = t === "K"
      ? (PST.K[idx] * phase + PST.Ke[idx] * (24 - phase)) / 24
      : PST[t][idx]
    if (p === t) score += VALUE[t] + pos
    else score -= VALUE[t] + pos
  }
  return score
}

function moveScore(m) {
  var s = 0
  if (m.captured) s = VALUE[m.captured.toUpperCase()] * 16 - VALUE[m.piece.toUpperCase()]
  if (m.flags && m.flags.indexOf("promo") >= 0) s += VALUE[m.promo.toUpperCase()] * 16
  return s
}

function orderMoves(moves) {
  moves.sort(function (a, b) { return moveScore(b) - moveScore(a) })
}

// The engine must be bound before searching. In QML, Main.qml calls
// AI.setEngine(Chess) after importing both files.
var Engine = null
function setEngine(engineObj) { Engine = engineObj }

// Color-relative score for the side to move.
function search(state, depth, alpha, beta, ply) {
  var moves = Engine.generateMoves(state)
  if (moves.length === 0) {
    if (Engine.inCheck(state, state.turn)) return ply - MATE  // this side is mated
    return 0
  }
  if (depth <= 0) return (state.turn === WHITE ? 1 : -1) * evaluate(state)

  orderMoves(moves)
  var best = -INF
  for (var i = 0; i < moves.length; i++) {
    Engine.makeMove(state, moves[i])
    var v = -search(state, depth - 1, -beta, -alpha, ply + 1)
    Engine.undoMove(state)
    if (v > best) best = v
    if (v > alpha) alpha = v
    if (alpha >= beta) break
  }
  return best
}

function searchRoot(state, depth, alpha, beta) {
  var moves = Engine.generateMoves(state)
  var best = -INF
  var picks = []
  orderMoves(moves)
  for (var i = 0; i < moves.length; i++) {
    Engine.makeMove(state, moves[i])
    var v = -search(state, depth - 1, -beta, -alpha, 1)
    Engine.undoMove(state)
    if (v > best) {
      best = v
      picks = [moves[i]]
      if (v > alpha) alpha = v
    } else if (v === best) {
      picks.push(moves[i])
    }
  }
  return { score: best, moves: picks }
}

// Returns the chosen move object (or null when no moves exist). Options:
//   depth  — maximum search depth (default 3)
//   timeMs — soft node budget; stops deepening once exceeded (0 = ignore)
function chooseMove(state, opts) {
  var maxDepth = (opts && opts.depth) || 3
  var timeMs = (opts && opts.timeMs) || 0
  var start = Date.now()
  var result = null

  for (var d = 1; d <= maxDepth; d++) {
    if (d > 1 && timeMs && Date.now() - start > timeMs) break
    result = searchRoot(state, d, -INF, INF)
    if (timeMs && Date.now() - start > timeMs) break
  }

  if (!result || result.moves.length === 0) return null
  return result.moves[Math.floor(Math.random() * result.moves.length)]
}

// No module.exports here: Quickshell's QML runtime must never touch
// node-specific globals. Main.qml calls AI.setEngine(Chess) on load, and
// node tests do the same with require("./ChessEngine.js").