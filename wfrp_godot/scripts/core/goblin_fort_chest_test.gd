extends RefCounted
class_name GoblinFortChestTest
## Verifies the Goblin Fort chest's lock/trap/loot/idol-ambush mechanics
## after their move from a hand-placed Overworld tile into the fort's
## own Dungeon Map room (see field_encounter_screen.gd's "Goblin Fort
## chest" section, ported from Overworld's now-removed chest
## functions). Calls the chest functions directly against a real
## FieldEncounterScreen instance rather than driving the actual
## turn-based UI buttons — the button wrappers (_on_open_chest_pressed()
## etc.) are thin action-economy shells around these, already covered
## by the same pattern every other exploration action
## (_on_open_door_pressed(), _on_jump_chasm_pressed()) already uses
## elsewhere in this project.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	## A very high Perception/Pick Lock advance on the player so the
	## dice-driven Tests inside the chest functions succeed reliably —
	## this test is about the chest's own state machine, not about
	## re-verifying TestResolver's own pass/fail math (covered
	## elsewhere).
	game_state.player_character.skill_advances["Perception"] = 20
	game_state.player_character.skill_advances["Pick Lock"] = 20

	game_state.pending_dungeon_theme_id = "goblin_fort"
	game_state.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment
	var fes = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fes)
	tree.current_scene = fes
	for i in range(10):
		await tree.process_frame

	## --- Case 1: entering the fort fired the entry ambush AND set up a
	## fresh, locked, unlooted chest.
	checks.append(["Case 1: entry ambush actually spawned monsters", fes.monsters.size() > 0])
	checks.append(["Case 1: dungeon_state.entry_ambush_fired is now true", fes.dungeon_state.get("entry_ambush_fired", false) == true])
	checks.append(["Case 1: chest starts locked", fes.dungeon_state.get("chest_locked", false) == true])
	checks.append(["Case 1: chest starts unlooted", fes.dungeon_state.get("chest_looted", true) == false])

	## --- Case 2: opening a still-locked chest does nothing.
	fes._on_open_chest()
	checks.append(["Case 2: _on_open_chest() on a locked chest is a no-op", fes.dungeon_state.get("chest_looted", false) == false])

	## --- Case 3: breaking a locked chest whose trap hasn't been
	## spotted yet springs the trap instead of looting it.
	var wounds_before: int = fes.player.wounds_current
	fes._on_break_chest()
	checks.append(["Case 3: an unspotted trap springs on Break instead of looting", fes.dungeon_state.get("chest_trap_spotted", false) == true and fes.dungeon_state.get("chest_looted", false) == false])
	checks.append(["Case 3: the trap actually costs real Wounds", fes.player.wounds_current < wounds_before])

	## --- Case 4: breaking it again (trap now spotted) actually unlocks
	## and loots it, granting real coin.
	var bp_before: int = fes.player.brass_pennies
	var ss_before: int = fes.player.silver_shillings
	fes._on_break_chest()
	checks.append(["Case 4: chest is unlocked after a successful Break", fes.dungeon_state.get("chest_locked", true) == false])
	checks.append(["Case 4: chest is now looted", fes.dungeon_state.get("chest_looted", false) == true])
	checks.append(["Case 4: real coin was actually granted", fes.player.brass_pennies > bp_before or fes.player.silver_shillings > ss_before])

	## --- Case 5: looting an already-empty chest grants nothing more.
	var bp_after_first_loot: int = fes.player.brass_pennies
	fes._loot_chest()
	checks.append(["Case 5: re-looting an emptied chest grants no further coin", fes.player.brass_pennies == bp_after_first_loot])

	## --- Case 6: the idol ambush — only while the Elder's quest is
	## genuinely at Stage 3 — grants the idol AND forces a real fight.
	game_state.player_character.start_elder_quest()
	var elder_q: Dictionary = game_state.player_character.get_elder_quest()
	elder_q["elder_stage"] = 3
	## Fresh chest state so _loot_chest() actually runs its full body
	## again instead of hitting the "already looted" early-out.
	fes.dungeon_state["chest_looted"] = false
	fes.dungeon_state["chest_locked"] = false
	var monsters_before_idol: int = fes.monsters.size()
	fes._loot_chest()
	checks.append(["Case 6: the Stolen Idol was actually added to the party's inventory", game_state.player_character.inventory.has("Stolen Idol")])
	checks.append(["Case 6: retrieving the idol force-spawned a real ambush fight", fes.monsters.size() > monsters_before_idol])
	checks.append(["Case 6: GameState.pending_idol_ambush is set for the party-wipe handler", game_state.pending_idol_ambush == true])

	fes.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Goblin Fort Chest): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
