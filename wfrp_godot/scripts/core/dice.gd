extends RefCounted
class_name Dice
## Centralised randomness so tests/combat are reproducible and easy to
## unit-test (swap the RNG's seed in tests).

static var rng := RandomNumberGenerator.new()

static func _ensure_seeded() -> void:
	if rng.seed == 0:
		rng.randomize()

static func d10() -> int:
	_ensure_seeded()
	return rng.randi_range(1, 10)

static func d100() -> int:
	## Returns 1-100 inclusive (100 represents the classic "00" result).
	_ensure_seeded()
	return rng.randi_range(1, 100)

static func roll_2d10() -> int:
	return d10() + d10()

static func roll_characteristic(base: int) -> int:
	return base + roll_2d10()

## Rolls a simple "XdY" dice spec string (e.g. "1d10", "2d10") — used
## by Miscast/Wrath tags that specify their damage this way rather than
## a fixed number, matching how the book itself writes these entries.
static func roll_dice_string(spec: String) -> int:
	var parts := spec.split("d")
	if parts.size() != 2:
		return 0
	var count := int(parts[0]) if parts[0] != "" else 1
	var sides := int(parts[1])
	if sides <= 0:
		return 0
	var total := 0
	for i in range(count):
		_ensure_seeded()
		total += rng.randi_range(1, sides)
	return total
