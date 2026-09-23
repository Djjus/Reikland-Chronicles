extends Resource
class_name SpellDefinition
## A single spell, checked against the rulebook's Casting Test rules
## (p.234-238). Descriptions are original wording, not copied text — the
## mechanical fields (CN, Range, Target, Duration) are game data, not
## copyrightable expression.

@export var spell_name: String = ""
@export_enum("Petty", "Arcane", "Lore", "Chaos") var spell_type: String = "Petty"
## Which Lore this belongs to ("" for Petty spells and generic Arcane
## spells, which can be cast by any Lore). Matches the Channelling skill's
## group_options (e.g. "Aqshy", "Ghyran") for Lore-specific spells.
@export var lore: String = ""

## Casting Number: your Language (Magick) Test's SL must meet or exceed
## this to successfully cast the spell (p.234).
@export var casting_number: int = 0

@export var range_text: String = "You"
@export var target_text: String = "You"
@export var duration_text: String = "Instant"

## Magic missiles follow special rules (p.236): Hit Location is
## determined by reversing the Language (Magick) roll, and Damage =
## spell's flat Damage + Willpower Bonus + the casting Test's SL.
@export var is_magic_missile: bool = false
@export var damage_flat: int = 0
@export var is_area_of_effect: bool = false

## Per the request: a generic, data-driven way for a spell to inflict a
## real Condition on a successful cast — e.g. Shock's own "leaves the
## target Stunned." Empty means no Condition effect. This is what
## actually lets a monster's own AI recognize and use a
## condition-inflicting spell without hardcoded per-spell-name logic.
@export var inflicts_condition: String = ""
@export var inflicts_condition_stacks: int = 1

@export var summary: String = ""

## Every spell whose actual mechanical effect, at cast time, is hand-
## written directly into field_encounter_screen.gd's dispatch chain
## (_apply_cast_spell_outcome/_apply_cast_spell_outcome_aoe) rather than
## driven purely by is_magic_missile/inflicts_condition below — Drain's
## own damage+self-heal hybrid, Light's lamp behaviour, Flaming Sword of
## Rhuin's weapon-enchant, Cauterise's heal, Crown of Flame/Flaming
## Hearts' Willpower buff. This is the single manually-maintained list
## is_mechanically_implemented() needs; every OTHER real spell is
## detected automatically from its own data flags with zero maintenance
## here. Add a spell's name the moment a genuine "spell_name == ..."
## branch for it lands in that dispatch chain — see that file's own
## header comment on _apply_cast_spell_outcome for the authoritative,
## up-to-date list this must stay in sync with.
const BESPOKE_IMPLEMENTED_SPELLS := [
	"Drain", "Light", "Flaming Sword of Rhuin", "Cauterise",
	"Crown of Flame", "Flaming Hearts", "Firewall", "Great Fires of U'Zhul",
]

## True once this spell actually does something in play beyond showing
## its own flavor text (`summary`) — per the explicit request ("grey
## out and disable all spells which are not implemented [in the Learn-a-
## Spell lists]... re-enable them as we implement them"). A spell counts
## as implemented the moment ANY of its own real-effect data fields are
## set (is_magic_missile — real Wound damage; inflicts_condition — a
## real Condition on a successful cast) or it's one of the hand-written
## exceptions in BESPOKE_IMPLEMENTED_SPELLS above. Every spell in this
## project's own database that isn't one of those two things falls
## straight into _apply_cast_spell_outcome's generic catch-all (shows
## `summary`, does nothing else) — this mirrors that exact same
## real-vs-flavor split, so it can never drift from what actually
## happens when the spell is cast.
func is_mechanically_implemented() -> bool:
	return is_magic_missile or inflicts_condition != "" or BESPOKE_IMPLEMENTED_SPELLS.has(spell_name)

func get_max_rank(_character: Character) -> int:
	return 1   ## spells aren't "taken" in ranks like talents; kept for API symmetry
