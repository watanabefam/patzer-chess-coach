# Packs

Each pack is three small JSON files. The audio that belongs with them is
generated, versioned separately, and **never committed** — see `PLAN.md` §11.7.

```
packs/en-child/
├── phrases.json     authored text (CC0) — the actual asset
├── manifest.json    key → { clip, duration, category, variants }
└── build.json       provenance: model + hash, ORT version, codec, speed, pitch
```

## phrases.json

The authored lines. This is the thing worth protecting and the thing worth
contributing to. Write to `docs/CHILD_REGISTER.md`.

## manifest.json

The contract between text and audio. One entry per renderable line:

```json
{
  "hangs.one": {
    "clip": "3f9a1c…b7.opus",
    "duration": 1.42,
    "category": "evaluation",
    "variants": ["3f9a1c…b7.opus", "9d2e44…0a.opus"],
    "source": "hangs"
  }
}
```

`category` is one of `confirmation | information | prediction | emotion |
evaluation` — used to enforce "never two of the same in a row" (PLAN.md §6b, D2).

## build.json

Everything needed to know *how* the audio was made, so a rebuild is verifiable
even though Kokoro output is not bit-identical across runtimes:

```json
{
  "engine": "kokoro-82m",
  "engine_version": "1.0",
  "voice": "af_heart",
  "voicepack_sha256": "…",
  "onnxruntime": "1.x.y",
  "dtype": "fp32",
  "device": "cpu",
  "speed": 0.95,
  "pitch_semitones": 0,
  "sample_rate": 24000,
  "codec": "opus",
  "codec_bitrate_kbps": 24,
  "generated_at": "2026-…"
}
```

## Engine-agnostic by design

Nothing in `manifest.json` names an engine. A pack rendered with Piper instead
of Kokoro drops into the same structure and differs only in `build.json`.

That matters: Kokoro is the right choice for quality here (MOS 4.5 vs 3.3), but
Piper is 8–10× faster and is the only practical option on a Raspberry Pi or a
no-AVX CPU. A contributor with weak hardware should still be able to publish a
pack.
