extends Resource
class_name CreatureTemplateDefinition
## Creature Templates ("quick ways to create a more forbidding creature
## able to provide greater challenge to an adventuring party"): Leader,
## Commander, Soldier, Skirmisher, Elite, Spellcaster, Spellcaster Lord.
## Each is a set of characteristic/skill/talent bonuses meant to be
## layered on top of an EXISTING creature's own stat block to make a
## tougher variant (a "Leader" Orc, a "Spellcaster Lord" Goblin, etc.) —
## this is data about the template itself, not a creature.
##
## Per the request ("create new tables for these creature templates, but
## don't wire anything up just yet"): this class and its matching
## CreatureTemplateDatabase/data resource are recorded for reference
## only. Nothing in this project reads or applies a
## CreatureTemplateDefinition yet — same "intentionally inert until a
## later pass wires it up" convention already used for
## MonsterDefinition.optional_creature_traits. It is also deliberately
## NOT registered in GameData yet (no project-wide load() for this
## database), so nothing even has a path to reach it by accident.

@export var template_name: String = ""
@export var description: String = ""

## Characteristic bonuses to add on top of the base creature's own
## CharacteristicSet — keyed by CharacteristicSet.KEYS (e.g.
## "weapon_skill", "strength"). A characteristic the book lists as "–"
## (no change) is simply absent from this dictionary rather than stored
## as 0, so a future "apply this template" step can tell "no bonus" apart
## from "explicitly zero."
@export var characteristic_bonuses: Dictionary = {}

## Movement (M) bonus — every template published so far lists "–" here,
## but the field exists for completeness/future templates that don't.
@export var movement_bonus: int = 0

## Skill bonuses exactly as printed in the book (e.g. "Cool +15",
## "Melee (Any Two) +15", "Ranged (Bow, Sling, or Throwing) +10") —
## stored as raw strings rather than parsed into skill name + value,
## since several entries name a choice of specialisation ("Basic or
## Polearm") that only a human (or a later, purpose-built parser) can
## resolve sensibly.
@export var skill_bonuses: Array[String] = []

## Talent names exactly as printed, including "either/or" choices
## ("Aethyric Attunement or Instinctive Diction") and rated talents
## ("Instinctive Diction 2") verbatim — same reasoning as skill_bonuses
## above.
@export var talents: Array[String] = []

## Spell-selection guidance for the two Spellcaster templates (empty for
## every other template) — e.g. "Choose up to 3 spells from the Petty
## Magic list and up to 3 from a suitable magical Lore."
@export var spell_note: String = ""

## The book's own "* Wounds need to be increased due to..." footnote,
## verbatim — every template recalculates Wounds from its own modified
## S/T/WP rather than adding a flat bonus, so this is kept as guidance
## text rather than a number.
@export var wounds_note: String = ""
