# The child register

How the phrasing in `packs/*/phrases.json` is written, and why. Every rule below
traces to a source in `PLAN.md` §6c or §6b.

## The rules

1. **Twelve words or fewer.**
   Eight-year-olds recall naturally spoken sentences better than synthetic ones
   *even when intelligibility is equal* — synthetic speech spends working memory
   on decoding (Greene, 1987). Short lines are the mitigation.

2. **Warm, not neutral.**
   Emotionally positive tone measurably raised comprehension accuracy in
   children (Dylman et al., 2025). Praise is a comprehension aid, not decoration.

3. **Name the consequence, not the solution.**
   "He can just take that" — not "you should have played Nf3". The child has to
   do the search. Withholding is the mechanism (Miwa et al., 2014).

4. **Only name square and piece when they are in the computed motifs.**
   The facts come from `moveMotifs()`. A line that invents a square is a bug,
   and the test suite rejects it.

5. **No vocabulary beyond the pieces.**
   Knight, rook, bishop, queen, king, pawn. Not "unprotected", not "hanging",
   not "tempo". Say what happens, in ordinary words.

6. **Silence is a valid output.**
   Target 40–70% of moves, not 100% (Reid & Swafford, 2020).

7. **Vary it.**
   Four or more variants per key; never repeat within six plies. Synthetic
   monotony has a measured cost for children (Hanulíková et al., 2025).

## Before and after

| Patzer's panel wording | Child register |
|---|---|
| "Left unprotected after this move: bishop on e5. The opponent can win material." | "Oh — your bishop's on his own there. He can just take it." |
| "This move allows the opponent to checkmate at once: Qxf7#." | "Stop — he can mate you right there." |
| "The opponent's best answer: Nf6." | "He'll probably bring the knight out." |
| "it develops a piece" | *(silence)* |
| — | "Nice. That was free." |
| — | "Good — you got it out of danger." |

## Two things to keep out

- **False authority.** Never state an evaluation the engine did not compute.
  This is the whole reason the coach does not generate its own analysis.
- **Contempt.** No "obviously", no "unfortunately", no "you should have". He is
  seven, and he is allowed to lose.

## Voice settings

Rendered at speed **0.95–1.0**, never faster — fast speech measurably degrades
children's comprehension, while slow and normal do not differ (Haake et al.,
2013). Do not over-slow; it reads as patronising and buys nothing.

Two to three prosodic treatments per template (speed ±5%, pitch ±1 semitone),
rotated per session.
