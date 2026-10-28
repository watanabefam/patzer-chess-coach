# AGENTS.md

Rules for working in this repo. `README.md` is for humans; `PLAN.md` is the
design record with the research behind it. This file is the short list of things
that are easy to get wrong.

## Source of truth

- **`PLAN.md` is normative.** Section numbers cited below point at it — read the
  cited section before changing what it covers.
- **`packs/*/manifest.json` is generated** by `build/render.py`. Never hand-edit.
- **`docs/CHILD_REGISTER.md` governs all wording** in `packs/*/phrases.json`.
- **Patzer's own repo is the authority on Patzer's code**, not this one.

## Hard invariants

1. **Never commit audio.** No `.opus`, `.wav`, `.tar.gz`, no `clips/` directory.
   `.gitignore` enforces it — **do not override with `git add -f`.** The repo is
   deliberately under 1 MB so it clones instantly on a second machine. (§11.7)
2. **Never claim copyright in the clips.** They are AI-generated and — under the
   US Copyright Office's position — not protectable. `LICENSE-CONTENT` already
   states this correctly. Do not "improve" it into a licence of the audio. (§11.5)
3. **Render fp32 on CPU only.** No int8, no WebGPU. Both have documented,
   deterministic corruption paths. (§6c)
4. **The QC gate is not optional.** Any change to `render.py` must leave
   `qc.py` still failing on corrupted clips. (§6c)
5. **No TTS engine inside Patzer.** Clips are static assets. Patzer's
   CONTRIBUTING rejects heavy dependencies. (§11.3)
6. **No user-facing env config in Patzer.** Runtime settings live in SQLite and
   the Admin/Settings UI. (§11.3)
7. **Templates for the per-move layer, always.** Never put an LLM call on the
   instant path — the latency makes it unusable and the cost is unbounded. (§6, App. B)
8. **One concern per upstream PR, issue first.** (§11.3)

## Verify before claiming done

```bash
python build/verify.py --pack en-child   # every phrase has a clip; no orphans
python build/qc.py     --pack en-child   # no corrupt audio (needs clips fetched)
```

`verify.py` must pass **with no clips present** — it checks the text layer only.
If it starts requiring audio, the CI job that runs on every push breaks.

Fetch audio first if you need it:

```bash
./scripts/fetch-pack.sh en-child
```

## Changing wording

1. Change `docs/CHILD_REGISTER.md` first if a *rule* needs to change.
2. Then edit `packs/*/phrases.json`: ≤12 words, warm, name the consequence not
   the solution, silence is a valid line.
3. Re-run `build/render.py` and `build/qc.py`. The audio is regenerated, never
   committed.

## Scope

This repo exists to coach one seven-year-old in a child register, over a
pre-rendered voice, on top of Patzer. It is not a general chess-coach framework,
and it is not a Patzer fork — upstream changes go to Patzer as pull requests.
