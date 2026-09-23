extends RefCounted
class_name MagicResolver
## Implements the core rulebook's spellcasting rules (p.234-238), checked
## against the book rather than reconstructed: the Casting Test, Critical
## Casting bonus choices, Fumbled Casting, the Channelling Test for
## powering up spells over multiple rounds, and Overcasting. Table
## wording below is original, not copied text — the roll ranges and
## mechanical effects match the book.

## Each entry's "tags" describe the real mechanical consequence to
## apply, parsed by Character.apply_miscast_tags(): "condition:NAME:N"
## adds N stacks of a Condition, "corruption:N" adds Corruption points,
## "wounds_direct:XdY" deals wounds ignoring Toughness/Armour (matching
## the book's own "ignoring Toughness Bonus and APs" wording on the
## entries that say that), "save:SKILL:then:TAG" attempts a Test and
## only applies the following tag on failure. Entries with no reliable
## single-character mechanical shape (scenery/narrative effects, GM-
## adjudicated stuff, "everyone nearby") are left with empty tags —
## same principle as the Oops! table elsewhere in this project: kept
## honestly narrative rather than forced into an inaccurate mechanic.
const MINOR_MISCAST_TABLE := [
	{"min": 1, "max": 5, "text": "A nearby birth is touched by wild magic in some small, strange way.", "tags": []},
	{"min": 6, "max": 10, "text": "Every drop of milk within a wide radius turns sour in an instant.", "tags": []},
	{"min": 11, "max": 15, "text": "Crops for miles around wither overnight.", "tags": []},
	{"min": 16, "max": 20, "text": "Your ears clog with thick wax — you're Deafened until someone cleans them out.", "tags": ["condition:Deafened:1"]},
	{"min": 21, "max": 25, "text": "You glow like a bonfire, in a colour matching your Lore, for several rounds.", "tags": []},
	{"min": 26, "max": 30, "text": "A whisper of dread brushes your mind — resist or gain a Corruption point.", "tags": ["save:cool:then:corruption:1"]},
	{"min": 31, "max": 35, "text": "Your nose, eyes, and ears bleed profusely — several rounds of Bleeding.", "tags": ["condition:Bleeding:2"]},
	{"min": 36, "max": 40, "text": "The ground seems to lurch — you're knocked Prone.", "tags": ["condition:Prone:1"]},
	{"min": 41, "max": 45, "text": "Every buckle and lace on your person comes undone at once.", "tags": []},
	{"min": 46, "max": 50, "text": "Your own clothes seem to writhe and grasp — you're briefly Entangled.", "tags": ["condition:Entangled:1"]},
	{"min": 51, "max": 55, "text": "All alcohol nearby turns bitter and undrinkable.", "tags": []},
	{"min": 56, "max": 60, "text": "A wave of exhaustion leaves you Fatigued for a while.", "tags": ["condition:Fatigued:1"]},
	{"min": 61, "max": 65, "text": "You're badly startled — Surprised if already in combat, otherwise just rattled.", "tags": ["condition:Surprised:1"]},
	{"min": 66, "max": 70, "text": "Unsettling visions leave you Blinded; fight off a second bout with a Cool Test.", "tags": ["save:cool:then:condition:Blinded:1"]},
	{"min": 71, "max": 75, "text": "Your tongue trips over itself — a penalty to Language Tests, including future Casting Tests, for a while.", "tags": []},
	{"min": 76, "max": 80, "text": "Sheer horror threatens to break you — resist with a hard Cool Test or gain the Broken Condition.", "tags": ["save:cool:then:condition:Broken:1"]},
	{"min": 81, "max": 85, "text": "The touch of Chaos lingers — gain a Corruption point.", "tags": ["corruption:1"]},
	{"min": 86, "max": 90, "text": "The spell's effect happens somewhere else entirely, miles away, with unpredictable consequences.", "tags": []},
	{"min": 91, "max": 95, "text": "Misfortune compounds — roll twice more on this table.", "tags": ["roll_again:2"]},
	{"min": 96, "max": 100, "text": "Things spiral badly — roll on the Major Miscast Table instead.", "tags": []},
]

const MAJOR_MISCAST_TABLE := [
	{"min": 1, "max": 5, "text": "Whispers from the Realm of Chaos are heard by everyone nearby — resist or gain a Corruption point.", "tags": ["save:cool:then:corruption:1"]},
	{"min": 6, "max": 10, "text": "Your eyes take on an unnatural colour and you're Blinded for hours, no matter what you try.", "tags": ["condition:Blinded:3"]},
	{"min": 11, "max": 15, "text": "A shock of raw magic wounds you badly, ignoring armour, and may leave you Stunned.", "tags": ["wounds_direct:1d10", "save:endurance:then:condition:Stunned:1"]},
	{"min": 16, "max": 20, "text": "Plant life withers wherever you walk for the next several hours.", "tags": []},
	{"min": 21, "max": 25, "text": "Your body betrays you completely, leaving you Fatigued and humiliated.", "tags": ["condition:Fatigued:2"]},
	{"min": 26, "max": 30, "text": "You're wreathed in unholy flame — the Ablaze Condition.", "tags": ["condition:Ablaze:1"]},
	{"min": 31, "max": 35, "text": "You gabble uncontrollably, unable to speak clearly or cast for several rounds.", "tags": []},
	{"min": 36, "max": 40, "text": "Aethyric vermin swarm you for several rounds before retreating.", "tags": []},
	{"min": 41, "max": 45, "text": "You're hurled through the air and land hard, Prone and wounded.", "tags": ["condition:Prone:1", "wounds_direct:1d10"]},
	{"min": 46, "max": 50, "text": "One limb locks up entirely for hours, as good as lost until it passes.", "tags": []},
	{"min": 51, "max": 55, "text": "Your Second Sight falters for hours, and Channelling suffers for it.", "tags": []},
	{"min": 56, "max": 60, "text": "A reckless surge of power grants a pool of bonus Fortune points — but spending any of them courts Corruption.", "tags": ["fortune:1"]},
	{"min": 61, "max": 65, "text": "You're borne aloft on the Winds of Magic, floating helplessly for a while.", "tags": []},
	{"min": 66, "max": 70, "text": "Violent nausea leaves you Stunned for several rounds.", "tags": ["condition:Stunned:2"]},
	{"min": 71, "max": 75, "text": "A shockwave knocks everyone nearby Prone.", "tags": ["condition:Prone:1"]},
	{"min": 76, "max": 80, "text": "The Dark Gods whisper a tempting bargain — a dark boon awaits if you betray an ally.", "tags": []},
	{"min": 81, "max": 85, "text": "The backlash leaves you Prone, Fatigued, and touched by Corruption.", "tags": ["condition:Prone:1", "condition:Fatigued:1", "corruption:1"]},
	{"min": 86, "max": 90, "text": "You reek horribly for hours, an unmistakable and unpleasant presence.", "tags": []},
	{"min": 91, "max": 95, "text": "Your gift falters — the Talent you cast with is unusable for some minutes.", "tags": []},
	{"min": 96, "max": 100, "text": "The energy vents violently into everyone nearby, friend and foe alike, wounding and felling them — or, with nowhere to go, turns on you alone.", "tags": ["wounds_direct:2d10"]},
]

class CastResult:
	var test_result: TestResolver.TestResult
	var success: bool = false          ## SL met or exceeded the spell's CN
	var overcast_sl: int = 0           ## SL beyond CN, available to spend on Overcasting
	var critical: bool = false
	var fumble: bool = false
	var miscast: Dictionary = {}       ## {"tier": "minor"/"major", "roll": int, "text": String}

## Resolves a Casting Test for a spell (p.234). `effective_cn` lets
## callers apply Grimoire-doubling or a Channelling Test's CN-0 discount
## without mutating the spell data itself.
##
## Instinctive Diction (p.132): "Tests: Language (Magick) when casting"
## — the standard WFRP4e "Tests:" Talent pattern, +10 per rank to that
## Test — plus its own stated effect, "you do not suffer a Miscast if
## you roll a double on a successful Language (Magick) Test." Computed
## here from the caster directly rather than as a caller-supplied flag:
## a real, previously-existing bug meant no caller in this project ever
## actually passed has_instinctive_diction, so the Talent silently did
## nothing at all even though the parameter existed.
static func cast(caster: Character, spell: SpellDefinition, modifier: int = 0,
		effective_cn: int = -1, has_ingredient: bool = false) -> CastResult:
	var result := CastResult.new()
	var cn: int = spell.casting_number if effective_cn < 0 else effective_cn
	var language_magick: SkillDefinition = GameData.skill_db.find_by_name("Language (Magick)")
	var diction_rank := caster.get_talent_rank("Instinctive Diction")
	var has_instinctive_diction := diction_rank > 0

	result.test_result = TestResolver.resolve_skill_test(caster, language_magick, "", modifier + diction_rank * 10)
	result.critical = result.test_result.is_critical
	result.fumble = result.test_result.is_fumble

	if result.test_result.success and result.test_result.success_levels >= cn:
		result.success = true
		result.overcast_sl = result.test_result.success_levels - cn

	if result.fumble:
		result.miscast = _apply_ingredient(roll_minor_miscast(), has_ingredient)
	elif result.critical and not has_instinctive_diction:
		result.miscast = _apply_ingredient(roll_minor_miscast(), has_ingredient)

	return result

static func _apply_ingredient(miscast: Dictionary, has_ingredient: bool) -> Dictionary:
	if not has_ingredient:
		return miscast
	## An ingredient downgrades a Major Miscast to Minor, and negates a
	## Minor Miscast entirely, but is consumed either way (p.235).
	if miscast.get("tier", "") == "major":
		miscast = roll_minor_miscast()
	else:
		miscast = {}
	return miscast

static func roll_minor_miscast() -> Dictionary:
	var roll := Dice.d100()
	for entry in MINOR_MISCAST_TABLE:
		if roll >= entry["min"] and roll <= entry["max"]:
			if roll >= 96:
				var major := roll_major_miscast()
				major["cascaded_from_minor"] = true
				return major
			var tags: Array = entry["tags"].duplicate()
			var texts: Array[String] = [entry["text"]]
			## "Misfortune compounds — roll twice more on this table"
			## (p.235): resolved by actually rolling twice more and
			## merging every result's real tags and text, rather than
			## leaving the compounding as flavour text only. Each extra
			## roll can itself cascade to Major or compound further.
			if tags.has("roll_again:2"):
				tags.erase("roll_again:2")
				for i in range(2):
					var extra := roll_minor_miscast()
					texts.append(extra.get("text", ""))
					tags.append_array(extra.get("tags", []))
			return {"tier": "minor", "roll": roll, "text": "; ".join(texts), "tags": tags}
	return {}

static func roll_major_miscast() -> Dictionary:
	var roll := Dice.d100()
	for entry in MAJOR_MISCAST_TABLE:
		if roll >= entry["min"] and roll <= entry["max"]:
			return {"tier": "major", "roll": roll, "text": entry["text"], "tags": entry["tags"]}
	return {}

## --- Channelling (p.237) --------------------------------------------------
## Tracks one Lore's Extended Channelling Test across multiple Rounds.
## Deliberately NOT tied to a specific spell: the book's own "Arcane
## Spells" rule (p.242) already treats Arcane spells as a single shared
## pool any Arcane Magic holder can cast, and per the request,
## Channelling a Wind powers up casting from that Lore generally —
## whichever known Arcane spell is actually cast next benefits, evaluated
## against accumulated_sl at cast time, rather than committing to one
## spell up front while still channelling.
class ChannellingProgress:
	var accumulated_sl: int = 0
	var critical_ready: bool = false   ## a Critical Channel: next cast is free of CN regardless of accumulated_sl

## Advances a Channelling attempt by one Round. Fumbling (any double, or
## any roll ending in 0 that's over the caster's Skill) loses all
## accumulated SL and inflicts a Major Miscast. A Critical lets the next
## spell of this Lore be cast next Round regardless of accumulated SL,
## at the cost of a Minor Miscast (unless the caster has Aethyric
## Attunement).
static func channel_round(caster: Character, progress: ChannellingProgress,
		lore: String, modifier: int = 0, has_aethyric_attunement: bool = false) -> Dictionary:
	var channelling: SkillDefinition = GameData.skill_db.find_by_name("Channelling")
	var result := TestResolver.resolve_skill_test(caster, channelling, lore, modifier)
	var skill_value := caster.get_skill_value(channelling, lore)
	var is_channelling_fumble := (result.roll % 11 == 0) or \
		(result.roll % 10 == 0 and result.roll > skill_value)

	var out := {"test_result": result, "miscast": {}}

	if is_channelling_fumble:
		progress.accumulated_sl = 0
		progress.critical_ready = false
		out["miscast"] = roll_major_miscast()
		return out

	if result.is_critical:
		progress.critical_ready = true
		if not has_aethyric_attunement:
			out["miscast"] = roll_minor_miscast()
		return out

	if result.success:
		progress.accumulated_sl += result.success_levels
	return out

## Whether `progress` currently has enough channelled to cast `spell` at
## CN 0. Petty spells already have CN 0 (p.142 grants them outright, no
## Channelling Test needed) so they never benefit — checked explicitly
## rather than just happening to be true when accumulated_sl >= 0, so
## the "Petty can't be reduced further" rule is enforced on purpose.
static func is_channelled_for(progress: ChannellingProgress, spell: SpellDefinition) -> bool:
	if spell.spell_type == "Petty":
		return false
	return progress.critical_ready or progress.accumulated_sl >= spell.casting_number

## Real bug fix, per the report ("channelling should reduce the CN by
## the channelling SL, this should work for partial CN reduction as
## well and to CN 0"): p.237's actual rule is "each SL scored on the
## Channelling Test reduces the Casting Number of a spell cast within
## the next round by 1, to a minimum of 0" — a running 1-for-1 discount,
## not the all-or-nothing gate is_channelled_for() implements above
## (which only ever paid off once accumulated_sl reached the spell's
## FULL Casting Number, e.g. 6 SL accumulated toward a CN 10 spell got
## nothing at all, when the book always meant it to knock 6 off,
## leaving CN 4). Returns the actual reduction to apply, already capped
## at the spell's own Casting Number (accumulating more than a spell
## needs doesn't refund the difference or carry across into negative
## CN) — callers compute the spell's effective CN as
## `spell.casting_number - channelled_cn_reduction(...)`. A Critical
## Channel's own "next cast is free of CN regardless of accumulated_sl"
## bonus (critical_ready) still grants the FULL reduction outright,
## unchanged from before. Petty spells never benefit, same reasoning as
## is_channelled_for() above.
static func channelled_cn_reduction(progress: ChannellingProgress, spell: SpellDefinition) -> int:
	if spell.spell_type == "Petty":
		return 0
	if progress.critical_ready:
		return spell.casting_number
	return min(progress.accumulated_sl, spell.casting_number)

## --- Miscast mechanical effects -------------------------------------------
## Parses and applies a Miscast entry's "tags" to `character`, returning
## human-readable lines describing what actually happened (for the
## combat log) — the real mechanical follow-through for a Miscast,
## rather than the table text being flavour-only. `roll_again` tags are
## intentionally NOT resolved here (the caller re-rolls and re-applies
## for those, since it needs to pick a fresh table entry each time).
static func apply_miscast_tags(character: Character, tags: Array) -> Array[String]:
	var lines: Array[String] = []
	for tag in tags:
		var parts: Array = str(tag).split(":")
		if parts[0] == "condition" and parts.size() >= 3:
			var cond_name: String = parts[1]
			var stacks: int = int(parts[2])
			character.add_condition(cond_name, stacks)
			lines.append("%s gains %d stack(s) of %s." % [character.character_name, stacks, cond_name])
		elif parts[0] == "corruption" and parts.size() >= 2:
			var amount: int = int(parts[1])
			character.corruption_points += amount
			lines.append("%s gains %d Corruption point(s) (now %d)." % [character.character_name, amount, character.corruption_points])
		elif parts[0] == "mental_corruption":
			## A specifically Mental Corruption Point (p.184-185) —
			## this project doesn't yet implement the actual
			## consequences of crossing a Corruption threshold (same
			## documented gap as the plain "corruption" tag above), so
			## this is mechanically identical to gaining 1 Corruption
			## point, but the notice is honest about which kind it
			## actually was, for the record — some effects (like the
			## bespoke-trait sub-table pattern below) specifically
			## call for a Mental one rather than a Physical one.
			character.corruption_points += 1
			lines.append("%s gains 1 Mental Corruption point (now %d)." % [character.character_name, character.corruption_points])
		elif parts[0] == "wounds_direct" and parts.size() >= 2:
			var dice_spec: String = parts[1]
			var wounds := Dice.roll_dice_string(dice_spec)
			character.wounds_current = max(0, character.wounds_current - wounds)
			lines.append("%s suffers %d Wound(s), ignoring Toughness and Armour." % [character.character_name, wounds])
		elif parts[0] == "fortune" and parts.size() >= 2:
			var amount2: int = int(parts[1])
			character.fortune_points += amount2
			lines.append("%s gains %d bonus Fortune Point(s) (spending them risks Corruption)." % [character.character_name, amount2])
		elif parts[0] == "save" and parts.size() >= 4 and parts[2] == "then":
			var skill_name: String = parts[1]
			var skill_def: SkillDefinition = GameData.skill_db.find_by_name(skill_name.capitalize())
			## Resistance (Chaos) only applies to Tests made specifically
			## to resist a Corruption-Point gain — not every
			## save-or-suffer Miscast effect (resisting Blinded or
			## Broken isn't "resisting Corruption").
			## Pure Soul does NOT modify this Test at all (per its real
			## book text: "you may gain extra Corruption points equal to
			## your level of Pure Soul before having to Test to see if
			## you become corrupt") — its effect is a raised Corruption
			## Threshold, applied in Character.get_corruption_threshold(),
			## not a bonus here.
			var is_corruption_save: bool = parts[3] == "corruption" or parts[3] == "mental_corruption"
			var modifier := 0
			var modifier_breakdown: Array = []
			var save_result: TestResolver.TestResult
			if skill_def != null:
				save_result = TestResolver.resolve_skill_test(character, skill_def, "", modifier, modifier_breakdown)
			else:
				save_result = TestResolver.resolve_characteristic_test(character, skill_name, modifier, [], modifier_breakdown)
			## Resistance (p.138): "you may re-roll failed Tests made to
			## resist <situation>" — one guaranteed reroll of the
			## failure (not a choice of the better of two results).
			var reroll_note := ""
			if is_corruption_save and not save_result.success and character.has_talent("Resistance (Chaos)"):
				if skill_def != null:
					save_result = TestResolver.resolve_skill_test(character, skill_def, "", modifier, modifier_breakdown)
				else:
					save_result = TestResolver.resolve_characteristic_test(character, skill_name, modifier, [], modifier_breakdown)
				reroll_note = " (rerolled — Resistance (Chaos))"
			if save_result.success:
				lines.append("%s resists the effect (%s Test succeeds%s)." % [character.character_name, skill_name.capitalize(), reroll_note])
			else:
				lines.append("%s fails to resist (%s Test fails%s)." % [character.character_name, skill_name.capitalize(), reroll_note])
				var remaining_tag := ":".join(parts.slice(3))
				lines.append_array(apply_miscast_tags(character, [remaining_tag]))
	return lines


## --- Overcasting (Winds of Magic p.23) --------------------------------
## Supersedes the core rulebook's simpler "every +2 SL = one generic
## increment" rule with the sourcebook's own Overcast Table — checked
## against the book, not reconstructed. Each column (Targets, Damage,
## Range, Area of Effect, Duration) has its own SL thresholds, and only
## the highest threshold actually met applies (a real diminishing-
## returns curve, not a linear one): 1/2/3 SL all only buy +1 Target,
## for instance, while +2 Targets needs a genuine 5. "Effects can be
## drawn from multiple columns, but each column may only be accessed
## once per casting" — you choose how much SL to commit to each column
## you want to use; whatever's left unallocated is lost.
##
## This project only mechanically implements the Targets and Damage
## columns (see _offer_overcasting in field_encounter_screen.gd for
## why Range/Area of Effect/Duration remain a documented gap).
const OVERCAST_TABLE := [
	{"sl": 1, "targets": 1, "damage": 1, "range_mult": 2, "aoe_mult": 1, "duration_mult": 1},
	{"sl": 2, "targets": 1, "damage": 2, "range_mult": 2, "aoe_mult": 1, "duration_mult": 2},
	{"sl": 3, "targets": 1, "damage": 3, "range_mult": 2, "aoe_mult": 2, "duration_mult": 2},
	{"sl": 5, "targets": 2, "damage": 4, "range_mult": 3, "aoe_mult": 2, "duration_mult": 2},
	{"sl": 8, "targets": 2, "damage": 5, "range_mult": 3, "aoe_mult": 2, "duration_mult": 3},
	{"sl": 13, "targets": 2, "damage": 6, "range_mult": 3, "aoe_mult": 2, "duration_mult": 3},
	{"sl": 21, "targets": 3, "damage": 7, "range_mult": 4, "aoe_mult": 3, "duration_mult": 3},
]

## The benefit for spending `sl_spent` SL on a given column ("targets",
## "damage", "range_mult", "aoe_mult", "duration_mult") — the highest
## table row whose threshold is actually met, or -1 if even the lowest
## (1 SL) threshold isn't reached.
static func get_overcast_benefit(column: String, sl_spent: int) -> int:
	var best := -1
	for row in OVERCAST_TABLE:
		if sl_spent >= row["sl"]:
			best = row[column]
	return best

## The distinct SL spend amounts worth offering for a column, up to
## `max_sl` — only thresholds where the benefit actually changes from
## the previous one (so 2 and 3 SL aren't separately offered for
## Targets, since both only match what 1 SL already buys).
static func get_overcast_spend_options(column: String, max_sl: int) -> Array[int]:
	var options: Array[int] = []
	var last_benefit := -1
	for row in OVERCAST_TABLE:
		if row["sl"] > max_sl:
			break
		if row[column] != last_benefit:
			options.append(row["sl"])
			last_benefit = row[column]
	return options
