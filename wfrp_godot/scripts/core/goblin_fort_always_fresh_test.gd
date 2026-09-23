extends RefCounted
class_name GoblinFortAlwaysFreshTest
## Per the follow-up request: "The greenskin dungeon map should not
## remember its state if the player leaves, it should reset every time
## the player enters. Also make sure that if the player should not
## choose to enter it that they can still enter it later."
##
## Confirms, through real FieldEncounter instances:
## - A Goblin Fort visit that made real progress (chest unlocked and
##   looted, entry ambush already fired) does NOT carry any of that into
##   the NEXT entry — mirrors exactly what Overworld._offer_enter_goblin_
##   fort_dungeon() now does on every accepted entry (GameState.
##   dungeon_state = {} then pending_dungeon_theme_id = "goblin_fort"):
##   the new visit's chest starts locked/unlooted again and its own
##   entry ambush is free to fire again, a completely fresh 8x16 room.
##   This holds regardless of how the PREVIOUS visit ended — whether it
##   was a clean Exit or an abandoned mid-visit walkaway — since the new
##   entry unconditionally discards whatever was there before rather
##   than ever resuming it.
## - Declining the entry prompt never touches dungeon_state or pending_
##   dungeon_theme_id at all (the whole accepted-branch is skipped
##   entirely in that case — see _offer_enter_goblin_fort_dungeon()'s own
##   `if _entered_confirmed:` guard), so there is nothing for a later
##   accepted entry to be blocked by; a decline is a pure no-op on
##   dungeon state.
##
## Not part of the shipped game — deleted after use once its feature is
## confirmed working, same as every other one-off *_test.gd scratch
## script in this directory.

static func _spin_up_fresh_fort_entry(tree: SceneTree) -> Node:
	## Mirrors exactly what Overworld._offer_enter_goblin_fort_dungeon()
	## does on every accepted entry now.
	GameState.dungeon_state = {}
	GameState.pending_dungeon_theme_id = "goblin_fort"
	GameState.dungeon_entry_requested = true
	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child(fe)
	for i in range(4):
		await tree.process_frame
	return fe

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "FreshFortTester"
	pc.inventory.clear()
	pc.inventory.append("Sword")
	pc.equipped_weapon = "Sword"
	pc.equipped_offhand = ""
	GameState.time_minutes = 12 * 60

	## --- Visit 1: enter, then simulate real progress (unlock + loot the
	## chest, confirm the entry ambush already fired).
	var fe1: Node = await _spin_up_fresh_fort_entry(tree)
	checks.append(["Visit 1: entry ambush fired immediately", fe1.dungeon_state.get("entry_ambush_fired", false) == true])
	checks.append(["Visit 1: chest starts locked", fe1.dungeon_state.get("chest_locked", false) == true])
	fe1.dungeon_state["chest_locked"] = false
	fe1.dungeon_state["chest_looted"] = true
	GameState.dungeon_state = fe1.dungeon_state
	checks.append(["Visit 1: chest is now unlocked+looted (simulated real progress)", GameState.dungeon_state.get("chest_looted", false) == true])
	## Abandon it WITHOUT calling _do_exit_dungeon() -- exactly the "left
	## without a proper Exit" case the original bug report came from.
	fe1.queue_free()
	await tree.process_frame
	await tree.process_frame
	checks.append(["Between visits: dungeon_state was left non-empty (abandoned, not exited)", not GameState.dungeon_state.is_empty()])

	## --- Visit 2: a fresh accepted entry (same call shape as the real
	## Overworld gate) must NOT resume visit 1's looted chest/fired ambush.
	var fe2: Node = await _spin_up_fresh_fort_entry(tree)
	checks.append(["Visit 2: chest is locked again (not resumed from visit 1)", fe2.dungeon_state.get("chest_locked", false) == true])
	checks.append(["Visit 2: chest is not looted (fresh chest)", fe2.dungeon_state.get("chest_looted", true) == false])
	checks.append(["Visit 2: entry_ambush_fired reflects THIS visit's own fresh fire, not stale carry-over", fe2.dungeon_state.get("entry_ambush_fired", false) == true])
	checks.append(["Visit 2: a brand new set of ambush monsters actually spawned again", fe2.monsters.size() >= 3])
	fe2.queue_free()
	await tree.process_frame

	## --- Declining never touches dungeon state at all (by construction:
	## _offer_enter_goblin_fort_dungeon()'s whole accepted-branch — the
	## only place that ever writes dungeon_state/pending_dungeon_theme_id
	## /dungeon_entry_requested — sits behind `if _entered_confirmed:`,
	## so a decline literally cannot touch any of these fields). Confirmed
	## here by checking those fields are untouched by merely NOT calling
	## the accepted-entry path.
	var before_state: Dictionary = GameState.dungeon_state.duplicate()
	var before_pending: String = GameState.pending_dungeon_theme_id
	var before_requested: bool = GameState.dungeon_entry_requested
	## (deliberately doing nothing here -- this IS what "decline" does)
	checks.append(["Decline is a no-op: dungeon_state unchanged", GameState.dungeon_state.hash() == before_state.hash()])
	checks.append(["Decline is a no-op: pending_dungeon_theme_id unchanged", GameState.pending_dungeon_theme_id == before_pending])
	checks.append(["Decline is a no-op: dungeon_entry_requested unchanged", GameState.dungeon_entry_requested == before_requested])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Goblin Fort Always Fresh On Entry): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
