extends Resource
class_name CareerLevel
## One tier of a career, e.g. "Soldier" tier 1 of the "Soldier" career.

@export var level_name: String = ""       # e.g. "Soldier"
@export var tier: int = 1                 # 1 = Brass, 2 = Silver, 3 = Gold, 4 = ...
@export var status_tier: String = "Brass" # Brass / Silver / Gold
@export var status_stars: int = 0
@export var attribute_advances: Dictionary = {} # {"strength": 5} = +5 to that characteristic's advance cap
@export var skills: Array[String] = []    # skills trainable at this level
@export var talents: Array[String] = []   # talents available at this level
@export var trappings: Array[String] = [] # starting equipment names
@export var income_skill: String = ""     # skill used for the Income skill test

## Spells/Prayers granted for free at this tier (used by the four caster
## careers — Wizard, Witch, Priest, Nun — so a freshly-created character
## actually has something in their spellbook; empty for every other
## career).
@export var starting_spells: Array[String] = []
@export var starting_prayers: Array[String] = []
