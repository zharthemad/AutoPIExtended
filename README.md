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

- **Spec priority** — a Bloodmallet Power Infusion ranking (ordered by absolute
  DPS gained from PI), normalized to a score (top spec ≈ 1.0, bottom ≈ 0.0). Two
  rankings are bundled and chosen automatically by content (see
  [Spec priority lists](#spec-priority-lists-raid-vs-everything-else)).
- **Item level weighting** — inspected item level relative to an automatically
  computed group baseline.
- **Dynamic scoring** — `totalScore = specScore + ilvlScore`, where the item-level
  contribution is clamped so gear can break ties but never override a major spec
  difference.
- **Real-time inspect data** — spec and item level are gathered via the Inspect
  API (`NotifyInspect` / `INSPECT_READY` / `GetInspectSpecialization` /
  `C_PaperDollInfo.GetInspectItemLevel`) and cached by GUID.

As of WoW 12.0 the addon no longer depends on `LibGroupInSpecT`.

### Spec priority lists (raid vs. everything else)

The addon bundles two Bloodmallet Power Infusion rankings and picks the one that
matches your current content:

- **Single-target** (`Castingpatchwerk`) — used in **raid** instances.
- **Multitarget / AoE** (`Castingpatchwerk5`, 5-target) — used in **Mythic+,
  dungeons, scenarios, and the open world** (everything that isn't a raid).

The active list switches automatically on instance/zone changes, and the live
debug window (`/apir debug`) shows which one is in use. If you switch to the
manual spec-order editor, your custom order is used instead, regardless of
content.

> These rankings are static snapshots of Bloodmallet's sims. Bloodmallet re-sims
> each patch, so the lists drift over time and want a periodic manual refresh
> (WoW addons can't fetch the data at runtime).

### Macro management

The `PI_WA_AUTO` macro is rewritten to point at the current best target. Because
Blizzard blocks macro edits in combat, updates are deferred during combat and
re-applied automatically when combat ends (`PLAYER_REGEN_ENABLED`). It also
re-evaluates when you change zones or instances (`PLAYER_ENTERING_WORLD`), so the
active spec list stays correct.

## Installation

1. Copy the addon folder into your WoW AddOns directory:
   `World of Warcraft/_retail_/Interface/AddOns/AutoPIRemix/`
2. Ensure the folder name matches the `.toc` file name (`AutoPIRemix`).
3. Restart the client or reload the UI (`/reload`).

## Usage

- `/autopiremix` (or the short alias `/apir`, or legacy `/autopi`) — open the
  settings panel.
- `/apir debug` — open a live debug window that refreshes in place (no chat
  scroll) showing the current selection state: which spec list is active, DPS
  counts, inspect coverage, baseline, K, clamp, the ranked candidate breakdown,
  the winner, and inspect-pipeline telemetry (queue length, current target,
  request/success/timeout/skip counters). Draggable; close with the X or Esc.
- `/apir debug print` — dump that same report to the chat frame once.
- `/apir hud` — toggle the on-screen PI target box (see below).

## On-screen target box

A small draggable box shows the **Power Infusion icon**, the **current PI target**,
and the **selection confidence** (HIGH / MED / LOW, colored, with the score gap
to the runner-up; "preferred player" when chosen from your preferred list). Drag
it anywhere — its position is saved between sessions. Toggle it with `/apir hud`.
It's shown by default.

## Configuration

The settings panel exposes:

- Optional extra spells folded into the macro (e.g. Premonition, trinkets).
- Preferred-player list (character names, one per line) that take priority when
  in a DPS spec.
- Weighted scoring toggle, plus auto/manual **baseline** and **K**, and the
  item-level **clamp**.
- Manual spec-order editor (or use the content-aware Bloodmallet rankings).

## Design philosophy

AutoPI aims to answer one question: *"What player in the current group receives
the most value from Power Infusion right now?"* — deterministically, explainably,
without ever automating the cast, and adapting automatically to future item-level
squishes.

## Status

Updated for WoW **12.0.5** (Midnight). See open items in the issue tracker /
handoff notes.

## Credits

Author: **CzarTheMad**

## License

All Rights Reserved. See [LICENSE](LICENSE).
