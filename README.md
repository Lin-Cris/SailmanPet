# Luffy Coder — Native Codex Pet

This repository contains a real Codex custom-pet package. It does not contain or launch a standalone app, floating widget, preview runner, hook watcher, or parallel state system.

## Native registration

The distributable package is:

```text
pet-package/luffy-codex/
├── pet.json
└── spritesheet.webp
```

The installed native registration is:

```text
~/.codex/pets/luffy-codex/
├── pet.json
└── spritesheet.webp
```

Codex discovers custom pets from this registry for **Settings → Pet → Select Pet**. The manifest uses `spriteVersionNumber: 2`, and the atlas is the native 8-column × 11-row format (`1536×2288`, `192×208` per cell).

## Native behavior mapping

Codex owns state selection and animation playback. No external watcher or custom renderer is used.

| Native row | State | Frames | Behavior |
| --- | --- | ---: | --- |
| 0 | `idle` | 6 + neutral | Sleeping loop with subtle breathing and an attached snoring bubble that grows and shrinks |
| 7 | `running` | 6 | Active laptop typing for code generation, edits, and build work |
| 8 | `review` | 6 | Laptop analysis with one hand touching the chin for reading, reveal, inspection, and review |
| 9–10 | look directions | 16 | Clockwise pointer-following directions for the native v2 renderer |

Rows 1–6 retain the standard native drag, wave, jump, failure, and waiting animations.

Appearance and Pet Size are not reimplemented here. They remain native Codex renderer settings and therefore apply to this pet through the same atlas rendering path as built-in pets.

## Source art

- `coding.png`
- `review.png`
- `spritesheet.webp`

These files are retained as the supplied identity and pose sources. The package itself consumes only `pet.json` and the final native `spritesheet.webp`.

## Validation

Retained evidence is under `native-pet-run/`:

- `final/validation-native.json` — v2 atlas validation
- `qa/chroma-despill-native.json` — deterministic edge cleanup
- `qa/review.json` — standard-row structural inspection
- `qa/contact-sheet-native-extended.png` — all 11 rows
- `qa/look-directions-native.png` — neutral plus all 16 directions
- `qa/direction-blind-validation-native.json` — three-reviewer blind direction result
- `qa/direction-semantics.json` — labeled semantic review
- `qa/look-continuity-native.json` — adjacent direction measurements
- `qa/previews/` — row animation GIFs
- `qa/run-summary.json` — package and verification summary

The installed and workspace spritesheets share SHA-256:

```text
474bbe6c2ebc5baa29bc05d10855f506ab9028ab2edd9448dc07746a71973753
```

## UI verification limitation

The Codex computer-control safety layer blocks automation of `com.openai.codex`, so automated clicks inside Codex’s own Settings are unavailable. Package discovery, manifest integrity, atlas behavior, and renderer compatibility are verified; selection plus Appearance/Pet Size toggles require a manual Settings check.
