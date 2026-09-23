extends RefCounted
class_name Advancement
## Spending XP to improve a character, checked directly against the
## rulebook's Characteristic and Skill Improvement XP Costs table and
## the Talent/Career-change rules (p.47-48) rather than estimated.

## Bracket -> [characteristic_cost, skill_cost], keyed by the LOWER bound
## of the "Advances already purchased" bracket the character is *in*
## before this purchase (e.g. buying your 6th advance — the character
## already has 5 — costs the 5-9 bracket rate). Every bracket spans
## exactly 5 advances (0-4, 5-9, 10-14, 15-19, ...) — a real off-by-one
## bug used to make the first bracket span 6 (0-5) before the rest
## correctly spanned 5, shifting every later bracket's threshold one
## advance later than it should've been. Fixed and reverified against
## the actual book's Improvement cost table.
const COST_TABLE := [
	# [min_advances, characteristic_cost, skill_cost]
	[0, 25, 10], [5, 30, 15], [10, 40, 20], [15, 50, 30], [20, 70, 40],
	[25, 90, 60], [30, 120, 80], [35, 150, 110], [40, 190, 140],
	[45, 230, 180], [50, 280, 220], [55, 330, 270], [60, 390, 320],
	[65, 450, 380], [70, 520, 440],
]

## Advances required in every unlocked Characteristic and in 8 of the
## Career level's available Skills to "complete" that level (p.48).
const LEVEL_COMPLETION_ADVANCES := {1: 5, 2: 10, 3: 15, 4: 20}

class PurchaseResult:
	var success: bool = false
	var cost: int = 0
	var message: String = ""

static func _bracket_row(advances_already_purchased: int) -> Array:
	var row: Array = COST_TABLE[0]
	for r in COST_TABLE:
		if advances_already_purchased >= r[0]:
			row = r
		else:
			break
	return row

static func get_characteristic_advance_cost(advances_already_purchased: int, is_career: bool = true) -> int:
	var cost: int = _bracket_row(advances_already_purchased)[1]
	return cost if is_career else cost * 2

static func get_skill_advance_cost(advances_already_purchased: int, is_career: bool = true) -> int:
	var cost: int = _bracket_row(advances_already_purchased)[2]
	return cost if is_career else cost * 2

## Talent Advances cost 100 XP + 100 XP per Advance already taken in that
## Talent (so 1st purchase 100, 2nd 200, 3rd 300, ...) (p.48).
static func get_talent_advance_cost(rank_already_taken: int) -> int:
	return 100 * (rank_already_taken + 1)

## Verified against the book's own summary table (p.49, "Talent and
## Career Change XP Costs"): Leave a Complete Career 100 XP, Leave an
## Incomplete Career 200 XP, Enter a different Class +100 XP on top of
## whichever of those applies. A real bug used to charge the same cost
## regardless of class, missing that surcharge entirely.
static func get_change_career_cost(completed_current_level: bool, changing_class: bool = false) -> int:
	var base := 100 if completed_current_level else 200
	return (base + 100) if changing_class else base

## --- Career-scope checks --------------------------------------------------
## Characteristics/Skills unlock cumulatively from tier 1 up to the
## character's current tier; Talents are ONLY available at the exact
## current tier (p.47-48 — this is an explicit asymmetry in the rules,
## not an oversight here).

static func unlocked_characteristics(character: Character) -> Array:
	var result: Array = []
	for tier in range(1, character.current_tier + 1):
		var level := character.career.get_level(tier)
		if level:
			for key in level.attribute_advances.keys():
				if not result.has(key):
					result.append(key)
	return result

static func unlocked_skills(character: Character) -> Array:
	var result: Array = []
	for tier in range(1, character.current_tier + 1):
		var level := character.career.get_level(tier)
		if level:
			for s in level.skills:
				## "Any" qualifiers are kept even if this exact string
				## already appears — e.g. Warrior Priest grants "Melee
				## (Any)" at both Tier 1 and Tier 2, and each occurrence
				## is a genuinely separate one-time choice slot, not a
				## repeat of the same slot. Concrete skills (no "(Any)")
				## still dedupe as before — those aren't a repeatable
				## choice, just an unlocked skill you can keep advancing.
				if is_any_qualifier(s) or not result.has(s):
					result.append(s)
	## Craftsman (Trade) (p.135): "Add the associated Trade Skill to any
	## Career you enter" -- each resolved "Craftsman (X)" Talent unlocks
	## training in Trade (X) regardless of whether the current Career
	## actually lists it.
	for trade in character.get_craftsman_trades():
		var entry := "Trade (%s)" % trade
		if not result.has(entry):
			result.append(entry)
	return result

static func unlocked_talents(character: Character) -> Array:
	var level := character.career.get_level(character.current_tier)
	return level.talents.duplicate() if level else []

## --- Purchases --------------------------------------------------------

## `force_non_career`: if true, allows purchasing even if the
## characteristic isn't in the current career scope, at double cost
## (p.48). If false and the characteristic is out of scope, the purchase
## fails rather than silently charging double, so calling UI can prompt
## the player to confirm the non-career surcharge first.
static func purchase_characteristic_advance(character: Character, key: String,
		force_non_career: bool = false) -> PurchaseResult:
	var result := PurchaseResult.new()
	var in_scope := unlocked_characteristics(character).has(key)
	if not in_scope and not force_non_career:
		result.message = "%s isn't available at your current Career level yet (would cost double as a non-Career Advance)." % key
		return result

	var already: int = character.get_characteristic_advance_count(key)
	var cost := get_characteristic_advance_cost(already, in_scope)
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result

	character.experience_spent += cost
	character.characteristic_advances[key] = already + 1
	character.characteristics.set_value(key, character.characteristics.get_value(key) + 1)
	character.recompute_max_wounds()

	result.success = true
	result.cost = cost
	result.message = "%s increased by 1 (%d XP spent)." % [key, cost]
	return result

## `via_any_entry`: when this purchase is resolving a specific "(Any)"
## qualifier's own slot (e.g. "Melee (Any)"), pass that qualifier string
## so the purchase counts against skill_any_purchases — see that field's
## own comment on Character for why. Leave blank for an ordinary,
## directly-listed skill purchase.
static func purchase_skill_advance(character: Character, skill_def: SkillDefinition,
		specialisation: String = "", force_non_career: bool = false, via_any_entry: String = "") -> PurchaseResult:
	var result := PurchaseResult.new()
	var display_name := skill_def.display_name(specialisation)
	## A career might grant "Melee (Any)" — or a descriptive-word
	## variant like "Channelling (Any Colour)" — rather than a specific
	## group. Buying "Melee (Basic)" (or "Channelling (Fire)") to
	## fulfil that "(Any)" choice is legitimate and in-scope, even
	## though the exact resolved string doesn't appear in
	## unlocked_skills() itself. A real bug here only ever checked for
	## the literal hardcoded "(Any)" qualifier, so "(Any Colour)" and
	## every other descriptive-word variant never matched, silently
	## rejecting the purchase (the caller's UI would just re-render the
	## same unresolved picker with no visible error). Fixed by checking
	## every unlocked entry for the same base skill with ANY "(Any ...)"
	## qualifier, using the same detection is_any_qualifier already uses
	## elsewhere for this exact class of qualifier.
	var unlocked := unlocked_skills(character)
	var in_scope := unlocked.has(display_name)
	if not in_scope:
		for entry in unlocked:
			if is_any_qualifier(entry) and parse_skill_entry(entry)[0] == skill_def:
				in_scope = true
				break
	if not in_scope and not force_non_career:
		result.message = "%s isn't available at your current Career level yet (would cost double as a non-Career Advance)." % display_name
		return result

	var already: int = character.skill_advances.get(display_name, 0)
	var cost := get_skill_advance_cost(already, in_scope)
	## Craftsman (Trade) (p.135): "you may instead purchase the Skill for
	## 5 XP fewer per Advance" when the matching Trade specialisation is
	## already covered by a resolved "Craftsman (X)" Talent.
	if skill_def.skill_name == "Trade" and character.get_craftsman_trades().has(specialisation):
		cost = max(1, cost - 5)
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result

	character.experience_spent += cost
	character.skill_advances[display_name] = already + 1
	if via_any_entry != "":
		character.skill_any_purchases[via_any_entry] = character.skill_any_purchases.get(via_any_entry, 0) + 1
		## Real, confirmed bug fix (see Character.skill_any_resolved's own
		## comment): permanently remember that this "(Any)" slot resolved
		## to `display_name`, independent of skill_advances -- selling
		## every advance back off later must not make this choice
		## disappear from the Skills list.
		if not character.skill_any_resolved.has(display_name):
			character.skill_any_resolved.append(display_name)

	result.success = true
	result.cost = cost
	result.message = "%s advanced to %d (%d XP spent)." % [
		display_name, character.get_skill_value(skill_def, specialisation), cost
	]
	return result

## Talents can only be bought from the character's CURRENT career tier —
## unlike Skills/Characteristics, there's no "non-career, double cost"
## option for Talents under the core rules (p.48).
## True if `entry` (as it appears in a career's talent list, or in
## unlocked_talents' output) ends in a literal "(Any)" qualifier — the
## book's way of saying "pick one from this talent's own list of valid
## qualifiers" rather than a specific value the career locks you to.
static func is_any_qualifier(entry: String) -> bool:
	var stripped := entry.strip_edges().to_lower()
	## Matches the plain "(any)" case and the descriptive-word variants
	## this project's data actually uses — "(Any Colour)" for
	## Channelling, "(Any Arcane Lore)" for Arcane Magic — anything
	## that opens with "(any" is a picker-requiring slot, not a fixed
	## qualifier; no real WFRP skill/talent qualifier starts that way
	## for any other reason.
	return stripped.find("(any") != -1 and stripped.ends_with(")")

## The choices the player gets for an "(Any)" entry — the resolved
## talent's own situation_options. Empty for anything else (a fixed
## qualifier, no qualifier at all, or a talent with no options list even
## if it does say "(Any)" in the data — treated as nothing to choose).
static func get_situation_choices(entry: String) -> Array:
	if not is_any_qualifier(entry):
		return []
	var td: TalentDefinition = GameData.talent_db.find_by_name(entry)
	if td == null:
		return []
	return td.situation_options

## If the player already resolved this "(Any)" slot to a specific
## qualifier (e.g. picked "Sigmar" for a "Bless (Any)" grant, so it's
## stored as "Bless (Sigmar)" in talents_taken), returns that full
## string. Returns "" if not yet chosen, or if `entry` isn't an "(Any)"
## slot to begin with.
static func find_chosen_variant(character: Character, entry: String) -> String:
	var choices := get_situation_choices(entry)
	if choices.is_empty():
		return ""
	var td: TalentDefinition = GameData.talent_db.find_by_name(entry)
	if td == null:
		return ""
	for choice in choices:
		var candidate := "%s (%s)" % [td.talent_name, choice]
		if character.talents_taken.has(candidate):
			return candidate
	return ""

## --- The same "(Any)" mechanic, for Skills ---------------------------------
## Grouped Skills work exactly like the Talent case above: a career
## granting "Melee (Any)" lets the player choose which group (Basic,
## Two-Handed, ...) to actually train; "Melee (Basic)" specifically
## locks them to that one. A real bug used to let "(Any)" be purchased
## and stored AS A LITERAL SPECIALISATION — advances sat in a
## "Melee (Any)" bucket that no weapon's skill_group ever actually
## matched, so the XP spent had no effect on anything in combat. Fixed
## the same way Talents already were.

## Splits "Melee (Any)" into [SkillDefinition for "Melee", "Any"]. Shared
## parsing helper so every UI screen uses the same logic rather than
## duplicating (and risking diverging) string-splitting code.
static func parse_skill_entry(entry: String) -> Array:
	var base_name := entry
	var specialisation := ""
	var paren := entry.find(" (")
	if paren != -1:
		base_name = entry.substr(0, paren)
		specialisation = entry.substr(paren + 2, entry.length() - paren - 3)
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name(base_name)
	return [skill_def, specialisation]

static func get_skill_situation_choices(entry: String) -> Array:
	if not is_any_qualifier(entry):
		return []
	var parsed := parse_skill_entry(entry)
	var skill_def: SkillDefinition = parsed[0]
	if skill_def == null or not skill_def.is_grouped:
		return []
	return skill_def.group_options

## If the player already resolved a skill's "(Any)" slot to a specific
## specialisation (stored as e.g. "Melee (Basic)" in skill_advances once
## chosen), returns that full display string. Returns "" if not chosen.
## Real, confirmed bug fix ("using the cheat button, selling a skill to
## 0 advances removes it from the skill list", reported for Ride (Any)):
## also checks character.skill_any_resolved, a permanent record of every
## resolved choice that survives selling skill_advances back to 0 -- see
## that field's own comment on Character for the full story. Checking
## skill_advances.has() too keeps this working for saves from before
## skill_any_resolved existed, where a still-nonzero advance is its own
## proof the slot was resolved.
static func find_chosen_skill_variant(character: Character, entry: String) -> String:
	var choices := get_skill_situation_choices(entry)
	if choices.is_empty():
		return ""
	var parsed := parse_skill_entry(entry)
	var skill_def: SkillDefinition = parsed[0]
	if skill_def == null:
		return ""
	for choice in choices:
		var candidate: String = skill_def.display_name(choice)
		if character.skill_advances.has(candidate) or character.skill_any_resolved.has(candidate):
			return candidate
	return ""

## Returns every distinct specialisation of this "(Any)" group the
## character has ever resolved a slot to — plural, unlike
## find_chosen_skill_variant above, since a career can grant the same
## qualifier (e.g. "Melee (Any)") more than once across different
## Career Levels, each a genuinely separate choice. A character with two
## "Melee (Any)" slots who picked Basic for one and Polearm for the
## other should see both as filled, not just the first one found.
## Real, confirmed bug fix ("using the cheat button, selling a skill to
## 0 advances removes it from the skill list", reported for Ride (Any)):
## also checks character.skill_any_resolved so a resolved choice keeps
## showing even after its last advance is sold off — see that field's
## own comment on Character. skill_advances.has() is still checked too,
## for saves predating skill_any_resolved.
static func find_all_chosen_skill_variants(character: Character, entry: String) -> Array[String]:
	var found: Array[String] = []
	var choices := get_skill_situation_choices(entry)
	if choices.is_empty():
		return found
	var parsed := parse_skill_entry(entry)
	var skill_def: SkillDefinition = parsed[0]
	if skill_def == null:
		return found
	for choice in choices:
		var candidate: String = skill_def.display_name(choice)
		if character.skill_advances.has(candidate) or character.skill_any_resolved.has(candidate):
			found.append(candidate)
	return found

## `talent_name` is normally the exact string from unlocked_talents(). If
## it's an "(Any)" slot (e.g. "Bless (Any)"), pass the player's pick in
## `chosen_situation` ("Sigmar") — the talent actually purchased and
## stored is "Bless (Sigmar)", not the literal "(Any)" placeholder,
## since "Any" was never a real qualifier to hold, just an instruction
## to choose one. Talents are purchased at a flat cost per rank —
## unlike Skills/Characteristics, there's no "non-career, double cost"
## option for Talents under the core rules (p.48).
static func purchase_talent_advance(character: Character, talent_name: String,
		chosen_situation: String = "") -> PurchaseResult:
	var result := PurchaseResult.new()
	if not unlocked_talents(character).has(talent_name):
		result.message = "%s isn't offered at your current Career level." % talent_name
		return result

	var actual_name := talent_name
	if is_any_qualifier(talent_name):
		if chosen_situation == "":
			result.message = "Choose a specific option for %s before buying." % talent_name
			return result
		var choices := get_situation_choices(talent_name)
		if not choices.has(chosen_situation):
			result.message = "%s isn't a valid choice for %s." % [chosen_situation, talent_name]
			return result
		var base_td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		actual_name = "%s (%s)" % [base_td.talent_name, chosen_situation]

	var td: TalentDefinition = GameData.talent_db.find_by_name(actual_name)
	var already: int = character.get_talent_rank(actual_name)
	if td:
		var max_rank := td.get_max_rank(character)
		if already >= max_rank:
			result.message = "%s is already at its maximum rank (%d)." % [actual_name, max_rank]
			return result

	## Chaos Magic (Lore) (p.134): "Each time you take this Talent, which
	## always costs 100 XP per time instead of the normal cost, you learn
	## another spell from your chosen Lore and gain a Corruption point" —
	## unlike every other Talent, its cost does NOT scale with rank
	## already taken (the normal formula would charge 200, 300, ... from
	## the 2nd rank on).
	var is_chaos_magic := actual_name.begins_with("Chaos Magic (")
	var cost := 100 if is_chaos_magic else get_talent_advance_cost(already)
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result

	character.experience_spent += cost
	character.talents_taken[actual_name] = already + 1
	## Hardy (p.130): "a permanent addition to your Wounds, equal to
	## your Toughness Bonus" per rank -- recompute_max_wounds() only
	## used to run off Characteristic Advances, so taking (or later
	## selling) a rank of Hardy itself never actually updated Wounds
	## until some unrelated later Toughness change happened to trigger
	## it. Called unconditionally here (cheap, and correct for any
	## future Wounds-affecting Talent too) rather than special-cased to
	## just Hardy by name.
	character.recompute_max_wounds()

	result.success = true
	result.cost = cost
	result.message = "%s taken (rank %d, %d XP spent)." % [actual_name, already + 1, cost]

	if is_chaos_magic:
		## "gain a Corruption point as the spell infiltrates your mind" —
		## this project's Chaos-Lore spell list isn't populated yet (see
		## the Talent's own summary), so no specific spell is granted
		## here, but the Corruption cost is real and applied every rank.
		character.corruption_points += 1
		result.message += " Gained 1 Corruption Point (%d/%d)." % [character.corruption_points, character.get_corruption_threshold()]
		var mutation_notice := CorruptionResolver.check_and_apply_threshold(character)
		if mutation_notice != "":
			result.message += " " + mutation_notice

	return result

## Checks whether the character has met the requirements to "complete"
## their current career level (p.48): the completion-advances threshold
## in every unlocked Characteristic, in 8 of the level's available
## Skills, and at least 1 Talent from the current tier. Where a career
## grants an "(Any)" Skill or Talent (e.g. "Melee (Any)", "Bless (Any)"),
## the character's actual advances are stored under whichever specific
## choice they made (e.g. "Melee (Basic)"), not the literal "(Any)"
## string — a real bug here checked for the raw "(Any)" text directly,
## so a fully-advanced character with a properly resolved choice still
## showed as incomplete. Fixed by resolving to the chosen variant first,
## the same way the purchase/display code already does elsewhere.
##
## Note: careers still on the old 4-skill-per-tier simplification (see
## README — the Warrior class has been corrected to the book's real
## 8/6/4/2, most other classes haven't yet) have fewer than 8 unlocked
## Skills available at low tiers; min(8, available.size()) keeps
## completion reachable in that case rather than permanently impossible.
static func has_completed_current_level(character: Character) -> bool:
	var required: int = LEVEL_COMPLETION_ADVANCES.get(character.current_tier, 20)

	for key in unlocked_characteristics(character):
		if character.get_characteristic_advance_count(key) < required:
			return false

	var available_skills := unlocked_skills(character)
	var need: int = min(8, available_skills.size())
	var met := 0
	## Group "Any" occurrences by qualifier first — unlocked_skills() now
	## preserves each one (a career can grant the same qualifier, e.g.
	## "Melee (Any)", more than once across different Career Levels, and
	## each is a genuinely separate choice slot). Counting occurrences
	## naively here would double-count a single purchased skill against
	## every occurrence of the qualifier that could have produced it —
	## instead, each occurrence is matched against a distinct chosen
	## variant (find_all_chosen_skill_variants), capped at however many
	## variants were actually chosen.
	var any_counts: Dictionary = {}
	for s in available_skills:
		if is_any_qualifier(s):
			any_counts[s] = any_counts.get(s, 0) + 1
			continue
		if character.skill_advances.get(s, 0) >= required:
			met += 1
	for qualifier in any_counts.keys():
		var slot_count: int = any_counts[qualifier]
		var chosen_variants := find_all_chosen_skill_variants(character, qualifier)
		var counted := 0
		for variant in chosen_variants:
			if counted >= slot_count:
				break
			if character.skill_advances.get(variant, 0) >= required:
				met += 1
			counted += 1
	if met < need:
		return false

	var has_current_tier_talent := false
	for t in unlocked_talents(character):
		var actual_talent_name: String = t
		if is_any_qualifier(t):
			var chosen := find_chosen_variant(character, t)
			if chosen != "":
				actual_talent_name = chosen
		if character.has_talent(actual_talent_name):
			has_current_tier_talent = true
			break
	return has_current_tier_talent

## Per the request ("when switching career allow character to directly
## enter higher tiers of other classes if they have already completed
## lower ones in that target career"): the highest tier of `career_name`
## this character has ever actually STOOD IN, whether that's the career
## they're in right now or one recorded in career_history from an
## earlier stint in it. Returns 0 if the character has never set foot
## in this career at all.
##
## Real, confirmed bug fixed here (Alberta: started in Thief Tier 1 —
## her character's very FIRST career, assigned at creation, never
## itself logged as a career_history entry — then switched straight to
## Duellist Tier 1; that switch's own history entry records Thief only
## as its `from_career`/`from_tier`, never as a `to_career`): checking
## only `to_career` entries, as an earlier version of this function
## did, completely misses any career a character was standing in
## before their first ever change_career() call, since career_history
## only starts recording once a change actually happens — the career
## being LEFT is recorded as that same entry's `from_career`, not a
## `to_career` of its own. Both sides of every entry are checked now.
static func highest_tier_reached(character: Character, career_name: String) -> int:
	var highest := 0
	if character.career != null and character.career.career_name == career_name:
		highest = character.current_tier
	for entry in character.career_history:
		if str(entry.get("to_career", "")) == career_name:
			highest = max(highest, int(entry.get("to_tier", 0)))
		if str(entry.get("from_career", "")) == career_name:
			highest = max(highest, int(entry.get("from_tier", 0)))
	return highest

## Per a real, confirmed bug (Alberta: started Thief Tier 1, switched
## straight to Duellist Tier 1 — highest_tier_reached("Thief") is 1, but
## re-entering Thief only offered Tier 1, not Tier 2): the tier a
## character having stood in Tier N of a career unlocks for RE-ENTRY is
## Tier N+1, not Tier N itself — she left Thief AT Tier 1, so Thief
## Tier 1 is behind her; Tier 2 is the next real door. Per an explicit
## follow-up ("she should not need to complete duelist tier 1 to do so
## either"): this is intentionally NOT gated on Advancement.
## has_completed_current_level() for either the career she's leaving or
## the one tier she previously stood in — simply having been there is
## enough, matching how the ordinary "advance to the next tier of your
## CURRENT career" button already works (always offered once you're in
## a tier, cost is merely higher if that tier isn't complete; nothing
## ever blocks the advance outright). Capped at the target career's own
## highest defined tier, so a career that's shorter than the reached-
## tier-plus-one can't be asked for a tier it doesn't have.
static func max_reentry_tier(character: Character, target_career: CareerDefinition) -> int:
	var cap: int = highest_tier_reached(character, target_career.career_name) + 1
	var career_top := 0
	for lvl in target_career.levels:
		career_top = max(career_top, lvl.tier)
	if career_top > 0:
		cap = min(cap, career_top)
	return max(1, cap)

## Changing Career (p.48-49) covers both moving to a different tier of
## the SAME career and moving to an entirely different one. Cost is 100
## XP if the current Career level is completed, 200 XP if not — PLUS a
## further +100 XP if the new career belongs to a different Class than
## the current one (e.g. Warrior -> Academic). Entering a career from a
## different Class normally means its Tier 1 (p.49: "enter the first
## level of a Career from a different Class") — UNLESS the character
## has already stood in that exact target career before, on an earlier
## stint (see max_reentry_tier() above), per the request: re-entering a
## career you've already made progress in can resume one tier above
## where you left it, rather than forcing a climb back from scratch.
## This is enforced by the caller (the UI computes max_reentry_tier()
## as the ceiling for its Tier picker, which the player then chooses
## from — see the follow-up "it should be an option, not forced to the
## higher tier"), not re-validated here beyond the ordinary "does this
## tier exist" check below — a caller could still explicitly pass a
## lower tier (e.g. the "advance same career by one tier" button always
## passes current_tier + 1), which stays perfectly valid.
static func change_career(character: Character, new_career: CareerDefinition, new_tier: int) -> PurchaseResult:
	var result := PurchaseResult.new()
	var changing_class := character.career != null and character.career.career_class != new_career.career_class
	var cost := get_change_career_cost(has_completed_current_level(character), changing_class)
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result
	if new_career.get_level(new_tier) == null:
		result.message = "%s has no tier %d." % [new_career.career_name, new_tier]
		return result

	var from_career_name := character.career.career_name if character.career != null else ""
	var from_tier := character.current_tier

	character.experience_spent += cost
	character.career = new_career
	character.current_tier = new_tier
	## Per the request: a Career tab "advancement/change breakdown and
	## records" — logged here so it covers both a same-career tier
	## advance and a full career switch, the two things this function
	## already handles identically.
	character.career_history.append({
		"from_career": from_career_name,
		"from_tier": from_tier,
		"to_career": new_career.career_name,
		"to_tier": new_tier,
		"day_of_year": GameState.day_of_year,
		"imperial_year": GameState.imperial_year,
		"cost": cost,
	})

	result.success = true
	result.cost = cost
	result.message = "Now %s (%s, tier %d) — %d XP spent." % [
		new_career.get_level(new_tier).level_name, new_career.career_name, new_tier, cost
	]
	return result

## --- Selling (undoing a purchase) --------------------------------------
## Refunds the XP for the MOST RECENT advance/rank of something and
## removes it — there's no rule in the book for this (advancement is
## normally a one-way ratchet), but it exists here specifically so a
## misclick or a change of mind while spending XP doesn't need a
## from-scratch character to fix. Refunds reduce experience_spent
## (increasing XP available), not experience_total — you don't get to
## "un-earn" XP, you just get to change your mind about how it was
## spent. Each sell uses the CURRENT in-career/non-career status to work
## out the refund, which can differ from what was actually paid if the
## character's career has changed since — a documented simplification,
## not a rules position.

static func sell_characteristic_advance(character: Character, key: String) -> PurchaseResult:
	var result := PurchaseResult.new()
	var already: int = character.get_characteristic_advance_count(key)
	if already <= 0:
		result.message = "No purchased advances in %s to sell." % key
		return result

	var in_scope := unlocked_characteristics(character).has(key)
	var refund := get_characteristic_advance_cost(already - 1, in_scope)

	character.experience_spent = max(0, character.experience_spent - refund)
	character.characteristic_advances[key] = already - 1
	if character.characteristic_advances[key] <= 0:
		character.characteristic_advances.erase(key)
	character.characteristics.set_value(key, character.characteristics.get_value(key) - 1)
	character.recompute_max_wounds()

	result.success = true
	result.cost = refund
	result.message = "%s reduced by 1 (%d XP refunded)." % [key, refund]
	return result

static func sell_skill_advance(character: Character, skill_def: SkillDefinition,
		specialisation: String = "") -> PurchaseResult:
	var result := PurchaseResult.new()
	var display_name := skill_def.display_name(specialisation)
	var already: int = character.skill_advances.get(display_name, 0)
	if already <= 0:
		result.message = "No purchased advances in %s to sell." % display_name
		return result

	var any_display_name := skill_def.display_name("Any")
	var unlocked := unlocked_skills(character)
	var in_scope := unlocked.has(display_name) or unlocked.has(any_display_name)
	var refund := get_skill_advance_cost(already - 1, in_scope)

	character.experience_spent = max(0, character.experience_spent - refund)
	character.skill_advances[display_name] = already - 1
	if character.skill_advances[display_name] <= 0:
		character.skill_advances.erase(display_name)

	result.success = true
	result.cost = refund
	result.message = "%s reduced to %d (%d XP refunded)." % [
		display_name, character.get_skill_value(skill_def, specialisation), refund
	]
	return result

static func sell_talent_advance(character: Character, talent_name: String) -> PurchaseResult:
	var result := PurchaseResult.new()
	var already: int = character.get_talent_rank(talent_name)
	if already <= 0:
		result.message = "%s isn't taken, nothing to sell." % talent_name
		return result

	var refund := get_talent_advance_cost(already - 1)

	character.experience_spent = max(0, character.experience_spent - refund)
	character.talents_taken[talent_name] = already - 1
	if character.talents_taken[talent_name] <= 0:
		character.talents_taken.erase(talent_name)
	## See purchase_talent_advance's own comment -- Hardy's Wounds bonus
	## must shrink back down immediately on a sell too.
	character.recompute_max_wounds()

	result.success = true
	result.cost = refund
	result.message = "%s rank reduced to %d (%d XP refunded)." % [talent_name, already - 1, refund]
	return result

## --- Miracles (p.204/226) ---------------------------------------------
## "You are blessed by one of the Gods and can empower one of your
## Cult's Miracles" (Invoke's own Talent text) — the first Miracle comes
## free with the Talent itself; further ones cost 100 XP per Miracle
## currently known ("if you already know 3 miracles, your next miracle
## costs 300 XP"). Must be from the same god as the character's Invoke
## Talent — Blessings and Miracles can't be split across different gods.
## Shared tiered-cost calculation for Petty Magic (p.142) and Arcane
## Magic (p.147) — both use the same shape of table ("Up to Bonus×1:
## cost, Up to Bonus×2: 2×cost, ..."), just with a different base cost
## and a different bonus Characteristic. Worked through both talents'
## own examples by hand to get this right rather than guessing at the
## formula from the table headers alone:
## - Petty (WPB=3, already know 3 from the free grant): the 4th spell
##   (bought while knowing 3, which is "up to WPB×1") costs 50 XP; the
##   5th/6th/7th (bought while knowing 4/5/6, "up to WPB×2") cost 100
##   XP each. So the tier is ceil(known_count / bonus), using whatever
##   is currently known *before* this purchase.
## - Arcane (INT Bonus=4, no free grant): the 1st spell (known=0) still
##   costs 100 XP, i.e. tier 1 — the one case ceil(known/bonus) alone
##   doesn't cover, since ceil(0/4) is 0. Special-cased to tier 1 when
##   nothing is known yet; Petty never actually hits this case since
##   its free grant means known_count is never 0 before a purchase.
static func _tiered_spell_cost(known_count: int, bonus: int, base_cost: int) -> int:
	if bonus <= 0:
		return base_cost
	var tier: int = 1 if known_count == 0 else ceili(float(known_count) / float(bonus))
	return base_cost * tier

## Petty Magic (p.142): "You have the spark to cast magic... When you
## take this Talent, you manifest, and permanently memorise, a number
## of spells equal to your Willpower Bonus" (handled at
## learn_petty_magic_from_trainer, not here) "You can learn extra
## Petty spells for the following cost in XP" — this is that "extra."
static func purchase_petty_spell(character: Character, spell_name: String) -> PurchaseResult:
	var result := PurchaseResult.new()
	if not character.has_talent("Petty Magic"):
		result.message = "You need the Petty Magic Talent before you can learn Petty spells."
		return result
	var spell: SpellDefinition = GameData.spell_db.find_by_name(spell_name)
	if spell == null or spell.spell_type != "Petty":
		result.message = "%s isn't a known Petty spell." % spell_name
		return result
	if character.known_spells.has(spell_name):
		result.message = "You already know %s." % spell_name
		return result

	var known_count := 0
	for s in character.known_spells:
		var sd: SpellDefinition = GameData.spell_db.find_by_name(s)
		if sd != null and sd.spell_type == "Petty":
			known_count += 1
	var wpb := character.get_characteristic_bonus("willpower")
	var cost := _tiered_spell_cost(known_count, wpb, 50)
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result

	character.experience_spent += cost
	character.known_spells.append(spell_name)
	result.success = true
	result.cost = cost
	result.message = "%s learned (%d XP spent)." % [spell_name, cost]
	return result

## Arcane Magic (Lore) (p.147): "You may now memorise spells from your
## chosen Lore for the following cost in XP" — no free grant here,
## unlike Petty Magic; every Arcane spell, including the first, costs
## XP. Per the book's own "Arcane Spells" section (p.242): these are
## "extra options for every Lore of Magic... counted as Lore spells in
## all ways, [learnable] from and taught to those sharing the same
## Arcane Magic Talent" — i.e. a single shared spell pool every
## Arcane Magic (Lore) holder draws from, regardless of which specific
## Lore they picked, rather than 15 separate per-Lore lists. Requires
## the character to actually have an Arcane Magic (Lore) Talent, but
## doesn't otherwise check which Lore, matching that shared-pool rule.
##
## Also covers each Lore's own unique spells (spell_type "Lore",
## e.g. the Lore of Fire's 8 signature spells on p.247-248) — unlike the
## generic Arcane list above, these DO require the spell's `lore` to
## match the character's own chosen Lore exactly ("Colour Magic" p.245:
## eight separate 8-spell lists, one per Lore, not a shared pool). Both
## kinds draw from the same known_count/XP tier, since the book prices
## them identically as "spells from your chosen Lore" — there's no
## separate cheaper/pricier bucket for the generic list vs. the Lore's
## own spells.
static func purchase_arcane_spell(character: Character, spell_name: String) -> PurchaseResult:
	var result := PurchaseResult.new()
	var lore := character.get_arcane_lore()
	if lore == "":
		result.message = "You need an Arcane Magic (Lore) Talent before you can learn Arcane spells."
		return result
	var spell: SpellDefinition = GameData.spell_db.find_by_name(spell_name)
	var is_generic_arcane: bool = spell != null and spell.spell_type == "Arcane"
	var is_matching_lore_spell: bool = spell != null and spell.spell_type == "Lore" and spell.lore == lore
	if spell == null or not (is_generic_arcane or is_matching_lore_spell):
		result.message = "%s isn't a spell from your Lore." % spell_name
		return result
	if character.known_spells.has(spell_name):
		result.message = "You already know %s." % spell_name
		return result

	var known_count := 0
	for s in character.known_spells:
		var sd: SpellDefinition = GameData.spell_db.find_by_name(s)
		if sd != null and (sd.spell_type == "Arcane" or sd.spell_type == "Lore"):
			known_count += 1
	var int_bonus := character.get_characteristic_bonus("intelligence")
	var cost := _tiered_spell_cost(known_count, int_bonus, 100)
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result

	character.experience_spent += cost
	character.known_spells.append(spell_name)
	result.success = true
	result.cost = cost
	result.message = "%s learned (%d XP spent)." % [spell_name, cost]
	return result

static func purchase_miracle(character: Character, miracle_name: String) -> PurchaseResult:
	var result := PurchaseResult.new()
	var god := character.get_invoke_god()
	if god == "":
		result.message = "You need the Invoke Talent before you can learn a Miracle."
		return result
	var miracle: PrayerDefinition = GameData.prayer_db.find_by_name(miracle_name)
	if miracle == null or miracle.prayer_type != "Miracle":
		result.message = "%s isn't a known Miracle." % miracle_name
		return result
	if miracle.god != god:
		result.message = "%s belongs to %s, not %s — Blessings and Miracles must be from the same god." % [miracle_name, miracle.god, god]
		return result
	if character.known_prayers.has(miracle_name):
		result.message = "You already know %s." % miracle_name
		return result

	var known_miracle_count := 0
	for p in character.known_prayers:
		var pd: PrayerDefinition = GameData.prayer_db.find_by_name(p)
		if pd != null and pd.prayer_type == "Miracle":
			known_miracle_count += 1

	var cost := 0 if known_miracle_count == 0 else 100 * known_miracle_count
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result

	character.experience_spent += cost
	character.known_prayers.append(miracle_name)
	result.success = true
	result.cost = cost
	result.message = "%s learned (%d XP spent)." % [miracle_name, cost]
	return result

## --- Learning outside a Career (p.48, "Training and Unusual Learning
## Endeavours... give the possibility of learning non-Career Talents")
## --------------------------------------------------------------------
## A trainer (e.g. a hermit wizard) can teach a Talent your own Career
## doesn't offer, at the normal cost rather than double — unlike
## purchase_talent_advance, this deliberately does NOT require the
## Talent to be in unlocked_talents(character).
##
## Petty Magic itself (p.142): "When you take this Talent, you
## manifest, and permanently memorise, a number of spells equal to your
## Willpower Bonus." Which specific spells isn't specified by the book
## (left to the GM/player) — chosen here as a random distinct sample
## from the Petty spell list, a reasonable simplification rather than
## an arbitrary single fixed set.
static func learn_petty_magic_from_trainer(character: Character) -> PurchaseResult:
	var result := PurchaseResult.new()
	if character.has_talent("Petty Magic"):
		result.message = "You already know Petty Magic."
		return result
	var cost := 100
	if character.get_experience_available() < cost:
		result.message = "Not enough XP (need %d, have %d)." % [cost, character.get_experience_available()]
		return result

	character.experience_spent += cost
	character.talents_taken["Petty Magic"] = 1

	var petty_pool: Array[String] = []
	for sp in GameData.spell_db.spells:
		if sp.spell_type == "Petty" and not character.known_spells.has(sp.spell_name):
			petty_pool.append(sp.spell_name)
	petty_pool.shuffle()
	var grant_count: int = min(character.get_characteristic_bonus("willpower"), petty_pool.size())
	var granted: Array[String] = []
	for i in range(grant_count):
		character.known_spells.append(petty_pool[i])
		granted.append(petty_pool[i])

	result.success = true
	result.cost = cost
	result.message = "Petty Magic learned (%d XP spent). Spells manifested: %s." % [cost, ", ".join(granted)]
	return result
