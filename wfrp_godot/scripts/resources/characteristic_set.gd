extends Resource
class_name CharacteristicSet
## Holds the ten characteristics used by the ruleset.
## Values are stored as full characteristic scores (e.g. 34), not bonuses.
## The "bonus" for a characteristic is always floor(value / 10).

@export var weapon_skill: int = 20
@export var ballistic_skill: int = 20
@export var strength: int = 20
@export var toughness: int = 20
@export var initiative: int = 20
@export var agility: int = 20
@export var dexterity: int = 20
@export var intelligence: int = 20
@export var willpower: int = 20
@export var fellowship: int = 20

## Ordered list of characteristic keys, used for iteration/UI generation.
const KEYS := [
	"weapon_skill", "ballistic_skill", "strength", "toughness",
	"initiative", "agility", "dexterity", "intelligence",
	"willpower", "fellowship"
]

const SHORT_NAMES := {
	"weapon_skill": "WS", "ballistic_skill": "BS", "strength": "S",
	"toughness": "T", "initiative": "I", "agility": "Ag",
	"dexterity": "Dex", "intelligence": "Int", "willpower": "WP",
	"fellowship": "Fel"
}

## Per the request: the Characteristics sub-tab's own grid should show
## full characteristic names instead of the cramped WS/BS/S abbreviations
## — SHORT_NAMES stays as-is above for the places that still need the
## compact form (e.g. Critical Wound penalty lines, compact stat headers).
const FULL_NAMES := {
	"weapon_skill": "Weapon Skill", "ballistic_skill": "Ballistic Skill", "strength": "Strength",
	"toughness": "Toughness", "initiative": "Initiative", "agility": "Agility",
	"dexterity": "Dexterity", "intelligence": "Intelligence", "willpower": "Willpower",
	"fellowship": "Fellowship"
}

## Defensive hardening, found while testing an unrelated fix: `get(key)`
## returns null (not 0) for anything that isn't one of the ten real
## characteristic properties above, which used to throw a real runtime
## error ("Trying to return a value of type Nil from a function whose
## return type is int") anywhere a SkillDefinition's own
## linked_characteristic didn't exactly match one of KEYS — as one still
## did until just now (see core_skills.tres's own Trade entry, which
## used the placeholder value "varies"). `key` genuinely not matching a
## real characteristic should never crash a Test/skill-value lookup
## outright; falling back to 0 here is a safety net for any future bad
## key, not a substitute for keeping the data itself correct.
func get_value(key: String) -> int:
	var v: Variant = get(key)
	return v if v is int else 0

func set_value(key: String, value: int) -> void:
	set(key, value)

## Returns the "bonus" (tens digit) for a characteristic - used constantly
## in derived stats (Wounds, damage, encumbrance, etc.)
func get_bonus(key: String) -> int:
	return int(floor(get_value(key) / 10.0))

func duplicate_set() -> CharacteristicSet:
	var c := CharacteristicSet.new()
	for k in KEYS:
		c.set_value(k, get_value(k))
	return c

func add_in_place(other_bonuses: Dictionary) -> void:
	## other_bonuses: { "strength": 5, "toughness": 3, ... }
	for k in other_bonuses.keys():
		set_value(k, get_value(k) + int(other_bonuses[k]))
