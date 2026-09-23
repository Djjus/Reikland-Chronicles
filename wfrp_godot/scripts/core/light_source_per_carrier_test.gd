extends RefCounted
class_name LightSourcePerCarrierTest
## Regression test for the reported bug ("light sources should only cast
## light around the player holding it, in these images Davrin has the
## lamp, but the light is casting from both characters"). Before the
## fix, _reveal_around_party() handed EVERY party member the same
## _current_light_radius() -- the single BEST light radius found
## anywhere in the party -- for their own bright circle, so a party
## member with no light of their own standing in a completely separate
## part of the dungeon from whoever actually held the lit lantern still
## got a full bright circle of their own, as if they personally carried
## it too.
##
## Sets up two party members far apart on a big open dungeon-shaped
## grid: only one (the lamp holder) has an active light source. Checks
## that ONLY the lamp holder's own square gets a real bright (vis=2)
## circle around it; the other member's own square (and the area around
## it, beyond their own Initiative-Bonus dim ring) stays at the shared
## dim ambient level or unexplored, never bright, purely from being
## physically near a party member who isn't the one holding the light.

static func run_test(fe) -> bool:
	var checks: Array = []

	GameState.party.clear()
	GameState.player_character = null
	GameState.ensure_player_character()
	var holder: Character = GameState.player_character
	holder.character_name = "Davrin"
	## A light source is equipped exactly like a weapon (see
	## get_equipped_light_item()'s own comment) -- held in the off-hand
	## here so a real melee weapon can still occupy the main hand, same
	## as a normal lantern-carrying character in actual play.
	holder.equipped_offhand = "Lantern"
	holder.equipped_weapon = "Sword"
	holder.light_mode = "on"
	holder.light_fuel_minutes = 999.0

	var dark_ally := Character.new()
	dark_ally.character_name = "Eric T"
	dark_ally.race = holder.race
	dark_ally.characteristics = holder.characteristics.duplicate()
	dark_ally.allegiance = "ally"
	dark_ally.wounds_max = 10
	dark_ally.wounds_current = 10
	dark_ally.equipped_weapon = "Sword"
	GameState.add_party_member(dark_ally)

	checks.append(["setup: the lamp holder genuinely has an active light source", holder.get_active_light_radius_tiles() > 0])
	checks.append(["setup: the other party member has no light source of their own", dark_ally.get_active_light_radius_tiles() <= 0 and not dark_ally.has_creature_trait("Dark Vision")])

	## A big, fully-open dungeon-shaped grid (no real DungeonGenerator
	## randomness needed here -- this test is about the light-radius
	## math, not room geometry) with the two party members placed far
	## enough apart that their own bright circles (up to radius 10)
	## could never legitimately overlap.
	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	var f: String = theme.floor_char
	var rows: Array = []
	for y in range(30):
		rows.append(f.repeat(40))
	GameState.dungeon_state = {
		"theme_id": "sewer",
		"grid_rows": rows,
		"entrance_pos": Vector2i(2, 2),
		"rooms": [],
		"hallway_segments": [],
		"visibility": {},
		"player_grid_pos": Vector2i(2, 2),
		"exit_used": false,
	}

	fe._start_exploration_mode()
	for i in range(3):
		await fe.get_tree().process_frame

	var holder_pos := Vector2i(5, 5)
	var dark_pos := Vector2i(35, 25)   ## far away -- radius 10 bright circles can't reach each other
	fe.battle_positions[holder] = holder_pos
	fe.battle_positions[dark_ally] = dark_pos
	fe._refresh_dungeon_battle_grid()
	fe._reveal_around_party()
	for i in range(2):
		await fe.get_tree().process_frame

	var vis: Dictionary = fe.dungeon_state.get("visibility", {})

	## The lamp holder's own square, and squares near it, should be
	## fully bright (vis=2) -- a real, working light source.
	checks.append(["the lamp holder's own square is bright (vis=2)", int(vis.get(holder_pos, -1)) == 2])
	checks.append(["a few squares out from the lamp holder is still bright, within the lantern's real radius", int(vis.get(holder_pos + Vector2i(3, 0), -1)) == 2])

	## THE FIX: the OTHER party member, standing far away with no light
	## of their own, should NOT have a bright CIRCLE of their own --
	## _light_bfs() always marks a BFS's own center cell as "reached"
	## even at radius 0 (so a character can always at least see the
	## single square they're physically standing on, light or no light
	## -- unrelated pre-existing behaviour, not part of this bug), but
	## nothing even one step out from their own square should read as
	## bright, since there's no real light radiating from them at all.
	var dark_ib: int = dark_ally.get_characteristic_bonus("initiative")
	checks.append(["THE FIX: even one square away from the non-lamp-holder, nothing is bright -- no real light radius of their own", int(vis.get(dark_pos + Vector2i(1, 0), -1)) != 2 and int(vis.get(dark_pos + Vector2i(-1, 0), -1)) != 2])
	checks.append(["the non-lamp-holder's own square is still at least dimly visible (their own ambient vision still works)", int(vis.get(dark_pos, -1)) >= 1])
	## A ring just past their own light-less dim radius should be
	## completely unrevealed -- confirms this isn't secretly still
	## bright at a smaller radius, it's genuinely capped at ambient.
	var far_beyond_dim: Vector2i = dark_pos + Vector2i(dark_ib + 5, 0)
	checks.append(["well beyond the non-lamp-holder's own ambient ring is unrevealed", int(vis.get(far_beyond_dim, -1)) == -1])

	fe.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Light Source Per Carrier): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
