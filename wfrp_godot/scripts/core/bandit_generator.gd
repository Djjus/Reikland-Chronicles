extends RefCounted
class_name BanditGenerator
## Per the request: "Bandit"/"Outlaw" enemies keep their existing
## monster names, but instead of a single fixed stat block, they're
## built on the fly as a real Character from a random player-eligible
## Race and an appropriate Career — the Outlaw career (Brigand ->
## Outlaw -> Outlaw Chief -> Bandit King), which already exists in this
## project's own career database — then scaled by the current field's
## Difficulty Tier.
##
## Deliberately reuses CharacterCreator/GameData rather than a
## parallel data structure — a "Bandit" built this way is a completely
## normal Character as far as the rest of the game (combat, natural
## weapon resolution, loot) is concerned; only how it got built is
## different from a MonsterDefinition-based monster.

const CAREER_NAME := "Outlaw"

## Per the follow-up request ("each difficulty tier should raise the
## career tier of the generated enemy"): Difficulty Tier 0 and 1 both
## still build from the career's own Tier 1 (Brigand) — Tier 0 as an
## even weaker beginner-area bandit than Tier 1 (see the "no talents at
## Tier 0" carve-out in build_bandit() below; the two share the same
## characteristics/skills otherwise, since char_bonus/skill_bonus are
## both 5*0=0 at Tier 0 anyway). Tiers 2-5 then raise the career tier in
## step, one-for-one — Outlaw only has 4 real CareerLevels, so Tier 5
## (the highest real Difficulty Tier) still only reaches career Tier 4,
## same as Tier 4 itself. _career_tier_for_area_tier() below re-clamps
## this generically against whatever career is actually passed in, so a
## future shorter career wouldn't be asked for a tier it doesn't have.
const AREA_TIER_TO_CAREER_TIER := {
	0: 1,
	1: 1,
	2: 2,
	3: 3,
	4: 4,
	5: 4,
}

static func _career_tier_for_area_tier(area_tier: int, career: CareerDefinition) -> int:
	var mapped: int = AREA_TIER_TO_CAREER_TIER.get(clampi(area_tier, 0, 5), 1)
	return clampi(mapped, 1, maxi(career.levels.size(), 1))

static func build_bandit(monster_name: String, area_tier: int) -> Character:
	var career: CareerDefinition = GameData.find_career(CAREER_NAME)
	if career == null:
		return null
	var career_tier := _career_tier_for_area_tier(area_tier, career)
	var level := career.get_level(career_tier)
	if level == null:
		return null

	var race := _pick_race(career)
	if race == null:
		return null

	var character := CharacterCreator.create_character(monster_name, race, career, {})
	character.allegiance = "adversary"
	## Starting default — a real primary weapon before combat even
	## begins. Once a fight starts, _maybe_switch_monster_weapon_for_
	## range() (field_encounter_screen.gd) re-picks this every Turn
	## based on actual range to the nearest enemy, per the follow-up
	## request ("weapons they should switch during combat to whatever
	## is best at the moment, ie ranged or melee") — this initial value
	## just needs to be A real weapon, not the final word.
	character.equipped_weapon = "Sword"
	## Per the follow-up request: the career tier this bandit stands in
	## now scales with the area's own Difficulty Tier (see
	## AREA_TIER_TO_CAREER_TIER above) rather than always being Tier 1 —
	## set here, before the cumulative unlocks below, so Advancement's
	## own unlocked_characteristics()/unlocked_skills() (which both walk
	## career.get_level(1..character.current_tier)) correctly pull in
	## every tier from Brigand up through whichever tier this Tier of
	## bandit has reached, not just Tier 1's own three stats.
	character.current_tier = career_tier

	## "each career tier above 0 should include characteristics, skill
	## and talents from that tier" — reuses Advancement's own cumulative
	## unlocked_characteristics()/unlocked_skills() (the same helpers a
	## real player Character's Career tab is built from) rather than
	## re-walking career.levels by hand, so a Tier 3 bandit's stat/skill
	## set is exactly "everything a real Tier 3 Outlaw would have
	## unlocked" — Brigand's WS/Strength/Toughness AND Outlaw's own
	## Ballistic Skill AND Outlaw Chief's own Initiative, not just
	## whichever single CareerLevel career_tier happens to land on.
	##
	## "increase characteristics and skill by +(difficult Tier x 5) as
	## now" — the flat per-stat bonus still scales off the raw area
	## Difficulty Tier (0-5), same formula as before this change; it's
	## the SET of characteristics/skills it's applied to that's now
	## cumulative across tiers, not the bonus amount itself.
	var char_bonus := 5 * area_tier
	if char_bonus > 0:
		for key in Advancement.unlocked_characteristics(character):
			character.characteristics.set_value(key, character.characteristics.get_value(key) + char_bonus)
			character.characteristic_advances[key] = character.characteristic_advances.get(key, 0) + char_bonus

	var skill_bonus := 5 * area_tier
	if skill_bonus > 0:
		for skill_display_name in Advancement.unlocked_skills(character):
			if Advancement.is_any_qualifier(skill_display_name):
				continue
			character.skill_advances[skill_display_name] = character.skill_advances.get(skill_display_name, 0) + skill_bonus

	## Per the follow-up request ("talents from difficulty tier 1-5 give
	## them all talents at rank 1 maximum from each career tier level
	## (difficulty tier 0 get no talents)"): a genuine behaviour change
	## from before — talents no longer scale their own rank with area
	## Tier (every talent is flatly rank 1, regardless of how high the
	## Tier is) and a Tier 0 bandit now has NO talents at all, rather
	## than the old "at least rank 1" floor. What DOES grow with Tier is
	## which talents are present at all: every talent from every
	## unlocked career level (1 up through career_tier) is granted, not
	## just career_tier's own — so a Tier 3 bandit has Brigand's own
	## talents (Combat Aware, Criminal, Rover, Flee!) AND Outlaw's
	## (Dirty Fighting, Marksman, Strike to Stun, Trapper) AND Outlaw
	## Chief's (Rapid Reload, Roughrider, Menacing, Very Resilient), each
	## at rank 1.
	if area_tier >= 1:
		for t in range(1, career_tier + 1):
			var tier_level := career.get_level(t)
			if tier_level == null:
				continue
			for talent_name in tier_level.talents:
				if Advancement.is_any_qualifier(talent_name):
					continue
				character.talents_taken[talent_name] = 1

	## Per the follow-up request ("what about trappings" -> "cumulative
	## like skills/talents"): every unlocked career tier's own Trappings
	## are added to inventory too, not just Tier 1's. CharacterCreator.
	## create_character() above already grants career_tier 1's own
	## trappings (Bedroll, Sword, Leather Jerkin, Tinderbox) unconditionally
	## — that part is untouched here, EXCEPT that Tier 1's trappings are
	## now also re-scanned below (t starts at 1, not 2) purely to pick up
	## Leather Jerkin for the equipped_armour pass, since Tier 1 armour
	## was previously just hardcoded separately. Tiers 2 through
	## career_tier layer on: a Tier 3 bandit ends up carrying Outlaw's own
	## Bow with 10 Arrows/Shield/Tent AND Outlaw Chief's own Helm/Riding
	## Horse with Saddle and Tack/Sleeved Mail Shirt/Band of Outlaws on
	## top of Brigand's starting kit. Uses the same AmmoLookup.
	## resolve_trapping() call CharacterCreator itself uses for Tier 1, so
	## a compound trapping string ("Bow with 10 Arrows") still splits into
	## a real equippable Bow plus real Arrow items exactly the same way.
	##
	## Per the explicit follow-up ("They should always use all the armor
	## they have"): every resolved trapping name that matches a real
	## ArmourDefinition (GameData.armour_db) is auto-equipped into
	## equipped_armour — not just left sitting in inventory. Real armour
	## pieces cover non-overlapping body locations (e.g. Leather Jerkin
	## is Body-only, Helm is Head-only), so a higher-tier bandit ends up
	## wearing everything it owns simultaneously, same as a real player
	## Character would choose to. Anything that doesn't resolve to a real
	## armour piece (a weapon, "Riding Horse with Saddle and Tack", "Band
	## of Outlaws", or the data-naming quirk "Sleeved Mail Shirt" which
	## doesn't exactly match the "Mail Shirt" ArmourDefinition) is left as
	## an inert inventory item, same as before.
	##
	## Weapon selection, by contrast, is deliberately NOT set here at
	## all — per the same follow-up ("weapons they should switch during
	## combat to whatever is best at the moment, ie ranged or melee"),
	## that's now handled dynamically, once per Turn, by
	## _maybe_switch_monster_weapon_for_range() in
	## field_encounter_screen.gd, which picks ranged or melee from
	## whatever this bandit is carrying based on actual distance to the
	## nearest enemy. equipped_weapon above is just a starting default.
	var equipped_armour_names: Array[String] = []
	for t in range(1, career_tier + 1):
		var tier_level := career.get_level(t)
		if tier_level == null:
			continue
		for trapping in tier_level.trappings:
			var resolved := AmmoLookup.resolve_trapping(trapping)
			if t >= 2:
				character.inventory.append_array(resolved)
			for resolved_name in resolved:
				if GameData.armour_db.find_by_name(resolved_name) != null and not equipped_armour_names.has(resolved_name):
					equipped_armour_names.append(resolved_name)
	character.equipped_armour = equipped_armour_names

	character.recompute_max_wounds()
	character.wounds_current = character.wounds_max
	return character

## Picks a race the Outlaw career is actually eligible for (matching
## the request's "human, dwarf, elf etc") rather than always Human —
## falls back to Human if the career's own valid_races is somehow
## empty or none of them resolve in GameData.
static func _pick_race(career: CareerDefinition) -> RaceDefinition:
	var eligible: Array[RaceDefinition] = []
	for race_name in career.valid_races:
		var r := GameData.find_race(race_name)
		if r != null:
			eligible.append(r)
	if eligible.is_empty():
		return GameData.find_race("Human")
	return eligible[randi() % eligible.size()]
