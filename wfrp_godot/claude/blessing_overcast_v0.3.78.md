# Blessing Overcast — v0.3.78

## Request

"blessings should allow overcast like spending on additional friendly targets (cost 2 SL), and multiply duration by x2/3/4/5..etc for 2 SL per stage."

## Design

Blessings (Prayers that grant a timed Characteristic/Damage buff — `BLESSING_STAT_MAP`'s ten named Blessings, plus Sigmar's Fiery Hammer) already resolved with an unused overflow SL amount (any Success Levels beyond the 0 needed to succeed) going nowhere. This adds a picker — offered right after a successful buff-prayer roll, same UX pattern the existing spell Overcast picker (`_offer_overcasting`/`_offer_overcasting_aoe`) already uses — letting the caster spend that overflow SL on either or both of:

- **Targets**: +1 additional friendly target for 2 SL (RAW's own rule, unchanged — core rulebook p.221 already prices extra Blessing targets this way).
- **Duration**: a house-rule departure from RAW, explicit and deliberate per the request. RAW prices extra Duration on a Blessing at a flat "+6 Rounds" per 2 SL. This instead **multiplies** the base Duration by the stage number — 2 SL → x2 Duration, 4 SL → x3, 6 SL → x4, and so on — applied to whatever the blessing's own actual base Duration is (a flat 6 Rounds for the ten `BLESSING_STAT_MAP` blessings, but Fellowship-Bonus Rounds for Sigmar's Fiery Hammer — the multiplier always applies to the caster's own real base, never a hardcoded 6).

Both spends draw from the same shared SL pool and can be combined (e.g. 5 SL → 1 stage of Duration + 1 extra Target, with 1 SL left unspent) — the picker's Confirm handler rejects any combination that overspends, and requires the Targets count picked to exactly match the number of candidates toggled on.

## Implementation

- `field_encounter_screen.gd`: removed the old, unused `_overflow_duration_bonus()`. `_apply_prayer_buff_effect()` now returns the full buff shape (characteristic bonuses, damage bonus, base Rounds) alongside its description, so the new picker has what it needs to compute a multiplied Duration against the *right* base. `_on_pray()` offers the new picker (`_offer_blessing_overcast()`) right after a successful buff-prayer resolution, gated on `success_levels` actually being spendable (`>= 2`).
- `_offer_blessing_overcast()` (new, ~140 lines): builds the same kind of scoped Magic/Prayers column UI as the spell Overcast picker — a Duration `OptionButton`, a Targets `OptionButton` (only shown if there's at least one other living ally to target), toggle buttons for each candidate ally, a live "N SL remaining" label, Confirm/Skip. On Confirm: applies the Duration multiplier to the original target's just-added buff entry, then replicates the same buff (at the new multiplied Duration) onto each chosen extra target.

## Testing

New `blessing_overcast_test.gd`, 21 checks: base Duration application, the sl<2 no-op case, the full picker flow (Duration + Targets spend together, candidate toggling), post-confirm state (multiplied Duration on the original target, the replicated buff correctly applied to the chosen extra target, an untouched non-chosen candidate), overspend/count-mismatch rejection (picker stays open, nothing applied), and a non-flat-base-Duration case (Sigmar's Fiery Hammer) confirming the multiplier is applied to *its own* Fellowship-Bonus-based Rounds, not a hardcoded 6.

Also fixed a genuine test-flakiness bug found while writing this: in a multi-character party, `field_encounter_screen.gd`'s own `player` field gets reassigned to whichever party member's Turn is currently active (`GameState.player_character` is itself a computed property reading `party[active_party_index]`) — so a test that assumes `player` still points at whoever was created first can intermittently fail depending on initiative/dice state. Both the new test and the already-shipped `blessing_buff_turn_order_test.gd` (which has the exact same assumption baked into one of its checks) now explicitly pin `fe.player` before relying on it. Confirmed via 3 consecutive full-suite runs before this fix (at least one failure per run) versus 3 consecutive clean runs after it.

Full regression suite: 507 checks across 20 suites, 0 failures, confirmed stable across 3 consecutive runs.

## Files changed/pushed to the device

- `scripts/ui/field_encounter_screen.gd`
- `scripts/core/blessing_overcast_test.gd` (new) + `.gd.uid`
- `scripts/core/blessing_buff_turn_order_test.gd` (flakiness fix, see above)
- `scripts/core/build_info.gd` (v0.3.77 → v0.3.78)

Pushed via `device_commit_files`, guarded by fresh `expectedMtimeMs` on every pre-existing file; all 8 files in this push (this doc's files plus the NPC ground-tile fix shipped in the same push — see `npc_ground_tile_mismatch_v0.3.78.md`) succeeded, none rejected.
