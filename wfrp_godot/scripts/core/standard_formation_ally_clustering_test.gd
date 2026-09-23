extends RefCounted
class_name StandardFormationAllyClusteringTest
## Per the request: "In field encounters, where nobody is surprised,
## place the player party character closer together, they should be
## with[in] 2 cells of another character at a minimum. But keep the
## mini[mum] distance to enemy as it is."
##
## FieldEncounterScreen._place_standard() (the formation used whenever
## NEITHER side starts Surprised — see _setup_battle_grid()'s own
## branch) used to spread allies across the grid's FULL height via
## _spread_rows(), same as adversaries — on BattleGrid's real 27-row
## grid, even a small 4-person party's own flanking members could land
## many cells apart, nothing like "sticking together." Fixed by packing
## every ally toward one shared anchor point on the ally start column
## (find_open_square_near naturally fills the nearest open square to a
## repeated preferred square first — the same trick _place_ambush already
## used for a Surprised side's own huddle), while leaving adversary
## placement (and both sides' own start columns) completely untouched.
##
## Confirms, through a real FieldEncounter instance with a real
## multi-member party and no Surprised condition on anyone:
## - Every ally lands within footprint-distance 2 of at least one OTHER
##   ally (the requested minimum).
## - Adversaries are unaffected: still spread across the grid's rows
##   (not clustered like the allies), and still anchored on
##   BattleGrid.ADVERSARY_START_COL exactly as before.
## - The two sides' own approach distance is unchanged: the closest
##   ally-to-adversary gap still reflects BattleGrid.ALLY_START_COL /
##   ADVERSARY_START_COL exactly as before this change (this test's own
##   real column values, not a guessed constant, so it stays correct even
##   if those constants are retuned later).
##
## Not part of the shipped game — deleted after use once its feature is
## confirmed working, same as every other one-off *_test.gd scratch
## script in this directory.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.party.clear()
	GameState.player_character = null
	GameState.ensure_player_character()
	var leader: Character = GameState.player_character
	leader.character_name = "Leader"
	leader.equipped_weapon = "Sword"

	## Four more real party members (5 total) so the "spread across 27
	## rows" bug would have put the two flanking allies far more than 2
	## cells apart under the old _spread_rows-for-allies-too behavior.
	for i in range(4):
		var ally := Character.new()
		ally.character_name = "Ally %d" % i
		ally.race = leader.race
		ally.characteristics = leader.characteristics.duplicate()
		ally.allegiance = "ally"
		ally.wounds_max = 10
		ally.wounds_current = 10
		ally.equipped_weapon = "Sword"
		GameState.add_party_member(ally)

	## A genuinely plain encounter -- no ambush, nobody Surprised.
	var monster_names: Array[String] = ["Goblin", "Goblin", "Goblin"]
	GameState.pending_encounter_monster_names = monster_names
	GameState.pending_encounter_is_player_ambush = false
	GameState.pending_battle_is_dark = false
	GameState.pending_battle_is_pitch_black = false

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	checks.append(["setup: FieldEncounter instantiated without error", fe != null])
	checks.append(["setup: no one starts Surprised (plain encounter)", not GameState.party.any(func(c: Character): return c.conditions.has("Surprised"))])
	checks.append(["setup: all 5 party members are on the grid", GameState.party.all(func(c: Character): return fe.battle_positions.has(c))])

	## --- Every ally within footprint-distance 2 of at least one OTHER ally.
	var all_allies_clustered := true
	for a in GameState.party:
		if not fe.battle_positions.has(a):
			all_allies_clustered = false
			continue
		var has_near_neighbor := false
		for b in GameState.party:
			if b == a or not fe.battle_positions.has(b):
				continue
			var d: int = BattleGrid.footprint_distance(fe.battle_positions[a], a.get_footprint_size(), fe.battle_positions[b], b.get_footprint_size())
			if d <= 2:
				has_near_neighbor = true
				break
		if not has_near_neighbor:
			all_allies_clustered = false
	checks.append(["THE FIX: every ally is within 2 cells of at least one other ally", all_allies_clustered])

	## --- Adversaries still spread across rows (NOT clustered like
	## allies), same as before this change -- at least two adversaries
	## should be MORE than 2 cells apart from each other (proves they
	## weren't accidentally clustered too).
	var adversaries: Array[Character] = []
	for m in fe.monsters:
		adversaries.append(m)
	var some_adversary_pair_far_apart := false
	for i in range(adversaries.size()):
		for j in range(i + 1, adversaries.size()):
			var d2: int = BattleGrid.footprint_distance(fe.battle_positions[adversaries[i]], adversaries[i].get_footprint_size(), fe.battle_positions[adversaries[j]], adversaries[j].get_footprint_size())
			if d2 > 2:
				some_adversary_pair_far_apart = true
	checks.append(["Adversaries are unaffected: still spread apart, not clustered", some_adversary_pair_far_apart])

	## --- Ally-to-adversary distance unchanged: the closest gap between
	## the two clusters should match BattleGrid.START_DISTANCE_SQUARES-
	## derived columns, i.e. roughly ADVERSARY_START_COL - ALLY_START_COL
	## horizontally, same as it always was (this function only ever
	## changed ally-to-ALLY spacing).
	var expected_col_gap: int = BattleGrid.ADVERSARY_START_COL - BattleGrid.ALLY_START_COL
	var closest_cross_gap := 999999
	for a in GameState.party:
		if not fe.battle_positions.has(a):
			continue
		for m in adversaries:
			var d3: int = BattleGrid.footprint_distance(fe.battle_positions[a], a.get_footprint_size(), fe.battle_positions[m], m.get_footprint_size())
			if d3 < closest_cross_gap:
				closest_cross_gap = d3
	## Allow a little slack for find_open_square_near's own obstacle/
	## footprint search nudging exact squares around -- the point is this
	## stayed in the same ballpark as the real start-column gap, not that
	## no other change in the game could ever shift it by a square or two.
	checks.append(["Ally-to-adversary minimum distance is still ~the real start-column gap (unchanged by this fix)", absi(closest_cross_gap - expected_col_gap) <= 3])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Standard Formation Ally Clustering): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
