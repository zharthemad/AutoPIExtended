# AutoPI Extended

A World of Warcraft **Retail** addon for **Priests** that determines the optimal
[Power Infusion](https://www.wowhead.com/spell=10060/power-infusion) target and
maintains a character-specific macro (`APIE`) that always points to the
currently selected target.

> **AutoPI does not cast Power Infusion for you.** It only keeps a macro updated
> so you cast PI normally while remaining compliant with Blizzard's protected
> action restrictions.

The addon loads only for **Priests** — it stays completely inert for every other
class (no database, no events, no macro).

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
debug window (`/apie debug`) shows which one is in use. If you switch to the
manual spec-order editor, your custom order is used instead.

> These rankings are static snapshots of Bloodmallet's sims (last refreshed
> 2026-06-24, SimC `c12e9e5`). Bloodmallet re-sims each patch, so the lists drift
> over time and want a periodic manual refresh (WoW addons can't fetch the data
> at runtime).

### Selection priority

Target selection resolves in this order, falling through when a step finds no
eligible player:

1. **Preferred-player list** — a character you named (one per line in settings)
   who is currently in the group in a DPS spec.
2. **Manual spec-order list** — if you've switched to the manual editor.
3. **Auto Bloodmallet list** — the content-aware ranking, used as the final
   fallback. If a manual spec-order list is configured but nobody in the group
   matches it, selection falls back to the auto list (shown as `auto-fallback`
   confidence).

### Macro management

The `APIE` macro is rewritten to point at the current best target. Because
Blizzard blocks macro edits in combat, updates are deferred during combat and
re-applied automatically when combat ends (`PLAYER_REGEN_ENABLED`). It also
re-evaluates when you change zones or instances (`PLAYER_ENTERING_WORLD`), so the
active spec list stays correct.

## Installation

1. Copy the addon folder into your WoW AddOns directory:
   `World of Warcraft/_retail_/Interface/AddOns/AutoPIExtended/`
2. Ensure the folder name matches the `.toc` file name (`AutoPIExtended`).
3. Restart the client or reload the UI (`/reload`).

## Usage

- `/autopie` (or the short alias `/apie`) — open the settings panel.
- `/apie debug` — open a live debug window that refreshes in place (no chat
  scroll) showing the current selection state: which spec list is active, DPS
  counts, inspect coverage, baseline, K, clamp, the ranked candidate breakdown,
  the winner, and inspect-pipeline telemetry (queue length, current target,
  request/success/timeout/skip counters). Draggable; close with the X or Esc.
- `/apie debug print` — dump that same report to the chat frame once.
- `/apie hud` — toggle the on-screen PI target box (see below).

## On-screen target box

A small draggable box shows the **Power Infusion icon**, the **current PI target**,
and the **selection confidence** (HIGH / MED / LOW, colored, with the score gap
to the runner-up; "preferred player" when chosen from your preferred list,
"auto-fallback" when the manual list matched no one). Drag it anywhere — its
position is saved between sessions. Toggle it with `/apie hud`. It's shown by
default.

It also includes:

- **Scan progress** (`xx/yy`) — how many group DPS have been inspected out of the
  total to scan.
- **Clickable PI icon** — clicking it targets the current PI recipient (uses a
  secure button so it works in combat).
- **`A` button** — re-announces the current PI target to chat (handy when a priest
  joins late and missed the automatic announcement).
- **`D` button** — opens the live debug window.

## Chat announcements

Once spec scanning settles (no new inspect data arriving for a few seconds), the
addon announces the current PI target to your group — **instance chat** in
LFG/LFR, otherwise **raid** or **party** chat. (Settling on a short debounce
rather than a fully-drained inspect queue is deliberate: in a large raid like LFR
a few players are never inspectable, so the queue may never reach empty.) The
message is intentionally neutral
(`AutoPI Extended: PI → Name`) — it does **not** broadcast the HIGH/MED/LOW
confidence rating, since next to a player's name that reads like a judgment of the
person rather than the score margin it actually reflects. Only when the pick is a
genuine toss-up does it append the runner-up as useful backup info
(`PI → Name (Other close behind)`). Full confidence detail stays on the HUD and
debug window, for your eyes only. It re-announces when the target changes (e.g.
roster changes) so other priests know who you're infusing, without spamming when
nothing has changed. Use the HUD **`A`** button to re-send on demand.

## Configuration

The settings panel exposes (top to bottom):

- **Trinkets / spells** folded into the macro.
- **Show on-screen PI target box** toggle.
- **Preferred-player list** (character names, one per line) that take priority
  when in a DPS spec (step 1 of [Selection priority](#selection-priority)).
- **Target Scoring** — weighted-scoring toggle, plus auto/manual **baseline** and
  **K**, and the item-level **clamp**. The manual boxes dim when their auto-toggle
  is on (and all dim when weighted scoring is off).
- **Spec Priority Order** — use the content-aware Bloodmallet rankings, or switch
  to a manual drag-order editor.

## Design philosophy

AutoPI aims to answer one question: *"What player in the current group receives
the most value from Power Infusion right now?"* — deterministically, explainably,
without ever automating the cast, and adapting automatically to future item-level
squishes.

## Status

Updated for WoW **12.0.7** (Midnight). See open items in the issue tracker /
handoff notes.

## Credits

Author: **CzarTheMad**

Inspired by [AutoPI - Power Infusion Made Easy](https://www.curseforge.com/wow/addons/autopi-power-infusion-made-easy) by its original author. AutoPI Extended started as a personal fork and has since grown into a significantly reworked addon, but the original concept and name come from that project.

## License

Licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

This addon incorporates code from
[AutoPI - Power Infusion Made Easy](https://www.curseforge.com/wow/addons/autopi-power-infusion-made-easy),
which is distributed under the GPLv3; as a derivative work, AutoPI Extended is
released under the same license.
