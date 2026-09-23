extends RefCounted
class_name ContainerTrappingTest
## Per the request ("a number of items that where provided to
## characters during char creation are actually unusable, like
## 'Backpack containing Tinderbox, Blanket, Rations (1 day)', this
## should actually be 4 separate items which narratively where just
## described as being inside the backpack. Lets resolve these, and
## make the solution fix any current unusable items if possible"):
## confirms every known "<Container> containing <contents...>" starting
## trapping (class_trappings_table.gd's own Academic/Burgher/Courtier/
## Peasant/Ranger/Riverfolk/Rogue entries, plus the Artist/Duellist/
## Herbalist/Spy Career trappings in data/careers/*.tres) now splits
## into real, separate, individually usable inventory items via
## AmmoLookup.resolve_trapping() — the container itself becomes a real,
## equippable ItemDefinition instead of an inert, no-match string, and
## each of its former "contents" becomes its own standalone entry; a
## content token with an exact real-item naming mismatch (e.g.
## "Rations (1 day)" vs. the real "Rations, 1 day") gets normalized via
## the existing KNOWN_TRAPPING_RENAMES table. Also confirms this reaches
## a real end-to-end CharacterCreator.create_character() call (not just
## the resolver in isolation), and that a character SAVED before this
## fix — one whose inventory still literally contains the old broken
## compound string — gets migrated automatically the next time
## Character.from_save_dict() loads it.

## Every "<Container> containing <contents...>" starting trapping this
## project currently has, paired with the exact split it should
## resolve to. Sourced directly from class_trappings_table.gd's FIXED
## dict and the four data/careers/*.tres entries found via a full-repo
## grep for the literal word "containing" — if a new one is ever added
## to either source without a matching case here, this test won't
## catch it, but every entry that exists as of this fix is covered.
const KNOWN_CONTAINING_TRAPPINGS := {
	"Sling Bag containing Writing Kit": ["Sling Bag", "Writing Kit"],
	"Sling Bag containing Lunch": ["Sling Bag", "Lunch"],
	"Pouch containing Tweezers, Ear Pick, and a Comb": ["Pouch", "Tweezers", "Ear Pick", "Comb"],
	"Sling Bag containing Rations (1 day)": ["Sling Bag", "Rations, 1 day"],
	"Backpack containing Tinderbox, Blanket, Rations (1 day)": ["Backpack", "Tinderbox", "Blanket", "Rations, 1 day"],
	"Sling Bag containing a Flask of Spirits": ["Sling Bag", "Flask of Spirits"],
	"Sling Bag containing 2 Candles": ["Sling Bag", "Candle (dozen)"],
	"Sling Bag containing Trade Tools (Artist)": ["Sling Bag", "Trade Tools (Artist)"],
	"Sling Bag containing Clothing and 1d10 Bandages": ["Sling Bag", "Clothing", "1d10 Bandages"],
	"Sling Bag containing Assortment of Herbs": ["Sling Bag", "Assortment of Herbs"],
	"Sling Bag containing 2 different sets of clothing and Hooded Cloak": ["Sling Bag", "2 different sets of clothing", "Hooded Cloak"],
}

## Real ItemDefinition/WeaponDefinition/ArmourDefinition container names
## used above — checked separately for "is this genuinely equippable
## now" rather than folded into the exact-split check, so a future
## content-splitting tweak doesn't accidentally stop testing the part
## that matters most (the container becoming real).
const REAL_CONTAINER_NAMES := ["Backpack", "Sling Bag", "Pouch"]

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Every known compound string splits exactly as expected --------
	for trapping in KNOWN_CONTAINING_TRAPPINGS:
		var expected: Array = KNOWN_CONTAINING_TRAPPINGS[trapping]
		var actual: Array[String] = AmmoLookup.resolve_trapping(trapping)
		checks.append(["'%s' splits into %s" % [trapping, str(expected)], actual == expected])

	## --- Every real container name used above is a genuine, equippable
	## ItemDefinition with its own container slot --------------------------
	for container_name in REAL_CONTAINER_NAMES:
		var def: ItemDefinition = GameData.item_db.find_by_name(container_name)
		checks.append(["'%s' is a real ItemDefinition with a container slot" % container_name, def != null and def.container_slot != ""])

	## --- Renamed content tokens land on the real ItemDefinition name ----
	var rations_def: ItemDefinition = GameData.item_db.find_by_name("Rations, 1 day")
	checks.append(["The real item database spells it 'Rations, 1 day' (the renamed form), confirming the rename target is correct", rations_def != null])
	var candle_def: ItemDefinition = GameData.item_db.find_by_name("Candle (dozen)")
	checks.append(["'2 Candles' resolves to the real 'Candle (dozen)' ItemDefinition", candle_def != null and AmmoLookup.resolve_trapping("2 Candles") == ["Candle (dozen)"]])

	## --- Idempotency: an already-resolved, ordinary item name (real or
	## fallback-priced) is returned completely unchanged, so running the
	## resolver again (e.g. on every save load) never double-processes
	## or corrupts a normal inventory ---------------------------------------
	checks.append(["An ordinary already-resolved weapon name passes through unchanged", AmmoLookup.resolve_trapping("Sword") == ["Sword"]])
	checks.append(["A real container name on its own (no 'containing' clause) passes through unchanged", AmmoLookup.resolve_trapping("Backpack") == ["Backpack"]])
	checks.append(["A no-database-entry starting trapping with no 'containing' clause (e.g. Cloak) still passes through unchanged, exactly as before this fix", AmmoLookup.resolve_trapping("Cloak") == ["Cloak"]])

	## --- Real end-to-end character creation: Ranger's Class Trappings
	## ("Backpack containing Tinderbox, Blanket, Rations (1 day)") genuinely
	## lands as 4 separate inventory entries on a freshly created character,
	## not just in the resolver's own isolated unit checks above -----------
	var human: RaceDefinition = GameData.find_race("Human")
	var ranger_career: CareerDefinition = null
	for c in GameData.careers:
		if c.career_class == "Ranger":
			ranger_career = c
			break
	checks.append(["Found a real Ranger-class career to create a test character with", ranger_career != null])
	if human != null and ranger_career != null:
		var class_trappings: Array = []
		ClassTrappingsTable.grant_to("Ranger", class_trappings)
		checks.append(["ClassTrappingsTable still hands back the raw, unresolved compound string (the resolving happens in CharacterCreator, not here) — confirms this test is exercising the real fix location, not a stale copy", class_trappings.has("Backpack containing Tinderbox, Blanket, Rations (1 day)")])

		var new_character: Character = CharacterCreator.create_character(
			"Test Ranger", human, ranger_career, {}, [], 0, [], [], [], {}, "", class_trappings)
		checks.append(["A freshly created character exists", new_character != null])
		if new_character != null:
			checks.append(["The compound string itself never appears anywhere in the finished character's real inventory", not new_character.inventory.has("Backpack containing Tinderbox, Blanket, Rations (1 day)")])
			checks.append(["...the real, separate Backpack is there instead", new_character.inventory.has("Backpack")])
			checks.append(["...and Tinderbox", new_character.inventory.has("Tinderbox")])
			checks.append(["...and Blanket", new_character.inventory.has("Blanket")])
			checks.append(["...and the renamed 'Rations, 1 day' (not the mismatched 'Rations (1 day)')", new_character.inventory.has("Rations, 1 day") and not new_character.inventory.has("Rations (1 day)")])

			## The Backpack is now genuinely equippable for its real
			## Carrying Capacity bonus — the whole point of splitting it
			## out, not just a cosmetic renaming.
			var capacity_before := new_character.get_carrying_capacity()
			new_character.set_equipped_container("Back", "Backpack")
			checks.append(["The split-out Backpack can genuinely be equipped for a real Carrying Capacity bonus", new_character.get_carrying_capacity() > capacity_before])

	## --- Save/load migration: a character saved BEFORE this fix, whose
	## inventory still literally contains the old broken compound string,
	## gets migrated automatically the next time it loads -------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var migrate_character: Character = GameState.player_character
	migrate_character.inventory = ["Backpack containing Tinderbox, Blanket, Rations (1 day)", "Sword"]
	var legacy_save: Dictionary = migrate_character.to_save_dict()
	checks.append(["Sanity: the legacy save dict genuinely still has the old broken compound string in it (proving this check exercises real migration, not a no-op)", (legacy_save.get("inventory", []) as Array).has("Backpack containing Tinderbox, Blanket, Rations (1 day)")])

	var json_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(legacy_save))
	var reloaded: Character = Character.from_save_dict(json_roundtrip)
	checks.append(["A reloaded legacy character exists", reloaded != null])
	if reloaded != null:
		checks.append(["Reloading a legacy save with the old broken compound string in it splits it automatically — the compound string itself is gone", not reloaded.inventory.has("Backpack containing Tinderbox, Blanket, Rations (1 day)")])
		checks.append(["...replaced by the real, separate Backpack", reloaded.inventory.has("Backpack")])
		checks.append(["...Tinderbox", reloaded.inventory.has("Tinderbox")])
		checks.append(["...Blanket", reloaded.inventory.has("Blanket")])
		checks.append(["...and the renamed Rations, 1 day", reloaded.inventory.has("Rations, 1 day")])
		checks.append(["An ordinary, already-fine item in the same legacy save (Sword) survives the migration untouched", reloaded.inventory.has("Sword")])
		checks.append(["The migration didn't invent extra items — exactly 5 inventory entries (Backpack/Tinderbox/Blanket/Rations, 1 day/Sword)", reloaded.inventory.size() == 5])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Container Trapping Splitting + Migration Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
