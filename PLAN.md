# Patzer Live Commentary — Implementation Plan (v2, verified)

**Goal:** Dr. Wolf-style *per-move, spoken* commentary for a 7-year-old, built on Patzer.
**Status:** Planned, verified against `SikamikanikoBG/patzer@main` (pushed 2026-10-24)
**Licence:** MIT — upstream-first (§11)
**Revision:** v5. v2 methods survey (§6b); v3 voice pipeline (§6c); v4 contribution/distribution/licensing (§11); v5 asset distribution — repo kept light, audio as release assets (§11.7).

---

## 1. Objective

A short spoken line after **every** user move, in under a second; deeper explanation only on interesting moves, a few seconds later; occasional praise; a warning before an obvious blunder.

## 2. Non-goals (decided — do not re-litigate)

| Excluded | Why |
|---|---|
| Persona / mascot | Child doesn't need one |
| Native app | Browser is fine |
| UI redesign | Existing UI is adequate |
| Simplified piece names ("horsey") | Child already knows Knight and Rook |
| Lichess integration | Legal constraint — assistance only vs the Lichess AI (§3) |
| LLM call per move | 5–30 s latency — unusable (§6) |

## 3. Decision record: why Patzer

| Candidate | Score today | Modifiable? | Verdict |
|---|---|---|---|
| **Patzer** | 62 → ~90 | ✅ MIT | **Build here** |
| Dr. Wolf | 90 | ❌ closed, mobile-only, no web build | Bridge subscription |
| ChessKid Gold | 88 | ❌ | Not selected |
| Lichess | 60 | ⚠️ AGPL, huge | Practice only |
| Glassfish | 64 | ❌ no licence file | Reference only |
| proveo-ca/chess-coach | — | ❌ repo deleted | Dead |
| Chess.com Play Coach | 84 | ❌ | Age-gated 13+ |

Lichess permits assistance only against the Lichess AI, never against a human. Patzer owns its board, so the constraint does not apply.

## 4. Verified current state (with code anchors)

Everything below was read, not assumed.

| Capability | Status | Anchor |
|---|---|---|
| Coach intensity setting | ✅ | `server/src/types.ts` — `CoachBehavior = 'silent' \| 'on_demand' \| 'always_on_pedagogical'` |
| Per-move classification | ✅ | `ws/play.ts` → `quickClassify({ depth: 10 })` |
| Classification sent to client | ✅ | `ws/play.ts` → `send('move_classified', {…})`; handled at `web/src/pages/Play.tsx:550` |
| Push commentary on blunder/mistake | ✅ | `ws/play.ts` — gated on `coach_behavior === 'always_on_pedagogical'` |
| Streaming coach output | ✅ | `send('coach_chunk')` / `send('coach_done')` |
| **Motif detector** | ✅ | `coach/tactics.ts` → **`moveMotifs(fenBefore, san)`**, synchronous, pure chess.js |
| Motif shape | ✅ | `MoveMotifs`: `mate, check, castles, promotes, develops, captured, fork[], hangs[], saves[], threatens[], allowsMate, stopsMate, threatensMate` |
| **Motif → sentence renderer** | ✅ | `coach/coaching.ts` → **`moveReasons(motifs, lang, aud)`**, returns 0–3 strings |
| Negative phrases | ✅ | `Phrases.allowsMate(m)`, `Phrases.hangs(p)`, `Phrases.opponentReply(m)`, `Phrases.quiet` |
| Phrase bank, localised | ✅ | `PHRASES` — **en, es, de, ru** (+1) |
| Verdict tone | ✅ | `toneFor(classification) → 'praise' \| 'correct' \| 'neutral'` |
| Audience-aware piece names | ✅ | `pieceLabel(p, lang, audience)`; `Audience` includes `'kid'` |
| Hallucination guard | ✅ | `contradiction(text, classification, lang)` |
| Deterministic fallback text | ✅ | `fallbackText(facts, lang)` |
| **Client auto-speaks coach output** | ✅ | `web/src/components/CoachPanel.tsx` — `playTts()` calls `speak()` with `tts_enabled`, `tts_voice`, `tts_rate`, `tts_pitch`, `mutedRef` |
| TTS engine | ✅ | `web/src/lib/tts.ts` — voice pick, cancel-generation guard, BCP-47, Chrome bug workaround |
| Pre-move preview | ✅ | `preview_result` message in `ws/play.ts` |
| CHECK-widening migration precedent | ✅ | `db.ts` → `widenGamesSourceCheck()` (v7.15, for `games.source`) |
| Auto-review worker (event → async LLM) | ✅ | `server/src/autoReview.ts` |

**Design law already enforced in-repo** (`tactics.ts`):

> "Everything the coach says about *why* a move is good or bad comes from here or from the engine, never from the LLM… even a 27B model, given only 'the knight goes to f6' and 'material is equal', called the move that allows Qxf7# 'great development' (discussion #37)."

## 5. The gap — five items, all small

1. **Motifs are never computed on the live move path.** `moveMotifs()` exists, but `quickClassify()` returns only `{ classification, cp_loss, best_uci, best_san, eval_after_cp }`. Verified.
2. **The deterministic sentence is never sent live.** `moveReasons()` is called only *inside* `explainCoaching()` (prompt construction + fallback). It never reaches the socket directly.
3. **The gate is error-only.** The server fires only on `blunder | mistake`, so praise, neutral commentary and quiet-move acknowledgements never occur.
4. **No single-move praise phrase.** `toneFor()` yields `'praise'`, but `Phrases` has no per-move congratulations — only `greatFinds(n)` for cross-game totals.
5. **There is no separate "comment on everything" density.** `coach_behavior` is `CHECK`-constrained (`db.ts:24`) with only `silent | on_demand | always_on_pedagogical`.
   **But this is not a blocker:** `always_on_pedagogical` already drives the auto panel (`Play.tsx:917` → `showAlwaysCoach` → `<CoachPanel autoPlay />`). The gap is only that the *server* narrows that mode to blunder/mistake. Widen the server condition and per-move commentary works with **no schema change**.
   A migration (rebuild `profiles` with a widened CHECK; precedent: `widenGamesSourceCheck()`) is needed only if you later want two distinct densities — "errors only" vs "every move".

## 6. Architecture

The instant path is **synchronous and engine-free**. This is what removes the latency risk.

```
type === 'move'  (ws/play.ts)
│
├─ session.chess.move(...)                      ← state committed
│
├─ SYNC  m = moveMotifs(fenBefore, move.san)    ← chess.js, ~1 ms
│        line = instantLine(m, lang, audience)
│        send('coach_instant', { ply, key, text })
│        client speaks it                        ← <100 ms end-to-end
│
└─ ASYNC quickClassify(depth 10)                ← unchanged
         send('move_classified', …)             ← already exists
         if cp_loss > THRESHOLD and LLM configured:
           coachExplain(...) → send('coach_chunk' / 'coach_done')   ← 3–8 s
```

**`instantLine()` — reuse the existing composition, do not invent one.** `explainCoaching()` already does exactly this at lines ~429–432:

```ts
if (m.allowsMate)        return P.allowsMate(naturalLine(m.allowsMate, fenAfter));
else if (m.hangs.length) return P.hangs(pieceList(m.hangs.slice(0, 2), lang, aud));
else                     return moveReasons(m, lang, aud).join("; ") || P.quiet;
```

Promote that block into an exported `instantLine(m, fenAfter, lang, aud)` and call it from both places.

**Rules**

- The instant send must happen **before** `runOnAnalysisEngine(...)`, outside the async IIFE.
- `moveMotifs` runs on `fenBefore` + `move.san` — both already in scope at the commit point.
- **Bypass `CoachPanel`'s debounced auto-fetch.** It re-requests on `triggerKey` change with `debounceMs = 600`, which would add 600 ms to a line that should appear in 100. `coach_instant` carries its own text over the socket — render and speak it directly, do not route it through the fetch path.
- `Play.tsx:917` also requires `coachConfigured`; the instant text path should work even when no LLM is configured (it is deterministic), so render it independently of `showAlwaysCoach`.
- Silence is already correct behaviour: `moveReasons` returns `[]` for a plain quiet move.
- Priority inside `moveReasons` is already implemented (mate → stopsMate → fork → captured → threatensMate → saves → threatens → castles → develops → check).

**Cost:** instant path = zero. LLM escalation only above threshold (~10–20% of moves, ~$0.01/game on a paid key).

## 6b. Methods survey — what the best systems do, and what we adopt

Eighteen sources, 1998–2026, converge on seven decisions. Reading order: the oldest (MIKE) got selection right; the newest (Queen, ACT-Eval) got verification right.

| Axis | Best method found | Source | Patzer today | Decision |
|---|---|---|---|---|
| **When to speak** | Importance score per candidate utterance; speak only when marginal information gain is positive | Tanaka-Ishii et al., ACL 1998 (MIKE, 39 cites) | Hard priority list, no budget | **Adopt scoring** (D1) |
| **Timing vs wording** | Separate *utterance timing identification* from *utterance generation* | Ishigaki et al., INLG 2021 | Already split (motifs vs phrases) | Keep |
| **What categories to use** | Five utterance types: confirmation, information, prediction, emotion, evaluation — with per-scene rules | Mamada et al., *Applied Sciences* 2023 | Implicit only | **Adopt taxonomy** (D2) |
| **How to realise text** | Templates for the many; LLM only for the few | Dr. Wolf, Patzer, Chess.com | Templates for errors only | **Adopt for all motifs** (D3) |
| **How to stay true** | Expert computes; language layer only translates | Kim et al., NAACL 2025; Tang et al. 2026; Take Take Take | Already the design | Keep — this is the strongest convergence in the literature |
| **How to verify** | Decompose into **atomic claims**, verify each with a tool. Reference-based and LLM-as-judge *cannot* detect these errors | Hebbar et al., ACT-Eval 2026 | Regex `contradiction()` | **Adopt claim checks** (D4) |
| **How to avoid repetition** | Correctness constraint + variety sampling (COVET) | ChessCoach (GPL); Sheng et al. 2025 names repetition as a core failure | Variants, no policy | **Adopt rotation** (D5) |
| **How to hide latency** | Generate *in parallel with playback*; buffer candidates. Sequential pipelines accumulate waiting time | Kawamatsu et al., IJCAI 2026 | Sequential | **Adopt pipelining** (D6) |

### The eight decisions

**D1 — Score, don't rank.** Give each candidate line an importance score (material swing, mate involvement, novelty, whether it was already said) and speak only above a threshold. A hard priority list cannot express "this is technically a fork but pointless." Keep `moveReasons`' existing ordering as the *tie-breaker*, not the gate.

**D2 — Use the five-category repertoire.** This is the cleanest available schema, and every category already has a home in the system:

| Category | Coach function | Patzer primitive |
|---|---|---|
| **Evaluation** | "That loses a piece." | `allowsMate`, `hangs` |
| **Information** | "He can fork you from there." | `fork`, `threatens` |
| **Prediction** *(anticipation)* | "He'll probably take." | not present — new |
| **Emotion** *(praise)* | "Nice — that was free." | `toneFor('praise')`, missing phrase |
| **Confirmation** *(are you sure?)* | "Stop — that hangs your queen." | `preview_result` |

Rule: never emit the same category twice in a row. That single constraint does most of the work of a silence policy.

**D3 — Templates for every motif, LLM only above threshold.** Unanimous across Dr. Wolf, Patzer, Chess.com, Sheng et al. and Take Take Take. Corroborated negatively: a neural commentator trained on **44 million** self-play games was judged by its own author as *"not very insightful and often wrong."*

**D4 — Verify at the claim level.** For the LLM escalation path only. Decompose the generated sentence into atomic claims — *"piece X is on square Y", "Y is attacked by Z", "material is +N"* — and check each against `chess.js`. ACT-Eval's finding is the important part: **reference-based and LLM-as-judge scoring cannot reliably catch these errors**, so a second model is not a valid check. `contradiction()` stays as a cheap first pass; claim checks are the backstop.

**D5 — Rotate variants, per session.** Correctness plus variety. Never reuse a variant within 6 plies; cap any template at once per game. This is the documented failure mode of every template system, including the commercial one.

**D6 — Pipeline, don't sequence.** Generate line N+1 while line N is being spoken; buffer 2–3 candidates. Kawamatsu et al. identify the real latency bug as *accumulated waiting time* from strict sequentiality, not per-call latency. Applies to the TTS queue in Phase 2.

**D7 — Explain by comparing children, not by describing the position.** Queen's distillation loop works by explaining the positions after the top candidate moves, then consolidating into an explanation of *why this one beats those*. Adopt it in the prompt: pass the top 2–3 candidate moves with their resulting evals and ask for the comparison. This is a strictly better prompt than "explain this move," and it is the one method here worth copying wholesale.

**D8 — Mine phrasing from teaching material, don't invent it.** ASSESS (LREC 2024) extracts evaluative move-language from chess textbooks. Use the same idea for the praise bank: source phrasing from real instructional writing rather than generating it, so it sounds like a teacher.

### What we deliberately do *not* do

| Method | Why not |
|---|---|
| Train a commentary model | ChessCoach: 44M games → "often wrong". Queen: 4B params, GM-strength encoder, frontier teacher, **7 distillation iterations**, 400k positions. Not a weekend, and not needed. |
| Fine-tune a small local model | `chess-gemma-270m` exists and is thin; a 270M model will produce flatter prose than a hand-written line |
| LLM-as-judge verification | ACT-Eval shows it cannot detect these errors |
| Trust LLM self-explanation | Parfenova (2026): explanations make moves recoverable, but the advantage **collapses once explicit move hints are removed** — i.e. partly post-hoc rationalisation |

## 6c. Voice pipeline — Kokoro `af_heart`, pre-rendered

Kokoro-82M: Apache-2.0 weights, 24 kHz mono, voicepack `af_heart.bin` (522 kB), MOS ≈ 4.45 — the quality leader in an independent CPU benchmark. Audio may be pre-rendered and redistributed freely.

### Where synthesis runs

| Environment | RTF | Verdict |
|---|---|---|
| Browser WASM, 1 thread *(what an extension gets)* | **2.00** — half real time | ❌ never |
| Browser WASM, 4 threads *(needs `COOP`/`COEP`)* | 0.998 | ❌ not available in an extension |
| Browser WebGPU fp32 | 0.105 | ⚠️ 2.3 s cold load, 92–326 MB weights |
| **Node on CPU (fp32)** | **0.206** | ✅ **here** |

Multi-threaded WASM needs `SharedArrayBuffer`, which needs cross-origin isolation an extension cannot request on an arbitrary page. At RTF 2.0 the renderer "falls behind and can only recover during silences."

**Decision: pre-render offline; when dynamic synthesis is unavoidable, run it in Patzer's existing Node server — never in the client.**

### The three tiers (revised)

| Tier | Content | Method | Clips | Size |
|---|---|---|---|---|
| **A** | Fixed templates + praise | Pre-rendered **whole sentences** | ~60 × 3 prosodic variants ≈ 180 | ~1.1 MB |
| **B1** | Single-slot ("your queen on d8 is undefended") | Pre-rendered **whole sentences**, one per piece-square | ~1,500 | ~6.5 MB |
| **B2** | Multi-slot ("he can fork your king and rook") | Pre-rendered **pieces only, no squares** | ~110 | ~0.5 MB |
| **C** | LLM escalation | Text only at first; server-side Kokoro if wanted | — | — |

**Total for a fully offline instant layer: ~1,800 clips, ~8 MB.** Not a sound library — a vocabulary. (dmitlichess: 187 MB for 8,794 broadcast clips.)

### Three decisions forced by the evidence

**1. Multi-slot phrases name pieces, not squares.**
Naive enumeration of `fork(ps)` is 384² = **147,456** clips. Naming only the pieces gives 6² = **36**. It is also better for a 7-year-old — "he can fork your king and rook" is trackable; "king on e8 and rook on a8" is not. Square names stay in single-slot phrases, where they add information and cost only 384 each.

**2. Joins only at clause boundaries, with silence.**
Concatenative synthesis has one famous unsolved defect: **audible discontinuity at the join** (Hunt & Black, ICASSP 1996, 546 cites — the founding unit-selection paper). Bjørkan (2010): "a major problem… is the large variability in quality due to audible discontinuities… units from different speech contexts do not fit together acoustically." Bellegarda (2004, 2006) showed no objective discontinuity metric correlates well with *perceived* discontinuity.

So mid-clause splicing cannot be made good. Rule: **only concatenate where a 150–250 ms pause is natural**, and insert that silence explicitly.

**3. Speech rate 0.95–1.0 — never faster.**
Haake et al. (2013), 102 children on TROG'2: **fast speech rate degraded comprehension**; normal and slow did not differ. Mullally (1972) found comprehension declines monotonically as speech is compressed. So bake in ≤1.0; do not over-slow, because there is no evidence of benefit and it reads as patronising.

### Two constraints on utterance design

- **Cap at ~12 words.** Eight-year-olds recall naturally-produced speech better than synthetic **even when intelligibility is equated** (Greene, 1987) — synthetic speech spends the child's working memory on decoding. Dylman et al. (2025) likewise found natural voice beat TTS for comprehension. Short lines are the mitigation.
- **Vary the prosody, deliberately.** Positive emotional tone measurably improved comprehension accuracy in 11–13-year-olds (Dylman et al., 2025, *Educational Psychology*) — warmth is a comprehension aid, not decoration. And synthetic speech "lacks human-like variability… especially critical in interactions with children" (Hanulíková et al., 2025). Therefore: **render 2–3 prosodic treatments per Tier-A template** (speed ±5%, pitch ±1 semitone) and rotate them. Monotony is a measurable cost, not a taste issue.

### Technical specification

| Concern | Decision | Why |
|---|---|---|
| **Codec** | **Ogg/Opus**, 24 kHz mono, 24–32 kbps | Opus carries a `pre-skip` field so decoding is sample-accurate (RFC 7845). MP3 has no standard — players kludge by scanning for silence, leaving ~576 samples of padding per clip: an audible click at every join |
| **AudioContext** | `new AudioContext({ sampleRate: 24000 })` | buffers at a different rate get **resampled, which introduces gaps** (WebAudio issue #1091; SO) |
| **Player** | `decodeAudioData` → `AudioBufferSourceNode` | MDN: buffers for "shorter, more sample-like tracks". `HTMLAudioElement` is asynchronous and "purely unreliable" for precise timing |
| **Scheduling** | `source.start(ctx.currentTime + t)` at computed end times; **~100 ms lookahead, 25 ms tick** | AudioContext runs on its own thread; `setTimeout` drifts with layout/GC (web.dev, "A tale of two clocks") |
| **Never** | chain clips via `onended` | event jitter accumulates; compute durations from `buffer.duration` and schedule ahead |
| **Unlock** | prime on first user gesture | autoplay policy blocks otherwise (MDN, "Audio for Web games") |
| **Cache key** | `sha256(text \| voice \| speed \| pitch)` | content-addressed; identical for build-time and runtime |

### Build script (the real work, ~half a day + QC)

```
scan PHRASES → enumerate slots → render each with af_heart@24kHz fp32 on CPU
→ QC gate on every clip  ← see below
→ encode Ogg/Opus → name by sha256(text|voice|speed|pitch)
→ write manifest.json (key → file, duration) + build.json (provenance)
→ verify: every phrase string has a clip, no orphans, no duplicates
```

**Bake in speed and pitch now.** Pre-rendered audio freezes them; changing either later means re-rendering everything. Keep the generator, manifest and provenance file as first-class artifacts, checked in.

**Do not claim bit-exact reproducibility.** Kokoro output is deterministic *given the same runtime*, but varies across runtimes and precisions — a burn-onnx port of the same graph reaches only Pearson r = 0.69 against ONNX Runtime, and fp16 vs fp32 can change the *token* sequence outright, making comparison meaningless. Record provenance (`build.json`: model file + hash, `af_heart.bin` hash, ONNX Runtime version, dtype, codec settings, speed, pitch) so a rebuild is *verifiable*, and drop the reproducibility claim.

**Render fp32 on CPU, never int8, never WebGPU.** Two documented corruption classes, both deterministic and content-triggered:

- **sherpa-onnx #3754** — Kokoro int8 on Android/ARM intermittently returns a whole sentence as rail-pinned samples (~+1.0, a loud pop then DC silence). "Not input-deterministic — engine-state-dependent… depending on what was synthesized before it." fp32 and x86_64 unaffected.
- **onnxruntime #29807** — WebGPU on Intel Iris Xe deterministically degrades specific inputs: fp32 corrupts ~⅓ of sentences ("congested" timbre), fp16 corrupts **10/10**. WASM and Adreno unaffected.

Convenient convergence: fp32 was also the *faster* path on Node (RTF 0.206 vs 0.499 for q8), so the safe choice is the quick one.

**The QC gate is mandatory, not optional.** Because corruption is deterministic and input-specific, spot-listening will miss it. Check every clip:

| Check | Catches |
|---|---|
| Rail/peak detection — fraction of samples at \|x\| ≥ 0.99 | the sherpa-onnx pinned-garbage class |
| Silence ratio + duration sanity vs `len(text)/expected rate` | truncated or swallowed sentences |
| **ASR round-trip** (whisper-tiny) vs source phrase; fail on low similarity | timbre-level corruption that stays *intelligible* to a human but is degraded |
| Zero-length / NaN / DC offset | the obvious failures |

This is the `verify:lessons` pattern applied to audio, and it belongs in CI so a re-render can never quietly ship a broken clip.

### What we deliberately do not do

| Rejected | Why |
|---|---|
| Kokoro in the browser | RTF 2.0 single-threaded; falls behind speech |
| MP3 clips | No gapless metadata; clicks at every join |
| Mid-clause splicing | Perceived discontinuity is unsolved (Bellegarda) |
| Ship 92–326 MB of ONNX to the client | Server already has it; 2.3 s cold load |
| One flat voice for every line | Synthetic monotony is a measurable cost for children |

## 7. Implementation phases

Total estimated: **~1.75 days** (v1 said 3–4; verification removed the authoring and the migration; the voice pipeline added back 2 h).

### Phase 0 — Boot and measure (1 h)

Two of the four original unknowns are **already closed** by code reading during v2/v5 verification:

- ✅ No `coach_behavior` migration is needed — `always_on_pedagogical` already opens the auto panel. Drop item 5 from v1.
- ✅ `CoachPanel.autoPlay` follows `coach_behavior === 'always_on_pedagogical'` (`Play.tsx:917`), and `coachConfigured` is a separate gate.

What remains, and can only be measured on the machine that will run it:

1. **Boot.** `npm run setup && npm run dev`, record CPU model, confirm Stockfish fetches and a bot game starts.
2. **Measure `quickClassify`.** Ten moves; record median and worst. Budget: **median < 300 ms, worst < 800 ms.**
3. **Measure `moveMotifs` + `moveReasons`.** Expect **~1 ms**. This is the number that validates the architecture — the instant line must never touch the engine.

**Why (2) matters.** Every move already runs two Stockfish evaluations at depth 10 (before and after) through one serialised queue. If that overruns the bot's reply time, the queue backs up and the coach drifts behind the game. The instant line is immune either way — but the LLM escalation attaches to the classified result, so its delay compounds.

**How to measure.** Play a bot game with devtools open on the WebSocket frames; compare the arrival time of `move_classified` against the moment the move was sent. Alternatively wrap `quickClassify` in a server-side timer. Ten moves is enough.

**Outcome.** Three numbers recorded in §14. If they land inside budget, Phase 1 needs no design change. If `quickClassify` overruns, the options in order are: lower the depth, cache eval-by-FEN, or decouple escalation from classification entirely.

### Phase 1 — Instant line (4 h)

- Export `instantLine(m, fenAfter, lang, aud)` from `coach/coaching.ts`, refactoring the existing block in `explainCoaching`.
- In `ws/play.ts`, immediately after `session.chess.move(...)`:
  ```ts
  const m = moveMotifs(fenBefore, move.san);
  if (m) send(ws, 'coach_instant', { ply: userPly, key: motifKey(m), text: instantLine(m, fenAfterUserMove, lang, aud) });
  ```
- Handle `coach_instant` in `web/src/pages/Play.tsx` (next to the `move_classified` case at :550).
- Render in `CoachPanel`.

### Phase 2 — Voice (4 h, was 2)

Existing `web/src/lib/tts.ts` uses the **Web Speech API** (system voices). §6c specifies **pre-rendered Kokoro `af_heart`**. Keep both:

- Add a `clipPlayer` alongside `speak()`: fetch clip → `decodeAudioData` → `AudioBufferSourceNode`, on a **24 kHz AudioContext**.
- Preload the Tier-A manifest at game start; lazy-load Tier-B on first use.
- Schedule with ~100 ms lookahead on the AudioContext clock. **Do not chain via `onended`.**
- Fall back to Web Speech when a clip is missing (manifest miss) so the coach never goes silent.
- Respect `tts_enabled`, `mutedRef`, `cancelSpeak()`; cancel in-flight audio on a newer event; never talk over the bot's reply.
- **Pipeline (D6):** while line N is speaking, line N+1 is already decoded and buffered — Kawamatsu et al. identify accumulated sequential waiting as the real latency bug.
- Arm audio on first user gesture (autoplay policy).
- Accept an optional **synthesise-on-miss** path: request the line from the server (Node Kokoro, RTF ≈ 0.2), cache by hash.

### Phase 3 — Praise + density (2 h)

- Extend `Phrases` with single-move praise, e.g. `praise: { best, great, capture }`. Ship **en first**; other languages fall back to `en` via `phrases(lang)`.
- **Reuse `always_on_pedagogical`** — it already enables `CoachPanel autoPlay`. Widen the *server* condition in `ws/play.ts` from `(blunder || mistake)` to "any move where `instantLine` yields text".
- Optional, only if two densities are wanted: add `'every_move'` to `CoachBehavior` and migrate `profiles` with the `widenGamesSourceCheck()` pattern. **Not required for v1.**

### Phase 4 — LLM escalation (2 h)

- Reuse `coachExplain` from `coach/explain.ts`.
- Fire when `cp_loss > THRESHOLD` (start 150 cp), independent of classification.
- Append to the instant line; never replace it.
- **Explain by comparison (D7):** pass the top 2–3 candidate moves with their resulting evals, and ask *why the played move is worse than the best one* — not "explain this move." This is Queen's distillation pattern and it produces materially better explanations.
- **Claim-check the output (D4):** decompose the returned sentence into atomic claims and verify each against `chess.js`; suppress the line if any claim fails. `contradiction()` remains the cheap first pass.

### Phase 5 — "Are you sure?" (2 h)

- Hook `preview_result`: if a previewed move classifies as a blunder, return a prompt instead of a classification.
- Client shows confirm/cancel. Advise, never block.

### Phase 6 — Upstream (ongoing)

See §11.

## 8. Authoring work (much smaller than v1 assumed)

v1 planned 100–300 new templates. **Not needed.** `PHRASES` already covers reasons, hangs, allowsMate, opponentReply, quiet, hint, takeaway and kind — in 4–5 languages.

What must actually be authored:

| Item | Count | Notes |
|---|---|---|
| Single-move praise lines | ~12 (en) | e.g. "Nice — that was free.", "Best move. Well spotted." |
| Variant rotation | ~3 per praise key | Avoid the same line twice within 6 plies |
| Optional: more `reasons` variants | ~10 | Existing lines repeat; breadth is the known weakness |

**Anti-repetition (D5):** rotate variants per session; never reuse a variant within 6 plies; use any single template at most once per game. This is the documented failure mode of every template system — including Dr. Wolf, whose App Store reviews cite "repetitive phrasing." ChessCoach's answer was COVET (correctness-constrained variety sampling); ours is constraint plus rotation.

**Source phrasing, don't invent it (D8):** where possible take praise and explanation wording from real instructional writing — the method ASSESS (LREC 2024) applies at scale by mining evaluative move-language from chess textbooks.

## 9. Silence policy

Mostly free, because `moveReasons` already returns `[]` for quiet moves.

**Suppress when:**

- `moveReasons` is empty and no negative motif fired (already the default).
- Opening book (first ~8 plies).
- Forced recapture with one legal reply.
- The previous ply already spoke.
- The child has taken 3 hints in 5 moves (help-abuse guard).

**Target speech rate: 40–70% of moves.**

*Rationale:* feedback on 30–67% of trials beat 100% for retention (Reid & Swafford, 2020; Hula et al., 2008). Deliberate withholding is the mechanism (Miwa et al., 2014).

## 10. Test plan

**Unit**
- `instantLine` over ≥13 synthetic FEN/SAN pairs — one per motif key.
- Priority: a position with two motifs picks the higher-priority one.
- `moveReasons` returns `[]` for a plain quiet move (regression guard for silence).
- Variant rotation never repeats within 6 plies.

**Integration**
- Scripted 10-move game over the websocket: assert `coach_instant` arrives **before** `move_classified` (proves the engine is off the critical path).
- Assert no `coach_instant` for book plies.

**Regression**
- `server/test/coach-*.test.ts` stays green.
- No new LLM call when `llmConfigured()` is false.

**Hallucination guard**
- Fail any test where rendered text names a square or piece absent from `MoveMotifs`.
- **Atomic-claim test (D4):** decompose a sample of LLM-escalated lines into claims (*piece on square*, *attacked by*, *material count*) and assert each verifies against `chess.js`. Any line with an unverifiable claim must be suppressed, not shown.

**Category discipline (D2)**
- Assert no two consecutive utterances share a category (evaluation / information / prediction / emotion / confirmation).

**Variety (D5)**
- Assert no template repeats within 6 plies, and none repeats within a game.

**Latency budgets**
- `move commit → coach_instant`: **< 100 ms**
- `speak()` start on iPad Safari: **< 300 ms**

## 11. Contribution, distribution and licensing

Verified against Patzer's `CONTRIBUTING.md` and researched against prior art.

### 11.1 Not a plugin, not a fork — a pack plus upstream PRs

**No plugin system exists.** Zero files match plugin/extension/hook/addon; the only extension point is the `sound_set` / `move_sound_set` profile columns selecting bundled WAVs. Building a plugin API would be larger than the feature, and CONTRIBUTING pushes back on new structure without prior discussion.

**A fork is wasteful.** 296 files, 4.7 MB, a maintainer pushing daily, six CI suites and a Docker boot test. Nixpkgs' own guidance is explicit: an overlay "is easier to maintain than a fork and, unlike a fork, it can be combined with others."

**The split:**

| Artefact | Contents | Where |
|---|---|---|
| **A. Engine PRs** | `instantLine()`, `coach_instant`, clip player, density setting, praise phrases | Upstream, ~400 lines |
| **B. Voice pack** | `phrases/*.json`, Kokoro build script, clips, `manifest.json` | Own repo, ~8 MB |
| **C. Fallback** | Patch series + Dockerfile, only if A is declined | Own repo |

**B is the durable artefact** — the code is 400 lines a maintainer could write; the pack is 1,800 clips and a child-register phrase bank that only you will. It is also what others can contribute to independently (a German pack, a British voice, an older-child register).

### 11.2 Model the pack on Piper, publish on HuggingFace

The established prior art is **`rhasspy/piper-voices`**: 35 languages, one archive per voice named `voice-<lang>-<speaker>-<quality>.tar.gz`, two files per voice, plus a machine-readable `voices.json` catalogue and a human-readable `VOICES.md`. Voices are organised "by language, country code, speaker/dataset name, and quality level."

It works at scale — the single most-downloaded Piper voice has **284,159 downloads**; most others sit between 12k and 50k.

**Adopt the same shape:**

```
patzer-voicepack/
├── README.md · LICENSE · packs.json      ← catalogue, like voices.json
├── packs/
│   └── en-child-af_heart/
│       ├── phrases.json                  ← the authored text (the real asset)
│       ├── manifest.json                 ← key → {file, duration, category, variants}
│       ├── build.json                    ← provenance: model+hash, ORT, codec, speed, pitch
│       └── clips/<sha256>.opus
├── build/render.py · build/verify.py
└── docs/CHILD_REGISTER.md                ← why the wording is what it is
```

Publish to **HuggingFace**, not just GitHub — that is where TTS voice packs are discovered and where Piper's audience already looks.

### 11.3 PR discipline, with evidence

| Practice | Evidence |
|---|---|
| **Open an issue first** | Rahman (2026), *Why Do Pull Requests Go Silent?* — PRs are lost to silence, not rejection; contribution type and discussion-level barriers predict abandonment |
| **One concern per PR, single file where possible** | Rahman, Codabux & Roy (2026) — 330,343 multi-file PRs; file ordering and change-set size affect review effectiveness |
| **Optimise for reviewer comprehension, not just correctness** | Hijazi et al. (IEEE TSE 2022) — review quality tracks reviewer cognitive load; Fregnan et al. (2022) — reviewers struggle to understand change-sets |
| **Follow the project's idiom** | Beller et al. (MSR 2014, 257 cites) — most review fixes are *evolvability* problems, so fit matters more than raw correctness |
| **Write it like a human contributor** | Duma et al. (2026) — AI-generated PRs receive **no review far more often** than human ones; human involvement arrives as agent-steering rather than review |

That last row matters here specifically. A large, uniform, generated-looking diff is the most likely way to have this ignored. Each PR should carry: what it does, what you tested, the failing-test output for regressions, and a link to the discussion.

**Sequence** (each with tests — CI runs typecheck, unit, build, e2e, resume, OIDC, UI, Docker boot):

1. Issue: "Live per-move commentary from the existing `moveMotifs`/`moveReasons`" — note both functions already exist and only the wiring is missing.
2. PR 1 — export `instantLine`, refactor `explainCoaching` to use it *(pure refactor, no behaviour change — easiest possible first PR)*
3. PR 2 — `coach_instant` event + client render
4. PR 3 — clip player (§6c) with Web Speech fallback
5. PR 4 — praise phrases + `verify:voice` script (mirrors `verify:lessons`)
6. PR 5 — density setting + CHECK migration
7. PR 6 — preview-based "are you sure?"

**Bundle the clips; do not add a config path.** CONTRIBUTING's invariant is hard: *"No user-facing config in env vars. Anything a user might want to change at runtime lives in the SQLite DB."* So a `VOICE_PACK_PATH` env var is out. Ship the clips as static assets and select with a profile column, exactly like `sound_set`. Directory-scanning plus an Admin upload is a later, separate PR.

**Do not bundle Kokoro.** CONTRIBUTING rejects "pulling in heavy dependencies for tiny features." Pre-rendered clips are static assets, not a dependency — which is another reason §6c's pre-render decision is the only one that would merge.

### 11.4 Fallback: a patch series, not a fork

Debian's guidance is the model: small or temporary divergence → **a patch series** (`debian/patches/*.patch`, DEP-3 format, `series` file); large and permanent → fork, and *"before forking the project, reach out to the maintainer."* Debian also names the pattern worth copying: a **"downstream fork"** — downstream of Patzer, upstream of anyone consuming your build — *"which makes it easier to merge your project back upstream if the situation improves."*

For git specifically, four strategies exist for carrying downstream patches (merge / squash-merge / rebase+force-push / **history-preserving rebase**). The last — `git merge -s ours` then `git rebase --onto` — keeps the patch stack at the tip of history **without force-pushing**, so consumers of your build never have to re-clone.

**So the fallback repo is `patches/*.patch` + a `Dockerfile` that applies them** — a few hundred KB instead of 4.7 MB, and rebasing stays cheap.

### 11.5 Licensing — the audio is not yours to license

This is the finding that changes the earlier recommendation.

**US Copyright Office, *Copyright and AI, Part 2: Copyrightability* (Jan 2025):**

> "Copyright does not extend to **purely AI-generated material**, or material where there is insufficient human control over the expressive elements."
> "Based on the functioning of current generally available technology, **prompts do not alone provide sufficient control**."
> "Human authors are entitled to copyright in their works of authorship that are perceptible in AI-generated outputs, as well as **the creative selection, coordination, or arrangement** of material in the outputs."

Precedent: the *Zarya of the Dawn* decision held the graphic novel copyrightable **as a whole** while "the individual images themselves could not be protected by copyright."

**Applied to this pack:**

| Element | Copyright status | Licence to apply |
|---|---|---|
| **Phrase text** | ✅ Human authorship — yours | **CC0** (or MIT). This is the real asset |
| **Compilation** — which clips exist, ordering, manifest | ✅ Selection/arrangement | **CC0** |
| **Build script** | ✅ Yours | **MIT** |
| **The audio clips** | ❌ **Effectively unprotectable in the US** | **Assert no rights.** Do not claim CC0 over something you don't own |

So the README should say, plainly: *"Audio generated by Kokoro-82M from the phrases in this repository. No copyright is claimed in the audio output. Kokoro-82M weights are Apache-2.0 (© hexgrad)."* Claiming to license the clips is misleading even where harmless — and the EU and UK differ (UK CDPA s.9(3) does protect computer-generated works), so a global audience should not be told they have rights you cannot grant.

**Contrast worth noting.** ElevenLabs' terms say "you retain all rights in and to your Output" — but its Sound Effects exhibit forbids making output "available as isolated audio files or samples, or as part of any sound, sample, effects, or music library." **That is precisely what a voice pack is.** So a commercial TTS vendor's contract would prohibit this distribution even though it "gives" you the output. Kokoro's Apache-2.0 weights have no such restriction, which is the actual reason this pack is distributable — not the copyright status of the audio.

### 11.6 What ships, in order

1. **Open the issue** (week 1) — cheap, and everything downstream depends on the answer.
2. **Build the pack repo** in parallel — useful whether or not the PRs land.
3. **Send PR 1 alone** and wait for a reaction — it's a pure refactor, the lowest-risk signal of whether the maintainer wants this.
4. **Send the rest in sequence**, one concern each.
5. **Patch series only if declined** — and tell the maintainer you're doing it.

### 11.7 Asset distribution — keep the repo light

Hard constraint from the user: Patzer will be installed on another machine, so the repo must not carry big files.

**The classifying question is whether the files are inputs or outputs.** git-sizer's guidance: *"Avoid storing generated files… It would be better to regenerate them when necessary."* Modern Git Academy's decision table is blunter — compiled binaries and distributable archives belong in release assets, **"never in Git history. This is the category that causes the most damage… the repository grows monotonically."**

The clips are **outputs**. So:

| Element | Kind | Lives in |
|---|---|---|
| `phrases.json` | authored **input** | **Git** (~60 KB) |
| `manifest.json` | derived, small, needed for verification | **Git** (~180 KB) |
| `build.json` | provenance | **Git** (1 KB) |
| `build/*.py` | source | **Git** (~30 KB) |
| **`clips/*.opus`** | **generated output** | **Release asset** (~8 MB) |

**Repo: ~500 KB. Audio: a release asset, versioned by tag.**

#### Why not Git LFS

LFS is for large **inputs** that must match the code (test fixtures, design sources). It also carries a nasty failure mode: over the free 10 GiB quota with no payment method, *"you can still clone repositories with large assets — you will only retrieve the pointer files."* A silent, partial clone that looks successful. And 8 MB does not need it.

#### Why not plain Git

- GitHub recommends **1 MB maximum per object** (enforced at 100 MiB, warned at 50 MiB).
- **Directory width: 3,000 entries recommended.** `clips/` with 1,800 files sits at two-thirds of that on the first pack — and each new language or voice multiplies it.
- git-sizer: *"Avoid storing file archives in Git, especially if compressed. Different versions don't delta well."* So a tarball of clips is not an escape either.

#### Where the release asset goes — and the CORS trap

Verified against live GitHub behaviour (July 2026 onward): release downloads 302 to `release-assets.githubusercontent.com`, and **that host sends no `Access-Control-Allow-Origin` header at all**, even with an `Origin` on the request. Independently confirmed in four separate projects.

| Host | CORS | Verdict |
|---|---|---|
| Release assets (`github.com/…/releases/download/…`) | ❌ none | ✅ **primary** — `curl`/`gh` install step |
| `raw.githubusercontent.com` | ✅ allows | small files only |
| `api.github.com` | ✅ `*` | metadata, not blobs |
| **GitHub Pages** | ✅ `*` on every file | ✅ if a browser must fetch directly |
| **HuggingFace** | ✅ | ✅ mirror, and where TTS packs are discovered |

This is fine for us: **Patzer's own server serves the clips once they are on disk**, so the download is a one-time CLI step, not a browser fetch. If the Admin UI ever grows a "download pack" button, it must fetch from Pages or HuggingFace, **not** from a release asset.

#### What this buys

- Clone is instant on the second machine — half a megabyte.
- The text layer is fully verifiable **without any audio**: CI checks phrases ↔ manifest consistency on every push, and only builds audio on a tag.
- The copyrightable asset (the phrases) is what is versioned; the unprotectable, regenerable artefact is not.

## 12. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| `quickClassify` backing up the serialized engine queue | Late classification | Instant path no longer depends on it |
| SQLite `CHECK` blocks new density value | Migration needed | `widenGamesSourceCheck()` precedent |
| TTS overlaps the bot's move | Feels broken | Cancel-on-new-event; hold during bot reply |
| iOS Safari blocks audio | Silent on iPad | Arm on first gesture |
| Repetition → child tunes out | Engagement loss | Variant rotation + authored breadth |
| **Manifest drift** — phrase edited, clip not re-rendered | Coach goes partly silent | CI check: every phrase string has a clip; Web Speech fallback on miss |
| **AudioContext sample-rate mismatch** | Audible gaps between clips | Pin the context to 24 kHz to match Kokoro output |
| Kokoro unavailable on the target server | No dynamic Tier C | Tier A/B are pre-rendered and unaffected; Tier C is text-only by default |
| Over-talking → help dependence | Worse learning | §9 policy + density setting |
| Upstream declines | Fork upkeep | Code is small; fork is cheap |

**Removed since v1:** "depth-10 classify too slow" is no longer a risk for the instant line, which is engine-free.

## 13. Definition of done

- Every user move yields a spoken line or a deliberate silence within 100 ms.
- Speech occurs on 40–70% of moves in a full game.
- No spoken line names a piece or square absent from computed facts.
- Praise fires on good moves and free captures.
- Deeper explanation appends within ~8 s above threshold.
- All existing tests pass; new tests cover every motif key.
- Feels, to the child, like Dr. Wolf.

## 14. Open questions (remaining)

1. ✅ *Resolved* — `quickClassify` does **not** compute motifs; call `moveMotifs` separately (synchronous, cheap).
2. ✅ *Resolved* — `coach_behavior` is `CHECK`-constrained (`db.ts:24`), **but** `always_on_pedagogical` already enables the auto panel (`Play.tsx:917`). Reuse it; no migration needed for v1.
3. Which LLM for escalation — local Ollama on the existing box, or cheap hosted?
4. Should the instant line fire for the **bot's** moves too? (Dr. Wolf does both; likely yes, lower density.)
5. Actual `quickClassify` latency on target hardware — measure in Phase 0. *This is the only remaining unknown that code reading cannot settle.*
6. Are the non-English `PHRASES` complete enough, or do praise lines ship en-only at first?

## 15. Verification log (v1 → v2)

| Claim in v1 | Verified outcome | Evidence |
|---|---|---|
| "Template bank must be authored (100–300 lines)" | ❌ **Wrong** — bank exists | `coaching.ts` `PHRASES`, `moveReasons()` |
| "Sentence generation must be built" | ❌ **Wrong** — exists | `moveReasons(m, lang, aud)` |
| "TTS not wired to push stream" | ⚠️ **Partly wrong** — `playTts()` auto-speaks | `CoachPanel.tsx` ~line 118–137 |
| "`quickClassify` may already compute motifs" | ❌ It does not | verified return type |
| "Enum may need migration" | ⚠️ **Partly wrong** — constrained, but `always_on_pedagogical` already enables the auto panel; migration optional | `db.ts:24`, `Play.tsx:917` |
| "Silence policy must be implemented" | ⚠️ Mostly free — `moveReasons` returns `[]` | `coaching.ts:333–347` |
| "3–4 days" | Revised to ~1.5 days | §7 |
| "Client can take the text as-is" | ⚠️ One trap found — `CoachPanel` debounces 600 ms; bypass it | `CoachPanel.tsx:43,147` |

---

## Appendix A — Pedagogy rationale

| Finding | Consequence |
|---|---|
| Immediate/frequent feedback raises practice performance but lowers retention (Hula et al., 2008, 93 cites) | Signal instantly, explain later |
| Knowledge-of-results on 30–67% of trials beat 100% (Reid & Swafford, 2020) | §9; 40–70% speech rate |
| Delayed feedback → worse acquisition, better retention (Anderson, 1994) | Late LLM explanation is a feature |
| LLM latency 5–30 s on free/cheap models | Templates carry the per-move load |
| 72% of unscaffolded help-seeking is unproductive (Aleven et al., 2006, 408 cites) | Rate-limit hints |
| Feedback *about* help-seeking changes behaviour (Aleven et al., 2016, 257 cites) | Future meta-nudge layer |
| Withholding hints improves learning (Miwa et al., 2014) | Silence is pedagogy |
| Learned commentary from 44M self-play games was "often wrong" (ChessCoach, 536★) | Never train a commentary model |

## Appendix B — Why not an LLM per move

| | Per-move LLM |
|---|---|
| Free tier (50 req/day) | One game exhausts the day |
| Latency | 5–30 s — unusable |
| Cost on paid key | ~$0.01/game — fine |
| Failure mode | Confidently wrong to a child who cannot detect it |

Cost is solvable; **latency is not**.

## Appendix C — Evidence base

- Patzer: `SikamikanikoBG/patzer` (MIT), audited at `2026-10-24`; files cited above
- Dr. Wolf: `learnchesswithdrwolf.com`, App Store id1353041020; ChessPivot audit (0 on repertoire/endgames/puzzles/positional)
- dmitlichess: `vincentsimard/dmitlichess` (WTFPL); 8,794 clips, 8% with descriptors, keyed by move-notation only
- Lichess fair-play grid; `ui/learn/src/stage/list.ts` (18 stages)
- ChessCoach: `chrisbutner/ChessCoach` (GPL-3.0)
- Lichess accuracy: `lichess.org/page/accuracy`; `lila` `Advice.scala` (AGPL — implement from the docs page)
- OpenRouter free tier: 20 req/min, 50/day (<10 credits lifetime)

### Methods literature (§6b)

| Source | Contribution |
|---|---|
| Tanaka-Ishii, Hasida & Noda, ACL/COLING 1998 — MIKE | Importance scores; maximise information gain under a budget |
| Ishigaki et al., INLG 2021 | Split utterance timing from utterance generation |
| Zang, Yu & Wan, ACL 2019 | Neural chess engine coupled to generation, 5 commentary categories |
| Kim et al., NAACL 2025 | Concept-guided commentary — expert concepts steer the LLM |
| Tang et al., arXiv 2026 | Distilling expert *reasoning* (not just outputs) into faithful explanations |
| Bhaskar, Cheng & Chen, arXiv 2026 — Queen | Explain-by-children + Bellman-style language distillation; 4B params, 2697 Elo |
| Hebbar et al., arXiv 2026 — ACT-Eval | Atomic-claim, tool-augmented verification; LLM-as-judge fails |
| Parfenova, arXiv 2026 | LLM chess explanations are partly post-hoc rationalisation |
| Kawamatsu et al., IJCAI 2026 | Accumulated waiting time; generate in parallel with playback |
| Sheng et al., *Mathematics* 2025 | Templates + LLM → repetitive phrasing and delayed responses |
| Cook & Karakuş, *KBS* 2024 | Fine-tuned LLM commentary (football events) on consumer hardware |
| Mamada et al., *Applied Sciences* 2023 | Five utterance categories + per-scene rules |
| Marrese-Taylor et al., EMNLP 2022 | Open-domain video commentary generation |
| Yao et al., INLG 2017 | Streaming content selection from live commentary |
| Alrdahi & Batista-Navarro, LREC 2024 — ASSESS | Mining evaluative move-language from chess textbooks |
| Nanduri, 2025 (NCI thesis) | Real-time browser-extension move explanation |
| Nye, Graesser & Hu, 2014 (+286 cites) | Dialogue-based tutoring design |
| Chris Butner, ChessCoach (GPL) | COVET sampling; 44M-game commenter judged "often wrong" |

### Voice literature (§6c)

| Source | Contribution |
|---|---|
| Haake, Hansson, Gulz, Schötz & Sahlén, *IJSLP* 2013 | 102 children, TROG'2: **fast speech degraded comprehension**; slow ≈ normal |
| Mullally, 1972 (ERIC) | Listening comprehension declines monotonically as speech is compressed |
| Greene, *JASA* 1987 | 8-year-olds recall natural speech better than synthetic **even at equal intelligibility** — synthetic costs working memory |
| Dylman, Champoux-Larsson & Frances, *Educational Psychology* 2025 | **Positive emotional prosody raised comprehension accuracy**; natural voice beat TTS |
| Dylman et al., *Cogent Psychology* 2025 | Replicates the natural-vs-synthetic comprehension gap across recall conditions |
| Hanulíková, Tolksdorf & Kapp, *Front. Robotics & AI* 2025 | Synthetic speech "lacks human-like variability… especially critical in interactions with children" |
| Hunt & Black, ICASSP 1996 (546 cites) | Founding unit-selection paper; join cost = concatenation quality |
| Bjørkan, 2010 | "Major problem… audible discontinuities" when joining units from different contexts |
| Bellegarda, 2004 / *IEEE TASLP* 2006 | No objective discontinuity metric correlates with **perceived** discontinuity |
| RFC 7845 (Ogg Opus) | `pre-skip` field → sample-accurate trim; the reason Opus is gapless and MP3 is not |
| Daede, Vimeo Engineering, 2023 | MP3 priming has no standard; Opus "no issues with gaps" |
| `astoeckel/opus_gapless`, 2017 | Practical independently-encoded Ogg/Opus gapless playback via WebAudio |
| MDN — Web Audio best practices | Buffers for "shorter, more sample-like tracks"; media elements for full-length |
| web.dev — "A tale of two clocks" (C. Wilson) | AudioContext runs off-thread; `setTimeout` drifts; ~100 ms lookahead / 25 ms tick |
| WebAudio issue #1091 (rtoy) | **Sample-rate mismatch causes resampling gaps**; Ogg Opus decodes correctly in Chrome/Firefox |
| MDN — "Audio for Web games" | Autoplay requires a user gesture; prime audio on first interaction |
| `briantung.me`, Aug 2026 | Browser Kokoro RTF: WASM 1-thread **2.00**, 4-thread 0.998, WebGPU 0.105 |
| `onnx-community/Kokoro-82M-v1.0-ONNX` | Model sizes 326/163/92 MB; `af_heart.bin` 522 kB; Apache-2.0 |
| `gauravvij` CPU benchmark | Kokoro MOS 4.45 vs Supertonic-3 4.37, Inflect-Nano 3.48 |

### Contribution, distribution & licensing (§11)

| Source | Contribution |
|---|---|
| **US Copyright Office, *Copyright & AI Part 2: Copyrightability*, Jan 2025** | "Copyright does not extend to purely AI-generated material"; prompts alone insufficient; selection/arrangement *is* protectable |
| USCO, *Registration Guidance* (Mar 2023) | *Zarya of the Dawn* — compilation protected, individual AI images not |
| Gaidartzi & Stamatoudi, *Laws* 2025 (23 cites) | Most jurisdictions retain strict human authorship |
| Rahman, *Why Do Pull Requests Go Silent?* (2026) | PRs lost to silence, not rejection; contribution type predicts abandonment |
| Duma et al., *These Aren't the Reviews You're Looking For* (2026) | AI-generated PRs receive no review far more often than human ones |
| Rahman, Codabux & Roy, *Does Order Matter?* (2026) | 330,343 multi-file PRs; change-set size/ordering affects review |
| Beller et al., MSR 2014 (257 cites) | Most review fixes are *evolvability* problems — fit beats correctness |
| Hijazi et al., *IEEE TSE* 2022 | Review quality tracks reviewer cognitive load |
| Fregnan et al., *JSS* 2022 | Reviewers struggle to comprehend change-sets |
| Badampudi, Unterkalmsteiner & Britto, *ACM TOSEM* 2023 | MCR literature-vs-practice mapping |
| **`rhasspy/piper-voices`** | Prior art: per-voice `.tar.gz`, `voices.json` catalogue, 35 languages, 284k downloads on the top voice |
| NixOS Wiki, *Modifying packages* | Overlay "easier to maintain than a fork"; composable |
| NixOS/nixpkgs#27312 | Overlay keeps history clear; drop the patch once upstreamed |
| Debian Wiki, *ManageUpstreamDifferences* | quota patch series for small/temporary divergence; "reach out before forking"; the "downstream fork" pattern |
| `amboar`, history-preserving fork maintenance (2021) | `merge -s ours` + `rebase --onto` keeps a patch stack without force-push |
| Lamb & Zacchiroli, *IEEE Software* 2021 (88 cites) | Reproducible builds: verify artifacts match source |
| Fourné et al., *IEEE S&P* 2023 (29 cites) | R-Bs perceived as out of reach; adopt provenance without the bit-exact claim |
| ElevenLabs ToS / Sound Effects exhibit | "You retain all rights in your Output" — **but** forbids releasing output "as isolated audio files… or as part of any sound… library" |
| sherpa-onnx #3754 | Kokoro **int8/ARM** intermittent rail-pinned garbage; state-dependent; fp32 clean |
| onnxruntime #29807 | Kokoro **WebGPU/Iris Xe** deterministic corruption of specific inputs; fp16 10/10 |
| `tracel-ai/burn-onnx` Kokoro check | Same graph, different runtime → r = 0.69 vs ORT reference |
