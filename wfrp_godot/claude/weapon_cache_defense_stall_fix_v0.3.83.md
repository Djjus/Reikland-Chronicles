# Combat stall on a monster's turn — v0.3.83

Per the report, with two screenshots: a live dungeon fight (Round 18) froze on the Wight's turn (3/17 wounds) — the bottom action panel was completely empty, nothing clickable, no way to continue the fight.

## Root cause

Several places in `field_encounter_screen.gd` indexed the `weapons` cache (`Character -> WeaponDefinition`) directly — `weapons[player]`, `weapons[actor]`, `weapons[attacker]` — instead of the safe `weapons.get(...)` pattern already used at other call sites in the same file. GDScript has no try/catch, so a direct dictionary index on a missing key throws and silently aborts whatever function was running, right where it stands.

`player` in particular gets reassigned mid-turn to whichever party member is actually defending (see `_prompt_player_defense`'s own `player = attack_target`, set right before it's called from `_monster_attack`). In `_prompt_player_defense()` specifically, the unsafe index sat well after `pending_defense`/`awaiting_player_target` were already set (needed so the pre-existing v0.3.38 monster-turn watchdog treats this as a legitimate wait) but before any actual Button got added to the screen. If that Character was ever missing from the `weapons` cache, the function would crash right there — leaving those flags permanently set with nothing rendered. The watchdog, seeing `pending_defense` non-empty, correctly assumed a real prompt must be up and never force-ended the stuck turn. That combination — flags say "waiting on the player," screen says nothing at all — is exactly what the two screenshots showed.

## The fix

Two independent layers:

1. **`_weapon_for(c: Character) -> WeaponDefinition`** — a new safe, self-healing accessor. Falls back to `_resolve_weapon(c)` (which always returns a real weapon, worst case "Unarmed" — never null) and writes the result back into the cache, so a repaired lookup doesn't need to repeat the fallback next time. Every direct `weapons[...]` read in the file (the `_prompt_player_defense` one that matches the report, plus five other equally-unsafe reads found in the same audit — `weapons[player]` in the opening-exchange notice and the Enter-hotkey/free-action paths, and `weapons[actor]`/`weapons[attacker]` in the monster AI, monster attack setup, and attack-card display) now goes through this instead. The one existing write (`weapons[player] = _resolve_weapon(player)`, populating the cache after a weapon switch) is untouched — that's a write, not a read, and was never the problem.

2. **`_has_any_actionable_button()`** — the monster-turn watchdog used to trust the five "legitimate wait" flags (`pending_defense`, `awaiting_continue`, `awaiting_fortune_choice`, `awaiting_player_target`, `awaiting_deathblow_choice`) on their word alone. It now also requires real, visible proof: at least one actual `Button` node somewhere under `target_container` or `side_actions_container`. If a flag says "waiting" but there's genuinely nothing clickable on screen, the watchdog force-ends the turn exactly as if no flag were set at all. This closes the whole class of bug structurally — any future silent crash inside any flag-setting function, not just this one line, can no longer wedge the game with an empty panel and no recovery.

## Testing

New `weapon_cache_defense_stall_fix_test.gd` (9 checks): confirms `_weapon_for()` returns the cached weapon normally, then removes a Character's cache entry and confirms the old crash no longer happens — it returns a real weapon and repairs the cache. Confirms `_has_any_actionable_button()` correctly reads false with both containers genuinely empty and true the instant a real Button is added. Finally, a direct regression of the reported bug's shape: calls `_prompt_player_defense()` with the defender's cache entry deliberately missing (reproducing the exact crash condition) and confirms it now completes without aborting, with a real defend button actually on screen afterward — the specific "flag set, nothing rendered" state from the screenshots can no longer occur here.

Ran the full local headless suite (this new test plus the 7 already covering spells/lores/Channelling/lighting/buffs/outnumbering) 3 times with the official Godot 4.7 headless binary. All 101 checks passed every time, no regressions.

## Files changed

- `scripts/ui/field_encounter_screen.gd` — new `_weapon_for()`/`_has_any_actionable_button()`/`_subtree_has_button()`, every unsafe `weapons[...]` read switched to `_weapon_for()`, watchdog hardened to require a real button.
- `scripts/core/weapon_cache_defense_stall_fix_test.gd` — new test suite (+ its `.gd.uid`).
- `scripts/core/build_info.gd` — version bump to v0.3.83.
