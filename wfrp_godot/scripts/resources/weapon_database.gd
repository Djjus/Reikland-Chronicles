extends Resource
class_name WeaponDatabase

@export var weapons: Array[WeaponDefinition] = []

func find_by_name(weapon_name: String) -> WeaponDefinition:
	for w in weapons:
		if w.weapon_name == weapon_name:
			return w
	return _resolve_composed_quality_name(weapon_name)

## Self-healing fallback for the report ("dungeon weapon and armor
## drops seem not to be equipable/usable").
##
## FieldEncounterScreen's own _grant_weapon_reward() (a Dungeon Weapon
## Rack's reward) and ShopScreen's own _on_place_craft_order() (a
## Crafting order) both compose a General Trapping Item Quality name
## like "Durable Sword" or "Lightweight Practical Halberd" and
## register a brand-new WeaponDefinition straight into THIS array the
## first time that exact combination is ever seen — see either
## function's own header comment ("duplicate-and-register... reused
## afterward, same 'same name, same stats, share one definition'
## convention"). That registration only ever happens in memory: nothing
## persists `weapons` itself (SaveManager only ever saves Character
## data — inventory is a flat Array[String] of names). So a composed
## name resolves fine for the rest of the session it was created in,
## then stops resolving the moment the app restarts — GameData._ready()
## reloads this Resource fresh from its static .tres file, which never
## had the dynamic entry. From then on this exact weapon is silently
## un-equippable forever: character_menu_screen.gd's own equip-button
## logic renders nothing at all when find_by_name() misses (see its
## `inv_weapon == null` fallthrough), so the item just sits in
## inventory looking like plain, unusable clutter.
##
## Rather than teaching SaveManager to serialize arbitrary extra
## WeaponDefinition Resources (a much bigger, riskier change to the
## save format), this reconstructs the exact same Resource on demand
## the moment anything asks for it by name again: greedily peels known
## Item Quality tokens (Durable/Fine/Lightweight/Practical, each
## optionally followed by a rating number, e.g. "Durable 2" — see
## ItemQualityRules.QUALITY_NAMES/parse_entry) off the FRONT of the
## name — the LONGEST such run, not just one — then checks whether
## what's left resolves to a real registered base weapon, and if so
## recomposes via the exact same duplicate/derive-price/register steps
## _grant_weapon_reward() uses.
##
## Deliberately the longest peel rather than trying shorter ones first:
## a Crafting order's own base is always guaranteed quality-prefix-free
## (the Crafting tab's own base-item picker excludes every static
## Fine/Durable/etc. variant — see CraftingTest), so for that flow the
## longest peel is always exactly correct. A dungeon Weapon Rack's own
## base, by contrast, is drawn from this WHOLE array via pick_random()
## and can occasionally already BE a quality-tagged static item (e.g.
## "Fine Sword") before further qualities get rolled on top — a name
## like "Durable Fine Sword" is then genuinely ambiguous (qualities
## [Durable, Fine] on plain "Sword", or just [Durable] on "Fine
## Sword"?) with no way to recover the true original split from the
## string alone. This deliberately resolves that rare case as the
## former (all peelable words treated as qualities, plain "Sword" as
## the base) rather than trying to special-case it: the result is
## still a fully valid, correctly-priced, genuinely equippable weapon
## either way — only its derived stats/price potentially differ very
## slightly from the exact original roll — so preferring the split that
## keeps the much more common, much more heavily-used Crafting flow
## 100% correct is the right trade-off.
func _resolve_composed_quality_name(weapon_name: String) -> WeaponDefinition:
	var tokens := weapon_name.split(" ")
	var peeled: Array[String] = []
	var i := 0
	while i < tokens.size():
		var word: String = tokens[i]
		if not ItemQualityRules.QUALITY_NAMES.has(word):
			break
		var entry := word
		i += 1
		if i < tokens.size() and tokens[i].is_valid_int():
			entry = "%s %s" % [word, tokens[i]]
			i += 1
		peeled.append(entry)
	if peeled.is_empty() or i >= tokens.size():
		return null   ## nothing peelable, or nothing left over to be a base weapon
	var remainder := " ".join(tokens.slice(i))
	var base: WeaponDefinition = find_by_name(remainder)
	if base == null:
		return null
	return _compose_and_register(base, peeled)

func _compose_and_register(base: WeaponDefinition, item_qualities: Array[String]) -> WeaponDefinition:
	var composed_name := "%s %s" % [" ".join(item_qualities), base.weapon_name]
	## A flat, direct scan here (never find_by_name(), which would fall
	## back into _resolve_composed_quality_name() again for this exact
	## same not-yet-registered name and recurse forever).
	for w in weapons:
		if w.weapon_name == composed_name:
			return w
	var wd: WeaponDefinition = base.duplicate()
	wd.weapon_name = composed_name
	wd.item_qualities = item_qualities
	wd.item_flaws = []
	var derived := ItemQualityRules.compute_derived(base.price_pennies, base.availability, item_qualities, [], base.encumbrance)
	wd.price_pennies = int(derived["price_pennies"])
	wd.availability = String(derived["availability"])
	weapons.append(wd)
	return wd
