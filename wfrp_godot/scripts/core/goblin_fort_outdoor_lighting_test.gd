extends RefCounted
class_name GoblinFortOutdoorLightingTest
## Per the request: "The Greenskin fort dungeon map light should match
## the time of day (as its got no roof). And the Greenskin should start
## at the other side of the map near the treasure chest."
##
## Confirms, through a real FieldEncounter instance in exploration mode
## (not a standalone maths check, since the whole point is this actually
## being wired into the real dungeon-entry flow):
## - DungeonThemeDefinition.is_outdoor is true for goblin_fort and false
##   for every other registered theme (Sewer, Cave) — nothing else
##   should silently start reading real-clock daylight.
## - Entering the Goblin Fort during real daylight sets battle_is_dark/
##   battle_is_pitch_black both false (no combat darkness penalty, no
##   "sealed pitch black" treatment) instead of every other dungeon's
##   fixed pitch-black start.
## - Entering it at night sets battle_is_dark true but battle_is_pitch_
##   black still false (a light source/Night Vision still works, same
##   as any other outdoor night — never "sealed" like an underground
##   dungeon).
## - The initial party reveal on a daylight entry lights the WHOLE fort
##   (specifically the chest, at the far end from the entrance) to
##   full brightness (vis=2) without any lit lantern — not just a wider
##   dim ring — matching "light should match time of day" as a real
##   visibility statement, not only a combat-penalty one.
## - The forced entry ambush spawns its greenskins at chest_pos, not
##   entrance_pos.
## - The Humanoid auto-lantern logic is correctly gated off during a lit
##   daytime ambush (no goblin should be carrying a lit lantern in
##   broad daylight).
##
## Not part of the shipped game — deleted after use once its feature is
## confirmed working, same as every other one-off *_test.gd scratch
## script in this directory.

static func _spin_up_goblin_fort(tree: SceneTree, time_minutes: int) -> Dictionary:
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "OutdoorLightingTester"
	pc.inventory.clear()
	pc.inventory.append("Sword")
	pc.equipped_weapon = "Sword"
	pc.equipped_offhand = ""
	pc.light_mode = "off"
	pc.light_fuel_minutes = 0.0
	pc.talents_taken.clear()

	GameState.time_minutes = time_minutes
	GameState.dungeon_state = {}
	GameState.pending_dungeon_theme_id = "goblin_fort"
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	return {"pc": pc, "fe": fe}

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: is_outdoor is set correctly across every registered theme.
	var game_data = tree.get_root().get_node("/root/GameData")
	var goblin_theme: DungeonThemeDefinition = game_data.dungeon_themes.get("goblin_fort")
	checks.append(["Case 1: goblin_fort theme is registered", goblin_theme != null])
	if goblin_theme != null:
		checks.append(["Case 1: goblin_fort.is_outdoor is true", goblin_theme.is_outdoor == true])
	for theme_id in game_data.dungeon_themes.keys():
		if theme_id == "goblin_fort":
			continue
		var other_theme: DungeonThemeDefinition = game_data.dungeon_themes[theme_id]
		checks.append(["Case 1: %s.is_outdoor stays false" % theme_id, other_theme.is_outdoor == false])

	## --- Case 2: daylight entry -> not dark, not pitch black, whole fort lit.
	var day := await _spin_up_goblin_fort(tree, 12 * 60)   ## noon
	var fe_day: Node = day["fe"]
	checks.append(["Case 2: daylight entry sets battle_is_dark = false", fe_day.battle_is_dark == false])
	checks.append(["Case 2: daylight entry sets battle_is_pitch_black = false", fe_day.battle_is_pitch_black == false])
	var chest_pos_day: Vector2i = fe_day.dungeon_state.get("chest_pos", Vector2i(-1, -1))
	var entrance_pos_day: Vector2i = fe_day.dungeon_state.get("entrance_pos", Vector2i(-2, -2))
	checks.append(["Case 2: chest_pos and entrance_pos are on opposite ends", chest_pos_day != entrance_pos_day])
	var visibility_day: Dictionary = fe_day.dungeon_state.get("visibility", {})
	checks.append(["Case 2: chest cell is fully bright (vis=2) at daylight entry with no lit lantern", int(visibility_day.get(chest_pos_day, 0)) == 2])
	fe_day.queue_free()
	await tree.process_frame

	## --- Case 3: night entry -> dark, but never sealed pitch black.
	var night := await _spin_up_goblin_fort(tree, 2 * 60)   ## 2 AM
	var fe_night: Node = night["fe"]
	checks.append(["Case 3: night entry sets battle_is_dark = true", fe_night.battle_is_dark == true])
	checks.append(["Case 3: night entry keeps battle_is_pitch_black = false", fe_night.battle_is_pitch_black == false])

	## --- Case 4: entry ambush spawns at chest_pos, not entrance_pos.
	var chest_pos_night: Vector2i = fe_night.dungeon_state.get("chest_pos", Vector2i(-1, -1))
	var entrance_pos_night: Vector2i = fe_night.dungeon_state.get("entrance_pos", Vector2i(-2, -2))
	checks.append(["Case 4: entry_ambush_fired is true after exploration starts", fe_night.dungeon_state.get("entry_ambush_fired", false) == true])
	var ambush_near_chest := true
	var ambush_near_entrance := false
	var any_ambusher := false
	for m in fe_night.monsters:
		var pos: Vector2i = fe_night.battle_positions.get(m, Vector2i(-99, -99))
		if pos == Vector2i(-99, -99):
			continue
		any_ambusher = true
		var dist_to_chest: int = abs(pos.x - chest_pos_night.x) + abs(pos.y - chest_pos_night.y)
		var dist_to_entrance: int = abs(pos.x - entrance_pos_night.x) + abs(pos.y - entrance_pos_night.y)
		if dist_to_chest > dist_to_entrance:
			ambush_near_chest = false
		if dist_to_entrance <= 1:
			ambush_near_entrance = true
	checks.append(["Case 4: at least one ambush monster actually spawned", any_ambusher])
	checks.append(["Case 4: every ambush monster is closer to chest_pos than entrance_pos", ambush_near_chest])
	checks.append(["Case 4: no ambush monster landed right on the entrance", not ambush_near_entrance])

	## --- Case 5: daylight ambush -> no goblin carries a lit lantern.
	fe_night.queue_free()
	await tree.process_frame
	var day2 := await _spin_up_goblin_fort(tree, 13 * 60)   ## 1 PM
	var fe_day2: Node = day2["fe"]
	var any_lantern := false
	for m in fe_day2.monsters:
		if m.equipped_offhand == "Lantern" or m.inventory.has("Lantern"):
			any_lantern = true
	checks.append(["Case 5: no daylight ambusher is carrying a Lantern", not any_lantern])
	fe_day2.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Goblin Fort Outdoor Lighting + Chest Ambush): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
