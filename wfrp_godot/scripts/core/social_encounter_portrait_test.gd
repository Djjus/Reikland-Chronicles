extends RefCounted
class_name SocialEncounterPortraitTest
## Verifies the "NPC portraits" feature: every one of the 12 core Social
## Encounters has a portrait_career_key that actually resolves to a
## real, non-fallback CareerPortraits texture (not a silent fallback to
## the generic default — that would mean a typo'd/missing key slipped
## through), and that the live SocialEncounterScreen actually shows a
## texture for both the NPC and each present party member.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: every core encounter's portrait_career_key resolves
	## to a real file, not the generic fallback.
	var fallback_tex: Texture2D = load(CareerPortraits.FALLBACK_PATH) as Texture2D
	var db: SocialEncounterDatabase = GameData.social_encounter_db
	var checked_count := 0
	for enc: SocialEncounterDefinition in db.encounters:
		checked_count += 1
		var key: String = enc.portrait_career_key
		var resolved: Texture2D = CareerPortraits.get_portrait(key)
		checks.append(["Case 1: '%s' has a non-empty portrait_career_key" % enc.encounter_name, key != ""])
		checks.append(["Case 1: '%s's portrait_career_key ('%s') resolves to real art, not null/fallback" % [enc.encounter_name, key], resolved != null and resolved != fallback_tex])
	checks.append(["Case 1: actually checked all 12 core encounters", checked_count == 12])

	## --- Case 2: a live SocialEncounterScreen shows a real NPC
	## portrait texture and at least one party portrait.
	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var ses = load("res://scenes/SocialEncounter.tscn").instantiate()
	tree.get_root().add_child(ses)
	tree.current_scene = ses
	for i in range(10):
		await tree.process_frame

	checks.append(["Case 2: the NPC portrait TextureRect has a real texture", ses.npc_portrait_rect.texture != null])
	checks.append(["Case 2: at least one party portrait was built", ses.party_portraits_box.get_child_count() >= 1])
	## Per the Social Combat follow-up: each party portrait now sits in a
	## small VBox alongside its own Composure bar (see
	## social_encounter_screen.gd's own _build_party_portraits()), so the
	## portrait itself is no longer party_portraits_box's own direct
	## child — party_portrait_rects (Character -> TextureRect) is the
	## screen's own public map straight to the real TextureRect node.
	var first_portrait: TextureRect = ses.party_portrait_rects.values()[0] if not ses.party_portrait_rects.is_empty() else null
	checks.append(["Case 2: the first party portrait has a real texture", first_portrait != null and first_portrait.texture != null])

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
	print("RESULT (Social Encounter Portraits): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
