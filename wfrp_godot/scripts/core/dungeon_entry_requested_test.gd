extends RefCounted
class_name DungeonEntryRequestedTest
## Real bug fix regression test: "all outdoor field combat encounters
## jump to the Goblin Fort dungeon."
##
## Root cause: FieldEncounterScreen._has_pending_exploration_map() used
## to gate purely on `not GameState.dungeon_state.is_empty() or
## GameState.pending_dungeon_theme_id != ""`. dungeon_state deliberately
## survives a save/reload and is only cleared by a proper Exit at the
## dungeon's own entrance — so a party that left a dungeon visit
## unfinished (very reachable since the Goblin Fort's entry ambush now
## spawns clear across the map from the entrance, at the treasure chest)
## got stuck with dungeon_state permanently non-empty. Since every field
## encounter — dungeon or not — transitions through the same
## FieldEncounter.tscn, that stale dungeon_state silently hijacked every
## later ordinary Overworld encounter into resuming the abandoned dungeon
## instead of the intended normal fight.
##
## Fix: a new GameState.dungeon_entry_requested one-shot flag, set only
## by the real dungeon-entry call sites (Overworld._offer_enter_goblin_
## fort_dungeon()/_offer_enter_cave_dungeon(), RatCatcherGuildScreen.
## _on_quest_pressed()) right before their own change_scene_to_file, now
## decides whether a FieldEncounter.tscn load resumes exploration —
## nothing else can trigger it any more, regardless of leftover
## dungeon_state.
##
## Confirms, through real FieldEncounter instances:
## - An abandoned (non-empty, but not freshly "entry requested")
##   dungeon_state no longer hijacks a normal encounter — the normal
##   monster group actually spawns, exploration mode never activates.
## - dungeon_state itself is left untouched by that normal encounter
##   (the abandoned dungeon can still be resumed later by walking back
##   into it).
## - A real dungeon entry (dungeon_entry_requested = true, mirroring
##   what the real entry call sites now do) still works exactly as
##   before — exploration mode activates, the dungeon loads.
##
## Not part of the shipped game — deleted after use once its feature is
## confirmed working, same as every other one-off *_test.gd scratch
## script in this directory.

static func _spin_up(tree: SceneTree) -> Node:
	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child(fe)
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	return fe

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "DungeonEntryRequestedTester"
	pc.inventory.clear()
	pc.inventory.append("Sword")
	pc.equipped_weapon = "Sword"
	pc.equipped_offhand = ""

	## --- Case 1: simulate an ABANDONED Goblin Fort visit — dungeon_state
	## non-empty (as if the party fought the chest ambush and quit
	## without walking back to Exit), dungeon_entry_requested left at its
	## real-world default (false) — then trigger what should be a plain
	## outdoor encounter, exactly like Overworld's own _trigger_encounter()
	## and friends do (they only ever set pending_encounter_monster_names,
	## never dungeon_entry_requested).
	var goblin_theme: DungeonThemeDefinition = load("res://data/dungeons/goblin_fort_dungeon_theme.tres")
	GameState.dungeon_state = DungeonGenerator.generate_fixed_room(goblin_theme, 8, 16)
	GameState.dungeon_state["entry_ambush_fired"] = true   ## the ambush already happened before they abandoned it
	GameState.dungeon_entry_requested = false
	GameState.pending_dungeon_theme_id = ""
	var wolf_names: Array[String] = ["Wolf", "Wolf"]
	GameState.pending_encounter_monster_names = wolf_names
	GameState.pending_battle_is_dark = false
	GameState.pending_battle_is_pitch_black = false

	var fe1: Node = await _spin_up(tree)
	checks.append(["Case 1: a stale abandoned dungeon_state does NOT force exploration mode", fe1._exploration_mode == false])
	checks.append(["Case 1: the normal encounter's own monster group actually spawned", fe1.monsters.size() == 2])
	var got_wolves := true
	for m in fe1.monsters:
		if m.character_name != "Wolf":
			got_wolves = false
	checks.append(["Case 1: the spawned monsters are the requested Wolves, not Greenskins", got_wolves])
	checks.append(["Case 1: dungeon_theme stayed null for this plain fight", fe1.dungeon_theme == null])
	checks.append(["Case 1: the abandoned dungeon_state itself is left untouched (still resumable later)", not GameState.dungeon_state.is_empty()])
	fe1.queue_free()
	await tree.process_frame
	await tree.process_frame

	## --- Case 2: a REAL dungeon entry (dungeon_entry_requested = true,
	## mirroring what Overworld._offer_enter_goblin_fort_dungeon() now
	## does) still correctly activates exploration mode.
	GameState.dungeon_state = {}
	GameState.pending_dungeon_theme_id = "goblin_fort"
	GameState.dungeon_entry_requested = true
	var fe2: Node = await _spin_up(tree)
	checks.append(["Case 2: a real dungeon entry still activates exploration mode", fe2._hosted_by_exploration == true])
	checks.append(["Case 2: dungeon_theme is the Goblin Fort", fe2.dungeon_theme != null and fe2.dungeon_theme.theme_id == "goblin_fort"])
	checks.append(["Case 2: dungeon_entry_requested was consumed (one-shot)", GameState.dungeon_entry_requested == false])
	fe2.queue_free()
	await tree.process_frame

	## --- Case 3: after that real dungeon entry, dungeon_state is now
	## non-empty again but dungeon_entry_requested is back to false (its
	## normal one-shot-consumed resting state) — the very next PLAIN
	## encounter must not be hijacked either, confirming the fix holds
	## even immediately after a legitimate entry, not just a long-stale one.
	var wolf_names2: Array[String] = ["Wolf"]
	GameState.pending_encounter_monster_names = wolf_names2
	var fe3: Node = await _spin_up(tree)
	checks.append(["Case 3: right after a real entry, the next plain encounter still isn't hijacked", fe3._exploration_mode == false and fe3.dungeon_theme == null])
	fe3.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dungeon Entry Requested — stuck dungeon_state no longer hijacks encounters): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
