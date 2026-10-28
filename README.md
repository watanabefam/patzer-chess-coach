# patzer-chess-coach

Live, per-move **voice coaching** for a child, built on [Patzer](https://github.com/SikamikanikoBG/patzer).

Two deliverables live here:

1. **Engine PRs** — the ~400 lines Patzer needs to speak a line after every move.
   Written up in [`PLAN.md`](PLAN.md), contributed upstream rather than forked.
2. **Voice packs** — the authored phrase banks and the Kokoro build pipeline that
   turn them into audio.

`PLAN.md` is the design document. Read it first; it records the research, the
rejected alternatives, and the reasoning behind every decision.

## Why this repo is deliberately small

The repo is **text and scripts only — roughly 500 KB.** The generated audio
(~8 MB) is *never* committed.

The reasoning is in `PLAN.md` §11.7, in short:

- Clips are **build outputs**, not inputs. Version control is for inputs.
- 1,800 clips would blow past GitHub's 3,000-entry directory guidance and each
  binary blob is stored forever in history.
- Audio is unprotectable (§11.5), so the *phrases* are the real asset — and they
  are a few hundred kilobytes of JSON.

The audio ships as a **GitHub Release asset**, versioned by tag, with no
bandwidth charge. Download it when you need it:

```bash
./scripts/fetch-pack.sh en-child
```

## Layout

```
PLAN.md                    the design and the reasoning
AGENTS.md                  hard rules and traps for AI agents (read before editing)
packs/en-child/
  phrases.json             authored text — the actual asset (CC0)
  manifest.json            phrase key → clip file, duration, category, variants
  build.json               provenance: model hash, ONNX Runtime version, codec, speed
build/
  render.py                Kokoro af_heart → Ogg/Opus, with the QC gate
  qc.py                    rail/peak, silence, ASR round-trip
  verify.py                every phrase has a clip; no orphans
scripts/fetch-pack.sh      download + unpack a released pack
docs/CHILD_REGISTER.md     how the wording is written, and why
```

## Building a pack

```bash
pip install kokoro soundfile onnxruntime
python build/render.py --pack en-child --voice af_heart --speed 0.95
python build/qc.py     --pack en-child      # fails on any corrupt clip
python build/verify.py --pack en-child      # fails on any missing phrase
```

Rendering is **fp32 on CPU**, never int8, never WebGPU — both documented
corruption paths are in `PLAN.md` §6c. The QC gate is mandatory because that
corruption is deterministic per input, so listening to a few clips will miss it.

## Licensing

| What | Licence | File |
|---|---|---|
| Build and verify scripts | **MIT** | `LICENSE` |
| Phrase text and manifests | **CC0** | `LICENSE-CONTENT` |
| Generated audio | **No rights asserted** | see `PLAN.md` §11.5 |

Per the US Copyright Office, purely AI-generated material is not copyrightable,
so no claim is made over the clips. Kokoro-82M weights are Apache-2.0 (© hexgrad).

## Status

Pre-implementation. Phase 0 (verification) is next — see `PLAN.md` §7.
