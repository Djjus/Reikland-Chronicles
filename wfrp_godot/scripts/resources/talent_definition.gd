extends Resource
class_name TalentDefinition
## A single talent, matching the ruleset's own "Talent Format":
##   Talent Name (situation) / Max / Tests / Description
## Mechanical effects are expressed as data so the rules engine can look
## them up by name rather than needing hardcoded special cases scattered
## through the code.

## The name, e.g. "Acute Sense". If the talent has a parenthetical
## qualifier (a situation it applies to, chosen at the time it's taken —
## e.g. "Acute Sense (Sense)" where the player picks which sense) that
## goes in `situation`, not in the name itself.
@export var talent_name: String = ""
## The situation/qualifier shown in parentheses, e.g. "Chaos" for
## "Resistance (Chaos)". Used as a FIXED default when a talent's
## qualifier never varies. For talents whose qualifier is chosen from a
## list (Etiquette, Bless, Invoke...), leave this blank and use
## situation_options instead — see that field's comment.
@export var situation: String = ""
## The valid choices for this talent's qualifier, e.g. Etiquette's
## ["Criminals", "Cultists", "Guilders", "Nobles", "Scholars",
## "Servants", "Soldiers"]. When a career grants "Etiquette (Any)", the
## player picks one of these; when it grants "Etiquette (Cultists)"
## specifically, they're locked to that one value with no choice. Empty
## for talents with a fixed or no qualifier.
@export var situation_options: Array[String] = []

## --- Max ----------------------------------------------------------------
## How many times the talent can be taken. Per the ruleset this is either
## a flat number (commonly 1, sometimes higher) OR tied to a Characteristic
## Bonus (e.g. "Max: Initiative Bonus" — a character with Initiative 34
## could take that talent up to 3 times).
@export_enum("fixed", "characteristic_bonus") var max_mode: String = "fixed"
@export var max_fixed: int = 1
@export var max_characteristic: String = ""   ## used when max_mode == "characteristic_bonus"

func get_max_rank(character: Character) -> int:
	if max_mode == "characteristic_bonus" and character != null:
		return max(1, character.get_characteristic_bonus(max_characteristic))
	return max_fixed

## --- Tests ----------------------------------------------------------------
## If the talent is tied to one or more Tests, they're listed here (e.g.
## ["Charm Animal"], ["Melee (Basic)"], ["Perception"]). Per the ruleset's
## default rule: for every rank taken, the character gains +1 Success
## Level on any successful use of a Skill tied to the Talent — UNLESS the
## talent's own description spells out a different, bespoke effect (see
## `overrides_default_test_effect` below), in which case the default +1 SL
## does NOT stack on top of it.
@export var tests: Array[String] = []
@export var overrides_default_test_effect: bool = false

## --- Description ----------------------------------------------------------
@export var summary: String = ""   ## short original description (not book text)

## Effect tags let systems query "does this character have an effect that
## does X" without string-matching on talent names — used for talents
## whose effect isn't a Test bonus at all (extra Fate, extra Wounds,
## flat damage, carrying capacity, etc.) and for the bespoke effects noted
## by `overrides_default_test_effect` above.
@export var effect_tags: Array[String] = []
@export var effect_value: int = 0

## --- Implementation status -------------------------------------------------
## Set true for a Talent whose real book effect has no clear plan for if
## or when it'll be implemented -- typically because it needs a whole
## subsystem this project doesn't have yet (a Crafting Endeavour tracker,
## a fall-damage formula, an NPC bribery interaction, etc.), rather than
## just being unwired. The Talent's data stays in the Master Talent List
## either way (name/Max/Tests/Description all still correct and visible)
## -- this only gates whether a player can spend XP training INTO it, so
## nobody buys a rank of something that currently does nothing.
## IMPORTANT: this is meant to be temporary. When the blocking subsystem
## (or a bespoke implementation) lands, flip this back to false and clear
## parked_reason in the same pass -- don't leave a newly-working Talent
## stuck disabled.
@export var mechanically_parked: bool = false
## Shown as the disabled Train button's tooltip when mechanically_parked
## is true -- name the specific missing system, e.g. "Needs a Crafting
## Endeavour system this project doesn't have yet."
@export var parked_reason: String = ""
