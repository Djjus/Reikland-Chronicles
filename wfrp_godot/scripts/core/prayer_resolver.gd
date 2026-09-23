extends RefCounted
class_name PrayerResolver
## Implements the core rulebook's Blessings and Miracles rules (p.217-218),
## including the full Sin Points and Wrath of the Gods system. Table
## wording below is original, not copied text — the roll ranges and
## mechanical effects match the book's own 30-entry table (percentile
## rolls 1 through 151+, since Sin points add +10 each to the roll and
## can push it well past 100).

## Each entry's "tags" work like Miscast's (MagicResolver), with one
## addition: "condition_sin:NAME:BASE" and "wounds_sin:XdY" scale their
## amount by the character's Sin points at the time of the roll — e.g.
## "Divine Wounds: Gain 1+Sin points Bleeding Conditions" is
## "condition_sin:Bleeding:1", giving 1 + current Sin stacks. Entries
## with no reliable single-character mechanical shape (multi-day Talent
## loss, summoned Daemons, "consult your GM") are left with empty tags,
## same principle as the Oops! and Miscast tables elsewhere in this
## project — kept honestly narrative rather than forced into an
## inaccurate mechanic.
const WRATH_OF_THE_GODS_TABLE := [
	{"min": 1, "max": 5, "text": "Holy Visions: unless you pass an Average (+20) Endurance Test, you gain a Stunned Condition.", "tags": ["save:endurance:then:condition:Stunned:1"]},
	{"min": 6, "max": 10, "text": "Think Over Your Deeds: any successful Pray Test cannot achieve more than +0 SL for the next week.", "tags": []},
	{"min": 11, "max": 15, "text": "Heed My Lessons: you suffer a penalty to Pray for a while.", "tags": []},
	{"min": 16, "max": 20, "text": "Prove Your Devotion: you gain the Prone Condition, removed only by a successful Average (+20) Pray Test.", "tags": ["condition:Prone:1"]},
	{"min": 21, "max": 25, "text": "You Try My Patience: you cannot enact any Pray Tests for a while.", "tags": []},
	{"min": 26, "max": 30, "text": "You Do Not Understand My Intent: a penalty lingers on Skills tied to your deity.", "tags": []},
	{"min": 31, "max": 35, "text": "I Find Your Lack Of Faith Disturbing: you cannot enact any Pray Tests for a longer while.", "tags": []},
	{"min": 36, "max": 40, "text": "Share My Pain: you suffer 1+Sin points Wounds, ignoring Toughness Bonus and Armour Points. Unless you pass an Average (+20) Endurance Test, you also gain a Stunned Condition.", "tags": ["wounds_sin:1", "save:endurance:then:condition:Stunned:1"]},
	{"min": 41, "max": 45, "text": "Your Cause Is Unworthy: your target gains the Prone Condition, and your Blessings/Miracles automatically fail against them for a while.", "tags": ["target_condition:Prone:1"]},
	{"min": 46, "max": 50, "text": "Cease Your Prattling: you cannot enact any Pray Tests for a long stretch.", "tags": []},
	{"min": 51, "max": 55, "text": "Feel My Wrath: you suffer 1d10+Sin points Wounds. Unless you pass a Challenging (+0) Endurance Test, you also gain a Stunned Condition.", "tags": ["wounds_sin:1d10", "save:endurance:then:condition:Stunned:1"]},
	{"min": 56, "max": 60, "text": "I Shall Not Aid You: a penalty lingers on a Skill tied to your deity.", "tags": []},
	{"min": 61, "max": 65, "text": "Divine Wounds: you gain 1+Sin points Bleeding Conditions.", "tags": ["condition_sin:Bleeding:1"]},
	{"min": 66, "max": 70, "text": "Struck Blind: you gain the Prone Condition and 1+Sin points Blinded Conditions, removed only by a successful Challenging (+0) Pray Test.", "tags": ["condition:Prone:1", "condition_sin:Blinded:1"]},
	{"min": 71, "max": 75, "text": "What Will You Sacrifice?: you suffer 1d10+Sin points Wounds, ignoring Toughness Bonus and Armour Points. Unless you pass a Difficult (–10) Endurance Test, you also gain a Stunned Condition.", "tags": ["wounds_sin:1d10", "save:endurance:then:condition:Stunned:1"]},
	{"min": 76, "max": 80, "text": "You Have Sinned Against Me: your god forces you to spend your Actions on Pray Tests for a while, as penance.", "tags": []},
	{"min": 81, "max": 87, "text": "Purge the Flesh: you suffer 2d10+Sin points Wounds, ignoring Toughness Bonus and Armour Points. Unless you pass a Hard (–20) Endurance Test, you gain a Stunned Condition — and a severe failure leaves you Unconscious.", "tags": ["wounds_sin:2d10", "save:endurance:then:condition:Stunned:1"]},
	{"min": 88, "max": 88, "text": "Daemonic Interference: the Dark Gods answer your pleas instead — Lesser Daemons appear nearby and attack the nearest targets.", "tags": []},
	{"min": 89, "max": 95, "text": "Fear My Wrath: you gain 1+Sin points Broken Conditions.", "tags": ["condition_sin:Broken:1"]},
	{"min": 96, "max": 100, "text": "Go On Penance: your god requires you undertake a Penance.", "tags": []},
	{"min": 101, "max": 105, "text": "Castigation: you're reduced to 0 Wounds and gain an Unconscious Condition, not removed until you regain at least 1 Wound.", "tags": ["wounds_to_zero", "condition:Unconscious:1"]},
	{"min": 106, "max": 110, "text": "Do Not Use My Name In Vain: you lose the Bless and Invoke Talents for a while.", "tags": []},
	{"min": 111, "max": 115, "text": "Rely Not Upon Your Vanities: all your trappings are stripped from you, returned one at a time as you complete Penances.", "tags": []},
	{"min": 116, "max": 120, "text": "You Abuse My Mercy: you lose the Invoke and Bless Talents for a longer while.", "tags": []},
	{"min": 121, "max": 125, "text": "Behold Your Wickedness: you suffer excruciating visions of your failures — work out a fitting Psychology with your GM.", "tags": []},
	{"min": 126, "max": 130, "text": "Thunderbolts and Lightning: your god smites you — reduced to 0 Wounds and set Ablaze.", "tags": ["wounds_to_zero", "condition:Ablaze:1"]},
	{"min": 131, "max": 135, "text": "Suffer As I Suffer: you gain 1+Sin points Bleeding Conditions every morning until you perform a Penance.", "tags": ["condition_sin:Bleeding:1"]},
	{"min": 136, "max": 140, "text": "Excommunication: you lose the Invoke and Bless Talents until you perform two Penances, and every cultist of your god knows of your fall.", "tags": []},
	{"min": 141, "max": 145, "text": "Prove Your Worth: a Divine Servant of your deity appears and attacks, intervenes, or berates you.", "tags": []},
	{"min": 146, "max": 150, "text": "I Cast You Out: you permanently lose the Bless and Invoke Talents and all Pray Advances — your god abandons you.", "tags": []},
	{"min": 151, "max": 999, "text": "Called To Account: you're summoned before your god for final judgement. Without a Fate Point, you never return; spending one returns you, but still costs everything I Cast You Out does.", "tags": []},
]

class PrayerResult:
	var test_result: TestResolver.TestResult
	var success: bool = false
	var fumble: bool = false
	var wrath: Dictionary = {}   ## {"roll": int, "text": String, "tags": Array} if Wrath of the Gods was triggered

## Resolves a Pray Test (Challenging, +0 difficulty by default) to enact a
## Blessing or Miracle (p.217). A bare success manifests the prayer; SL
## above that can be spent on the prayer's own listed bonus effects
## (adjudicated narratively, same as Overcasting).
##
## Wrath of the Gods triggers two ways (p.217-218), both checked here:
## a Fumbled Pray Test, or — even on a SUCCESS — when the roll's units
## die is less than or equal to the character's current Sin points
## ("Sin and Wrath": "if the units die of the result is equal to or
## less than your current Sin point total, then you will suffer the
## Wrath of the Gods, even if the Pray Test is successful").
static func pray(character: Character, prayer: PrayerDefinition, modifier: int = 0) -> PrayerResult:
	var result := PrayerResult.new()
	var pray_skill: SkillDefinition = GameData.skill_db.find_by_name("Pray")
	result.test_result = TestResolver.resolve_skill_test(character, pray_skill, "", modifier)
	result.success = result.test_result.success
	result.fumble = result.test_result.is_fumble

	var units_die := result.test_result.roll % 10
	var sin_triggers_wrath := character.sin_points > 0 and units_die <= character.sin_points

	if result.fumble or sin_triggers_wrath:
		result.wrath = roll_wrath_of_the_gods(character)
	return result

## Rolls on the Wrath of the Gods table (p.218), applying the book's
## +10-per-Sin-point roll penalty with NO upper clamp — Sin can
## genuinely push the roll past 100 into the table's harsher upper
## tiers, which a fixed 1-100 clamp would silently make unreachable —
## then reduces the character's Sin by 1 (minimum 0) as the divine
## rebuke is "paid off" (p.218's own wording).
static func roll_wrath_of_the_gods(character: Character) -> Dictionary:
	var roll: int = Dice.d100() + character.sin_points * 10
	character.sin_points = max(0, character.sin_points - 1)
	for entry in WRATH_OF_THE_GODS_TABLE:
		if roll >= entry["min"] and roll <= entry["max"]:
			return {"roll": roll, "text": entry["text"], "tags": entry["tags"]}
	return {}

## Applies a Wrath entry's real mechanical tags to `character`, mirroring
## MagicResolver.apply_miscast_tags but adding the Sin-scaled variants
## ("condition_sin"/"wounds_sin": base amount + current Sin points) and
## "wounds_to_zero" (reduced straight to 0 Wounds, not a dice roll).
## Returns human-readable lines describing what actually happened.
static func apply_wrath_tags(character: Character, tags: Array) -> Array[String]:
	var lines: Array[String] = []
	for tag in tags:
		var parts: Array = str(tag).split(":")
		if parts[0] == "wounds_to_zero":
			character.wounds_current = 0
			lines.append("%s is reduced to 0 Wounds." % character.character_name)
		elif parts[0] == "condition_sin" and parts.size() >= 3:
			var cond_name: String = parts[1]
			var base: int = int(parts[2])
			var stacks: int = base + character.sin_points
			character.add_condition(cond_name, stacks)
			lines.append("%s gains %d stack(s) of %s (%d base + %d Sin)." % [character.character_name, stacks, cond_name, base, character.sin_points])
		elif parts[0] == "wounds_sin" and parts.size() >= 2:
			var dice_spec: String = parts[1]
			var rolled := Dice.roll_dice_string(dice_spec) if dice_spec.find("d") != -1 else int(dice_spec)
			var total_wounds := rolled + character.sin_points
			character.wounds_current = max(0, character.wounds_current - total_wounds)
			lines.append("%s suffers %d Wound(s) (%d rolled + %d Sin), ignoring Toughness and Armour." % [character.character_name, total_wounds, rolled, character.sin_points])
		elif parts[0] == "target_condition":
			## Applied to whoever the Blessing/Miracle targeted, not the
			## caster — handled by the caller, which has that reference;
			## nothing to do here beyond noting it in the text already.
			pass
		else:
			lines.append_array(MagicResolver.apply_miscast_tags(character, [tag]))
	return lines
