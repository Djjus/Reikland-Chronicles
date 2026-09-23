extends RefCounted
class_name ItemQualityRules
## General Trapping Item Qualities & Flaws (rulebook p.301-302): Durable,
## Fine, Lightweight, Practical (Qualities) and Ugly, Shoddy (Flaws).
##
## Deliberately a SEPARATE system from each WeaponDefinition/
## ArmourDefinition's own `qualities: Array[String]` combat-quality list
## (Fast, Defensive, Precise, Pistol, Shield N, Unbreakable, Dangerous,
## Imprecise, Reload N, Slow, Tiring, Undamaging — see
## WeaponDefinition.WEAPON_FLAWS and Character.get_effective_weapon_
## qualities()), per the request ("Weapons/Armor Qualities, live side by
## side with these Item Qualities"). The two lists are never merged: a
## weapon or armour piece now carries its combat qualities in `qualities`
## exactly as before, and separately carries these general Trapping
## qualities/flaws in its own new `item_qualities`/`item_flaws` arrays
## (see WeaponDefinition/ArmourDefinition). Untrained combat-quality
## suppression (get_effective_weapon_qualities) never touches
## item_qualities/item_flaws — a Fine sword stays Fine even in
## untrained hands.
##
## Entries are plain strings, with a trailing rating number for the two
## stackable Qualities ("Durable 2", "Fine 3") — matching this project's
## existing "Shield 2"/"Reload 2" rated-quality string convention. A
## bare name ("Lightweight", "Practical", "Ugly", "Shoddy") implies
## rating 1; those four are never taken more than once per RAW (the
## rulebook only calls out Durable and Fine as repeatable).

const QUALITY_NAMES: Array[String] = ["Durable", "Fine", "Lightweight", "Practical"]
const FLAW_NAMES: Array[String] = ["Ugly", "Shoddy"]
const STACKABLE_QUALITIES: Array[String] = ["Durable", "Fine"]

## Availability, worst (rarest) last — used to shift a base item's
## availability up (toward Common, for Flaws) or down (toward Exotic,
## for Qualities) by a number of steps, clamped at either end. Matches
## the exact @export_enum order already used on ItemDefinition/
## WeaponDefinition/ArmourDefinition.
const AVAILABILITY_ORDER: Array[String] = ["Common", "Scarce", "Rare", "Exotic"]

## Splits a rated entry like "Durable 2" into {"name": "Durable",
## "rating": 2}. A bare name like "Practical" or an unrecognised string
## returns rating 1 so a caller can always safely sum ratings without a
## null-check.
static func parse_entry(entry: String) -> Dictionary:
	var trimmed := entry.strip_edges()
	var parts := trimmed.split(" ")
	if parts.size() >= 2 and parts[parts.size() - 1].is_valid_int():
		var rating := int(parts[parts.size() - 1])
		var name := " ".join(parts.slice(0, parts.size() - 1))
		return {"name": name, "rating": max(1, rating)}
	return {"name": trimmed, "rating": 1}

## Finds a specific quality/flaw's rating within an item_qualities or
## item_flaws array (e.g. "does this weapon have Durable, and if so how
## many points?"). Returns 0 if the item doesn't have it at all — the
## natural "no bonus" value for every hook below (extra durability
## points, saving-throw bonus, etc. all add 0 when absent).
static func rating_of(entries: Array, quality_name: String) -> int:
	for entry in entries:
		var parsed := parse_entry(String(entry))
		if parsed.name == quality_name:
			return int(parsed.rating)
	return 0

static func has(entries: Array, quality_name: String) -> bool:
	return rating_of(entries, quality_name) > 0

## Sum of every entry's rating — the "for each Item Quality/Flaw" count
## the price/availability rule (p.301) scales by. A Durable 3 sword with
## no other qualities counts as 3 for this purpose, matching the book's
## own Molli/Durable-3 example math (each point of a rated Quality is
## itself one more Item Quality for pricing).
static func total_rating(entries: Array) -> int:
	var total := 0
	for entry in entries:
		total += int(parse_entry(String(entry)).rating)
	return total

## Shifts `base` by `steps` positions toward the rare end of
## AVAILABILITY_ORDER (negative steps shift toward Common instead),
## clamped at both ends — an Exotic item stays Exotic no matter how many
## further Qualities pile on, and a Common item stays Common no matter
## how many Flaws.
static func shift_availability(base: String, steps: int) -> String:
	var idx := AVAILABILITY_ORDER.find(base)
	if idx < 0:
		return base
	idx = clampi(idx + steps, 0, AVAILABILITY_ORDER.size() - 1)
	return AVAILABILITY_ORDER[idx]

## Each Item Quality doubles price; each Item Flaw halves it (p.301-302)
## — the two counts compound independently (a Trapping with both
## Qualities and Flaws isn't RAW-legal as a single labelled category,
## but the price math itself is well-defined either way, which the
## Crafting order screen relies on since it lets a character stack any
## number of the 4 Qualities together).
static func price_multiplier(quality_count: int, flaw_count: int) -> float:
	return pow(2.0, quality_count) * pow(0.5, flaw_count)

## "A Trapping is called a Quality Trapping if it has more Item
## Qualities than Flaws... A Trapping with more Qualities than its
## Encumbrance, and that lacks any Flaws, is called a Best Quality
## Trapping" / "...a Flawed Trapping if it has more Item Flaws than
## Qualities" (p.301-302). Returns "" for a Trapping that's neither
## (equal counts, or no qualities/flaws at all).
static func classify(quality_count: int, flaw_count: int, encumbrance: int) -> String:
	if quality_count > flaw_count:
		if flaw_count == 0 and quality_count > encumbrance:
			return "Best Quality Trapping"
		return "Quality Trapping"
	if flaw_count > quality_count:
		return "Flawed Trapping"
	return ""

## Computes the derived price/availability/classification for a base
## item once a specific set of item_qualities/item_flaws is applied —
## the single source of truth used both when hand-authoring the shop's
## static Quality-variant stock entries (Fine weapons, Lightweight/
## Durable armour) and when the Crafting order screen prices a
## player-designed custom order.
static func compute_derived(base_price_pennies: int, base_availability: String, item_qualities: Array, item_flaws: Array, encumbrance: int) -> Dictionary:
	var quality_count := total_rating(item_qualities)
	var flaw_count := total_rating(item_flaws)
	var multiplier := price_multiplier(quality_count, flaw_count)
	return {
		"price_pennies": int(round(base_price_pennies * multiplier)),
		"availability": shift_availability(shift_availability(base_availability, quality_count), -flaw_count),
		"classification": classify(quality_count, flaw_count, encumbrance),
		"quality_count": quality_count,
		"flaw_count": flaw_count,
	}

## Durable's saving throw (p.301): "9+ on a 1d10 roll against instant
## breakage... improves by 1 each time it's taken" (Durable 1 = 9+,
## Durable 2 = 8+, Durable 3 = 7+, etc., floored at needing at least a
## 1). Used by Character.destroy_weapon()/destroy_armour_piece() for
## any instant-break source (Trap Blade, Shoddy) — NOT for the gradual
## per-use damage_flat/armour_points tally, which Durable instead
## extends via extra_durability_points() below.
static func durable_save_target(durable_rating: int) -> int:
	return clampi(10 - durable_rating, 1, 9)

## Shared "Qualities and Flaws" column formatter, used by every UI grid
## that lists a weapon/armour's combat qualities (Fast, Precise, Slow...)
## alongside its general Trapping item_qualities/item_flaws (Fine,
## Durable, Lightweight, Practical / Ugly, Shoddy). Per the request
## ("Weapons/Armor Qualities, live side by side with these Item
## Qualities"), the two lists are shown side by side, separated by
## " | ", rather than merged into one — so a reader can tell at a
## glance which system each entry belongs to. Returns "-" if both are
## empty, matching every one of these grids' existing "nothing to show"
## convention.
static func combined_display(combat_qualities: Array, item_qualities: Array, item_flaws: Array) -> String:
	var combat_part := ", ".join(combat_qualities)
	var item_entries: Array = item_qualities.duplicate()
	item_entries.append_array(item_flaws)
	var item_part := ", ".join(item_entries)
	if combat_part != "" and item_part != "":
		return "%s | %s" % [combat_part, item_part]
	if item_part != "":
		return item_part
	if combat_part != "":
		return combat_part
	return "-"

## How many extra points of gradual damage/wear a Durable item can
## absorb before the normal breakage threshold (damage_flat for
## weapons, armour_points per location for armour) is reached — one
## point of buffer per Durable rating, straight from "the item can take
## +Durable Damage points before it suffers any negatives."
static func extra_durability_points(item_qualities: Array) -> int:
	return rating_of(item_qualities, "Durable")
