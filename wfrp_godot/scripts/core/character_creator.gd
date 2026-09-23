extends RefCounted
class_name CharacterCreator
## Orchestrates the character-creation sequence, following the book's
## own step order (p.24): 1) Species, 2) Class and Career,
## 3) Attributes, 4) Skills and Talents, 5) Trappings.
##
## Bonus XP for accepting randomness (p.24/33): the book offers XP for
## letting dice choose instead of picking — +20 XP for a random
## Species, +50/+25 XP for keeping a random Career roll (first roll vs
## one of three), +50/+25 XP for keeping vs rearranging random
## Characteristic rolls. Tracked here as plain ints the UI reads and
## adds to the character's starting XP once creation finishes.

## Species Skills and Talents (Character Creation): fixed book numbers,
## the same for every Species — only the pool each Species offers
## differs (RaceDefinition.racial_skill_pool). "Choose 3 Skills to gain
## 5 Advances each, and 3 Skills to gain 3 Advances each."
const SPECIES_HIGH_PICK_COUNT := 3
const SPECIES_HIGH_PICK_AMOUNT := 5
const SPECIES_LOW_PICK_COUNT := 3
const SPECIES_LOW_PICK_AMOUNT := 3

## Career Skills and Talents (Character Creation): "Allocate 40
## Advances to your eight starting Skills, with no more than 10
## Advances allocated to any single Skill at this stage."
const CAREER_SKILL_ADVANCE_POOL := 40
const CAREER_SKILL_ADVANCE_CAP := 10

## Attributes (p.33), Step 3's "Point Buy" alternative: "allocate 100
## points across the 10 Characteristics as you prefer, with a minimum
## of 4 and a maximum of 18 allocated to any single Characteristic."
## Like rerolling, this has no Bonus XP attached.
const POINT_BUY_TOTAL := 100
const POINT_BUY_MIN := 4
const POINT_BUY_MAX := 18

static func roll_characteristics(race: RaceDefinition) -> CharacteristicSet:
	var set := CharacteristicSet.new()
	for key in CharacteristicSet.KEYS:
		var base: int = race.characteristic_bases.get(key, 20)
		set.set_value(key, Dice.roll_characteristic(base))
	return set

## Advance Characteristics (Attributes step, p.33's Advance Scheme):
## "you can allocate a total of 5 Advances across [the] three
## Characteristics" marked with a cross (no brass/silver/gold
## background) in the chosen Career's own Advance Scheme. Per
## clarification, those three are exactly the Characteristics keyed in
## the Career's own Tier 1 (Brass) CareerLevel.attribute_advances (see
## career_level.gd) — the same dictionary BanditGenerator.build_bandit()
## already reads the same way to find "the career's tier
## characteristics" for its own free-advance grant, so no new data was
## needed. Unlike the old Human-only "+1 to 2 Characteristics" Bonus
## Pick mechanic this replaces, every Race gets the same allocation,
## because the book ties it to the Career, not the Species.
const ADVANCE_CHARACTERISTICS_POOL := 5

## The (up to 3) Characteristics eligible for this Career's free Advance
## Characteristics allocation. Empty only if the Career has no Tier 1
## level at all, which shouldn't happen for any real, fully-defined
## Career.
static func get_advance_characteristics(career: CareerDefinition) -> Array:
	if career == null:
		return []
	var level := career.get_level(1)
	return level.attribute_advances.keys() if level else []

## `advance_choices`: {characteristic_key: advances_spent}, expected to
## already be validated by the UI to sum to no more than
## ADVANCE_CHARACTERISTICS_POOL and to only use keys from
## get_advance_characteristics(character.career). Writes to BOTH
## character.characteristics (the actual +1-per-Advance bump) and
## character.characteristic_advances (the running Advance count
## Advancement.gd's own XP-cost curve builds on for every later paid
## Advance) — mirrors Advancement.purchase_characteristic_advance()'s own
## bookkeeping and BanditGenerator.build_bandit()'s own free-advance
## grant, so these free creation-time Advances count the same as any
## other Advance from here on, rather than being an invisible flat bonus
## that later purchases would mis-price.
static func apply_advance_characteristics(character: Character, advance_choices: Dictionary) -> void:
	for key in advance_choices:
		var amount: int = int(advance_choices[key])
		if amount <= 0:
			continue
		character.characteristics.set_value(key, character.characteristics.get_value(key) + amount)
		character.characteristic_advances[key] = character.characteristic_advances.get(key, 0) + amount

## Applies the race's own guaranteed talents plus, per independent
## choice group in race.racial_talent_choice_groups, the player's one
## pick from that group — the book's own "Skill/Talent OR Skill/Talent"
## listings. A Species can have more than one such group (e.g. Dwarfs:
## "Read/Write or Relentless" AND, separately, "Resolute or
## Strong-minded") — `choice_group_picks[i]` is the pick for group i,
## ignored (not an error) if missing or not actually a member of that
## group.
static func apply_racial_talents(character: Character, race: RaceDefinition, choice_group_picks: Array = []) -> void:
	for t in race.racial_talents:
		character.talents_taken[t] = character.talents_taken.get(t, 0) + 1
	for i in range(race.racial_talent_choice_groups.size()):
		if i >= choice_group_picks.size():
			continue
		var pick: String = choice_group_picks[i]
		var group: Array = race.racial_talent_choice_groups[i]
		if group.has(pick):
			character.talents_taken[pick] = character.talents_taken.get(pick, 0) + 1

## True if `pool` is large enough to offer a genuine "3 for +5, then 3
## more for +3" choice. False for this project's own small non-book
## pools (Gnome/Ogre, both size 3 — see auto_grant_species_skills).
static func species_pool_needs_choice(pool: Array) -> bool:
	return pool.size() > SPECIES_HIGH_PICK_COUNT

## Fallback for a pool too small to offer a real choice — grants every
## pool entry at the high (+5) rate rather than forcing a degenerate
## "3-of-3, then 3-of-nothing" picker on the player. Only this
## project's own non-book Gnome/Ogre currently hit this path.
static func auto_grant_species_skills(character: Character, pool: Array) -> void:
	for entry in pool:
		character.skill_advances[entry] = character.skill_advances.get(entry, 0) + SPECIES_HIGH_PICK_AMOUNT

## Applies the player's resolved Species Skill picks. `high_picks` (up
## to SPECIES_HIGH_PICK_COUNT) get +5 Advances each, `low_picks` (up to
## SPECIES_LOW_PICK_COUNT, drawn from whatever's left of the pool) get
## +3 each. Entries must already be resolved to a specific
## specialisation if the pool entry itself was an "(any)" qualifier
## (e.g. "Trade (Cook)", not "Trade (any one)") — the UI resolves that
## choice before calling this.
static func apply_species_skill_picks(character: Character, high_picks: Array, low_picks: Array) -> void:
	for entry in high_picks:
		character.skill_advances[entry] = character.skill_advances.get(entry, 0) + SPECIES_HIGH_PICK_AMOUNT
	for entry in low_picks:
		character.skill_advances[entry] = character.skill_advances.get(entry, 0) + SPECIES_LOW_PICK_AMOUNT

## Grants race.racial_random_talent_count rolls on the book's Random
## Talents table (RandomTalentsTable), rerolling any result that
## duplicates a Talent the character already has — the table's own
## note: "If you roll a Talent you already have, you may reroll."
## Three table results carry their own "(any one)" sub-choice (Acute
## Sense, Craftsman, Resistance) — resolved against the matching
## TalentDefinition's own situation_options where this project's data
## has one populated (only Craftsman currently does); granted as the
## bare base name otherwise, rather than fabricating an option list the
## data doesn't back. `sub_choice_resolver`, if given, is called as
## Callable(base_name: String, options: Array) -> String to ask the
## player for their pick; an empty/invalid result falls back to the
## first listed option (also the behaviour with no resolver at all).
static func roll_racial_random_talents(character: Character, race: RaceDefinition,
		sub_choice_resolver: Callable = Callable()) -> Array[String]:
	var granted: Array[String] = []
	var attempts := 0
	while granted.size() < race.racial_random_talent_count and attempts < 200:
		attempts += 1
		var base_name := RandomTalentsTable.roll_name()
		var final_name := base_name
		if RandomTalentsTable.needs_sub_choice(base_name):
			var td: TalentDefinition = GameData.talent_db.find_by_name(base_name)
			var options: Array = td.situation_options if td else []
			if not options.is_empty():
				var chosen := ""
				if sub_choice_resolver.is_valid():
					chosen = sub_choice_resolver.call(base_name, options)
				if chosen == "" or not options.has(chosen):
					chosen = options[0]
				final_name = "%s (%s)" % [base_name, chosen]
		if character.talents_taken.has(final_name) or granted.has(final_name):
			continue   ## reroll on duplicate, per the table's own note
		character.talents_taken[final_name] = character.talents_taken.get(final_name, 0) + 1
		granted.append(final_name)
	return granted

## Applies the player's Career Skill Advance allocation — `allocations`
## is {skill_display_name: advances}, already validated by the UI
## against CAREER_SKILL_ADVANCE_POOL/_CAP. Adds on top of any Advances
## the same Skill already has from Species picks, per the book's own
## worked example (Lindsay can put Career Advances into Leadership even
## though Human already grants it Species Advances — the 10-cap applies
## only to this single 40-point allocation, not the running total).
static func apply_career_skill_allocation(character: Character, allocations: Dictionary) -> void:
	for entry in allocations:
		var amount: int = allocations[entry]
		if amount > 0:
			character.skill_advances[entry] = character.skill_advances.get(entry, 0) + amount

## Applies the player's single Career Talent pick (one of the 4 listed
## at Tier 1 — "You may also choose a single Talent to learn").
static func apply_career_talent_pick(character: Character, talent_name: String) -> void:
	if talent_name != "":
		character.talents_taken[talent_name] = character.talents_taken.get(talent_name, 0) + 1

static func create_character(name: String, race: RaceDefinition, career: CareerDefinition,
		advance_choices: Dictionary = {}, racial_talent_group_picks: Array = [],
		bonus_xp: int = 0, species_skill_high_picks: Array = [], species_skill_low_picks: Array = [],
		rolled_random_talents: Array = [], career_skill_allocations: Dictionary = {},
		career_talent_pick: String = "", class_trappings: Array = []) -> Character:
	var character := Character.new()
	character.character_name = name
	character.race = race
	character.career = career
	character.current_tier = 1

	character.characteristics = roll_characteristics(race)
	apply_advance_characteristics(character, advance_choices)

	character.fate_points = race.starting_fate
	character.fortune_points = race.starting_fate
	character.resilience = race.starting_resilience
	character.resolve = race.starting_resilience

	apply_racial_talents(character, race, racial_talent_group_picks)
	if species_pool_needs_choice(race.racial_skill_pool):
		apply_species_skill_picks(character, species_skill_high_picks, species_skill_low_picks)
	else:
		auto_grant_species_skills(character, race.racial_skill_pool)
	## rolled_random_talents arrives already resolved (rolled, reroll-on-
	## duplicate applied, sub-choices picked) by the Skills and Talents
	## step — granted here rather than re-rolled, so what the player saw
	## during creation is exactly what the finished character has.
	for t in rolled_random_talents:
		character.talents_taken[t] = character.talents_taken.get(t, 0) + 1

	apply_career_skill_allocation(character, career_skill_allocations)
	apply_career_talent_pick(character, career_talent_pick)

	## Luck (p.??): "your maximum Fortune Points now equal your current
	## Fate points plus the number of times you've taken Luck" — every
	## talent grant above (racial, random, career pick) is done by this
	## point, so a newly-created character who happens to start with Luck
	## already gets the correct higher starting Fortune total instead of
	## the plain race.starting_fate value set earlier.
	character.fortune_points = character.get_max_fortune_points()

	## Starting career tier grants trainable skills/talents/trappings.
	## Per the ammo request: AmmoLookup.resolve_trapping() splits a
	## compound trapping string like "Bow with 10 arrows" into the real,
	## equippable "Bow" plus 10 real "Arrow" items — previously the
	## whole string was pushed into inventory verbatim, which matched no
	## real WeaponDefinition (so the weapon couldn't even be equipped)
	## and granted no real ammo at all. A trapping that doesn't fit that
	## shape (a bare weapon name, or any other kind of trapping text)
	## comes back unchanged, exactly as before.
	var level := career.get_level(1)
	if level:
		for trapping in level.trappings:
			character.inventory.append_array(AmmoLookup.resolve_trapping(trapping))
		for spell_name in level.starting_spells:
			character.known_spells.append(spell_name)
		for prayer_name in level.starting_prayers:
			character.known_prayers.append(prayer_name)
	## Class Trappings (Trappings step): granted by Class on top of the
	## Career's own Tier-1 trappings above, per the book's own separate
	## "CLASS TRAPPINGS" section. Arrives pre-resolved (dice already
	## rolled, Rogues' Hood-or-Mask already picked) by the Trappings
	## step, same reasoning as rolled_random_talents above.
	for trapping in class_trappings:
		character.inventory.append_array(AmmoLookup.resolve_trapping(trapping))

	## Real starting XP in the book comes from character-creation
	## background questions (Chapter 2) this project doesn't implement,
	## plus any Bonus XP earned during creation for accepting random
	## results (see the class doc comment above) — passed in from the
	## creation screen once the player's actually made those choices.
	## As a placeholder for the background-questions portion so the
	## Advancement screen has something to work with immediately, every
	## new character starts with a flat stipend on top of that.
	character.experience_total = 100 + bonus_xp

	## A single starting consumable so the "Use Item" combat action has
	## something to actually use — there's no shop/economy system yet to
	## buy more.
	character.inventory.append("Healing Draught")

	character.recompute_max_wounds()
	## recompute_max_wounds() only ever clamps wounds_current DOWN to the
	## computed max (it's also called after buying a Toughness/Strength/
	## Willpower advance mid-game, where healing the character back to
	## full would be wrong) — but Character.wounds_current defaults to 1,
	## so a freshly created character was left at 1/N Wounds instead of
	## full. Explicitly heal to full here, once, at creation.
	character.wounds_current = character.wounds_max
	return character
