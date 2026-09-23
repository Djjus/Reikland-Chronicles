extends RefCounted
class_name PartyLightBearerTest
## Per the request ("show the player character light nimbus no matter
## which character is selected at the time on the world map. if
## multiple character have light equipped use only one at a time in
## character order (ie don't consume the other one) and switch to the
## backup automatically"):
##
## Confirms Overworld._party_light_bearer() — the single source of
## truth _light_source_effective()/_apply_light_source_overlay()/
## _tick_light_source_fuel() all now share — resolves the party's one
## shared light purely by party order and who's genuinely lit, with no
## regard at all for GameState.active_party_index (which member is
## currently being controlled/displayed). Case 1 confirms a lit
## NON-active member's lantern still lights the nimbus. Case 2
## confirms that once the FIRST-in-order member also lights their own
## lantern, the bearer switches to them (party order wins) and fuel
## ticking drains ONLY that one — the second member's own fuel is
## completely untouched while the first is still lit. Case 3 confirms
## that once the first bearer's own light genuinely goes out (empty,
## no spare oil), the very next tick automatically resolves the bearer
## to the backup with no separate hand-off logic required.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var char_a: Character = GameState.player_character   ## party index 0, active
	char_a.character_name = "Alpha"
	char_a.inventory.clear()
	char_a.equipped_weapon = ""
	char_a.equipped_offhand = ""
	char_a.light_mode = "off"
	char_a.light_fuel_minutes = 0.0

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var char_b: Character = CharacterCreator.create_character("Bravo", human, soldier, {})
	char_b.inventory.clear()
	char_b.equipped_weapon = ""
	char_b.equipped_offhand = ""
	char_b.light_mode = "off"
	char_b.light_fuel_minutes = 0.0
	GameState.add_party_member(char_b)   ## party index 1, NOT active

	checks.append(["setup: party has 2 members, Alpha (char_a) active at index 0", GameState.party.size() == 2 and GameState.active_party_index == 0 and GameState.player_character == char_a])

	## Deep night core (22:30) -- flat NIGHT_DARKNESS_MAX, so
	## _light_source_effective() has a genuine "dark enough" backdrop
	## to work with once a party member actually has a lit source.
	GameState.time_minutes = 22 * 60 + 30
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	## --- Case 1: the NON-active party member (Bravo) is the only one
	## carrying a lit lantern -- the nimbus should still reflect it.
	char_b.inventory.append("Lantern")
	char_b.equipped_weapon = "Lantern"
	char_b.light_mode = "on"
	char_b.light_fuel_minutes = 100.0

	checks.append(["Case 1: the currently ACTIVE/selected character (Alpha) has no light source of their own", not char_a.has_active_light_source()])
	checks.append(["Case 1: _party_light_bearer() finds Bravo's lit lantern even though Bravo isn't the selected character", ow._party_light_bearer() == char_b])
	checks.append(["Case 1: _light_source_effective() is true purely from Bravo's lit lantern, regardless of who's selected", ow._light_source_effective()])

	ow._apply_light_source_overlay()
	var mat: ShaderMaterial = ow.night_overlay.material
	checks.append(["Case 1: the nimbus shader itself is genuinely driven by Bravo's radius even with Alpha selected", mat != null and float(mat.get_shader_parameter("light_radius_px")) > 0.0])

	## --- Case 2: Alpha (party-order FIRST) also lights their own
	## lantern -- the bearer should switch to Alpha (party order, not
	## selection state, decides), and fuel should drain ONLY Alpha's,
	## leaving Bravo's completely untouched while Alpha is still lit.
	char_a.inventory.append("Lantern")
	char_a.equipped_weapon = "Lantern"
	char_a.light_mode = "on"
	char_a.light_fuel_minutes = 50.0

	checks.append(["Case 2: with BOTH lit, _party_light_bearer() picks Alpha -- first in party order, not Bravo", ow._party_light_bearer() == char_a])

	var bravo_fuel_before: float = char_b.light_fuel_minutes
	ow._tick_light_source_fuel()
	checks.append(["Case 2: ticking fuel drains the party-order-first bearer (Alpha)...", char_a.light_fuel_minutes < 50.0])
	checks.append(["Case 2: ...and does NOT touch Bravo's own fuel at all while Alpha is still lit (no double-consumption)", is_equal_approx(char_b.light_fuel_minutes, bravo_fuel_before)])

	## --- Case 3: Alpha's own light genuinely runs out (empty, no
	## spare Lamp Oil in their own inventory) -- the very next tick
	## should automatically resolve the bearer to Bravo, no separate
	## "switch to backup" step required, and fuel should now correctly
	## come out of Bravo's own reserve instead.
	## Set well below even a single tick's minimum possible burn (a
	## whole tile step always burns SOME positive amount of game time,
	## see GameState.minutes_per_tile_fraction()) so this reliably
	## empties on the very next tick regardless of Alpha's own Movement
	## stat, rather than depending on knowing that fraction exactly.
	char_a.light_fuel_minutes = 0.001
	ow._tick_light_source_fuel()
	checks.append(["Case 3: Alpha's own light goes out once truly empty (no spare oil in Alpha's inventory)", char_a.light_mode == "off"])
	checks.append(["Case 3: _party_light_bearer() automatically falls through to Bravo (the backup) the instant Alpha's own light goes out", ow._party_light_bearer() == char_b])

	var bravo_fuel_before2: float = char_b.light_fuel_minutes
	ow._tick_light_source_fuel()
	checks.append(["Case 3: fuel now correctly burns from the new bearer (Bravo) on the very next tick", char_b.light_fuel_minutes < bravo_fuel_before2])

	ow.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Party Light Bearer — selection-independent nimbus + one-at-a-time fuel): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
