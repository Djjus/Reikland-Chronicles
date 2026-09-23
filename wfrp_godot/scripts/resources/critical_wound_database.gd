extends Resource
class_name CriticalWoundDatabase
## The four Critical Wound tables from Up in Arms' "An Alternative
## Approach to Injury" (p.83-86) — the expanded system this project
## uses instead of the core rulebook's simpler one, per the request.
## Each table is an Array of Dictionaries: {min, max, name, wounds,
## flavor, conditions}. `wounds` is "T" (Trivial, no extra loss),
## an int (extra Wounds lost), or "Death" (instant kill).
## `conditions` maps a Condition name to a stack count to apply.

@export var head_table: Array = []
@export var arm_table: Array = []
@export var body_table: Array = []
@export var leg_table: Array = []

## Location -> table. "Left Arm"/"Right Arm" and "Left Leg"/"Right Leg"
## both use the same Arm/Leg table — the book only has one of each,
## same convention already used for this project's Armour mapping.
func get_table(location: String) -> Array:
	match location:
		"Head":
			return head_table
		"Left Arm", "Right Arm":
			return arm_table
		"Body":
			return body_table
		"Left Leg", "Right Leg":
			return leg_table
		_:
			return body_table

## `roll` may exceed 100 — Up in Arms' own "+10 per excess Wound when
## finishing off an opponent already at 0 Wounds" rule (p.81) can push
## it past the table's nominal top band, which is exactly why the
## table's own highest band (Death) has an effectively unbounded max.
func lookup(location: String, roll: int) -> Dictionary:
	var table := get_table(location)
	for entry: Dictionary in table:
		if roll >= entry["min"] and roll <= entry["max"]:
			return entry
	return table[-1] if not table.is_empty() else {}
