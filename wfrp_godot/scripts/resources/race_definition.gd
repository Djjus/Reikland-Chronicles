extends Resource
class_name RaceDefinition
## Defines a playable species: base characteristics, random-generation
## ranges, and racial traits. Numbers here are game-mechanical values
## (formulas), not text lifted from any published book.

@export var race_name: String = "Human"

## Base value added to the 2d10 roll for each characteristic during
## character creation, e.g. {"weapon_skill": 20, "strength": 20, ...}
@export var characteristic_bases: Dictionary = {
	"weapon_skill": 20, "ballistic_skill": 20, "strength": 20,
	"toughness": 20, "initiative": 20, "agility": 20,
	"dexterity": 20, "intelligence": 20, "willpower": 20,
	"fellowship": 20
}

## Fixed starting Fate, Resilience, Extra Wound points, and Movement.
@export var starting_fate: int = 0
@export var starting_resilience: int = 1
## Per the request: spendable during character creation to increase
## Fate and/or Resilience — the book's own "Extra Points" row on the
## Attributes Table, previously present in this project's own summary
## notes but never actually implemented as a real, spendable choice.
@export var extra_points: int = 2
@export var starting_extra_wounds: int = 0
@export var movement: int = 4

## The book's own "Species Skills and Talents" pool (Character Creation):
## every listed entry is a candidate the player chooses FROM, not an
## automatic grant — pick 3 of these for +5 Advances each, then 3 MORE
## (of whatever's left) for +3 Advances each (see
## CharacterCreator.SPECIES_*_PICK_* for those fixed book numbers,
## same for every Species). Entries may carry a "(any one)"/"(Any)"
## qualifier (e.g. "Trade (any one)") exactly like career-granted
## skills already do — resolved through Advancement.is_any_qualifier /
## get_skill_situation_choices, the same helpers career Advancement
## purchases already use, rather than a second parallel mechanism.
## Species with a pool too small to offer a real choice (this
## project's own non-book Gnome/Ogre, both size 3) fall back to
## auto-granting the whole pool — see CharacterCreator.pick_species_skills.
@export var racial_skill_pool: Array[String] = []

## Talents every member of this race starts with, no choice involved
## (list of talent_name strings, e.g. "Acute Sense (Sight)" when the
## book fixes the qualifier itself).
@export var racial_talents: Array[String] = []

## Independent "pick exactly 1 of N" Talent choice groups — the book's
## "Skill/Talent OR Skill/Talent" listings. A Species can have more
## than one such group (e.g. Dwarfs: "Read/Write or Relentless" AND,
## separately, "Resolute or Strong-minded") — each inner Array is one
## group; the player makes one independent choice per group.
@export var racial_talent_choice_groups: Array[Array] = []

## How many rolls on the book's Random Talents table (RandomTalentsTable)
## this Species grants (Humans 3, Halflings 2, others 0 per the book
## page this project transcribed this from).
@export var racial_random_talent_count: int = 0

## Short, original one-line flavour (not copied from any sourcebook).
@export var summary: String = ""
