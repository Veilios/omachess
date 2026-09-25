// ChessEngine.js — pure rules for veilios.omachess.
//
// Board space: a1 = 0, files a..h on the low 3 bits, ranks 1..8 on the next
// 3 bits (index = rank * 8 + file, rank 0 = rank 1). Pieces are single chars:
// uppercase = white, lowercase = black, space = empty.
//
// Plain JS with a module.exports guard so the same source runs in QML
// (import "ChessEngine.js" as Chess) and under node for perft tests.

var WHITE = "w"
var BLACK = "b"
var EMPTY = " "

var FILES = "abcdefgh"

var START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

// ----------------------------------------------------------------- utilities
function pieceColor(p) { return p === EMPTY ? null : (p === p.toUpperCase() ? "w" : "b") }
function pieceType(p) { return p === EMPTY ? null : p.toUpperCase() }

function fileOf(sq) { return sq & 7 }
function rankOf(sq) { return sq >> 3 }
function sqFrom(file, rank) { return (rank << 3) | file }

function sqName(sq) {
  return FILES[fileOf(sq)] + String(rankOf(sq) + 1)
}

function parseSq(name) {
  var f = FILES.indexOf(name[0])
  var r = parseInt(name[1], 10) - 1
  if (f < 0 || isNaN(r) || r < 0 || r > 7) return -1
  return sqFrom(f, r)
}

function inBoard(sq) { return sq >= 0 && sq <= 63 }
function opp(color) { return color === WHITE ? BLACK : WHITE }

function pawnIs(p, c) { return p === (c === WHITE ? "P" : "p") }
function knightIs(p, c) { return p === (c === WHITE ? "N" : "n") }
function bishopIs(p, c) { return p === (c === WHITE ? "B" : "b") }
function rookIs(p, c) { return p === (c === WHITE ? "R" : "r") }
function queenIs(p, c) { return p === (c === WHITE ? "Q" : "q") }
function kingIs(p, c) { return p === (c === WHITE ? "K" : "k") }

// -------------------------------------------------------------------- state
function emptyBoard() {
  var b = new Array(64)
  for (var i = 0; i < 64; i++) b[i] = EMPTY
  return b
}

function newGame() { return stateFromFen(START_FEN) }

function stateFromFen(fen) {
  var parts = String(fen || "").trim().split(/\s+/)
  if (parts.length < 4) return null

  var board = emptyBoard()
  var rank = 7
  var file = 0
  var row = parts[0]
  if (rank < 0) return null
  for (var i = 0; i < row.length; i++) {
    var c = row[i]
    if (c === "/") {
      rank--
      file = 0
    } else if (c >= "1" && c <= "8") {
      file += parseInt(c, 10)
    } else {
      if (rank < 0 || file > 7) return null
      board[sqFrom(file, rank)] = c
      file++
    }
  }

  var castling = { wk: false, wq: false, bk: false, bq: false }
  for (var j = 0; j < parts[2].length; j++) {
    var ch = parts[2][j]
    if (ch === "K") castling.wk = true
    else if (ch === "Q") castling.wq = true
    else if (ch === "k") castling.bk = true
    else if (ch === "q") castling.bq = true
  }

  var ep = parts[3] === "-" ? -1 : parseSq(parts[3])

  return {
    board: board,
    turn: parts[1] === "b" ? BLACK : WHITE,
    castling: castling,
    ep: ep,
    halfmove: parts.length > 4 ? (parseInt(parts[4], 10) || 0) : 0,
    fullmove: parts.length > 5 ? (parseInt(parts[5], 10) || 1) : 1,
    moves: [],
    keys: [],
    san: []
  }
}

function fenOf(state) {
  var rows = []
  for (var r = 7; r >= 0; r--) {
    var line = ""
    var empties = 0
    for (var f = 0; f < 8; f++) {
      var p = state.board[sqFrom(f, r)]
      if (p === EMPTY) {
        empties++
      } else {
        if (empties > 0) { line += String(empties); empties = 0 }
        line += p
      }
    }
    if (empties > 0) line += String(empties)
    rows.push(line)
  }
  var c = state.castling
  var castle =
    (c.wk ? "K" : "") + (c.wq ? "Q" : "") +
    (c.bk ? "k" : "") + (c.bq ? "q" : "")
  return rows.join("/") + " " + state.turn + " " +
    (castle === "" ? "-" : castle) + " " +
    (state.ep >= 0 ? sqName(state.ep) : "-") + " " +
    state.halfmove + " " + state.fullmove
}

function positionKey(state) {
  var c = state.castling
  return state.board.join("") + state.turn +
    (c.wk ? "K" : "") + (c.wq ? "Q" : "") + (c.bk ? "k" : "") + (c.bq ? "q" : "") +
    state.ep
}

function copyState(state) {
  var c = state.castling
  return {
    board: state.board.slice(),
    turn: state.turn,
    castling: { wk: c.wk, wq: c.wq, bk: c.bk, bq: c.bq },
    ep: state.ep,
    halfmove: state.halfmove,
    fullmove: state.fullmove,
    moves: state.moves.slice(),
    keys: state.keys.slice(),
    san: state.san.slice()
  }
}

// ------------------------------------------------------------------- attacks
// Ray walkers. `d` is the rank delta (board delta = d*8 + fileStep below),
// `fstep` is the per-step file delta (0 for orthogonal N/S). The file step
// is recorded before the first move and checked each step to detect the
// file-wrap that stepping blindly across a board edge would produce.

var ORTHO = [[8, 0], [-8, 0], [1, 1], [-1, -1]]
var DIAG = [[9, 1], [-9, -1], [-7, 1], [7, -1]]
var ALL_DIRS = ORTHO.concat(DIAG)

function rayTargets(board, from, d, fstep) {
  var out = []
  var f = fileOf(from)
  var exp = f + fstep
  var to = from + d
  while (inBoard(to)) {
    if (fileOf(to) !== exp) break // wrapped across the board edge
    out.push(to)
    exp += fstep
    to += d
  }
  return out
}

function rayFirstBlocker(board, from, d, fstep) {
  var to = from + d
  var f = fileOf(from)
  var exp = f + fstep
  while (inBoard(to)) {
    if (fileOf(to) !== exp) break
    if (board[to] !== EMPTY) return to
    exp += fstep
    to += d
  }
  return -1
}

// Is `sq` attacked by any piece of color `by`?
function isAttack(state, by, sq) {
  var board = state.board
  var i, p, to

  // Pawns (one rank toward the attacker's home, one file over).
  if (by === WHITE) {
    if (inBoard(sq - 9) && board[sq - 9] === "P" && fileOf(sq - 9) === fileOf(sq) - 1) return true
    if (inBoard(sq - 7) && board[sq - 7] === "P" && fileOf(sq - 7) === fileOf(sq) + 1) return true
  } else {
    // Black pawns sit "below" the square they attack (sq + 9 / sq + 7).
    if (inBoard(sq + 9) && board[sq + 9] === "p" && fileOf(sq + 9) === fileOf(sq) + 1) return true
    if (inBoard(sq + 7) && board[sq + 7] === "p" && fileOf(sq + 7) === fileOf(sq) - 1) return true
  }

  // Knights.
  var nd = [-17, -15, -10, -6, 6, 10, 15, 17]
  for (i = 0; i < 8; i++) {
    to = sq + nd[i]
    if (inBoard(to) && Math.abs(fileOf(to) - fileOf(sq)) <= 2 &&
        Math.abs(rankOf(to) - rankOf(sq)) <= 2 &&
        kingPiece(board[to]) === "N" && pieceColor(board[to]) === by) return true
  }

  // King.
  var kd = [-9, -8, -7, -1, 1, 7, 8, 9]
  for (i = 0; i < 8; i++) {
    to = sq + kd[i]
    if (!inBoard(to)) continue
    if (Math.abs(fileOf(to) - fileOf(sq)) > 1) continue
    if (Math.abs(rankOf(to) - rankOf(sq)) > 1) continue
    if (kingPiece(board[to]) === "K" && pieceColor(board[to]) === by) return true
  }

  // Sliding pieces.
  var dirs, j, d, fstep
  dirs = ORTHO
  for (j = 0; j < 4; j++) {
    d = dirs[j][0]; fstep = dirs[j][1]
    to = rayFirstBlocker(board, sq, d, fstep)
    if (to >= 0) {
      p = board[to]
      if (pieceColor(p) === by && (kingPiece(p) === "R" || kingPiece(p) === "Q")) return true
    }
  }
  dirs = DIAG
  for (j = 0; j < 4; j++) {
    d = dirs[j][0]; fstep = dirs[j][1]
    to = rayFirstBlocker(board, sq, d, fstep)
    if (to >= 0) {
      p = board[to]
      if (pieceColor(p) === by && (kingPiece(p) === "B" || kingPiece(p) === "Q")) return true
    }
  }

  return false
}

function kingPiece(p) { return p === EMPTY ? null : p.toUpperCase() }

function findKing(state, color) {
  var k = color === WHITE ? "K" : "k"
  for (var i = 0; i < 64; i++) if (state.board[i] === k) return i
  return -1
}

function inCheck(state, color) {
  var k = findKing(state, color)
  return k >= 0 && isAttack(state, opp(color), k)
}

// ------------------------------------------------------------ move generation
function generatePseudo(state) {
  var moves = []
  var board = state.board
  var me = state.turn
  var up = me === WHITE ? 8 : -8
  var homeRank = me === WHITE ? 1 : 6
  var promoRank = me === WHITE ? 7 : 0

  var i, f, r, p, c, to, victim, deltas, j, d, fstep

  for (i = 0; i < 64; i++) {
    p = board[i]
    if (p === EMPTY) continue
    c = pieceColor(p)
    if (c !== me) continue
    f = fileOf(i)
    r = rankOf(i)
    var t = kingPiece(p)

    if (t === "P") {
      // Single push.
      to = i + up
      if (inBoard(to) && board[to] === EMPTY) {
        addPawnMove(moves, i, to, p, null, me, promoRank, [])
        // Double push from home rank.
        if (r === homeRank) {
          to = i + up * 2
          if (board[to] === EMPTY && board[i + up] === EMPTY) {
            moves.push({ from: i, to: to, piece: p, capture: null, captured: null, flags: ["double"] })
          }
        }
      }
      // Captures and en passant.
      for (var df = -1; df <= 1; df += 2) {
        to = i + up + df
        if (!inBoard(to)) continue
        if (fileOf(to) !== f + df) continue
        victim = board[to]
        if (victim !== EMPTY && pieceColor(victim) !== me) {
          addPawnMove(moves, i, to, p, victim, me, promoRank, ["capture"])
        } else if (state.ep === to && rankOf(i) === homeRank + 3 * (me === WHITE ? 1 : -1)) {
          moves.push({ from: i, to: to, piece: p, capture: null, captured: me === WHITE ? "p" : "P", flags: ["ep"] })
        }
      }
    } else if (t === "N" || t === "K") {
      deltas = t === "N"
        ? [-17, -15, -10, -6, 6, 10, 15, 17]
        : [-9, -8, -7, -1, 1, 7, 8, 9]
      var maxFileJump = t === "N" ? 2 : 1
      for (j = 0; j < deltas.length; j++) {
        to = i + deltas[j]
        if (!inBoard(to)) continue
        if (Math.abs(fileOf(to) - f) > maxFileJump) continue
        if (Math.abs(rankOf(to) - r) > maxFileJump) continue
        if (t === "N" && Math.abs(fileOf(to) - f) + Math.abs(rankOf(to) - r) !== 3) continue
        victim = board[to]
        if (victim === EMPTY) {
          moves.push({ from: i, to: to, piece: p, capture: null, captured: null, flags: [] })
        } else if (pieceColor(victim) !== me) {
          moves.push({ from: i, to: to, piece: p, capture: victim, captured: victim, flags: ["capture"] })
        }
      }
      if (t === "K") addCastling(moves, state, i, me)
    } else if (t === "R" || t === "B" || t === "Q") {
      var dirs = t === "R" ? ORTHO : (t === "B" ? DIAG : ALL_DIRS)
      for (j = 0; j < dirs.length; j++) {
        d = dirs[j][0]; fstep = dirs[j][1]
        var targets = rayTargets(board, i, d, fstep)
        for (var k = 0; k < targets.length; k++) {
          to = targets[k]
          victim = board[to]
          if (victim === EMPTY) {
            moves.push({ from: i, to: to, piece: p, capture: null, captured: null, flags: [] })
          } else {
            if (pieceColor(victim) !== me) {
              moves.push({ from: i, to: to, piece: p, capture: victim, captured: victim, flags: ["capture"] })
            }
            break
          }
        }
      }
    }
  }
  return moves
}

function addPawnMove(moves, from, to, p, victim, me, promoRank, flags) {
  if (rankOf(to) !== promoRank) {
    moves.push({
      from: from, to: to, piece: p,
      capture: victim, captured: victim, flags: flags
    })
  } else {
    var isC = flags.indexOf("capture") >= 0
    var f2 = isC ? ["capture"] : []
    var q = me === WHITE ? "Q" : "q"
    var r = me === WHITE ? "R" : "r"
    var b = me === WHITE ? "B" : "b"
    var n = me === WHITE ? "N" : "n"
    moves.push({ from: from, to: to, piece: p, capture: victim, captured: victim, flags: f2.concat(["promo"]), promo: q })
    moves.push({ from: from, to: to, piece: p, capture: victim, captured: victim, flags: f2.concat(["promo"]), promo: r })
    moves.push({ from: from, to: to, piece: p, capture: victim, captured: victim, flags: f2.concat(["promo"]), promo: b })
    moves.push({ from: from, to: to, piece: p, capture: victim, captured: victim, flags: f2.concat(["promo"]), promo: n })
  }
}

function addCastling(moves, state, kingSq, me) {
  var c = state.castling
  var kingside = me === WHITE ? c.wk : c.bk
  var queenside = me === WHITE ? c.wq : c.bq
  var back = me === WHITE ? 0 : 7
  var kDest = sqFrom(6, back)
  var qDest = sqFrom(2, back)
  var rK = sqFrom(7, back)
  var rQ = sqFrom(0, back)
  var k = me === WHITE ? "K" : "k"
  var r = me === WHITE ? "R" : "r"
  var enemy = opp(me)

  if (state.board[kingSq] !== k || inCheck(state, me)) return

  if (kingside && state.board[rK] === r &&
      state.board[sqFrom(5, back)] === EMPTY && state.board[sqFrom(6, back)] === EMPTY &&
      !isAttack(state, enemy, sqFrom(5, back)) && !isAttack(state, enemy, kDest)) {
    moves.push({ from: kingSq, to: kDest, piece: k, capture: null, captured: null, flags: ["kingside"] })
  }
  if (queenside && state.board[rQ] === r &&
      state.board[sqFrom(1, back)] === EMPTY &&
      state.board[sqFrom(2, back)] === EMPTY &&
      state.board[sqFrom(3, back)] === EMPTY &&
      !isAttack(state, enemy, sqFrom(3, back)) && !isAttack(state, enemy, qDest)) {
    moves.push({ from: kingSq, to: qDest, piece: k, capture: null, captured: null, flags: ["queenside"] })
  }
}

// Legal moves: filter pseudo-legal by own-king safety.
function generateMoves(state) {
  var pseudo = generatePseudo(state)
  var legal = []
  var i
  for (i = 0; i < pseudo.length; i++) {
    var m = pseudo[i]
    var copy = copyState(state)
    applyMutation(copy, m)
    if (!inCheck(copy, state.turn)) legal.push(m)
  }
  return legal
}

function movesFrom(state, sq) {
  var all = generateMoves(state)
  var out = []
  for (var i = 0; i < all.length; i++) if (all[i].from === sq) out.push(all[i])
  return out
}

function legalTargets(state, sq) {
  var out = []
  var ms = movesFrom(state, sq)
  for (var i = 0; i < ms.length; i++) out.push(ms[i].to)
  return out
}

// ----------------------------------------------------------- apply / make/undo
// Pure board mutation; does not touch move history. Used both by
// generateMoves' legality filter (on a copy) and by makeMove.
function applyMutation(state, move) {
  var board = state.board
  var me = state.turn
  var f = move.flags || []
  var kingside = f.indexOf("kingside") >= 0
  var queenside = f.indexOf("queenside") >= 0
  var isEp = f.indexOf("ep") >= 0
  var isPromo = f.indexOf("promo") >= 0

  // Remove captured piece first so the destination clears for the mover.
  if (move.captured) {
    if (isEp) {
      var capSq = move.to + (me === WHITE ? -8 : 8)
      board[capSq] = EMPTY
    } else {
      board[move.to] = EMPTY
    }
  }

  board[move.from] = EMPTY
  board[move.to] = isPromo ? move.promo : move.piece

  var c = state.castling
  if (kingside) {
    var rk = rankOf(move.from)
    board[sqFrom(5, rk)] = board[sqFrom(7, rk)]
    board[sqFrom(7, rk)] = EMPTY
  } else if (queenside) {
    var rq = rankOf(move.from)
    board[sqFrom(3, rq)] = board[sqFrom(0, rq)]
    board[sqFrom(0, rq)] = EMPTY
  }

  if (me === WHITE) {
    if (move.piece === "K") { c.wk = false; c.wq = false }
    if (move.from === 0 || move.to === 0) c.wq = false
    if (move.from === 7 || move.to === 7) c.wk = false
  } else {
    if (move.piece === "k") { c.bk = false; c.bq = false }
    if (move.from === 56 || move.to === 56) c.bq = false
    if (move.from === 63 || move.to === 63) c.bk = false
  }

  if (f.indexOf("double") >= 0) state.ep = (move.from + move.to) / 2
  else state.ep = -1

  if (kingPiece(move.piece) === "P" || move.captured) state.halfmove = 0
  else state.halfmove++

  state.turn = opp(me)
  if (me === BLACK) state.fullmove++
}

function moveString(state, move) {
  // state is the position BEFORE the move; side to move == mover.
  var f = move.flags || []
  if (f.indexOf("kingside") >= 0) return "O-O"
  if (f.indexOf("queenside") >= 0) return "O-O-O"

  var t = kingPiece(move.piece)
  var txt = t === "P" ? "" : t
  if (t !== "P") {
    var rivals = []
    var legal = generateMoves(state)
    for (var i = 0; i < legal.length; i++) {
      var m = legal[i]
      if (m.to === move.to && m.from !== move.from && kingPiece(m.piece) === t) rivals.push(m)
    }
    if (rivals.length > 0) {
      var sameFile = false
      var sameRank = false
      for (i = 0; i < rivals.length; i++) {
        if (fileOf(rivals[i].from) === fileOf(move.from)) sameFile = true
        if (rankOf(rivals[i].from) === rankOf(move.from)) sameRank = true
      }
      if (!sameFile) txt += FILES[fileOf(move.from)]
      else if (!sameRank) txt += String(rankOf(move.from) + 1)
      else txt += sqName(move.from)
    }
  }
  if (move.captured) txt += "x"
  txt += sqName(move.to)
  if (f.indexOf("ep") >= 0) txt += " e.p."
  if (f.indexOf("promo") >= 0) txt += "=" + move.promo.toUpperCase()
  return txt
}

function makeMove(state, move) {
  var preTurn = state.turn
  var preCastling = {
    wk: state.castling.wk, wq: state.castling.wq,
    bk: state.castling.bk, bq: state.castling.bq
  }
  var preEp = state.ep
  var preHalf = state.halfmove
  var preFull = state.fullmove

  var san = moveString(state, move)
  applyMutation(state, move)

  // Check / mate marker for the opponent, evaluated after the move.
  if (inCheck(state, state.turn)) {
    san += resultOf(state).type === "checkmate" ? "#" : "+"
  }

  move.san = san
  move.pre = {
    turn: preTurn,
    castling: preCastling,
    ep: preEp,
    halfmove: preHalf,
    fullmove: preFull
  }

  state.san.push(san)
  state.keys.push(positionKey(state))
  state.moves.push(move)
  return move
}

function undoMove(state) {
  if (state.moves.length === 0) return null
  var move = state.moves.pop()
  var board = state.board
  var f = move.flags || []
  var kingside = f.indexOf("kingside") >= 0
  var queenside = f.indexOf("queenside") >= 0
  var isEp = f.indexOf("ep") >= 0

  board[move.from] = move.piece
  if (move.captured) {
    if (isEp) {
      var capSq = move.to + (pieceColor(move.piece) === WHITE ? -8 : 8)
      board[capSq] = move.captured
      board[move.to] = EMPTY
    } else {
      board[move.to] = move.captured
    }
  } else {
    board[move.to] = EMPTY
  }

  if (kingside) {
    var rk = rankOf(move.from)
    board[sqFrom(7, rk)] = board[sqFrom(5, rk)]
    board[sqFrom(5, rk)] = EMPTY
  } else if (queenside) {
    var rq = rankOf(move.from)
    board[sqFrom(0, rq)] = board[sqFrom(3, rq)]
    board[sqFrom(3, rq)] = EMPTY
  }

  if (move.pre) {
    state.castling = move.pre.castling
    state.ep = move.pre.ep
    state.halfmove = move.pre.halfmove
    state.fullmove = move.pre.fullmove
    state.turn = move.pre.turn
  } else {
    state.turn = pieceColor(move.piece)
  }
  if (state.keys.length) state.keys.pop()
  if (state.san.length) state.san.pop()
  return move
}

// -------------------------------------------------------------------- status
function resultOf(state) {
  var legal = generateMoves(state)
  if (legal.length === 0) {
    return inCheck(state, state.turn)
      ? { type: "checkmate", winner: opp(state.turn) }
      : { type: "stalemate", winner: null }
  }
  if (state.halfmove >= 100) return { type: "draw50", winner: null }
  var k = positionKey(state)
  var count = 0
  for (var i = 0; i < state.keys.length; i++) if (state.keys[i] === k) count++
  if (count >= 3) return { type: "drawRepetition", winner: null }
  if (insufficientMaterial(state)) return { type: "drawMaterial", winner: null }
  return { type: "none", winner: null }
}

function insufficientMaterial(state) {
  var counts = { n: 0, b: 0, r: 0, q: 0 }
  var minors = 0
  var bishops = []
  for (var i = 0; i < 64; i++) {
    var t = kingPiece(state.board[i])
    if (t === null || t === "K") continue
    if (t === "P" || t === "R" || t === "Q") return false
    if (t === "N" || t === "B") {
      minors++
      counts[t]++
      if (t === "B") bishops.push((fileOf(i) + rankOf(i)) % 2)
    }
  }
  if (minors === 1) return true // K+N vs K or K+B vs K
  if (minors === 2 && counts.b === 2 && bishops[0] === bishops[1]) return true
  return false
}

function isCheck(state) { return inCheck(state, state.turn) }

// -------------------------------------------------------------------- exports
if (typeof module !== "undefined") {
  module.exports = {
    WHITE: WHITE,
    BLACK: BLACK,
    EMPTY: EMPTY,
    START_FEN: START_FEN,
    pieceColor: pieceColor,
    pieceType: kingPiece,
    fileOf: fileOf,
    rankOf: rankOf,
    sqFrom: sqFrom,
    sqName: sqName,
    parseSq: parseSq,
    newGame: newGame,
    stateFromFen: stateFromFen,
    fenOf: fenOf,
    generateMoves: generateMoves,
    movesFrom: movesFrom,
    legalTargets: legalTargets,
    makeMove: makeMove,
    undoMove: undoMove,
    moveString: moveString,
    resultOf: resultOf,
    isCheck: isCheck,
    inCheck: inCheck,
    copyState: copyState
  }
}