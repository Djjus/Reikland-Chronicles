extends RefCounted
class_name EncounterGroupBuilder
## Picks the group of MonsterDefinitions a field encounter will use —
## extracted out of field_encounter_screen.gd's own spawning loop so
## the new ambush-detection system (Overworld.gd) can select the exact
## same group *before* combat actually starts, roll the detection Test
## against it, and then have FieldEncounter build Characters from that
## already-decided group instead of rolling a fresh, potentially
## different one.

## 25% chance of 2 enemies rather than a flat 50/50 — with just the
## one player character, a 2-on-1 fight is already meaningfully
## harder, so a coin-flip chance of it happening every single
## encounter was too punishing. This should scale back up once
## hirelings/other party members exist to actually back the player up
## against larger groups.
##
## Per the follow-up request: Large+ creatures (Dire Wolf, Troll, Ogre,
## Giant, Rat Ogre) get a real, rare chance to appear on their own —
## Tier 2+ only, a flat 10% roll checked first, before the normal
## small-group selection below (a solo appearance, not grouped with
## anything else, matching how these already read as "boss-tier"
## encounters elsewhere in this project). Rolling the 10% and then
## finding nothing eligible (e.g. an empty tile_type/pool match) simply
## falls through to a normal encounter — the roll is never "wasted" as
## a guaranteed non-encounter.
static func select_group(pool: Array[String], tier: int, habitat: String, tile_type: String = "") -> Array[MonsterDefinition]:
	if tier >= 2 and randf() < 0.10:
		var large_mdef: MonsterDefinition = GameData.monster_db.random_large_monster_for_encounter(pool, tile_type, habitat)
		if large_mdef != null:
			return [large_mdef]

	## Per the request: once the party has more than one member, random
	## encounters always guarantee the creatures outnumber the party by
	## +1 — fulfils the TODO above this function's own doc comment, now
	## that party members genuinely exist to back each other up. Solo
	## play keeps the original 25%-chance-of-2 behaviour unchanged. The
	## Large+ solo-boss path above is a deliberate exception — matches
	## its own existing design as a solo "boss-tier" appearance, not
	## part of ordinary group-size scaling.
	var party_size: int = GameState.party.size()
	var monster_count: int
	if party_size > 1:
		monster_count = party_size + 1
	else:
		monster_count = 2 if randf() < 0.25 else 1
	var group_faction := ""
	var result: Array[MonsterDefinition] = []
	for i in range(monster_count):
		var mdef: MonsterDefinition = GameData.monster_db.random_monster_for_encounter(pool, tier, habitat, group_faction, tile_type)
		if mdef == null:
			break
		if i == 0:
			group_faction = mdef.faction   ## every monster after the first is constrained to this same faction
		result.append(mdef)
	return result
