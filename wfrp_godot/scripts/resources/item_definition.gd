extends Resource
class_name ItemDefinition
## A general trapping/trade good — food, trophies, tools, everyday goods
## — distinct from Weapons/Armour, which have their own databases with
## combat-specific fields. Availability and pricing follow the
## Consumers' Guide (p.288-291): Common items are always in stock
## everywhere; Scarce/Rare need an Availability roll that gets easier in
## bigger settlements; Exotic isn't sold at all under normal shop rules.

@export var item_name: String = ""
@export_enum("Food", "Trophy", "General", "Tool", "Container", "Reagent", "Ammunition") var category: String = "General"
@export_enum("Common", "Scarce", "Rare", "Exotic") var availability: String = "Common"
@export var price_pennies: int = 0   ## list price, in Brass Pennies (12d = 1s, 240d = 1 GC)
@export var encumbrance: int = 0
@export var summary: String = ""

## Per the "packs and containers" request: a wearable Container item
## (Backpack, Pouch, Sling Bag — Saddlebags is deliberately left ""
## here, per the request's own scope of only 3 real equip slots) names
## the one Character equip slot it can go into. "" means this item
## can't be worn as a container at all — including every non-Container
## item, and Saddlebags itself, which is still a real buyable/sellable
## Trapping, just not one the character straps on. See
## Character.get_equipped_container()/set_equipped_container() for the
## slot names this must match ("Back"/"Waist"/"Shoulder").
## Not an @export_enum ("" isn't a valid enum entry in Godot) — just a
## plain String, always one of "" (not equippable), "Back", "Waist", or
## "Shoulder" in practice.
@export var container_slot: String = ""
## How much extra Enc this container lets its wearer carry — the
## table's own "Carries" value. Character.get_container_capacity_bonus()
## nets this against the container's own worn Enc (its encumbrance,
## discounted by the usual Worn Items -1 rule) to get the real bonus to
## Carrying Capacity; this field alone is just the raw "Carries" number.
@export var container_capacity: int = 0

## Per the light-source request: 0 means "not a light source." A
## positive value is this item's illumination radius in tiles at its
## normal ("on") brightness — per the request's own reference material,
## treated as a straight 1-yard-per-tile conversion (e.g. the Lantern's
## "20 yards" trapping text becomes 20 here). Held exactly like a
## weapon, in Character.equipped_weapon/equipped_offhand — see
## Character.get_equipped_light_item().
@export var light_radius_tiles: int = 0
## 0 means this light source has no separate low-flame mode — the L
## hotkey's toggle simply skips "low" and cycles straight back to off.
## Positive for items where Lamp Oil's own text calls out a low-flame
## option (Lantern, Storm Lantern): per the request ("on/off(/lowlight
## if lantern)"), only lantern-type sources get this third state.
@export var light_radius_tiles_low: int = 0
## True for light sources that draw down a Lamp Oil reserve while lit
## (Lantern, Storm Lantern, and now Davrich Lamp too — see
## Character.LAMP_OIL_MINUTES/tick_light_fuel()); false for sources
## that don't touch Lamp Oil at all (Candle — see
## light_self_fuel_minutes below, which covers what Candle uses
## instead of this).
@export var light_requires_oil: bool = false
## Per the request ("Candles too but without the Oil/fuel component,
## candles last 4hrs each"): 0 for every light source above (they use
## light_requires_oil's Lamp Oil reserve, or — for a source with
## neither this nor light_requires_oil set — burn indefinitely once
## lit, with nothing to run out). Positive for a self-consuming light
## source like Candle: how many minutes ONE equipped unit of this item
## itself lasts before burning out, at which point
## Character.tick_light_fuel() erases that one spent unit from
## inventory and, if another copy of the same item is still in stock,
## silently lights it fresh from this same value — no separate fuel
## item (like Lamp Oil) ever enters the equation.
@export var light_self_fuel_minutes: float = 0.0
## Per the request ("note there should be 12/a dozen when buying
## them"): 1 for every item except Candle (dozen), where this is 12 —
## how many individual inventory copies a single Shop purchase grants,
## while price_pennies stays the price for the WHOLE purchase (i.e.
## the book's "Candle (dozen): 1/-" price buys all 12 candles for that
## 12d total, not 12d per candle) — see shop_screen.gd's
## _on_buy_item().
@export var purchase_bundle_quantity: int = 1

## Per the "implement Ammunition fully" request: these four fields are
## only populated for category == "Ammunition" items (0/false/empty on
## every other item, per this file's established category-gated-field
## convention — see container_slot/light_radius_tiles above for the
## same pattern). They mirror the core rulebook's Ammunition table's
## own Range/Damage/Qualities columns, applied on top of the firing
## weapon's own stats — see Character.get_active_ammo_item(),
## Character.get_effective_weapon_range(), and
## Character.get_effective_weapon_qualities().
## The table's "+50"/"-10" style range modifiers, added to the
## weapon's own range_yards (0 = no change).
@export var ammo_range_bonus: int = 0
## True only for ammo whose table entry reads "Half weapon" (currently
## just Improvised Shot and Powder) — the weapon's range_yards is
## halved before ammo_range_bonus is applied.
@export var ammo_range_halves: bool = false
## The table's flat Damage modifier ("+1" entries; 0 for a "–" entry).
@export var ammo_damage_bonus: int = 0
## The table's Qualities column, unioned onto the firing weapon's own
## effective qualities for as long as this ammo is loaded — plain
## quality names (e.g. "Impale", "Penetrating", "Accurate") union in
## directly; one special case is a rated "Blast +N" string (only Small
## Shot and Powder uses this today), which
## Character._apply_ammo_quality_bonus() interprets as "add N to the
## weapon's own Blast rating" (adding a fresh "Blast N" entry if the
## weapon has none) rather than as a literal quality name to union in.
@export var ammo_added_qualities: Array[String] = []
