extends RefCounted
class_name WeaponCacheDefenseStallFixTest
## Real bug fix, per the report ("combat flow stoped on enemies turn" —
## a live dungeon fight frozen on a monster's turn, Round 18, the
## bottom action panel completely empty and nothing clickable).
##
## Root cause: several places in field_encounter_screen.gd indexed the
## `weapons` cache directly — `weapons[player]`, `weapons[actor]`,
## `weapons[attacker]` — instead of the safe `weapons.get(...)` pattern
## already used elsewhere in the same file. `player` in particular gets
## reassigned mid-turn to whichever party member is actually defending
## (see _prompt_player_defense's own `player = attack_target`). If that
## Character was ever missing from `weapons`, the direct index throws
## and GDScript (no try/catch) silently aborts the calling function
## right there. In _prompt_player_defense() specifically, that landed
## AFTER pending_defense/awaiting_player_target were already set but
## BEFORE any Button was actually rendered — leaving the pre-existing
## monster-turn watchdog permanently convinced this was a "legitimate
## wait" with a real prompt up, when the screen actually had nothing on
## it at all.
##
## The fix has two independent layers, both covered below:
## 1. _weapon_for(c) — a self-healing safe accessor (falls back to
##    _resolve_weapon(), which never returns null, and repairs the
##    cache) now used at every one of those call sites.
## 2. _has_any_actionable_button() — the watchdog no longer trusts a
##    "legitimate wait" flag on its word alone; it also requires a real,
##    visible Button somewhere in target_container/side_actions_container,
##    so ANY future silent crash in a flag-setting function (not just
##    this one) can no longer wedge the game forever.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	## --- _weapon_for(): normal path, cache hit -------------------------
	var cached: WeaponDefinition = fe.weapons.get(pc)
	checks.append(["weapons cache is populated for the player after _start_encounter()", cached != null])
	checks.append(["_weapon_for() returns the same cached weapon when the entry exists", fe._weapon_for(pc) == cached])

	## --- THE FIX: cache miss no longer crashes, and self-heals ---------
	fe.weapons.erase(pc)
	checks.append(["cache entry removed for this check", not fe.weapons.has(pc)])
	var healed: WeaponDefinition = fe._weapon_for(pc)
	checks.append(["THE FIX: _weapon_for() never throws on a missing cache entry — always returns a real weapon", healed != null])
	checks.append(["THE FIX: _weapon_for() self-heals the cache so future direct lookups succeed too", fe.weapons.get(pc) == healed])

	## --- _has_any_actionable_button() structural safety net ------------
	fe._clear(fe.target_container)
	fe._clear(fe.side_actions_container)
	await tree.process_frame   ## _clear() only queue_free()s -- give it a frame to actually leave the tree
	checks.append(["with no buttons anywhere, _has_any_actionable_button() correctly reports false", not fe._has_any_actionable_button()])
	var probe_button := Button.new()
	fe.target_container.add_child(probe_button)
	checks.append(["a real Button anywhere under target_container is detected", fe._has_any_actionable_button()])
	fe.target_container.remove_child(probe_button)
	probe_button.queue_free()

	## --- Regression: _prompt_player_defense() no longer stalls when ----
	## the defender is (for whatever reason) missing from the weapons
	## cache — this is the exact shape of the reported bug: the flag
	## gets set, but without the fix the function would abort before
	## ever adding a button, leaving target_container/side_actions_
	## container empty despite awaiting_player_target being true.
	fe._clear(fe.target_container)
	fe._clear(fe.side_actions_container)
	await tree.process_frame
	fe.pending_defense = {}
	fe.awaiting_player_target = false
	var attacker_weapon: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	fe.player = pc
	fe.weapons.erase(pc)   ## reproduce the missing-cache-entry condition
	await fe._prompt_player_defense(pc, attacker_weapon, 0)
	checks.append(["REGRESSION: _prompt_player_defense() completes without aborting even with a missing weapons-cache entry", fe.awaiting_player_target == true])
	checks.append(["REGRESSION: a real defend Button is on screen afterwards — the exact 'flag set, nothing on screen' bug can no longer happen here", fe._has_any_actionable_button()])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Weapon Cache / Defense Stall Fix): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
