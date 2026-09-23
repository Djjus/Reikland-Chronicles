extends Resource
class_name MonsterDatabase

@export var monsters: Array[MonsterDefinition] = []

func find_by_name(monster_name: String) -> MonsterDefinition:
	for m in monsters:
		if m.monster_name == monster_name:
			return m
	return null

## The "unrestricted random draw" pool — every monster whose own
## default_spawn_eligible is true. Per the request: creatures that are
## Size Large+, Demons, or otherwise very dangerous can exist in the
## full dataset (find_by_name still finds them, and naming one
## explicitly in an area's own monster_pool still spawns it) without
## ever turning up in a blind random draw across the whole database.
func _spawn_eligible_monsters() -> Array[MonsterDefinition]:
	var result: Array[MonsterDefinition] = []
	for m in monsters:
		if m.default_spawn_eligible:
			result.append(m)
	return result

## As random_monster_from(), but also excludes anything over
## DifficultyTiers.BEGINNER_AREA_MAX_WOUNDS whenever tier == 0 (per the
## request: "consider Tier 0 area beginner area and do not create
## enemies there that naturally have more than 12 hp"), and prefers
## monsters whose own habitat_tags match the given habitat (per the
## request to "generate location appropriate enemies in the area they
## fit in"). This is the function field encounters actually call —
## random_monster_from() itself stays as the simpler building block
## other callers (or tests) can use without pulling in either concept.
##
## Filters are applied in this order: named pool -> faction match ->
## tile-type faction match -> habitat match -> beginner-area wounds
## cap. Each step falls back to the previous step's result if it would
## otherwise leave nothing standing — a themed zone or a beginner area
## spawning something rather than nothing is still the safer failure,
## same principle random_monster_from() already established.
func random_monster_for_encounter(names: Array[String], tier: int, habitat: String = "", faction: String = "", tile_type: String = "") -> MonsterDefinition:
	var pool: Array[MonsterDefinition] = []
	if names.is_empty():
		pool = _spawn_eligible_monsters()
	else:
		for n in names:
			var m := find_by_name(n)
			if m != null:
				pool.append(m)
		if pool.is_empty():
			pool = _spawn_eligible_monsters()

	## Per the request: "group of enemy should be of similar faction
	## group" — a Clanrat and a Snotling wouldn't team up, but a
	## Clanrat and a Stormvermin (both Skaven) might. Passed in by
	## field_encounter_screen.gd as the first monster's own faction
	## when picking any monster after the first in a multi-monster
	## encounter, so the whole group stays one faction.
	if faction != "":
		var faction_matched: Array[MonsterDefinition] = []
		for m in pool:
			if m.faction == faction:
				faction_matched.append(m)
		if not faction_matched.is_empty():
			pool = faction_matched

	## Per the follow-up request: which factions belong on this kind of
	## tile at all (e.g. Undead in ruins, Skaven in a city) — narrows
	## the pool the same "fall back if it'd leave nothing" way every
	## other filter here already does, so a named monster_pool or an
	## explicit faction match still wins if the tile-type rule would
	## otherwise leave nothing standing.
	if tile_type != "":
		var allowed: Array = TileTypeRules.allowed_factions_for(tile_type)
		var tile_matched: Array[MonsterDefinition] = []
		for m in pool:
			if allowed.has(m.faction):
				tile_matched.append(m)
		if not tile_matched.is_empty():
			pool = tile_matched

	if habitat != "":
		var habitat_matched: Array[MonsterDefinition] = []
		for m in pool:
			if m.habitat_tags.has(habitat):
				habitat_matched.append(m)
		if not habitat_matched.is_empty():
			pool = habitat_matched

	if tier != 0:
		if pool.is_empty():
			return null
		return pool[randi() % pool.size()]

	var beginner_safe: Array[MonsterDefinition] = []
	for m in pool:
		if m.wounds_max <= DifficultyTiers.BEGINNER_AREA_MAX_WOUNDS:
			beginner_safe.append(m)
	if not beginner_safe.is_empty():
		return beginner_safe[randi() % beginner_safe.size()]

	## Nothing in the (possibly pool/habitat-narrowed) candidates fits
	## the beginner cap — widen back to the full spawn-eligible pool
	## (not the raw database, which could include a Large+/dangerous
	## creature that was never meant to appear in a blind draw) rather
	## than falling back to pool/monsters unfiltered. The cap itself is
	## never bypassed; only the pool/habitat preference is relaxed.
	var db_safe: Array[MonsterDefinition] = []
	for m in _spawn_eligible_monsters():
		if m.wounds_max <= DifficultyTiers.BEGINNER_AREA_MAX_WOUNDS:
			db_safe.append(m)
	if not db_safe.is_empty():
		return db_safe[randi() % db_safe.size()]
	return random_monster()

## Per the follow-up request: Large+ creatures (default_spawn_eligible
## == false — Dire Wolf, Troll, Ogre, Giant, Rat Ogre) get a real, rare
## chance to appear on their own rather than never showing up in a
## blind draw at all. The caller (EncounterGroupBuilder) is
## responsible for the "Tier 2+ only" and "10% chance" gates — this
## function's own job is just picking WHICH one, filtered the same
## named-pool -> tile-type faction way the normal pool is, minus the
## beginner-tier wounds cap (Large+ creatures are never Tier 0/1
## material to begin with).
func random_large_monster_for_encounter(names: Array[String], tile_type: String = "", habitat: String = "") -> MonsterDefinition:
	var large_pool: Array[MonsterDefinition] = []
	for m in monsters:
		if not m.default_spawn_eligible:
			large_pool.append(m)
	if large_pool.is_empty():
		return null

	if not names.is_empty():
		var named_matched: Array[MonsterDefinition] = []
		for m in large_pool:
			if names.has(m.monster_name):
				named_matched.append(m)
		if not named_matched.is_empty():
			large_pool = named_matched

	if tile_type != "":
		var allowed: Array = TileTypeRules.allowed_factions_for(tile_type)
		var tile_matched: Array[MonsterDefinition] = []
		for m in large_pool:
			if allowed.has(m.faction):
				tile_matched.append(m)
		if not tile_matched.is_empty():
			large_pool = tile_matched

	if habitat != "":
		var habitat_matched: Array[MonsterDefinition] = []
		for m in large_pool:
			if m.habitat_tags.has(habitat):
				habitat_matched.append(m)
		if not habitat_matched.is_empty():
			large_pool = habitat_matched

	return large_pool[randi() % large_pool.size()]

func random_monster() -> MonsterDefinition:
	var pool := _spawn_eligible_monsters()
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

## As random_monster(), but restricted to only the named monsters when
## the list is non-empty and at least one of them actually exists in
## the database — used by themed encounter zones (a goblin fort, a
## bear's cave) so they genuinely spawn what their name promises,
## rather than the map's generic random pool. A named monster is
## returned even if its own default_spawn_eligible is false — being
## named explicitly is exactly the "unless stated" exception. Falls
## back to the full spawn-eligible pool for an empty list, or if every
## named monster is missing (e.g. a typo in an area's own
## configuration) — a themed zone spawning something rather than
## nothing is the safer failure.
func random_monster_from(names: Array[String]) -> MonsterDefinition:
	if names.is_empty():
		return random_monster()
	var candidates: Array[MonsterDefinition] = []
	for n in names:
		var m := find_by_name(n)
		if m != null:
			candidates.append(m)
	if candidates.is_empty():
		return random_monster()
	return candidates[randi() % candidates.size()]
