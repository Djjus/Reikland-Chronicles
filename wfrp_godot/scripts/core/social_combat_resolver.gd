extends RefCounted
class_name SocialCombatResolver
## Scores and applies one Social Combat exchange (Design Doc "Social
## Combat — Design Doc v1", Section 4). Deliberately mirrors
## CombatResolver's own split of responsibility: rolling a Test (and
## offering any Fortune/Dark Deal reroll on it) stays screen-side,
## exactly the shape social_encounter_screen.gd's pre-Social-Combat
## _attempt_skill() already uses (roll attacker -> roll NPC once,
## never rerolled -> Fortune-loop the attacker's own roll) — this
## class only does the SCORING and Composure-application once both
## sides' rolls are already final, the same way CombatResolver's own
## _apply_hit() only runs after the to-hit roll is settled.

enum AttackType { INTIMIDATE, CHARM, NEEDLE, REASON }

const ATTACK_TYPE_NAMES := {
	AttackType.INTIMIDATE: "Intimidate",
	AttackType.CHARM: "Charm",
	AttackType.NEEDLE: "Needle",
	AttackType.REASON: "Reason",
}

## Composure-damage multiplier per type (Design Doc Section 4: "Intimidate
## ×2, Charm ×1.5, Needle/Deceive ×1"). Reason has no entry — it heals
## instead of damaging (see finalize_party_attack below).
const DAMAGE_MULTIPLIER := {
	AttackType.INTIMIDATE: 2.0,
	AttackType.CHARM: 1.5,
	AttackType.NEEDLE: 1.0,
}

## The real party-side Skill each Attack Type rolls with. NEEDLE
## prefers Gossip, falling back to Haggle if the attacker never
## trained Gossip specifically (Design Doc Section 4: "Gossip or
## Haggle" — both are valid, Gossip is just the first choice). REASON
## uses Research rather than "Lore (any)" — Lore's per-specialisation
## nature (which Lore? Reikland? The Elf Courts?) adds real complexity
## for no Slice-1 benefit; Research is a single, always-the-same skill
## covering the same "logic/evidence" idea.
static func attacking_skill_for(attack_type: int, attacker: Character) -> SkillDefinition:
	match attack_type:
		AttackType.INTIMIDATE:
			return GameData.skill_db.find_by_name("Intimidate")
		AttackType.CHARM:
			return GameData.skill_db.find_by_name("Charm")
		AttackType.NEEDLE:
			var gossip := GameData.skill_db.find_by_name("Gossip")
			if gossip != null and attacker.has_skill(gossip):
				return gossip
			return GameData.skill_db.find_by_name("Haggle")
		AttackType.REASON:
			return GameData.skill_db.find_by_name("Research")
	return null

## Whether `character` can currently attempt this Attack Type at all —
## matters most for Reason: Research is an Advanced skill (unlike the
## other three), so a character who's never trained it genuinely
## cannot attempt it (Character.has_skill() already encodes that rule
## for every Advanced skill in the game). The screen uses this to
## decide which Attack Type buttons to actually offer the active
## character, same as the pre-Social-Combat code's own per-roller
## eligibility check.
static func can_use(attack_type: int, character: Character) -> bool:
	var skill := attacking_skill_for(attack_type, character)
	return skill != null and character.has_skill(skill)

## The always-real party-side Skill a defending party member resists
## an NPC's attack with — Cool, matching Composure's own Willpower +
## Cool formula (Design Doc Section 1).
static func defending_skill() -> SkillDefinition:
	return GameData.skill_db.find_by_name("Cool")

## Which of the NPC's own flat stats it defends a given Attack Type
## with (Design Doc Section 4's Defending Skill column, translated:
## Cool -> Willpower, Intuition -> Initiative). Social Encounter NPCs
## don't carry real linked Skills of their own — this mirrors how
## every Social Encounter already rolled the NPC's side via a bare
## TestResolver.resolve(npc_target) rather than a full
## resolve_skill_test(), before Social Combat existed.
static func npc_defense_target(attack_type: int, npc: Character) -> int:
	if attack_type == AttackType.INTIMIDATE or attack_type == AttackType.REASON:
		return npc.get_effective_characteristic_value("willpower")
	return npc.get_effective_characteristic_value("initiative")

## The single flat stat an NPC attacks with on its own turn. Slice 1
## simplification, called out explicitly in the design doc's review:
## Social Encounter NPCs only carry Fellowship/Willpower/Intelligence/
## Initiative (not a full ten-characteristic block), so there's no
## real per-Attack-Type stat for an NPC's own offense the way a party
## member has real Strength for Intimidate — Fellowship (general force
## of personality) stands in for all of an NPC's own attacks, matching
## how the pre-Social-Combat code already used npc_fellowship as the
## default all-purpose NPC target for most rolls.
static func npc_attack_target(npc: Character) -> int:
	return npc.get_effective_characteristic_value("fellowship")

class ExchangeResult:
	var attack_type: int = -1
	var opposed: TestResolver.OpposedResult
	var hit: bool = false
	var composure_damage: int = 0     ## already applied to the damaged Character by the time this is returned
	var social_armor_reduced: int = 0
	var bypassed_social_armor: bool = false
	var composure_healed: int = 0     ## Reason only; already applied to heal_target

## Scores and applies one party-member-attacks-NPC exchange, once both
## sides' Tests are already final (any Fortune/Dark Deal reroll on
## attacker_test has already happened — see this file's own header
## comment). REASON deals no Composure damage at all; instead it heals
## `heal_target` (the screen picks whichever living ally has taken the
## most damage this encounter and passes them in — this function
## doesn't know the whole party, only the two Characters actually
## rolling).
static func finalize_party_attack(attack_type: int, attacker_test: TestResolver.TestResult,
		defender_test: TestResolver.TestResult, defender_npc: Character, npc_social_armor: int,
		heal_target: Character = null) -> ExchangeResult:
	var result := ExchangeResult.new()
	result.attack_type = attack_type
	result.opposed = TestResolver.resolve_opposed(attacker_test, defender_test)
	result.hit = result.opposed.attacker_wins
	if not result.hit:
		return result

	var net_sl: int = result.opposed.net_success_levels

	if attack_type == AttackType.REASON:
		var heal: int = maxi(1, net_sl)
		result.composure_healed = heal
		if heal_target != null:
			heal_target.composure_current = mini(heal_target.composure_max, heal_target.composure_current + heal)
		return result

	var raw_damage: int = int(floor(maxi(1, net_sl) * DAMAGE_MULTIPLIER.get(attack_type, 1.0)))
	var final_damage: int = raw_damage
	if attack_type == AttackType.NEEDLE:
		## Bypasses Social Armor entirely (Design Doc Section 4).
		result.bypassed_social_armor = true
	else:
		result.social_armor_reduced = mini(npc_social_armor, raw_damage)
		final_damage = maxi(0, raw_damage - npc_social_armor)
	result.composure_damage = final_damage
	defender_npc.composure_current = maxi(0, defender_npc.composure_current - final_damage)
	return result

## Scores and applies one NPC-attacks-party-member exchange (the NPC's
## own turn in the Social Combat turn order) — flat damage, no
## multiplier table and no Social Armor on the party side (party
## members don't carry that stat).
static func finalize_npc_attack(attacker_test: TestResolver.TestResult,
		defender_test: TestResolver.TestResult, defender: Character) -> ExchangeResult:
	var result := ExchangeResult.new()
	result.opposed = TestResolver.resolve_opposed(attacker_test, defender_test)
	result.hit = result.opposed.attacker_wins
	if not result.hit:
		return result
	var damage: int = maxi(1, result.opposed.net_success_levels)
	result.composure_damage = damage
	defender.composure_current = maxi(0, defender.composure_current - damage)
	return result
