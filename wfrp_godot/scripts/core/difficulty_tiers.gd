extends RefCounted
class_name DifficultyTiers
## Enemy/Monster Difficulty Tier system, per the request: a template
## that adds a flat bonus to every one of a monster's base
## Characteristics (WS, BS, S, T, I, Agi, Dex, Int, WP, Fel) — not
## Wounds, Armour, or weapon Ratings directly, though a higher
## Toughness/Strength does flow through into more effective soak and
## Damage on its own. Applied once, at the moment a monster's
## Character is built for an encounter (see field_encounter_screen.gd)
## — never touches the underlying MonsterDefinition data itself, so
## the same "Giant Rat" template produces a stronger or weaker
## Character purely based on which Tier the encounter happened in.
##
## Originally "+0/5/10/15/20" across "tier 0-5" (with Tier 5's own
## value extrapolated, since only five values were given for six
## tiers). Corrected per the follow-up request to a doubled +10-per-
## tier progression instead.
const TIER_BONUS := {
	0: 0,
	1: 10,
	2: 20,
	3: 30,
	4: 40,
	5: 50,
}

## Per the request: "consider Tier 0 area beginner area and do not
## create enemies there that naturally have more than 12 hp." Checked
## against a monster's own base wounds_max (before any Tier bonus —
## Tier 0's own bonus is always +0 anyway, so this is also just its
## real Wounds) so a newly-added tough monster can never accidentally
## show up in a starting area just because no area happens to restrict
## its own monster_pool. Applies wherever tier == 0, not hardcoded to
## any one map's own beginner zone, so it holds for any future map
## too.
const BEGINNER_AREA_MAX_WOUNDS := 12

static func get_bonus(tier: int) -> int:
	return TIER_BONUS.get(clampi(tier, 0, 5), 0)

## Per the request ("we have difficulty level in combat, let's add it to
## social encounters too... all encounters should have the same
## modifiers"): Social Combat NPCs get the exact same TIER_BONUS table
## above applied to the four real Characteristics they carry (see
## apply_social_npc_tier_bonus() below), plus these two smaller tables
## for Composure and Social Armor — a Social NPC's "health" and damage
## reduction aren't derived from any Characteristic the way a monster's
## Wounds comes from Toughness, so they need their own bonus numbers
## rather than reusing TIER_BONUS's own (much larger, ~30-50 range)
## values wholesale. Originally scaled against a composure_max=20
## baseline (Tier 5 taking it to 30, +50%). CORRECTED per a direct
## follow-up balance request ("social encounters have too much health
## (composure) let half the current values for everyone"): the baseline
## itself was halved to 10 (see SocialEncounterDefinition.get_npcs()
## and SocialCombatNPCDefinition's own default), and this table was
## halved right alongside it so the same relative relationship holds —
## Tier 5 still takes Composure from 10 to 15 (still +50%), just off a
## shorter, faster-resolving baseline. Social Armor's own table is
## untouched — the request was specifically about Composure ("health"),
## not damage reduction.
const COMPOSURE_BONUS := {
	0: 0,
	1: 1,
	2: 2,
	3: 3,
	4: 4,
	5: 5,
}

static func get_composure_bonus(tier: int) -> int:
	return COMPOSURE_BONUS.get(clampi(tier, 0, 5), 0)

## Social Armor no longer gets a flat per-Tier bonus at all — per the
## request ("social encounter social armor should work by comparing
## attacker vs defender status... remove the static + to armor from
## difficulty tier level, it should increase status by NPCs career
## tier"), the Difficulty Tier's whole effect on Social Armor now flows
## entirely through SocialCombatNPCDefinition.get_status_ordinal()
## (the Tier stands in as the NPC's own Career's level, so a tougher
## area promotes the NPC to a higher real Status Tier instead of
## handing out a bonus number with no in-fiction meaning) and
## social_encounter_screen.gd's own Status-comparison armor formula.
## SOCIAL_ARMOR_BONUS/get_social_armor_bonus() are gone; nothing
## replaces them here.

## Applies the Tier's bonus to a Social Combat NPC Character — only the
## four Characteristics Social Combat actually reads (Willpower,
## Fellowship, Intelligence, Initiative; see SocialCombatNPCDefinition.
## to_character()'s own comment on why the other six are left at
## CharacteristicSet's meaningless defaults for these NPCs), plus
## Composure. Idempotent-unsafe by design, same as apply_tier_bonus()
## above — call exactly once, right after the NPC Character is built
## and before anything reads its stats.
static func apply_social_npc_tier_bonus(npc: Character, tier: int) -> void:
	var char_bonus := get_bonus(tier)
	if char_bonus > 0:
		npc.characteristics.willpower += char_bonus
		npc.characteristics.fellowship += char_bonus
		npc.characteristics.intelligence += char_bonus
		npc.characteristics.initiative += char_bonus
	var composure_bonus := get_composure_bonus(tier)
	if composure_bonus > 0:
		npc.composure_max += composure_bonus
		npc.composure_current += composure_bonus

## Adds the Tier's bonus to all 10 Characteristics on the given
## Character in place. Idempotent-unsafe by design (calling it twice
## would double-apply) — it's meant to be called exactly once, right
## after a monster's Character is built from its MonsterDefinition and
## before anything else (combat resolution, display, etc.) reads its
## stats.
static func apply_tier_bonus(character: Character, tier: int) -> void:
	var bonus := get_bonus(tier)
	if bonus == 0:
		return
	for key in CharacteristicSet.KEYS:
		var current: int = character.characteristics.get_value(key)
		character.characteristics.set_value(key, current + bonus)
