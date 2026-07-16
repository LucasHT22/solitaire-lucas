# Solitaire Lucas

A classic peg solitaire built from scratch in Godot. Cross board, move highlighting, tween-based jump animation, and a bitboard backtracking solver.

---

## How it works

### The board

The classic English board is a cross of 33 holes carved out of a 7x7 grid, every cell except the four 2x2 corners:

```
cell(r, c) is valid <=> (2 <= c <= 4) or (2 <= r <= 4)
```

The game starts with a peg in every valid cell except the center `(3, 3)`, which starts empty.

### The jump rule

A move takes a peg at position `p`, jumps it over an adjacent peg at `m`, landing on an empty hole at `q`, where `m` is the midpoint of `p` and `q`:

```
q = p + 2d, m = p + d, d ∈ {(1,0), (-1,0), (0,1), (0,-1)}

board(p) = 1, board(m) = 1, board(q) = 0 -> board(p) = 0, board(m) = 0, board(q) = 1
```

Every legal move removes exactly one peg. Starting from 32 pegs, a full solve is a sequence of exactly 31 jumps.

### Bitboard representation

For the solver, the 33 valid cells areflattened into a single integer, one bit per hole:

```
mask = Σ 2^i · board(cellᵢ) for i in 0..32
```

A move  becomes three bitmasks, `from`, `mid`, `to`, precomputed once at startup for every geometrically valid jump on the board. Applying a move is then pure bit arithmetric:

```
new_mask = (mask & ~from_bit & ~mid_bit) | to_bit
```

This is the same trick usedin chess engines (bitboards), turning board mutation into O(1) integer operations instaed of 2D array writes, which matters once you're exploring thousands of branches per second.

### Why the classic puzzle is solvable at all

It isnt obvious a priori that starting with the center empty and ending with one peg in the center is even possible, most peg-count reductions are. The classical proof uses a potential function (Conway calls these pagoda functions): assign a weight `w(cell)` to every hole such that for every legal jump `(p, m, q)`:

```
w(p) + w(m) >= w(q)
```

Summed over the whole board, the total weight is non-increasing after any move. If you can exhibit a weighting where the only single-peg configurations with weight >= the initial total are the ones you're trying to reach, you've proven those are the only reachables endpoints, without searching a single position. It's a beatiful example of proving something about an exponential search space using pure linear algebra.
