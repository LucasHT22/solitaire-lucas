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

This repo does implement a pagoda function, see "The pagoda function" section further down for the concrete weighting. Beyond that: the classic 33-hole board's center-to-center puzzle has been extensively analyzed by hand and by computer over the decades, and the shortest solutions in the range of ~18 moves are commonly cited in the literature (where a "move" can chain several same-peg jumps in sequence) - see References for sources of this.

### The solver

`solve_from(mask)` is plain recursive backtracking over the bitboard:

```gdscript
func solve_from(mask: int):
    if count_bits(mask) == 1:
        return []
    if solver_failed_cache.has(mask):
        return null
 
    for move in solver_moves:
        if (mask & move.from_bit) and (mask & move.mid_bit) and not (mask & move.to_bit):
            var rest = solve_from(apply(mask, move))
            if rest != null:
                return [move] + rest
 
    solver_failed_cache[mask] = true
    return null
```

The only thing standing between this and a combinatorial explosion is `solver_failed_cache`, a transposition table. The raw state space for "33 cells, some subset occupied" is `2^33` (~8.6 billion), but the reachable states from a legal board are far fewer, and most branches die within few plies. Caching "this exact configuration has no solution" means the search never re-explodes a dead subtree it's already proven dead - this single optimization is the difference between solving in under a second and not finishing at all.

### Board shapes and why the search doesn't scale gracefully

The English cross isn't the only valid board. This repo also supports the European cross (37 holes, rows of width `3,5,7,7,7,5,3`) and a Full Square (49 holes, no cells removed at all). Switching shapes only changes `is_valid_cell(r, c)`, the jump rule, the bitboard packing, and the solver are shape-agnostic by construction, since they all operate over whatever `valid_cells` happens to contain:

```
English (33): 2^33 = 8.6 x 10^9
European (37): 2^37 = 1.4 x 10^11
Full (49): 2^49 = 5.6 x 10^14
```

The transportation table (`solver_failed_cache`) tames this considerably in practice, most branches die within a few plies, and identical sub-configurations reached by different move orders are never re-explored. But there's a specific failure mode the cache cant rescue from: proving a position has no solution requires exhausting every branch. There's no shortcut for a negative result the way there is for a positive one (a solution just needs one succesful path; a non-solution needs all of them ruled out). On the English board this is still trackable. On the Full Square, if the position turns out to be unsolvable, the search may need to touch a meaningful fraction of that `5.6 x 10^14` befire it can honestly say so.

### Why 22 pegs can be instant and 15 pegs can time out

This is the counterintuitive part, fewer pegs does not mean easier search. It means shallower search, which is a different thing.

Every legal move removes exactly one peg, so a position with `k` pegs remaining is always exactly `k - 1` jumps from a single-peg finish, if a finish is reachable at all. That fixes the maximum depth of the search tree. The number of leaves at that depth, in the worst case grows like:

```
leaves = b^(k - 1)
```

where `b` is the average branching factor (how many legal jumps are available per position, typically somewhere in the 2-8 range on a mid-game board, depending on how clustered the remaining pegs are). This is why depth dominates: going from `k = 22` to `k = 15` cuts seven layers off the tree, which can mean several orders of magnitude fewer leaves, if both searches behave the same way. And that "if" is exactly where the asymmetry from the previous section bites.

 - If the `k = 22` position is solvable, `solve_from` typically finds a path without exploring anywhere near the full tree, it commmits to the first move that leads somewhere, recurses, and returns as soon as one branch succeeds. In the best case this is closer to `O(k · b)` than `O(b^k)`: it's a walk down one path, not an enumeration of all of them, only backtracking when a specific branch dead-ends.
 - If the `k = 15` position is unsolvable, which can happen if earlier manual play isolated a peg or split the board into disconnected clusters, there is no early exit. The search must expand and rule out every single one of those `~b^14` leaves before `solve_from` can honestly return `null`. Fewer pegs bought you a shallower tree, but a full enumeration of a shallow-but-unsolvable tree can still lose to a shallow walk down one path of a deeper-but-solvable one.

In other words: whether a search is fast is governed far more by whether the position is solvable than by how many pegs are on the board. Peg count sets an upper bound on the work, solvability decides whether the search gets to stop early or has to hit that bound. Bounding depth alone (the peg-count threshold) is not the same as bounding cost, a shallow-but-unsolvable subtree can still be expensive.

A sharper tool sidesteps the enumeration entirely: a pagoda function can sometimes prove a position unsolvable in closed form, no search at all, by exhibiting a weigthing where the position's total already falls short of the target's weight. This repo implements one, see "The pagoda function" section below for the concrete weighting.

### Why solve is restricted to the England board

One of the first tries of this solver, tried to handle the risk above with a node budget, cap the search effort, and if it ran out, report "inconclusive" instaed of a false negative. That works, but it's a patch over a problem that's better solved upstream: the English Cross is the only shape here with a well-established theory behind it. Its solvability (32 pegs down to 1, center to center) is proven via pagoda functions, independent of any search, it's not a hope, it's a certainty. The European Cross and Full Square have no such guarantee baked into this project, whether a given position on those boards is solvable is genuinely open until searched, and a full 49-cell board is exactly the case from the previous section where an unsolvable position can force to a full `2^49` enumeration.

Rather than let the player hit that well and get an ambiguous "ran out of budget" message, `Solve` simply isn't offered outside the English board:

```gdscript
func _on_solve_button_pressed() -> void:
    if animating or solving:
        return
    if board_shape != SHAPE_ENGLISH:
        game_over_message = "Solve is only available on the English Cross board."
        queue_redraw()
        return
    ...
```

`Hint` and `Count Solutions` don't get this restriction, they're already bounded by the peg-count threshold from the section above, which caps depth regardless of shape. That's a real bound, just a coarser one than "provably tractable": it doesn't rule out an expensive negative result at 15 pegs, but it keeps the worst case survivable on any board shape. `Solve`, left unrestricted, was the one feature exposed to the full, unbounded version of that risk, so it's the one that got a hard shape gate instaed of a soft depth gate.

### Counting solutions: from search to dynamic programming

```gdscript
func count_solutions(mask: int) -> int:
    if count_bits(mask) == 1:
        return 1
    if solution_count_cache.has(mask):
        return solution_count_cache[mask]
 
    var total = 0
    for move in applicable_moves(mask):
        total += count_solutions(apply(mask, move))
 
    solution_count_cache[mask] = total
    return total
```

### Unlock thresholds as a UX/performance tradeoff

### Jump animation

```
position(t) = from · (1 − t) + to · t, t ∈ [0, 1]
```

### The pagoda function

```
w(r, c) = φ^(-|r − target_r|) · φ^(-|c − target_c|),    φ = (1 + √5) / 2
```

### Winning strategy

### References

- Berlekamp, E. R., Conway, J. H., and Guy, R. K. — *Winning Ways for Your Mathematical Plays* (the original treatment of pagoda functions / potential-function arguments for peg solitaire and related games)
- Beasley, J. D. — *The Ins and Outs of Peg Solitaire* (a book-length treatment specifically of peg solitaire: board variants, solvability theory, and known solutions)
- Bell, G. I. — various published papers on peg solitaire, including work on counting solutions and computer-assisted solvability analysis
- "Peg solitaire," Wikipedia — general overview, including the standard boards and a summary of the pagoda-function solvability argument
- The Chess Programming Wiki — background on bitboards and transposition tables, the two techniques borrowed here from game-tree search