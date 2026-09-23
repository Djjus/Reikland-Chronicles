extends Resource
class_name SocialCombatNPCDefinition
## One opponent in a Social Combat encounter, per the design doc
## ("Social Combat — Design Doc v1", Section 1/2) and the follow-up
## request ("make sure it supports multiple NPCs in the same social
## combat"). SocialEncounterDefinition.npcs holds an Array of these —
## most encounters have exactly one (a single peddler, watchman, etc.)
## but a group encounter (e.g. two thugs shaking you down together)
## just populates more than one entry. Each NPC gets its own Composure
## pool, its own Wit (turn-order) stats, and its own portrait — a real
## roster, not one flat opponent.

## Empty means "generate one fresh via NPCNameGenerator," same as
## every existing Social Encounter does today for its one NPC.
@export var npc_display_name: String = ""

## "male", "female", or "" (generate one fresh via NPCNameGenerator
## alongside npc_display_name above — the normal case for every
## existing Social Encounter). Per the request ("wire it up to the
## Social NPCs too"): drives which of CareerPortraits' two art sets
## this NPC's own portrait comes from — see
## SocialEncounterScreen._build_npc_roster(). Only meaningful for a
## group encounter's 2nd+ NPC; the roster's very first NPC always
## mirrors the encounter's own name_info.gender instead, since that's
## also what the story text's {subj}/{obj}/{poss} pronouns already
## committed to.
@export var gender: String = ""

## Opposed-Test targets, same meaning as SocialEncounterDefinition's
## own legacy npc_fellowship/npc_willpower fields (kept there too, for
## the single-NPC synthesis fallback — see get_npcs() on that file).
@export var fellowship: int = 40
@export var willpower: int = 40

## Wit = intelligence + initiative (Design Doc Section 2) — determines
## this NPC's own slot in the Social Combat turn order alongside the
## party.
@export var intelligence: int = 35
@export var initiative: int = 35

## This NPC's own depleting Composure pool (Design Doc Section 1) — hit
## 0 and this specific NPC is out of the fight, same as a defeated
## monster in real combat (Design Doc Section 8). Per the request
## ("social encounters have too much health (composure) let half the
## current values for everyone"): halved from the original default of
## 20 — a hand-authored group encounter can still set its own value per
## NPC here, this is just the out-of-the-box default new entries start
## at.
@export var composure_max: int = 10

## A CareerPortraits key (see career_portraits.gd), same convention as
## SocialEncounterDefinition.portrait_career_key — empty falls back to
## the generic default portrait. Per the request ("social armor should
## work by comparing attacker vs defender status... it should increase
## status by NPCs career tier"), this key now does double duty: it's
## also the lookup into GameData.careers this NPC's Status Tier
## (Brass/Silver/Gold) derives from — see get_status_ordinal() below.
## Every one of the 12 core encounters' existing keys ("outlaw",
## "charlatan", "beggar", etc.) already matches a real CareerDefinition
## 1:1, so this needed no new data at all.
@export var portrait_career_key: String = ""

## This NPC's Status Tier (Brass=1/Silver=2/Gold=3), replacing the old
## flat `social_armor` int entirely. Per the request: derived from a
## REAL Career (looked up by portrait_career_key against GameData.careers,
## matching by CareerPortraits.key_for()) rather than a hand-set number —
## and the social Difficulty Tier of the encounter stands in as that
## Career's own level (1-4; every Career in this project has exactly 4
## CareerLevels), so a tougher area doesn't just make an NPC hit harder,
## it makes them a more senior member of their own profession, with the
## Status that implies. `social_tier` is GameState.current_social_difficulty_tier,
## already floored at 1 by the time an encounter starts (see
## Overworld._on_social_marker_clicked()) — clamped again here to each
## Career's own real level range regardless. Falls back to Brass (1),
## matching Character.get_status_ordinal()'s own no-career convention,
## when portrait_career_key is empty or matches no real Career.
func get_status_ordinal(social_tier: int) -> int:
	const ORDER := {"Brass": 1, "Silver": 2, "Gold": 3}
	var career := _resolve_career()
	if career == null or career.levels.is_empty():
		return 1
	var level := career.get_level(get_career_tier_level(social_tier))
	if level == null:
		return 1
	return ORDER.get(level.status_tier, 1)

## The Career Level (1-4) this NPC's Status actually derives from — the
## social Difficulty Tier standing in as that Career's own level, clamped
## to its real range (see get_status_ordinal()'s own comment for why).
## Broken out as its own value, rather than folded straight into
## get_status_ordinal() above, per the request ("show attacker / defender
## career tier lvl in the social encounter top bar") — the top bar wants
## the raw level number sitting right next to the Status name it
## produces, not just the Status itself. Falls back to 1 when there's no
## real Career to derive from, same no-career convention as
## get_status_ordinal()'s own.
func get_career_tier_level(social_tier: int) -> int:
	var career := _resolve_career()
	if career == null or career.levels.is_empty():
		return 1
	return clampi(social_tier, 1, career.levels.size())

## Shared portrait_career_key -> real CareerDefinition lookup, used by
## get_status_ordinal()/get_career_tier_level() above and
## get_etiquette_group() below — previously duplicated in both.
func _resolve_career() -> CareerDefinition:
	if portrait_career_key.is_empty():
		return null
	for c in GameData.careers:
		if CareerPortraits.key_for(c.career_name) == portrait_career_key:
			return c
	return null

## Which of Etiquette (Social Group)'s 7 situation_options (Criminals/
## Cultists/Guilders/Nobles/Scholars/Servants/Soldiers) this NPC counts
## as belonging to, for that Talent's own group-match bonus (see
## SocialEncounterScreen._attempt_social_attack()). Derived the same way
## get_status_ordinal() above derives Status -- looked up by
## portrait_career_key against a real GameData.careers entry -- but off
## that Career's own career_class rather than its level. Per the
## request ("Best-effort career_class mapping"): only 5 of the 8
## career_class values line up cleanly with one of Etiquette's 7 groups;
## Peasant/Ranger/Riverfolk (and "Cultists"/"Servants", which have no
## career_class counterpart at all) return "" -- no match, same as any
## other "not modeled yet" gap elsewhere in this Talent database.
const ETIQUETTE_GROUP_BY_CAREER_CLASS := {
	"Rogue": "Criminals",
	"Burgher": "Guilders",
	"Courtier": "Nobles",
	"Academic": "Scholars",
	"Warrior": "Soldiers",
}
func get_etiquette_group() -> String:
	var career := _resolve_career()
	if career == null:
		return ""
	return ETIQUETTE_GROUP_BY_CAREER_CLASS.get(career.career_class, "")

## Builds a real Character for this NPC, exactly mirroring
## MonsterDefinition.to_character()'s own pattern — SocialCombatEncounter
## seats party members and NPCs side-by-side in the same turn order, so
## an NPC needs to be a genuine Character (real Willpower/Fellowship/
## Intelligence/Initiative, a Composure pool, an "adversary" allegiance)
## rather than a special-cased second type every call site has to
## branch on. Only the four characteristics Social Combat actually
## reads (WP, Fel, Int, Initiative) are set from real data; the other
## six are left at CharacteristicSet's own defaults since nothing in
## Social Combat looks at a Weapon Skill or Strength for these NPCs.
## `display_name` is passed in rather than read from npc_display_name
## directly so the caller can supply a freshly-rolled NPCNameGenerator
## name when npc_display_name is empty (the normal case), matching how
## the single-NPC path already generates a name per playthrough today.
## `resolved_gender` works the same way for the same reason — see this
## resource's own `gender` field comment and
## SocialEncounterScreen._build_npc_roster().
func to_character(display_name: String, resolved_gender: String = "male") -> Character:
	var c := Character.new()
	c.character_name = display_name
	c.gender = resolved_gender
	var stats := CharacteristicSet.new()
	stats.willpower = willpower
	stats.fellowship = fellowship
	stats.intelligence = intelligence
	stats.initiative = initiative
	c.characteristics = stats
	c.composure_max = composure_max
	c.composure_current = composure_max
	c.allegiance = "adversary"
	return c
