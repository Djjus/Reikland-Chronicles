extends Resource
class_name ArmourDefinition
## A piece of armour. Armour Points reduce Damage at whichever Hit
## Locations the piece covers (see rulebook p.160/294 — this is a starter
## set, not the complete Consumers' Guide).

@export var armour_name: String = ""
## Any of: "Head", "Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"
@export var locations: Array[String] = []
@export var armour_points: int = 1
@export var encumbrance: int = 0
@export var qualities: Array[String] = []

## General Trapping Item Qualities/Flaws (p.301-302: Durable, Fine,
## Lightweight, Practical / Ugly, Shoddy) — see ItemQualityRules. A
## SEPARATE system from `qualities` above (Partial, Weakpoints, etc.,
## this piece's own combat qualities). "Durable 2" style rated entries;
## see ItemQualityRules.parse_entry().
@export var item_qualities: Array[String] = []
@export var item_flaws: Array[String] = []
@export var summary: String = ""
@export var price_pennies: int = 0   ## list price in Brass Pennies — 0 means not directly sold (a piece used elsewhere, e.g. starting/monster gear)
@export_enum("Common", "Scarce", "Rare", "Exotic") var availability: String = "Common"
## Layering (house rule, per the request): a character may wear up to
## 3 pieces at once covering the same location — one per tier (Light,
## Medium, Heavy) — but never two pieces of the SAME tier overlapping
## the same location. Light = Leather, Medium = Mail/Boiled Leather,
## Heavy = Plate.
@export_enum("Light", "Medium", "Heavy") var armor_tier: String = "Light"
## Magic/special items exempt from all armour-damage rules (Deflection,
## the Hack weapon Quality, etc.) — per the request, "some special and
## unusual magic items are indestructible."
@export var is_indestructible: bool = false
