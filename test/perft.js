#!/usr/bin/env node
"use strict"

// Perft validator for ChessEngine.js. Run: node test/perft.js
// Reference values are the classic published Perft results.

const Chess = require("../ChessEngine.js")

function perft(fen, depth) {
  const state = Chess.stateFromFen(fen)
  const t0 = Date.now()
  const nodes = perftNode(state, depth)
  const ms = Date.now() - t0
  return { nodes, ms }
}

function perftNode(state, depth) {
  if (depth === 0) return 1
  const moves = Chess.generateMoves(state)
  if (depth === 1) return moves.length
  let total = 0
  for (const m of moves) {
    Chess.makeMove(state, m)
    total += perftNode(state, depth - 1)
    Chess.undoMove(state)
  }
  return total
}

const cases = [
  {
    name: "initial position",
    fen: Chess.START_FEN,
    expected: [1, 20, 400, 8902, 197281, 4865609],
  },
  {
    name: "position 2 (Kiwipete)",
    fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    expected: [1, 48, 2039, 97862, 4085603],
  },
  {
    name: "position 3 (en passant)",
    fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    expected: [1, 14, 191, 2812, 43238, 674624],
  },
  {
    name: "position 4 (promotions)",
    fen: "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    expected: [1, 6, 264, 9467, 422333],
  },
  {
    name: "position 5 (short castling)",
    fen: "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    expected: [1, 44, 1486, 62379, 2103487],
  },
  {
    name: "position 6 (long castling)",
    fen: "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    expected: [1, 46, 2079, 89890, 3894594],
  },
]

let failed = 0
for (const test of cases) {
  const maxD = Math.min(test.expected.length - 1, 4)
  for (let d = 1; d <= 4; d++) {
    const exp = test.expected[d]
    if (exp === undefined) continue
    const { nodes, ms } = perft(test.fen, d)
    const ok = nodes === exp
    if (!ok) failed++
    console.log(
      `${ok ? "PASS" : "FAIL"} ${test.name} depth=${d}  got=${nodes} want=${exp}  (${ms}ms)`
    )
    if (!ok && d > 1) {
      // Print a sampled divergent move for debugging.
      const state = Chess.stateFromFen(test.fen)
      for (const m of Chess.generateMoves(state)) {
        Chess.makeMove(state, m)
        const sub = perftNode(state, d - 1)
        Chess.undoMove(state)
        const expectedSub = boxCheck(test.fen, m, d, test.expected[d - 1])
        if (typeof expectedSub === "number" && expectedSub !== sub) {
          console.log(`   first divergence: ${m.san || Chess.moveString(state, m)} ${Chess.sqName(m.from)}-${Chess.sqName(m.to)} got=${sub}`)
          break
        }
      }
    }
  }
}

// Fallback helper (only used in failure diagnostics; box check is optional).
function boxCheck() { return undefined }

console.log(failed === 0 ? "\nALL PERFT TESTS PASSED" : `\n${failed} FAILURES`)
process.exit(failed === 0 ? 0 : 1)