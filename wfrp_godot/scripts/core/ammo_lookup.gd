extends RefCounted
class_name AmmoLookup
## Maps a ranged WeaponDefinition to the Ammunition-category ItemDefinition
## name(s) that can feed it (p.294's own Ammunition table). Mirrors
## TrophyLookup's own "small static mapping, not a data field" pattern —
## kept out of WeaponDefinition itself since it's really a relationship
## between two different databases (weapons and items), not a property of
## the weapon alone.
##
## Per the request: "without it you can't shoot" — Bow/Crossbow/Sling/
## Blackpowder all need ammo tracked in inventory and consumed per shot;
## Throwing weapons (Rock, Javelin, Throwing Knife/Axe, Dart) don't — the
## weapon itself IS the projectile, matching the book's own Ammunition
## table, which has no Throwing section at all. Melee weapons obviously
## need none either.
##
## Each entry lists every acceptable ammo name for that skill_group, in
## preference order — a character with both Lead Bullet and Stone Bullet
## for a Sling burns through Lead Bullet first (better ammo used before
## the free-form stuff), same idea for Elf Arrow vs plain Arrow. "Rock"
## (the Throwing weapon — p.294's own free-form Sling ammo) is the
## last-resort entry: it's real inventory stock (see the Pick Up Rocks
## combat action), consumed like any other Sling ammo, but it's also a
## genuine WeaponDefinition in its own right, so the same Rock sitting
## in inventory is equally usable thrown on its own via the free-action
## weapon switch — per the request, "usable with thrown or a sling".
const REQUIRED_AMMO := {
	"Bow": ["Arrow", "Elf Arrow"],
	"Crossbow": ["Bolt"],
	"Sling": ["Lead Bullet", "Stone Bullet", "Rock"],
	"Blackpowder": ["Bullet and Powder", "Small Shot and Powder", "Improvised Shot and Powder"],
}

## Per the light-source follow-up request: several careers' own starting
## trappings (data/careers/*.tres) were written as compound strings that
## don't match any real ItemDefinition name — e.g. "Storm Lantern and
## Oil" — so the whole string was pushed into inventory verbatim,
## granting nothing equippable and (until now) nothing consequential,
## since there was no light system yet to notice. Now that carrying a
## real Lantern (equipped like a weapon, in equipped_weapon/
## equipped_offhand — see Character.get_equipped_light_item()) and a
## real Lamp Oil in inventory actually matter, this splits each
## known compound string into its real, separate ItemDefinition names —
## same "small static mapping, not a data field" pattern as
## REQUIRED_AMMO above. "Pole" has no ItemDefinition of its own in this
## project (no polearm-trapping item exists yet) — dropped rather than
## left as another unmatched string, same as before this fix for that
## one specific word.
const KNOWN_COMPOUND_TRAPPINGS := {
	"Storm Lantern and Oil": ["Storm Lantern", "Lamp Oil"],
	"Storm Lantern with Oil": ["Storm Lantern", "Lamp Oil"],
	"Lantern and Oil": ["Lantern", "Lamp Oil"],
	"Lantern and Pole": ["Lantern"],
	## Per the request ("separate 'Sturdy Boots and Cloak' into separate
	## items, and make this change retro active again to all existing
	## items"): Scout's and Hunter's own starting trappings (see
	## data/careers/scout.tres, hunter.tres) list this as a single
	## string, which previously became one unsplit, unusable "item" in
	## inventory. Split into the two real, separately-trackable/
	## sellable/favouritable items -- both already work correctly with
	## no formal ItemDefinition of their own via the same fallback-price
	## path "Cloak" alone already used before this change (see
	## ShopGridTest's "no-database-entry starting trapping" case).
	## Same mechanism as every other entry in this table: resolved for
	## brand-new characters via character_creator.gd's own
	## AmmoLookup.resolve_trapping() call, AND automatically retroactive
	## for every existing save via Character.from_save_dict()'s own
	## unconditional resolve_trapping() pass over loaded inventory.
	"Sturdy Boots and Cloak": ["Sturdy Boots", "Cloak"],
}

## As KNOWN_COMPOUND_TRAPPINGS, for single trapping strings that are
## just a plain naming mismatch against the real ItemDefinition — e.g.
## "Davrich Lantern" (no such item; the real one is "Davrich Lamp") and
## "Candles" (the real item is "Candle (dozen)"). Also covers the exact
## content strings produced by splitting a "<Container> containing
## <contents>" trapping below — e.g. Peasant/Ranger's own "Rations (1
## day)" content, which the real ItemDefinition spells "Rations, 1 day".
const KNOWN_TRAPPING_RENAMES := {
	"Davrich Lantern": "Davrich Lamp",
	"Candles": "Candle (dozen)",
	"Rations (1 day)": "Rations, 1 day",
	"2 Candles": "Candle (dozen)",
}

## Per the follow-up request ("a number of items that where provided to
## characters during char creation are actually unusable, like
## 'Backpack containing Tinderbox, Blanket, Rations (1 day)', this
## should actually be 4 separate items"): several Class Trappings
## (class_trappings_table.gd) and Career trappings (data/careers/*.tres)
## are written as "<Container> containing <contents...>" — a single
## string that matched no real ItemDefinition at all, so the container
## itself could never be equipped for its capacity bonus (see
## ContainersTest) and its contents never became real, separate,
## trackable inventory items in the first place. resolve_trapping()
## below splits on this literal separator, then splits the contents on
## ", "/" and "/Oxford-comma "and" the same way a person reading the
## sentence would, stripping a leading "a "/"an " article from each
## resulting content token (e.g. "a Flask of Spirits" -> "Flask of
## Spirits"). The container name here always already matches a real
## ItemDefinition in this project's own trapping data (Backpack/Sling
## Bag/Pouch), so it becomes equippable immediately; a content token
## that still doesn't match any real ItemDefinition (e.g. "Writing
## Kit") is nonetheless far more usable as its own standalone entry
## than buried unreachable inside one bigger string — it behaves
## exactly like any other no-database-entry starting trapping (e.g.
## "Cloak"), which this project already prices/sells/displays
## gracefully by design (see Shop's own fallback sell price).
const _CONTAINING_SEPARATOR := " containing "

## Every acceptable ammo item name for `weapon`, in try-this-first order.
## Empty for melee and Throwing weapons — nothing to check or consume.
static func required_ammo_names(weapon: WeaponDefinition) -> Array[String]:
	if weapon == null:
		return []
	var names: Array[String] = []
	for n in REQUIRED_AMMO.get(weapon.skill_group, []):
		names.append(n)
	return names

## True only for weapon types the Ammunition table actually gates —
## Throwing and melee weapons always return false here (nothing to run
## out of, in this project's model).
static func needs_ammo(weapon: WeaponDefinition) -> bool:
	return not required_ammo_names(weapon).is_empty()

## True if `weapon.skill_group == "Sling"` specifically — the one ranged
## category with a free fallback (a plain rock) rather than a hard "no
## ammo, no shot" gate. See Character.has_ammo_for()'s own Round-1
## exception and the "Pick Up Rocks" combat action.
static func is_sling(weapon: WeaponDefinition) -> bool:
	return weapon != null and weapon.skill_group == "Sling"

## The single ammo name a starting-trapping string like "Bow with 10
## arrows" should grant, for weapons whose REQUIRED_AMMO has more than
## one acceptable name — always the FIRST (best/most standard) entry,
## e.g. "Arrow" over "Elf Arrow", "Bullet and Powder" over the Blast-
## flavoured "Small Shot and Powder". The Blunderbuss is a documented
## exception: its whole point is the Blast +1 Small Shot gives it, so a
## starting Blunderbuss trapping grants that instead of plain Bullet and
## Powder.
static func default_trapping_ammo(weapon: WeaponDefinition) -> String:
	if weapon == null:
		return ""
	if weapon.weapon_name == "Blunderbuss":
		return "Small Shot and Powder"
	var names := required_ammo_names(weapon)
	return names[0] if not names.is_empty() else ""

## Splits a starting-trapping string like "Bow with 10 arrows" or "Sling
## with Ammunition" into real, equippable/consumable inventory item
## names — the actual weapon plus N copies of its default ammo — rather
## than the compound description string being pushed into `inventory`
## verbatim (which never matches a real WeaponDefinition name, so the
## weapon couldn't even be equipped, and grants no real ammo at all).
##
## Only handles the "<exact weapon name> with ..." shape: matched by
## checking every known weapon name as a literal prefix (longest match
## wins, so "Crossbow Pistol with 10 Bolts" resolves to Crossbow Pistol,
## not the shorter "Crossbow"). A bare weapon name with no "with" clause
## (e.g. "Bow") already matches a real WeaponDefinition on its own and is
## returned unchanged — same as today. Anything that doesn't fit this
## shape (bundled non-weapon trappings like "Riding Horse with Saddle
## and Tack", or an unresolved choice like "Sword or Bow with 10
## arrows" — no weapon name is a literal PREFIX of either, so neither
## matches) is returned unchanged too, exactly as it was handled before
## this function existed — a deliberate, safe fallback rather than a
## best-effort guess.
static func resolve_trapping(trapping: String) -> Array[String]:
	## Per the light-source follow-up request: fix known-broken compound/
	## renamed lantern-oil-candle trapping strings first, before any of
	## the weapon-ammo logic below even runs — these aren't weapons at
	## all, so they'd never have matched anything down there anyway.
	if KNOWN_COMPOUND_TRAPPINGS.has(trapping):
		var resolved: Array[String] = []
		for n in KNOWN_COMPOUND_TRAPPINGS[trapping]:
			resolved.append(n)
		return resolved
	if KNOWN_TRAPPING_RENAMES.has(trapping):
		return [KNOWN_TRAPPING_RENAMES[trapping]]
	## "<Container> containing <contents...>" — see the doc comment above
	## _CONTAINING_SEPARATOR. Checked before the weapon-ammo logic below
	## since a container/contents phrase never matches a weapon name
	## anyway; each split piece is fed back through resolve_trapping()
	## itself (not just the rename table) so a future container full of,
	## say, a bundled weapon-with-ammo trapping would still resolve
	## correctly too, not just plain renames.
	var containing_idx := trapping.find(_CONTAINING_SEPARATOR)
	if containing_idx != -1:
		var container_name := trapping.substr(0, containing_idx).strip_edges()
		var contents_str := trapping.substr(containing_idx + _CONTAINING_SEPARATOR.length())
		var resolved_container: Array[String] = [container_name]
		for token in _split_container_contents(contents_str):
			resolved_container.append_array(resolve_trapping(token))
		return resolved_container
	if GameData == null or GameData.weapon_db == null:
		return [trapping]
	## A bare weapon name (no "with" clause) already works as-is.
	if GameData.weapon_db.find_by_name(trapping) != null:
		return [trapping]
	var best_weapon: WeaponDefinition = null
	for w in GameData.weapon_db.weapons:
		var prefix := w.weapon_name + " with "
		if trapping.begins_with(prefix):
			if best_weapon == null or w.weapon_name.length() > best_weapon.weapon_name.length():
				best_weapon = w
	if best_weapon == null or not needs_ammo(best_weapon):
		return [trapping]
	var remainder := trapping.substr(best_weapon.weapon_name.length() + 5)   ## +5 = " with ".length()
	var ammo_name := default_trapping_ammo(best_weapon)
	if ammo_name == "":
		return [trapping]
	var count := 10   ## the book data's own consistent default bundle size wherever no number is given (e.g. "with Ammunition")
	var first_word := remainder.split(" ")[0]
	if first_word.is_valid_int():
		count = first_word.to_int()
	var resolved: Array[String] = [best_weapon.weapon_name]
	for i in range(count):
		resolved.append(ammo_name)
	return resolved

## Splits the "<contents...>" half of a "<Container> containing
## <contents...>" trapping into individual item-name tokens — e.g.
## "Tweezers, Ear Pick, and a Comb" -> ["Tweezers", "Ear Pick", "Comb"].
## Unifies the Oxford-comma "and" ("X, Y, and Z") and the plain two-item
## "and" ("X and Y") down to the same comma separator before splitting,
## then strips a leading "a "/"an " article from each resulting token
## (only ever appears on a single, ungrouped content item, e.g. "a
## Flask of Spirits" -> "Flask of Spirits") — a quantity prefix like "2
## Candles" is left alone (doesn't begin with "a "/"an ", so nothing to
## strip), matching the existing "N ItemName" convention already used
## elsewhere in this project's own trapping data (e.g. "3 Pamphleteers",
## "1d10 Rags").
static func _split_container_contents(contents: String) -> Array[String]:
	var normalized := contents.replace(", and ", ", ").replace(" and ", ", ")
	var result: Array[String] = []
	for part in normalized.split(","):
		var token := part.strip_edges()
		if token == "":
			continue
		if token.begins_with("a "):
			token = token.substr(2)
		elif token.begins_with("an "):
			token = token.substr(3)
		result.append(token)
	return result
