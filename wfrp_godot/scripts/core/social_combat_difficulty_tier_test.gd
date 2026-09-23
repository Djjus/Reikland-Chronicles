extends RefCounted
class_name SocialCombatDifficultyTierTest
## Verifies the Social Combat Difficulty Tier feature, per the request
## ("we have difficulty level in combat, let's add it to social
## encounters too... all encounters should have the same modifiers"):
## DifficultyTiers.apply_social_npc_tier_bonus() applies the right
## Characteristic/Composure numbers at the unit level, and GameState.
## current_social_difficulty_tier actually reaches a live
## SocialEncounter.tscn's seated NPC roster (the wiring
## social_encounter_screen.gd's own _build_npc_roster() is responsible
## for) rather than only existing on paper.
##
## Social Armor's own Tier scaling is no longer a flat bonus table at
## all — per the follow-up request ("social encounter social armor
## should work by comparing attacker vs defender status... it should
## increase status by NPCs career tier"), it now flows through
## SocialCombatNPCDefinition.get_status_ordinal(), which reads the
## NPC's real Career (via portrait_career_key) and uses the Difficulty
## Tier as that Career's own level (1-4). Covered by Case 1b (unit) and
## Case 2 (wiring) below instead.

## Independent re-derivation of SocialCombatNPCDefinition.get_status_ordinal()'s
## own expected result, used by Case 2 below to confirm the real wiring
## (GameState.current_social_difficulty_tier -> _build_npc_roster() ->
## npc_status_ordinal_by_char) reaches a live screen correctly — not
## just re-running the same production code against itself.
static func _expected_status_ordinal(portrait_career_key: String, tier: int) -> int:
	const ORDER := {"Brass": 1, "Silver": 2, "Gold": 3}
	if portrait_career_key.is_empty():
		return 1
	for c in GameData.careers:
		if CareerPortraits.key_for(c.career_name) == portrait_career_key:
			var level := c.get_level(clampi(tier, 1, c.levels.size()))
			if level != null:
				return ORDER.get(level.status_tier, 1)
	return 1

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: unit-level bonus tables, in isolation from any scene.
	checks.append(["Tier 0 has no bonus of any kind", DifficultyTiers.get_bonus(0) == 0 and DifficultyTiers.get_composure_bonus(0) == 0])
	checks.append(["Tier 3 Characteristic bonus is +30 (same table combat uses)", DifficultyTiers.get_bonus(3) == 30])
	checks.append(["Tier 3 Composure bonus is +3 (its own, smaller table, halved alongside the baseline)", DifficultyTiers.get_composure_bonus(3) == 3])
	checks.append(["Tier 5 Characteristic bonus is +50", DifficultyTiers.get_bonus(5) == 50])
	checks.append(["Tier 5 Composure bonus is +5 (halved alongside the baseline)", DifficultyTiers.get_composure_bonus(5) == 5])
	checks.append(["An out-of-range tier (9) clamps rather than erroring", DifficultyTiers.get_bonus(9) == 50 and DifficultyTiers.get_composure_bonus(9) == 5])

	## --- Case 1b: SocialCombatNPCDefinition.get_status_ordinal() at the
	## unit level. "outlaw" (data/careers/outlaw.tres) is Brass/Brass/
	## Brass/Silver across its real 4 CareerLevels — a real career with a
	## status change partway through, not a flat one, so this actually
	## exercises the per-level lookup rather than just checking a single
	## Brass or Gold career throughout.
	var outlaw_npc := SocialCombatNPCDefinition.new()
	outlaw_npc.portrait_career_key = "outlaw"
	checks.append(["get_status_ordinal(1) on an Outlaw is Brass (1) — its own real Tier 1 Status", outlaw_npc.get_status_ordinal(1) == 1])
	checks.append(["get_status_ordinal(3) on an Outlaw is still Brass (1) — its own real Tier 3 Status", outlaw_npc.get_status_ordinal(3) == 1])
	checks.append(["get_status_ordinal(4) on an Outlaw is Silver (2) — its own real Tier 4 Status", outlaw_npc.get_status_ordinal(4) == 2])
	checks.append(["get_status_ordinal(0) clamps to the Career's own level 1 (Brass)", outlaw_npc.get_status_ordinal(0) == 1])
	checks.append(["get_status_ordinal(9), an out-of-range Tier, clamps to the Career's own top level 4 (Silver)", outlaw_npc.get_status_ordinal(9) == 2])

	var no_career_npc := SocialCombatNPCDefinition.new()
	checks.append(["get_status_ordinal() with no portrait_career_key falls back to Brass (1), matching Character.get_status_ordinal()'s own no-career convention", no_career_npc.get_status_ordinal(4) == 1])
	var unknown_career_npc := SocialCombatNPCDefinition.new()
	unknown_career_npc.portrait_career_key = "not_a_real_career_xyz"
	checks.append(["get_status_ordinal() with a key matching no real Career also falls back to Brass (1)", unknown_career_npc.get_status_ordinal(4) == 1])

	var npc := Character.new()
	npc.characteristics = CharacteristicSet.new()
	npc.characteristics.willpower = 40
	npc.characteristics.fellowship = 35
	npc.characteristics.intelligence = 38
	npc.characteristics.initiative = 32
	npc.composure_max = 20
	npc.composure_current = 20
	DifficultyTiers.apply_social_npc_tier_bonus(npc, 3)
	checks.append(["apply_social_npc_tier_bonus(tier 3) bumps Willpower by +30", npc.characteristics.willpower == 70])
	checks.append(["...Fellowship by +30", npc.characteristics.fellowship == 65])
	checks.append(["...Intelligence by +30", npc.characteristics.intelligence == 68])
	checks.append(["...Initiative by +30", npc.characteristics.initiative == 62])
	checks.append(["...composure_max by +3", npc.composure_max == 23])
	checks.append(["...composure_current by +3 too (a fresh NPC starts at full)", npc.composure_current == 23])
	checks.append(["...leaves an untouched Characteristic (e.g. Strength) alone", npc.characteristics.strength == 20])

	var npc_untouched := Character.new()
	npc_untouched.characteristics = CharacteristicSet.new()
	npc_untouched.characteristics.willpower = 40
	npc_untouched.composure_max = 20
	npc_untouched.composure_current = 20
	DifficultyTiers.apply_social_npc_tier_bonus(npc_untouched, 0)
	checks.append(["apply_social_npc_tier_bonus(tier 0) changes nothing", npc_untouched.characteristics.willpower == 40 and npc_untouched.composure_max == 20])

	## --- Case 2: end-to-end wiring — GameState.current_social_
	## difficulty_tier actually reaches the seated NPC roster via
	## SocialEncounterScreen._build_npc_roster(), the same way
	## current_field_difficulty_tier already reaches spawned monsters.
	var game_state = tree.get_root().get_node("/root/GameState")

	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	game_state.current_social_difficulty_tier = 0
	var scene_res: PackedScene = load("res://scenes/SocialEncounter.tscn")
	var screen_t0: Control = scene_res.instantiate()
	tree.get_root().add_child(screen_t0)
	for i in range(10):
		await tree.process_frame
	var baseline_wp := -1
	var baseline_composure := -1
	var status_t0_ok := false
	if not screen_t0.npc_characters.is_empty() and screen_t0.encounter_def != null:
		var first_npc: Character = screen_t0.npc_characters[0]
		baseline_wp = first_npc.characteristics.willpower
		baseline_composure = first_npc.composure_max
		var expected_status_t0 := _expected_status_ordinal(screen_t0.encounter_def.portrait_career_key, 0)
		status_t0_ok = screen_t0.npc_status_ordinal_by_char.get(first_npc, -1) == expected_status_t0
	checks.append(["Case 2: Tier 0 screen seeded at least one NPC", baseline_wp >= 0])
	checks.append(["Case 2: Tier 0 screen's seated NPC Status matches its own real Career's Tier-1 Status (Tier 0 clamps to the Career's own level 1)", status_t0_ok])
	screen_t0.queue_free()
	for i in range(3):
		await tree.process_frame

	## Same encounter roll isn't guaranteed to repeat, so this doesn't
	## compare exact numbers against baseline_wp directly — instead it
	## re-derives what the SAME NPC's own pre-bonus stats would have
	## been (encounter_def.npc_willpower, per the legacy single-NPC
	## synthesis path every one of the 12 core encounters still uses —
	## see SocialEncounterDefinition.get_npcs()) and checks the seated
	## Character reflects exactly that plus the Tier 4 bonus.
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	game_state.current_social_difficulty_tier = 4
	var screen_t4: Control = scene_res.instantiate()
	tree.get_root().add_child(screen_t4)
	for i in range(10):
		await tree.process_frame

	var wiring_ok := false
	var status_t4_ok := false
	if not screen_t4.npc_characters.is_empty() and screen_t4.encounter_def != null:
		var npc4: Character = screen_t4.npc_characters[0]
		var base_wp: int = screen_t4.encounter_def.npc_willpower
		var base_composure := 10   ## SocialEncounterDefinition.get_npcs()'s own synthesized default (halved per the "too much health" request)
		wiring_ok = npc4.characteristics.willpower == base_wp + 40 and npc4.composure_max == base_composure + 4
		var expected_status_t4 := _expected_status_ordinal(screen_t4.encounter_def.portrait_career_key, 4)
		status_t4_ok = screen_t4.npc_status_ordinal_by_char.get(npc4, -1) == expected_status_t4
	checks.append(["Case 2: Tier 4 screen's seated NPC Willpower/Composure reflect the Tier bonus on top of its own base stats", wiring_ok])
	checks.append(["Case 2: Tier 4 screen's seated NPC Status matches its own real Career's Tier-4 Status", status_t4_ok])
	screen_t4.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Case 3: the "never Tier 0" floor, per the follow-up request
	## ("let social encounter difficulty tier minimum be 1, ie. never
	## 0... but let that rule affect nothing else"). Forces a real Tier
	## 0 area (empty difficulty_areas + default_difficulty_tier 0) on a
	## live Overworld instance and clicks a social marker planted in it —
	## proves _on_social_marker_clicked() floors current_social_
	## difficulty_tier at 1 while get_difficulty_tier_at() itself (what
	## combat reads) still genuinely reports 0 for that exact same tile,
	## i.e. the floor is social-only, not baked into the shared lookup.
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(15):
		await tree.process_frame

	var empty_areas: Array[DifficultyAreaDefinition] = []
	ow.difficulty_areas = empty_areas
	ow.default_difficulty_tier = 0
	var marker_tile: Vector2i = ow.player.grid_pos
	ow.social_marker_tile = marker_tile
	ow.social_marker_encounter = null

	checks.append(["Case 3: the forced area genuinely reports Tier 0 (the shared lookup itself is untouched)", ow.get_difficulty_tier_at(marker_tile) == 0])

	ow._on_social_marker_clicked()
	## _on_social_marker_clicked() is a coroutine (it awaits a timer
	## before the scene change) but the tier assignment happens BEFORE
	## its first await, so calling it without awaiting still lets this
	## check run against the already-assigned value on the very next
	## line — no frame wait needed.
	checks.append(["Case 3: clicking a marker in a real Tier 0 area still sets current_social_difficulty_tier to 1, not 0", game_state.current_social_difficulty_tier == 1])
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
	print("RESULT (Social Combat Difficulty Tier): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
