extends Resource
class_name WeaponDefinition
## A weapon's combat stats. Damage math follows the core rulebook:
## melee weapons usually add your Strength Bonus, ranged weapons usually
## have a fixed Damage value (see rulebook p.293 for the full item list —
## this is a starter set, not the complete Consumers' Guide).

@export var weapon_name: String = ""
@export var is_ranged: bool = false
## Matches a group_options entry on the "Melee" or "Ranged" grouped skill
## (e.g. "Basic", "Two-Handed", "Bow") — determines which specialisation
## is tested to use this weapon.
@export var skill_group: String = "Basic"
## Whether this weapon genuinely requires both hands — NOT the same as
## skill_group == "Two-Handed": several Polearms (Halberd, Spear, Pike,
## Quarter Staff) are two-handed weapons but belong to the "Polearm"
## skill group, not "Two-Handed". This is the real, authoritative flag
## used for off-hand validation and for the "(1H)"/"(2H)" UI labels —
## checking skill_group alone missed every two-handed Polearm.
@export var is_two_handed: bool = false

@export_enum("strength_bonus_plus", "fixed") var damage_mode: String = "strength_bonus_plus"
@export var damage_flat: int = 0   ## added to SB (melee) or used as-is (ranged fixed)

@export var range_yards: int = 0   ## 0 for melee weapons
@export var encumbrance: int = 0
@export var qualities: Array[String] = []   ## e.g. "Fast", "Defensive", "Pistol", "Precise"

## Weapon Groups (p.296): "While you still suffer all the weapon's
## Flaws, you cannot use any of its Qualities" when untrained (or
## using a fallback skill — Crossbow/Throwing via Ballistic Skill,
## Engineering via Ranged (Blackpowder)). Everything a weapon's own
## `qualities` array can hold is one or the other — this is the
## Flaws half; see Character.get_effective_weapon_qualities() for
## where the split is actually applied to combat. "Reload N" (a rated
## Flaw, like "Shield N" is a rated Quality) is matched separately by
## its own prefix there, same reason a fixed list can't hold it.
const WEAPON_FLAWS: Array[String] = ["Dangerous", "Imprecise", "Reload", "Slow", "Tiring", "Undamaging"]

## General Trapping Item Qualities/Flaws (p.301-302: Durable, Fine,
## Lightweight, Practical / Ugly, Shoddy) — see ItemQualityRules. A
## SEPARATE system from `qualities`/WEAPON_FLAWS above: these are never
## suppressed by untrained use, and never counted by
## Character.get_effective_weapon_qualities(). "Fine 2" / "Durable 3"
## style rated entries; see ItemQualityRules.parse_entry().
@export var item_qualities: Array[String] = []
@export var item_flaws: Array[String] = []
@export var summary: String = ""
@export var price_pennies: int = 0   ## list price in Brass Pennies (12d=1s, 240d=1GC) — p.293-298 / Up in Arms p.90-98
@export_enum("Common", "Scarce", "Rare", "Exotic") var availability: String = "Common"
## Weapon Reach (p.296-297): Personal < Very Short < Short < Average <
## Long < Very Long < Massive. Mechanically used here for the "Close
## the Distance" action (p.297: win an Opposed Melee Test to force
## in-fighting, reducing any weapon longer than Short to an Improvised
## Weapon) — the Engage-at-greater-distance effect of Very Long/Massive
## isn't modelled, since this project doesn't track battlefield yards.
@export_enum("Personal", "Very Short", "Short", "Average", "Long", "Very Long", "Massive") var reach: String = "Average"
## Magic/special weapons exempt from all weapon-damage rules (a
## fumble's "weapon takes 1 point of damage" result, etc.) — per the
## request, "some special and unusual magic items are indestructible."
@export var is_indestructible: bool = false

## Trap Blade (p.298) only triggers "when Parrying an attack from a
## Bladed weapon" — genuinely bladed (swords, axes, daggers), not every
## melee weapon (a Hammer or Flail isn't bladed). Not derivable from
## skill_group alone (Basic/Two-Handed/Fencing/Cavalry all mix bladed
## and non-bladed weapons), so tracked as its own explicit flag.
@export var is_bladed: bool = false

## Weapon Damage: reduced by 1 for every point of durability damage
## this specific character's copy of the weapon has taken (see
## Character.weapon_damage_taken) — a real fumble result ("your weapon
## takes 1 point of damage") until now only carried a narrative tag;
## this makes it a genuine, lasting reduction, tracked per-character
## rather than mutating this shared definition (every other character
## carrying a "Sword" shouldn't feel one person's fumble).
func get_weapon_damage(character: Character) -> int:
	var reduction := 0
	if character != null:
		reduction = int(character.weapon_damage_taken.get(weapon_name, 0))
	if damage_mode == "fixed":
		return max(0, damage_flat - reduction)
	var sb := character.get_characteristic_bonus("strength") if character else 0
	return max(0, sb + damage_flat - reduction)
