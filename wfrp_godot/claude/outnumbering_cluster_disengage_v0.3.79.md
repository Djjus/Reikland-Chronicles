# Outnumbering bonus not removed when a combatant moves away — v0.3.79

## Request

Two screenshots of a roll card: "Elrohir attacks Wight with a Sword... Modifier: Outnumbering +40," taken in a moment where Elrohir was the only party member actually standing next to the Wight — Aes had just fled (a failed Flee/Broken Cool Test after taking a free attack for moving away from melee without Disengaging) and Fredi was standing further back. "outnumbering bonus not being removed correctly the bonus should be removed if combatant move away and are no longer engaged. In this example Elrohir is left alone on the wight but still has +40 (3v1) bonus."

## Root cause

Outnumbering's headcount math (`CombatEncounter._cluster_headcount`/`get_outnumbering_bonus`) was already correct — it only counts combatants who genuinely `has_fought_anyone` (a permanent flag, by design: once you've swung a blade this encounter you stay a real participant even if your original opponent dies). The bug was one level up, in `field_encounter_screen.gd`'s `_local_melee_cluster()` — the live battle-grid BFS that decides who's physically part of "this scrum" right now, recomputed fresh on every attack.

That BFS walks ally-to-ally and ally-to-enemy adjacency alike (deliberately — so a non-fighting bystander standing between two separate knots of real combatants doesn't sever them into two artificially-smaller fights), and used to return the ENTIRE reachable set, unfiltered, as the cluster fed into the headcount math. Since `has_fought_anyone` never resets, any ally who'd fought the Wight earlier in the encounter — Aes (hit by its free attack) and Fredi (fought it in an earlier round) — kept qualifying for the headcount forever, and as long as either of them remained within one tile of *any* ally in the chain (not the Wight itself), they still got folded into Elrohir's cluster and inflated his ratio to 3:1, even though neither of them was anywhere near the Wight any more.

## The fix

`_local_melee_cluster()` still performs the exact same BFS walk (connectivity/segmentation behavior for genuinely separate fights on a bigger battlefield is unchanged), but now filters the returned set: a combatant only counts as part of the scrum if they are **themselves** currently within melee range (distance ≤ 1) of at least one living combatant on the opposing side — not merely reachable via a chain of allies. Someone who's backed off from every enemy — moved away, fled while Broken, repositioned to help elsewhere — stops contributing to either side's Outnumbering headcount the instant they do, regardless of who they're still standing next to. A genuine multi-front brawl (several real 1-on-1s bridged through the crowd) is unaffected, since every combatant that should count in that case is, by definition, already touching an enemy of their own.

## Testing

New `outnumbering_cluster_disengage_test.gd` (10 checks) exercises the real BFS directly (not the hand-built-cluster math test that already existed) — reproduces the exact reported shape: Elrohir adjacent to the Wight, Aes and Fredi both backed off but still chain-connected via Elrohir, all three with permanent `has_fought_anyone` flags from earlier in the fight. Confirms Aes/Fredi are now excluded from the cluster and Elrohir's Outnumbering bonus is correctly 0 (was +40 before this fix), then a contrast case where Aes moves back into real melee range of the Wight and a genuine 2:1 (+20) applies correctly to both her and Elrohir, while Fredi — still out of range — continues to not count.

A headless screenshot reproduces the reported scenario directly against a real roll card: Elrohir alone against the Wight (Aes and Fredi backed off, all three with prior `has_fought_anyone` history) shows only "Modifier: Darkness +-20" — no Outnumbering line at all, confirming the fix against the actual UI, not just the underlying math.

Full regression suite: 517 checks across 22 suites, 0 failures, stable across 3 consecutive runs.

## Files changed/pushed to the device

- `scripts/ui/field_encounter_screen.gd` (`_local_melee_cluster()` filter fix)
- `scripts/core/outnumbering_cluster_disengage_test.gd` (new) + `.gd.uid`
- `scripts/core/build_info.gd` (v0.3.78 → v0.3.79)

Pushed via `device_commit_files`, guarded by fresh `expectedMtimeMs` on both pre-existing files; all 4 files succeeded, none rejected.
