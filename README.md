# Luffy Coder

A native Codex custom pet packaged as a v2 sprite atlas. This repository contains the pet assets and validation evidence.

## Use the pet

The distributable files are in [`pet-package/luffy-codex/`](pet-package/luffy-codex/):

```text
pet-package/luffy-codex/
├── pet.json
└── spritesheet.webp
```

Install those files in `~/.codex/pets/luffy-codex/`, then select **Luffy Coder** in **Settings → Pet → Select Pet**. Appearance and Pet Size use Codex's native settings.

## Animation

The manifest uses `spriteVersionNumber: 2`. The atlas has 8 columns and 11 rows at 1536 × 2288 pixels (192 × 208 per cell). Codex selects and plays the states.

| Atlas rows | State | Frames | Motion |
| --- | --- | ---: | --- |
| 0 | `idle` | 6 + neutral | Sleeping and breathing with a snoring bubble |
| 1–6 | Standard states | — | Drag, wave, jump, failure, and waiting |
| 7 | `running` | 6 | Typing at a laptop |
| 8 | `review` | 6 | Reviewing with a hand at the chin |
| 9–10 | Look directions | 16 | Pointer-following directions |

The supplied pose artwork is retained as [`coding.png`](coding.png) and [`review.png`](review.png). The package consumes only `pet.json` and `spritesheet.webp`.

## Validation

See [`native-pet-run/`](native-pet-run/) for the [validation result](native-pet-run/final/validation-native.json), [full contact sheet](native-pet-run/qa/contact-sheet-native-extended.png), [direction preview](native-pet-run/qa/look-directions-native.png), [animation previews](native-pet-run/qa/previews/), and [run summary](native-pet-run/qa/run-summary.json).

Package integrity, atlas structure, direction behavior, and animation rows were checked. Final selection and appearance controls should be checked in Codex Settings.

## License and commercial use

Original materials owned by Lin-Cris are available for personal, noncommercial use under the [SailmanPet Noncommercial License](LICENSE). Commercial use requires prior written permission from Lin-Cris; contact the maintainer privately to discuss licensing. Third-party rights are not included.
