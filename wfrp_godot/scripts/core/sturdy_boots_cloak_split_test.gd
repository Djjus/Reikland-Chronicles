extends RefCounted
class_name SturdyBootsCloakSplitTest
## Per the request ("separate 'Sturdy Boots and Cloak' into separate
## items, and make this change retro active again to all existing
## items"): Scout's and Hunter's own starting trappings (data/careers/
## scout.tres, hunter.tres) list "Sturdy Boots and Cloak" as a single
## compound string, which previously became one unsplit, unusable
## "item" — same broken shape as the "<Container> containing
## <contents...>" bug ContainerTrappingTest already covers, just
## without the "containing" keyword. Fixed via the same established
## mechanism: a new KNOWN_COMPOUND_TRAPPINGS entry in ammo_lookup.gd.
## This test mirrors ContainerTrappingTest's own structure: the raw
## resolver split, a real end-to-end CharacterCreator.create_character()
## call for the Scout career, and a real save/load migration proving
## an existing character stuck with the old compound string gets fixed
## automatically the next time their save loads.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- The raw split itself ------------------------------------------
	var resolved: Array[String] = AmmoLookup.resolve_trapping("Sturdy Boots and Cloak")
	checks.append(["'Sturdy Boots and Cloak' splits into ['Sturdy Boots', 'Cloak']", resolved == ["Sturdy Boots", "Cloak"]])

	## --- Idempotency: the two split-out pieces, taken alone, still pass
	## through unchanged (same no-database-entry fallback-price path
	## 'Cloak' alone already used before this change) ----------------------
	checks.append(["'Sturdy Boots' alone passes through unchanged", AmmoLookup.resolve_trapping("Sturdy Boots") == ["Sturdy Boots"]])
	checks.append(["'Cloak' alone passes through unchanged", AmmoLookup.resolve_trapping("Cloak") == ["Cloak"]])

	## --- Real end-to-end character creation: Scout's own Tier-1
	## trapping list literally contains "Sturdy Boots and Cloak" ----------
	var human: RaceDefinition = GameData.find_race("Human")
	var scout_career: CareerDefinition = null
	for c in GameData.careers:
		if c.career_name == "Scout":
			scout_career = c
			break
	checks.append(["Found the real Scout career to create a test character with", scout_career != null])
	if human != null and scout_career != null:
		var level := scout_career.get_level(1)
		checks.append(["Sanity: Scout's own Tier 1 trappings still list the raw, unresolved compound string (confirms this test exercises the real fix location)", level != null and level.trappings.has("Sturdy Boots and Cloak")])

		var new_character: Character = CharacterCreator.create_character(
			"Test Scout", human, scout_career, {}, [], 0, [], [], [], {}, "", [])
		checks.append(["A freshly created Scout exists", new_character != null])
		if new_character != null:
			checks.append(["The compound string itself never appears anywhere in the finished character's real inventory", not new_character.inventory.has("Sturdy Boots and Cloak")])
			checks.append(["...the real, separate Sturdy Boots is there instead", new_character.inventory.has("Sturdy Boots")])
			checks.append(["...and Cloak", new_character.inventory.has("Cloak")])

	## --- Save/load migration: a character saved BEFORE this fix, whose
	## inventory still literally contains the old compound string, gets
	## migrated automatically the next time it loads ----------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var migrate_character: Character = GameState.player_character
	migrate_character.inventory = ["Sturdy Boots and Cloak", "Sword"]
	var legacy_save: Dictionary = migrate_character.to_save_dict()
	checks.append(["Sanity: the legacy save dict genuinely still has the old compound string in it", (legacy_save.get("inventory", []) as Array).has("Sturdy Boots and Cloak")])

	var json_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(legacy_save))
	var reloaded: Character = Character.from_save_dict(json_roundtrip)
	checks.append(["A reloaded legacy character exists", reloaded != null])
	if reloaded != null:
		checks.append(["Reloading a legacy save with the old compound string in it splits it automatically — the compound string itself is gone", not reloaded.inventory.has("Sturdy Boots and Cloak")])
		checks.append(["...replaced by the real, separate Sturdy Boots", reloaded.inventory.has("Sturdy Boots")])
		checks.append(["...and Cloak", reloaded.inventory.has("Cloak")])
		checks.append(["An ordinary, already-fine item in the same legacy save (Sword) survives the migration untouched", reloaded.inventory.has("Sword")])
		checks.append(["The migration didn't invent extra items — exactly 3 inventory entries (Sturdy Boots/Cloak/Sword)", reloaded.inventory.size() == 3])

	## --- Both split-out items are real, separately favouritable/
	## sellable inventory entries (not merged back down by any later
	## dedup logic) --------------------------------------------------------
	if reloaded != null:
		checks.append(["Sturdy Boots and Cloak are two genuinely distinct inventory entries, not one merged row", reloaded.inventory.count("Sturdy Boots") == 1 and reloaded.inventory.count("Cloak") == 1])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Sturdy Boots and Cloak Split + Migration Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
