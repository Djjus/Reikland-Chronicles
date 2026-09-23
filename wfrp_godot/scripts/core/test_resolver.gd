extends RefCounted
class_name TestResolver
## Implements the core "roll d100 under a target, count Success Levels"
## mechanic used for every skill/characteristic test and for attack rolls.

## Named difficulty modifiers, applied to the target number before rolling.
const DIFFICULTY := {
	"very_easy": 60,
	"easy": 40,
	"average": 20,
	"challenging": 0,
	"difficult": -10,
	"hard": -20,
	"very_hard": -30,
}

class TestResult:
	var target: int
	var roll: int
	var success: bool
	var success_levels: int
	var is_critical: bool   # rolled doubles that succeeded, e.g. 11, 22...
	var is_fumble: bool     # rolled doubles that failed, e.g. 11, 22... on a failure

	## For clear UI display: the SL the roll itself produced, before any
	## talent bonuses, and an itemised breakdown of where the rest came
	## from — e.g. base_success_levels=7, sl_breakdown=[{"name":"Berserk
	## Charge","amount":2},{"name":"Battle Rage","amount":2}], summing to
	## the final success_levels of 11. Likewise for the target number
	## itself: base_target is the raw skill/characteristic value, and
	## target_modifiers lists each named adjustment (Advantage, Additional
	## Effort, difficulty, ...) that was added to reach `target`.
	var base_success_levels: int = 0
	var sl_breakdown: Array = []
	var base_target: int = 0
	var target_modifiers: Array = []

	func _to_string() -> String:
		var outcome := "SUCCESS" if success else "FAILURE"
		return "%s (rolled %d vs target %d, SL %+d)" % [outcome, roll, target, success_levels]

## Resolves a single d100 test against a target number (already including
## characteristic + advances + situational modifiers).
## `sl_bonus_on_success` is added to Success Levels ONLY if the roll
## already succeeded on its own merits — it can never turn a failure into
## a success (see TalentDefinition's "success_level" bonus_mode).
## `forced_roll`, if >= 1, is used instead of rolling fresh d100 — needed
## by mechanics like Dual Wielder that reuse a specific roll (reversed)
## rather than rolling again.
static func resolve(target: int, sl_bonus_on_success: int = 0, forced_roll: int = -1) -> TestResult:
	var result := TestResult.new()
	## Real bug fix, per the request ("do not cap roll target at 100, so
	## if the accumulated value is higher then 100 do not cap it"): this
	## used to be clamp(target, 1, 100) — a genuinely stacked Casting
	## Number reduction/Advantage/Additional Effort total that added up
	## past 100 (e.g. the reported Bolt cast: base target with a -4 CN
	## and other bonuses landing well over 100) got silently truncated
	## back down to 100 for BOTH the displayed target AND, since SL below
	## is computed from this same value, the actual Success Level math --
	## losing real, earned SL along with the roll card simply showing the
	## wrong number. d100 still only ever ROLLS 1-100 (Dice.d100() itself
	## is unchanged), so a target this high just means "succeeds no
	## matter what's rolled, and by a lot" -- which is exactly the
	## correct WFRP behaviour for an very easy/heavily-boosted Test, not
	## a bug to guard against. The lower floor of 1 stays (a target of 0
	## or negative isn't a real Test any more, just an auto-fail with no
	## informative SL math), only the upper ceiling is gone.
	var clamped_target: int = max(target, 1)
	var roll: int = forced_roll if forced_roll >= 1 else Dice.d100()
	result.target = clamped_target
	result.roll = roll

	var computed_sl := int(floor(clamped_target / 10.0)) - int(floor(roll / 10.0))

	## House rule (per the request): auto-succeed on 01 only (not the
	## book's 01-05), auto-fail on 96-00 (unchanged from the book,
	## unless the target itself is already high enough to make that
	## moot). An auto-success scores +1 SL or the computed SL, whichever
	## is HIGHER; an auto-fail scores -1 SL or the computed SL,
	## whichever is LOWER.
	if roll == 1:
		result.success = true
		result.success_levels = max(computed_sl, 1)
	elif roll >= 96 and clamped_target < 96:
		result.success = false
		result.success_levels = min(computed_sl, -1)
	else:
		result.success = roll <= clamped_target
		result.success_levels = computed_sl
		if not result.success and result.success_levels >= 0:
			result.success_levels = -1 # a failure must have a negative SL

	result.is_critical = result.success and (roll % 11 == 0 or roll == 100)
	result.is_fumble = (not result.success) and (roll % 11 == 0)

	## Set here (before sl_bonus_on_success below) so it's always the
	## roll's own raw SL, matching TestResult's own doc comment — a
	## direct resolve() caller with no wrapper (e.g. Overworld's "Force
	## Door" Strength Test) still gets a meaningful base_success_levels
	## this way, not the class default of 0. resolve_skill_test() and
	## resolve_characteristic_test() both recompute this same value
	## themselves afterward anyway (to also account for a reversed-dice
	## retry), so this is a safe default, not a conflicting one.
	result.base_success_levels = result.success_levels

	## Success-Level-boosting talents (Savvy, Suave, etc.) only ever
	## apply once the test has already succeeded on its own.
	if result.success and sl_bonus_on_success != 0:
		result.success_levels += sl_bonus_on_success

	return result

## An Opposed Test's outcome — Design Doc "Social Combat — Design Doc
## v1", Section 4: "Net SL = Attacker SL - Defender SL". Deliberately
## takes two ALREADY-ROLLED TestResults rather than rolling them
## itself: every opposed exchange in this project (including Social
## Combat's own Fortune/Dark Deal wiring, Design Doc Section 9) needs
## the chance to offer a Fortune spend / reroll on EACH side's roll
## before the two are compared, so resolve_opposed() is purely the
## comparison step, called once both sides' rolls (and any rerolls)
## are already final. Before this, every opposed test in the project
## rolled both sides and compared success_levels inline at the call
## site (see social_encounter_screen.gd's pre-Social-Combat opposed
## situations) — this is that same comparison, factored out once so
## Social Combat's many opposed exchanges (party-attacks-NPC AND
## NPC-attacks-party) don't each duplicate it.
class OpposedResult:
	var attacker: TestResult
	var defender: TestResult
	var net_success_levels: int   ## attacker.success_levels - defender.success_levels
	var attacker_wins: bool       ## true only when the attacker actually prevails — see the tie-break rule below
	## Per an explicit request (matching the book's own opposed-test
	## tie-break, p.153): when both sides score the SAME Success Level,
	## the win goes to whichever side rolled against the HIGHER Target
	## Number — not automatically to the defender, and not automatically
	## to the attacker either. Only when the Target Numbers are ALSO
	## equal is it a genuine tie: nothing happens, for either side.
	## attacker_wins is false in both the "defender wins the SL tie on
	## target" case and the "true tie" case — is_true_tie tells a caller
	## which of those two it actually was, so messaging (and any
	## side-effect that would otherwise apply to "the loser") can tell a
	## real loss apart from a dead heat. Applies uniformly everywhere an
	## opposed Test is resolved — combat and non-combat alike.
	var is_true_tie: bool

static func resolve_opposed(attacker_result: TestResult, defender_result: TestResult) -> OpposedResult:
	var result := OpposedResult.new()
	result.attacker = attacker_result
	result.defender = defender_result
	result.net_success_levels = attacker_result.success_levels - defender_result.success_levels
	if result.net_success_levels != 0:
		result.attacker_wins = result.net_success_levels > 0
		result.is_true_tie = false
	elif attacker_result.target != defender_result.target:
		result.attacker_wins = attacker_result.target > defender_result.target
		result.is_true_tie = false
	else:
		result.attacker_wins = false
		result.is_true_tie = true
	return result

## Maps a Success Level to its named outcome tier (Astounding/Impressive/
## Success/Marginal on a pass, the mirror on a fail) — the same bands the
## Outcomes Table uses, for flavourful result text.
static func get_outcome_label(success_levels: int) -> String:
	if success_levels >= 6:
		return "Astounding Success"
	elif success_levels >= 4:
		return "Impressive Success"
	elif success_levels >= 2:
		return "Success"
	elif success_levels >= 0:
		return "Marginal Success"
	elif success_levels >= -1:
		return "Marginal Failure"
	elif success_levels >= -3:
		return "Failure"
	elif success_levels >= -5:
		return "Impressive Failure"
	else:
		return "Astounding Failure"

## Convenience wrapper for skill tests against a Character. Automatically
## looks up and applies the +1-SL-per-rank bonus from any talent whose
## Tests field matches this skill (see TalentDefinition).
## `modifier_breakdown` is optional and purely for UI display — an array
## of {"name": String, "amount": int} describing what makes up
## `modifier` (e.g. Advantage, Additional Effort) — the actual math still
## just uses the flat `modifier` int either way.
## `extra_sl_breakdown` lets a caller add SL bonuses that don't come
## from a Talent (get_test_success_level_breakdown only knows about
## Talents) — e.g. the Defensive weapon Quality's "+1 SL to any Melee
## Test when you oppose an incoming attack" (p.298), which is a property
## of the equipment being used to defend, not the character. Same
## caller-supplies-a-consistent-breakdown pattern already used for
## `modifier`/`modifier_breakdown`.
##
## `extra_scopes` lets a caller tag this specific Test with a situational
## label (e.g. "Melee when attacking with two weapons") so a narrowly-
## worded Talent like Dual Wielder — "Tests: Melee or Ranged when
## attacking with two weapons" (p.136) — only grants its SL bonus on the
## actual dual-wielding attack, not every Melee/Ranged Test generally.
static func resolve_skill_test(character: Character, skill_def: SkillDefinition,
		specialisation: String = "", modifier: int = 0, modifier_breakdown: Array = [], forced_roll: int = -1,
		extra_sl_breakdown: Array = [], extra_scopes: Array = []) -> TestResult:
	var scopes := [
		skill_def.skill_name,
		skill_def.display_name(specialisation),
		skill_def.linked_characteristic,
	]
	scopes.append_array(extra_scopes)
	var sl_breakdown := character.get_test_success_level_breakdown(scopes)
	sl_breakdown.append_array(extra_sl_breakdown)
	var sl_bonus := 0
	for entry in sl_breakdown:
		sl_bonus += entry["amount"]
	var base_target := character.get_skill_value(skill_def, specialisation)
	## Master Condition List (p.167-169): Fatigued/Stunned/Poisoned/
	## Broken/Blinded/Deafened/Prone/Entangled all impose real Test
	## penalties — folded into the modifier breakdown here so every
	## skill Test in the project applies them automatically rather
	## than requiring each call site to remember to check.
	var full_breakdown := modifier_breakdown.duplicate()
	var condition_penalties := character.get_condition_test_penalty_breakdown(scopes)
	full_breakdown.append_array(condition_penalties)
	var condition_modifier := 0
	for entry in condition_penalties:
		condition_modifier += entry["amount"]
	## Stinking Drunk table result 1-2 ("Marienburgher's Courage!"): a
	## real +20 to Cool Tests specifically — see Character.
	## get_drunk_test_modifier_breakdown()'s own comment. Folded in
	## here (same pipeline as the Condition penalties just above) so it
	## applies automatically to every Cool Test in the game, not just
	## ones a specific call site remembered to check.
	var drunk_bonus := character.get_drunk_test_modifier_breakdown(scopes)
	full_breakdown.append_array(drunk_bonus)
	var drunk_modifier := 0
	for entry in drunk_bonus:
		drunk_modifier += entry["amount"]
	## Ugly (p.302): -10 to Fellowship-scoped Tests while wearing/wielding
	## an Ugly item — see Character.get_item_test_modifier_breakdown().
	var item_penalties := character.get_item_test_modifier_breakdown(scopes)
	full_breakdown.append_array(item_penalties)
	var item_modifier := 0
	for entry in item_penalties:
		item_modifier += entry["amount"]
	var target := base_target + modifier + condition_modifier + drunk_modifier + item_modifier
	var result := resolve(target, sl_bonus, forced_roll)

	## Alley Cat (p.132, Stealth (Urban)), Carouser (p.134, Consume
	## Alcohol), and similar Talents: "you may reverse the dice of any
	## failed Test if this will score a Success." Retried once, using
	## the same digit-reversal CombatResolver already uses for Hit
	## Location (a roll of 23 becomes 32) — only on an actual failure,
	## and only if the reversed roll would genuinely succeed, matching
	## the book's own "if this will score a Success" condition (a worse
	## reversed roll is simply not used).
	if not result.success and character.has_reverse_dice_on_fail(scopes):
		var reversed_roll := CombatResolver.reverse_roll(result.roll)
		var retry := resolve(target, sl_bonus, reversed_roll)
		if retry.success:
			result = retry

	result.base_success_levels = result.success_levels - (sl_bonus if result.success else 0)
	result.sl_breakdown = sl_breakdown
	result.base_target = base_target
	result.target_modifiers = full_breakdown

	## Argumentative (p.133, Charm), Cardsharp (p.134, Gamble/Sleight of
	## Hand), and similar Talents: "you can choose to either use your
	## rolled SL, or the number rolled on your units die" — e.g. a
	## successful roll of 24 could be used for +4 SL instead of its
	## normal (lower) SL. Modelled as "whichever is better" rather than
	## an actual in-game choice, since a rational player always takes
	## the higher of the two anyway.
	if result.success and character.has_units_digit_as_sl(scopes):
		var units_digit := result.roll % 10
		if units_digit > result.success_levels:
			result.success_levels = units_digit

	return result

## Convenience wrapper for a raw characteristic test (e.g. "Toughness Test").
## `extra_scopes` lets callers add situational tags (e.g. combat code
## passing "Melee Tests when Frenzied") so situational talents can apply.
static func resolve_characteristic_test(character: Character, characteristic_key: String,
		modifier: int = 0, extra_scopes: Array = [], modifier_breakdown: Array = []) -> TestResult:
	var scopes := [characteristic_key] + extra_scopes
	var sl_breakdown := character.get_test_success_level_breakdown(scopes)
	var sl_bonus := 0
	for entry in sl_breakdown:
		sl_bonus += entry["amount"]
	## Real bug fix: this used to read character.characteristics.get_value()
	## directly, which bypasses active_buffs, critical_wound_penalties,
	## AND the Encumbrance Agility malus — a raw characteristic Test
	## (e.g. an Agility pull-test) used to ignore all three, even
	## though the equivalent skill Test (get_skill_value(), via
	## get_effective_characteristic_value()) already applied them.
	## Routing through the same helper skill Tests use fixes that gap
	## for every raw characteristic Test at once.
	var base_target: int = character.get_effective_characteristic_value(characteristic_key)
	var full_breakdown := modifier_breakdown.duplicate()
	var condition_penalties := character.get_condition_test_penalty_breakdown(scopes)
	full_breakdown.append_array(condition_penalties)
	var condition_modifier := 0
	for entry in condition_penalties:
		condition_modifier += entry["amount"]
	## Ugly (p.302): -10 to Fellowship-scoped Tests while wearing/wielding
	## an Ugly item — see Character.get_item_test_modifier_breakdown().
	## resolve_skill_test() has its own matching hook; this covers a raw
	## Fellowship characteristic Test taken outside of any specific skill.
	var item_penalties := character.get_item_test_modifier_breakdown(scopes)
	full_breakdown.append_array(item_penalties)
	var item_modifier := 0
	for entry in item_penalties:
		item_modifier += entry["amount"]
	var target := base_target + modifier + condition_modifier + item_modifier
	var result := resolve(target, sl_bonus)
	result.base_success_levels = result.success_levels - (sl_bonus if result.success else 0)
	result.sl_breakdown = sl_breakdown
	result.base_target = base_target
	result.target_modifiers = full_breakdown
	return result

## Per the request: any out-of-combat Test — social interactions
## (Charm, Gossip) most explicitly, but the same reasoning applies to
## Perception, Pick Lock, and anything else a party would naturally
## put its own best-suited member forward for — is rolled by every
## present party member automatically, rather than only whoever
## happens to be the currently active/controlled one. Returns both
## the best TestResult and specifically which Character rolled it, so
## the player can always see who actually succeeded (or came
## closest), not just an anonymous "the party" result. An empty
## party returns {"result": null, "roller": null}.
static func resolve_party_skill_test(party: Array[Character], skill_def: SkillDefinition,
		specialisation: String = "", modifier: int = 0) -> Dictionary:
	var best_result: TestResult = null
	var best_roller: Character = null
	for member in party:
		var result := resolve_skill_test(member, skill_def, specialisation, modifier)
		if best_result == null or result.success_levels > best_result.success_levels:
			best_result = result
			best_roller = member
	return {"result": best_result, "roller": best_roller}
