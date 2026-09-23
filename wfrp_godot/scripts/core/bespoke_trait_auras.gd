extends RefCounted
class_name BespokeTraitAuras
## Per the request: a reusable *pattern* for bespoke, one-off Creature
## Traits with their own sub-table — genuinely custom mechanics
## (like an ongoing aura the whole party must resist every Round)
## that a base game engine has no generic slot for, but that this
## project's own existing Condition/Corruption tag system (see
## MagicResolver.apply_miscast_tags(), already shared by Magic
## Miscasts and Prayer failures) is perfectly suited to wire into —
## the same "roll a d10, look up a {min, max, text, tags} entry,
## apply the tags" shape those two systems already use.
##
## Adding a new bespoke aura trait means: one new entry in
## AURA_TRAITS below (the resisting Test's own skill/characteristic
## and difficulty, the sub-table itself, and any extra tags that fire
## specifically on a Fumble), written in this project's own original
## wording. No new engine code is needed unless a specific sub-table
## entry calls for a mechanical effect the existing tag vocabulary
## genuinely doesn't cover yet — in which case that gap is the one
## thing that's genuinely bespoke, exactly as the request expects
## ("even if each one still needs individual code").
##
## Maddening Aura (the Jabberslythe's own Trait, WFRP p.17 Ubersreik
## Adventures: The Mad Men of Gotheim) is the concrete worked example
## below — an Average (+20) Cool Test every Round for every living
## combatant on the opposing side of anyone with this Trait, rolling
## on Creeping Irrationality on a failure, with a Fumble additionally
## costing a Mental Corruption Point. All wording is this project's
## own original writing, adapted from the general shape of the
## effect, not copied text.
const AURA_TRAITS := {
	"Maddening Aura": {
		"test_name": "Cool",
		"test_difficulty": 20,
		"fumble_tags": ["mental_corruption"],
		## A few of these entries are honestly left with empty tags —
		## "repeat your exact previous Round" and "Move or Action, not
		## both, then shake it off" don't have a clean single-
		## Character mechanical home in this project's turn structure
		## yet, so they're kept as real, visible narrative beats
		## rather than forced into an inaccurate substitute — the same
		## principle the Magic Miscast tables already use for their
		## own scenery-only entries.
		"sub_table": [
			{"min": 1, "max": 2, "text": "A wave of caution grips you — you hesitate, second-guessing every motion, before the feeling passes."},
			{"min": 3, "max": 4, "text": "The creature's presence scrambles your thoughts for a heartbeat, and you're caught flat-footed.", "tags": ["condition:Surprised:1"]},
			{"min": 5, "max": 6, "text": "A conviction seizes you that whatever you were just doing is exactly right — you find yourself repeating it, unable to think past the compulsion."},
			{"min": 7, "max": 7, "text": "A senseless, gnawing suspicion of everyone around you takes root, impossible to reason away."},
			{"min": 8, "max": 8, "text": "Something about the nearest face in view fills you with sudden, irrational loathing."},
			{"min": 9, "max": 9, "text": "All caution burns away in a red haze — nothing matters now but violence.", "tags": ["condition:Frenzy:1"]},
			{"min": 10, "max": 10, "text": "Something in your mind gives way, quietly and permanently.", "tags": ["mental_corruption"]},
		],
	},
}

## Checked once at the start of every Round — per the request's own
## "wiring a custom trait into the existing Condition/Corruption
## systems" framing, this reuses MagicResolver.apply_miscast_tags()
## directly rather than a parallel effect-application system. This
## project doesn't track battlefield range, so "everyone within X
## yards" becomes "every living combatant on the opposing side of
## whoever has the Trait" — the same simplification already used
## elsewhere for Distracting.
static func check_round_start_auras(combatants: Array) -> Array[String]:
	var lines: Array[String] = []
	var living: Array = []
	for c in combatants:
		if c.wounds_current > 0:
			living.append(c)
	for source in living:
		for trait_name in AURA_TRAITS:
			if not source.has_creature_trait(trait_name):
				continue
			var aura: Dictionary = AURA_TRAITS[trait_name]
			for target in living:
				if target == source or target.allegiance == source.allegiance:
					continue
				var test_result: TestResolver.TestResult
				var skill_def: SkillDefinition = GameData.skill_db.find_by_name(str(aura.get("test_name", "")))
				var difficulty: int = int(aura.get("test_difficulty", 0))
				if skill_def != null:
					test_result = TestResolver.resolve_skill_test(target, skill_def, "", difficulty)
				else:
					test_result = TestResolver.resolve_characteristic_test(target, str(aura["test_name"]).to_lower(), difficulty)
				if test_result.success:
					continue
				lines.append("[b]%s[/b] is shaken by %s's %s!" % [target.character_name, source.character_name, trait_name])
				var roll := randi_range(1, 10)
				for entry in aura["sub_table"]:
					if roll >= int(entry["min"]) and roll <= int(entry["max"]):
						lines.append(str(entry.get("text", "")))
						lines.append_array(MagicResolver.apply_miscast_tags(target, entry.get("tags", [])))
						break
				if test_result.is_fumble:
					lines.append_array(MagicResolver.apply_miscast_tags(target, aura.get("fumble_tags", [])))
				## Same Corruption Threshold check as every other
				## Corruption-Point source — see CorruptionResolver.
				var mutation_notice := CorruptionResolver.check_and_apply_threshold(target)
				if mutation_notice != "":
					lines.append(mutation_notice)
	return lines
