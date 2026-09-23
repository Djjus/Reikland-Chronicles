extends RefCounted
class_name CharacterGenderPersistenceTest
## Per the request ("the game is not recording gender, female character
## reset to male after restarting the game. can we fix this
## retrospectively and turn any char that was made female is turned
## back"): Character.gender was a real, correctly-typed field but was
## never written to or read from Character.to_save_dict()/
## from_save_dict() — every save/reload silently dropped it back to the
## class default ("male"). This test guards the actual bug: a female
## character's gender must survive a full to_save_dict() -> JSON ->
## from_save_dict() round trip, exactly like SaveManager performs for
## real saves. It also confirms old saves (written before this fix, with
## no "gender" key at all) still load without error and fall back to
## "male" -- the same value they'd have shown anyway, so this is a
## no-op for existing saves, not a behaviour change for them.
##
## The retroactive side of the request -- restoring whichever
## character(s) the player already had reset to male by the bug -- can't
## be done automatically: the save file never recorded which character
## was female, so there's no data left to recover it from. Instead,
## character_menu_screen.gd now has an always-visible "Toggle Gender"
## button right next to the Gender display, so the player can self-
## correct any affected character with one click. See
## CharacterMenuGenderToggleTest for that half.

static func run_test(_tree: SceneTree) -> bool:
	var checks: Array = []

	var race := GameData.find_race("Human")
	var career := GameData.find_career("Outlaw")
	checks.append(["Test fixture: Human race is registered", race != null])
	checks.append(["Test fixture: Outlaw career is registered", career != null])
	if race == null or career == null:
		print("RESULT (Character Gender Persistence): SOME FAILED (missing test fixtures)")
		return false

	## --- A female character survives a real save/load round trip -------
	var female_char := Character.new()
	female_char.character_name = "Rosalind Vane"
	female_char.race = race
	female_char.career = career
	female_char.characteristics = CharacteristicSet.new()
	female_char.gender = "female"
	var female_json := JSON.stringify(female_char.to_save_dict())
	var female_loaded := Character.from_save_dict(JSON.parse_string(female_json))
	checks.append(["A female character's gender is still 'female' after a full save/load round trip", female_loaded != null and female_loaded.gender == "female"])

	## --- A male character survives the same round trip ------------------
	var male_char := Character.new()
	male_char.character_name = "Tomas Grier"
	male_char.race = race
	male_char.career = career
	male_char.characteristics = CharacteristicSet.new()
	male_char.gender = "male"
	var male_json := JSON.stringify(male_char.to_save_dict())
	var male_loaded := Character.from_save_dict(JSON.parse_string(male_json))
	checks.append(["A male character's gender is still 'male' after a full save/load round trip", male_loaded != null and male_loaded.gender == "male"])

	## --- Backward compatibility: old saves have no "gender" key at all --
	var old_save_dict := female_char.to_save_dict()
	old_save_dict.erase("gender")
	checks.append(["Fixture: the simulated old save genuinely has no 'gender' key", not old_save_dict.has("gender")])
	var old_loaded := Character.from_save_dict(old_save_dict)
	checks.append(["A pre-fix save with no 'gender' key still loads (doesn't error/return null)", old_loaded != null])
	checks.append(["...and falls back to 'male', matching the pre-fix behaviour exactly (no surprise change for existing saves)", old_loaded != null and old_loaded.gender == "male"])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Gender Persistence): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
