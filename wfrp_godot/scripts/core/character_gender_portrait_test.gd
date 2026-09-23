extends RefCounted
class_name CharacterGenderPortraitTest
## Verifies the "female character option" feature, per the request
## ("time to add female character option, here are their portraits" and
## the follow-up "wire it up to the Social NPCs too"):
## CareerPortraits now resolves a second, full art set
## (assets/portraits/careers_female/) by gender, Character.gender drives
## get_portrait_for_character(), CharacterCreationScreen lets the player
## pick it (and the preview portrait actually updates), and Social
## Combat's NPC roster carries the encounter's own rolled/forced gender
## through to its portrait too.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: CareerPortraits.get_portrait()/path_for() by gender,
	## in isolation from any scene. "Soldier" is a real Career present
	## in both assets/portraits/careers/ and .../careers_female/.
	var male_tex := CareerPortraits.get_portrait("Soldier", "male")
	var female_tex := CareerPortraits.get_portrait("Soldier", "female")
	checks.append(["Case 1: get_portrait('Soldier','male') resolves to real art", male_tex != null])
	checks.append(["Case 1: get_portrait('Soldier','female') resolves to real art", female_tex != null])
	checks.append(["Case 1: the male and female Soldier portraits are different textures", male_tex != female_tex])
	checks.append(["Case 1: get_portrait('Soldier') with no gender arg defaults to the male set", CareerPortraits.get_portrait("Soldier") == male_tex])
	checks.append(["Case 1: path_for('Soldier','female') actually points into careers_female/", CareerPortraits.path_for("Soldier", "female").contains("careers_female")])

	## Fallback: a career with no real female art (a made-up name) still
	## resolves the SAME path shape as the male-only lookup, rather than
	## erroring or pointing at a nonexistent careers_female/ file.
	var fake_name := "Zzz Nonexistent Career"
	checks.append(["Case 1: path_for() for a career with no female art falls back to the male path shape", CareerPortraits.path_for(fake_name, "female") == CareerPortraits.path_for(fake_name, "male")])

	## --- Case 2: get_portrait_for_character() reads Character.gender.
	var soldier_career: CareerDefinition = GameData.find_career("Soldier")
	var male_char := Character.new()
	male_char.career = soldier_career
	male_char.gender = "male"
	var female_char := Character.new()
	female_char.career = soldier_career
	female_char.gender = "female"
	var no_gender_char := Character.new()
	no_gender_char.career = soldier_career
	no_gender_char.gender = ""   ## an old save/Character predating this field's default

	checks.append(["Case 2: get_portrait_for_character() returns the female art for gender='female'", CareerPortraits.get_portrait_for_character(female_char) == female_tex])
	checks.append(["Case 2: get_portrait_for_character() returns the male art for gender='male'", CareerPortraits.get_portrait_for_character(male_char) == male_tex])
	checks.append(["Case 2: an empty/unset gender still resolves to the male set, not null/fallback", CareerPortraits.get_portrait_for_character(no_gender_char) == male_tex])
	checks.append(["Case 2: Character.gender defaults to 'male' on a fresh Character", Character.new().gender == "male"])

	## --- Case 3: CharacterCreationScreen's Gender picker actually drives
	## the live preview portrait (Step 1's char_gender state).
	var cc_scene: PackedScene = load("res://scenes/CharacterCreation.tscn")
	var cc: Control = cc_scene.instantiate()
	tree.get_root().add_child(cc)
	for i in range(5):
		await tree.process_frame
	checks.append(["Case 3: CharacterCreationScreen defaults to 'male'", cc.char_gender == "male"])
	cc.selected_race = GameData.find_race("Human")
	cc.selected_career = soldier_career
	cc.char_gender = "female"
	cc._render_summary_header()
	checks.append(["Case 3: setting char_gender to 'female' updates the summary preview portrait", cc.summary_portrait.texture == female_tex])
	cc.char_gender = "male"
	cc._render_summary_header()
	checks.append(["Case 3: switching back to 'male' updates it back", cc.summary_portrait.texture == male_tex])
	cc.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Case 4: Social Combat NPC roster carries the encounter's own
	## rolled/forced gender through to its portrait (the "wire it up to
	## the Social NPCs too" follow-up). Forces a known name+gender via
	## GameState.pending_social_npc_name/gender (an existing mechanism —
	## see social_encounter_screen.gd's own _ready()), same as any
	## scripted/quest-bound social NPC would use.
	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var db: SocialEncounterDatabase = GameData.social_encounter_db
	var enc: SocialEncounterDefinition = db.encounters[0] if not db.encounters.is_empty() else null
	checks.append(["Case 4: a real core Social Encounter exists to test against", enc != null])

	if enc != null:
		GameState.pending_social_encounter_name = enc.encounter_name
		GameState.pending_social_npc_name = "Test Forcedwoman"
		GameState.pending_social_npc_gender = "female"
		GameState.pending_social_situation_index = 0
		GameState.pending_social_opening_flavor_index = 0
		var expected_female_tex := CareerPortraits.get_portrait(enc.portrait_career_key, "female")
		var ses = load("res://scenes/SocialEncounter.tscn").instantiate()
		tree.get_root().add_child(ses)
		tree.current_scene = ses
		for i in range(10):
			await tree.process_frame
		checks.append(["Case 4: forcing the social NPC's gender to female shows the female portrait pre-Social-Combat", ses.npc_portrait_rect.texture == expected_female_tex])
		var first_npc: Character = ses.npc_characters[0] if not ses.npc_characters.is_empty() else null
		checks.append(["Case 4: the seated Social Combat NPC's own Character.gender matches the forced gender", first_npc != null and first_npc.gender == "female"])
		ses.queue_free()
		for i in range(3):
			await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Gender Portrait): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
