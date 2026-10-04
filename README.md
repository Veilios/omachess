# OmaChess

A mini game with the pomodoro method at its core, played in your bar.

It's for people who want to focus and work but also need small breaks in
between — and a break that still engages and challenges you. A real game of
chess against a built-in AI, with a **Lock In** timer between moves: once you
play, the board blurs and the AI thinks behind it for a set focus block. The
board stays unusable until it finishes.

![A game in progress](screenshots/mid-game.png) ![Lock In running while the AI thinks](screenshots/lock-in.png)

## Install

```sh
omarchy plugin add https://github.com/Veilios/omachess.git
omarchy restart shell
```

## Play

Click the knight in the bar, or summon it from anywhere:

```sh
omarchy-shell shell toggle veilios.omachess
```

The same command closes it.

## License

MIT