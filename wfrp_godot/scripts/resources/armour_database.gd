extends Resource
class_name ArmourDatabase

@export var pieces: Array[ArmourDefinition] = []

func find_by_name(armour_name: String) -> ArmourDefinition:
	for a in pieces:
		if a.armour_name == armour_name:
			return a
	return _resolve_composed_quality_name(armour_name)

## Self-healing fallback — see WeaponDatabase._resolve_composed_quality_
## name()'s own header comment for the full report/root-cause writeup
## (report: "dungeon weapon and armor drops seem not to be equipable/
## usable") and its own reasoning for why this greedily peels the
## LONGEST run of leading Item Quality tokens rather than trying
## shorter peels first. Same exact bug, same exact fix, mirrored for
## armour: FieldEncounterScreen's own _grant_armour_reward() (a Dungeon
## Cupboard's reward) and ShopScreen's own _on_place_craft_order()
## compose a name like "Durable Mail Shirt" and register it live into
## THIS array, never persisted anywhere — so it silently stops
## resolving (and becomes permanently un-equippable) the moment the app
## restarts. Reconstructed on demand the same way: peel known Item
## Quality tokens off the front until nothing more peels, then check
## whether the remainder resolves to a real registered base armour
## piece, and recompose via the same duplicate/derive-price/register
## steps _grant_armour_reward() uses.
func _resolve_composed_quality_name(armour_name: String) -> ArmourDefinition:
	var tokens := armour_name.split(" ")
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
		return null   ## nothing peelable, or nothing left over to be a base armour piece
	var remainder := " ".join(tokens.slice(i))
	var base: ArmourDefinition = find_by_name(remainder)
	if base == null:
		return null
	return _compose_and_register(base, peeled)

func _compose_and_register(base: ArmourDefinition, item_qualities: Array[String]) -> ArmourDefinition:
	var composed_name := "%s %s" % [" ".join(item_qualities), base.armour_name]
	## A flat, direct scan here (never find_by_name(), which would fall
	## back into _resolve_composed_quality_name() again for this exact
	## same not-yet-registered name and recurse forever).
	for a in pieces:
		if a.armour_name == composed_name:
			return a
	var ad: ArmourDefinition = base.duplicate()
	ad.armour_name = composed_name
	ad.item_qualities = item_qualities
	ad.item_flaws = []
	var derived := ItemQualityRules.compute_derived(base.price_pennies, base.availability, item_qualities, [], base.encumbrance)
	ad.price_pennies = int(derived["price_pennies"])
	ad.availability = String(derived["availability"])
	pieces.append(ad)
	return ad
