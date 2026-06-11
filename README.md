# AutoPI Remix

A World of Warcraft **Retail** addon for **Priests** that determines the optimal
[Power Infusion](https://www.wowhead.com/spell=10060/power-infusion) target and
maintains a character-specific macro (`PI_WA_AUTO`) that always points to the
currently selected target.

> **AutoPI does not cast Power Infusion for you.** It only keeps a macro updated
> so you cast PI normally while remaining compliant with Blizzard's protected
> action restrictions.

## How it works

Target selection combines:

- **Spec priority** — a Bloodmallet-style ordered spec list, normalized to a score
  (top spec ≈ 1.0, bottom spec ≈ 0.0).
- **Item level weighting** — inspected item level relative to an automatically
  computed group baseline.
- **Dynamic scoring** — `totalScore = specScore + ilvlScore`, where the item-level
  contribution is clamped so gear can break ties but never override a major spec
  difference.
- **Real-time inspect data** — spec and item level are gathered via the Inspect
  API (`NotifyInspect` / `INSPECT_READY` / `GetInspectSpecialization` /
  `C_PaperDollInfo.GetInspectItemLevel`) and cached by GUID.

As of WoW 12.0 the addon no longer depends on `LibGroupInSpecT`.

### Macro management

The `PI_WA_AUTO` macro is rewritten to point at the current best target. Because
Blizzard blocks macro edits in combat, updates are deferred during combat and
re-applied automatically when combat ends (`PLAYER_REGEN_ENABLED`).

## Installation

1. Copy the addon folder into your WoW AddOns directory:
   `World of Warcraft/_retail_/Interface/AddOns/AutoPIRemix/`
2. Ensure the folder name matches the `.toc` file name (`AutoPIRemix`).
3. Restart the client or reload the UI (`/reload`).

## Usage

- `/autopi` — open the settings panel.
- `/autopi debug` — print the current selection state: DPS counts, inspect
  coverage, baseline, K, clamp, the ranked candidate breakdown, the winner, and
  inspect-pipeline telemetry (queue length, current target, request/success/
  timeout/skip counters).

## Configuration

The settings panel exposes:

- Optional extra spells folded into the macro (e.g. Premonition, trinkets).
- Preferred-player list (character names, one per line) that take priority when
  in a DPS spec.
- Weighted scoring toggle, plus auto/manual **baseline** and **K**, and the
  item-level **clamp**.
- Manual spec-order editor (or use the Bloodmallet default ordering).

## Design philosophy

AutoPI aims to answer one question: *"What player in the current group receives
the most value from Power Infusion right now?"* — deterministically, explainably,
without ever automating the cast, and adapting automatically to future item-level
squishes.

## Status

Migrated for WoW 12.0. See open items in the issue tracker / handoff notes.

## Credits

Author: **CzarTheMad**

## License

All Rights Reserved. See [LICENSE](LICENSE).
