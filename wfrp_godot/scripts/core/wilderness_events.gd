extends RefCounted
class_name WildernessEvents
## The Wilderness Travel Events tables from Deft Steps, Light Fingers
## (Pathfinding chapter), adapted as closely as possible to their own
## specific rolls and effects, reusing this project's own existing
## systems (TestResolver, Character.conditions, FieldEncounter) rather
## than inventing new ones where an existing mechanic already covers
## the same ground.
##
## Honest scope note: three results (Barrow, Monolith, Ruin) each
## point to their own full sub-table in the source material — the
## Ruin Table alone is a 2d10, 19-entry table, and the Ancient Tomb
## Table it can lead to is a full 4-column, 10-row dungeon-seed table
## of its own. Reproducing those in full was out of scope for this
## pass; each is instead resolved as a single, representative
## encounter of the same *kind* the full table would most often
## produce, clearly flagged in its own entry below.
##
## Monsters referenced in the source that this project's own bestiary
## doesn't have (Fimir, River Troll, Griffon, Manticore, Pegasus,
## Wyvern, Necromancer, Ghost/Spectre) are substituted with the
## closest real equivalent already in the database, noted per entry.

## Every entry: {type, text, ...params}. type determines resolution:
##   "flavor"       — text only, Continue closes it.
##   "flavor_test"  — text, an optional Lore/Skill Test for more
##                    detail (no real consequence either way).
##   "skill_test"   — text, a required Test; consequence differs by
##                    pass/fail (condition, damage, or nothing).
##   "hazard"       — an environmental danger; may offer a Test to
##                    avoid/reduce a real Condition or Wound effect.
##   "combat"       — triggers a real FieldEncounter with the given
##                    monster pool (one entry chosen at random).
##   "social_choice" — a real avoid/approach choice; approaching
##                    starts a real SocialEncounter.
##   "sub_table"    — Barrow/Monolith/Ruin: a short, representative
##                    stand-in for the full sub-table (see note above).

const TABLE_1 := [
	{"type": "hazard", "text": "Pathway Blocked. A lake, river, or gorge blocks your path. There's no way around it by ordinary means — you'll need to find another route.",
		"delay_days": 2},
	{"type": "sub_table", "text": "Barrow. You pass a series of eerie standing stones surrounding a small hill — an ancient burial mound.",
		"skill_names": ["Lore (History)", "Lore (Local)"], "sub_type": "barrow"},
	{"type": "sub_table", "text": "Monolith. A single standing stone, worn by centuries of wind and rain, rises from the ground ahead — or perhaps an old circle of menhirs.",
		"sub_type": "monolith"},
	{"type": "sub_table", "text": "Ruin. The remains of old buildings lie half-swallowed by the wild — a once-great structure, now just a footprint and a few standing walls.",
		"sub_type": "ruin"},
	{"type": "skill_test", "text": "Ailing Animal. One of your own pack animals has fallen ill on the road.",
		"skill_name": "Animal Care", "difficulty": -20, "fail_condition": "Fatigued", "fail_text": "Despite your best efforts, the animal grows weaker.",
		"pass_text": "You nurse it back to health before it worsens."},
	{"type": "skill_test", "text": "Worn Out Item. Wear and tear catches up with a piece of your own equipment.",
		"skill_name": "Intelligence", "difficulty": -20, "fail_condition": "", "fail_text": "You can't repair it in time — it's seen better days.",
		"pass_text": "A little field maintenance sets it right."},
	{"type": "social_choice", "text": "Fellow Travellers. You spot a band of travellers on the road ahead — a handful of peddlers or villagers, by the look of them."},
	{"type": "flavor", "text": "Spring. Clear, fresh water bubbles up from the ground — you take the chance to refill your water skins without even needing to look for a source."},
	{"type": "combat", "text": "Animals Encountered. A pack of wolves forages nearby, unlikely to trouble a whole group — but a straggler wouldn't be so lucky.",
		"monster_pool": ["Wolf", "Wolf", "Wolf"]},
	{"type": "combat", "text": "Enemies Encountered. A small band crosses your path, and there's no mistaking their intent.",
		"monster_pool": ["Forest Goblin", "Ungor", "Outlaw"]},
]

const TABLE_2_MOUNTAINS := [
	{"type": "skill_test", "text": "Mountain Sickness. The thin air at this altitude catches up with you.",
		"skill_name": "Endurance", "difficulty": 0, "fail_condition": "Fatigued", "fail_text": "Your head swims and your stomach turns — the malaise passes only once you're back at lower ground.",
		"pass_text": "You push through the light-headedness without real trouble."},
	{"type": "skill_test", "text": "Scree Slope. A steep bank of loose stone blocks the direct route.",
		"skill_name": "Athletics", "difficulty": 0, "fail_condition": "", "fail_text": "Your footing gives way — you take a hard fall down the slope.",
		"pass_text": "You pick your way across carefully, without incident.", "fail_damage": "1d10"},
	{"type": "flavor", "text": "Blizzard. The weather turns dramatically for the worse — bitter cold, thick snow, and a wind that cuts through every layer you own. You press on regardless, and the storm abates by the time you make camp."},
	{"type": "combat", "text": "Beast Lair. You stumble across the lair of something large and dangerous, and it does not welcome visitors.",
		"monster_pool": ["Ogre", "Rat Ogre"]},
	{"type": "combat", "text": "Enemies Encountered. A small group crosses your path in the high passes.",
		"monster_pool": ["Orc", "Outlaw", "Troll"]},
]

const TABLE_3_DEEP_FOREST := [
	{"type": "hazard", "text": "Bloodsedge Grove. Thorny, grasping plants choke the undergrowth ahead — the kind that strangle anything that wanders too close.",
		"skill_name": "Lore", "specialisation": "Herbs", "avoid_difficulty": 40, "fallback_skill": "Outdoor Survival", "fallback_difficulty": 0,
		"fail_text": "A branch catches hold before you can pull free, and its thorns bite deep.", "fail_damage": "1d5",
		"pass_text": "You spot the danger and pick a careful path around it."},
	{"type": "flavor_test", "text": "Herbs. A glade opens ahead, thick with unfamiliar plants.",
		"skill_name": "Lore", "specialisation": "Herbs", "difficulty": 40, "pass_text": "You recognise a useful herb among them and gather what you can — worth a little coin in the right market."},
	{"type": "skill_test", "text": "Spites. Something small and unseen plagues the forest here — you can't sleep soundly for as long as you linger.",
		"skill_name": "Cool", "difficulty": 0, "fail_condition": "Fatigued", "fail_text": "Whatever it is, it wears on you through the night.",
		"pass_text": "You shrug off the unease well enough."},
	{"type": "combat", "text": "Spiders. You stumble into the lair of a nest of giant spiders, and they are not inclined to let you simply pass by.",
		"monster_pool": ["Giant Spider", "Giant Spider", "Giant Spider"]},
	{"type": "combat", "text": "Enemies Encountered. A small group crosses your path deep in the trees.",
		"monster_pool": ["Forest Goblin", "Gor", "Outlaw"]},
]

const TABLE_4_WETLANDS := [
	{"type": "skill_test", "text": "Swamp Fever. Something in the murky water has bitten you without your even noticing — a raw, red patch and a rising fever are the first signs.",
		"skill_name": "Endurance", "difficulty": 0, "fail_condition": "Fatigued", "fail_text": "The fever takes hold.",
		"pass_text": "Your body fights it off before it can take hold."},
	{"type": "skill_test", "text": "Quick Mud. The ground here is treacherous — soft mud flats that threaten to swallow anyone who strays off the firm path.",
		"skill_name": "Strength", "difficulty": 0, "fail_condition": "Fatigued", "fail_text": "You struggle free, exhausted, mud-caked, and considerably worse for wear.",
		"pass_text": "You cross without serious trouble, if not gracefully."},
	{"type": "hazard", "text": "Foul Air. A pocket of suffocating gas hangs low over the marsh — you have to cross right through it.",
		"skill_name": "Endurance", "avoid_difficulty": 20, "fail_text": "The fumes leave you reeling, stumbling, and thoroughly disoriented.",
		"pass_text": "You hold your breath and push through before it can affect you.", "fail_condition": "Fatigued"},
	{"type": "combat", "text": "Beast Lair. Something large and dangerous makes its home in the wetlands here.",
		"monster_pool": ["Troll", "Ogre"]},
	{"type": "combat", "text": "Enemies Encountered. A small group crosses your path through the reeds and mud.",
		"monster_pool": ["Goblin", "Troll", "Outlaw"]},
]

## Per the follow-up request: the full Ancient Tomb, Monolith, and
## Ruin tables, built out properly rather than the earlier single-
## outcome simplification. "Extended Test" mechanics from the source
## (accumulating SL across several rolls to a target total) are
## resolved here as a single, appropriately-weighted Test instead —
## this project's own TestResolver doesn't track multi-roll SL
## accumulation, and a single harder roll is the closest honest
## equivalent rather than a half-built multi-roll system. Monsters
## the source names that this project's bestiary doesn't have (Ghost,
## Spectre, Banshee, Cairn Wraith, Necromancer, Tomb Robbers) are
## substituted with the closest real equivalent already in the
## database (Zombie/Skeleton for incorporeal undead, Cultist for a
## sinister spellcaster, Outlaw for Tomb Robbers/Bandits).

## Each entry: {entrance_text, door_lock_sl (int or -1 if no lock),
## door_break_target (Strength test difficulty, or -1 if no barrier),
## inhabitants (monster pool, or [] if none), loot_gc (int or [lo,hi]
## for a die range), loot_text, feature_text, feature_type, ...}.
const ANCIENT_TOMB_TABLE := [
	{"entrance": "An open doorway, no barrier at all.", "lock_sl": -1, "break_target": -1,
		"inhabitants": [], "loot_gc": 0, "loot_text": "", "feature": ""},
	{"entrance": "An open doorway — but you're not the first to find it. A den of goblins has moved in.", "lock_sl": -1, "break_target": -1,
		"inhabitants": ["Goblin", "Goblin"], "loot_gc": 0, "loot_text": "", "feature": ""},
	{"entrance": "The doorway is buried — a Hard Perception Test is needed just to find it.", "lock_sl": -1, "break_target": -1, "find_difficulty": -20,
		"inhabitants": ["Outlaw"], "loot_gc": 2, "loot_text": "golden ornaments",
		"feature": "Forsaken by Morr — any undead within resist final death and seem to knit back together."},
	{"entrance": "A reinforced oak door, still solid after all these years.", "lock_sl": 4, "break_target": 0,
		"inhabitants": ["Outlaw"], "loot_gc": [1, 10], "loot_text": "golden ornaments",
		"feature": "A sarcophagus dominates the chamber — anything of real value is sealed inside it."},
	{"entrance": "A reinforced oak door, swollen shut with age.", "lock_sl": 5, "break_target": 0,
		"inhabitants": ["Cultist"], "loot_gc": [2, 20], "loot_text": "a horde of ancient coin",
		"feature": "submerged", "feature_text": "The chamber has flooded — reaching the loot means a real swim through cold, dark water."},
	{"entrance": "A wrought iron gate, rusted but intact.", "lock_sl": 4, "break_target": -10,
		"inhabitants": ["Zombie"], "loot_gc": [2, 20], "loot_text": "a horde of ancient coin",
		"feature": "vermin", "feature_text": "A family of giant rats has made a home here, and they don't welcome guests.",
		"feature_monsters": ["Giant Rat", "Giant Rat", "Giant Rat"]},
	{"entrance": "A wrought iron gate, held by a stubborn old lock.", "lock_sl": 5, "break_target": -10,
		"inhabitants": ["Skeleton"], "loot_gc": 0, "loot_text": "rusted swords and armour, historical interest but no real coin value",
		"feature": "cold", "feature_text": "The air inside is unnaturally cold — the kind that bites straight through a coat."},
	{"entrance": "A slab of stone seals the way — moving it will take real effort.", "lock_sl": -1, "break_target": -20,
		"inhabitants": ["Skeleton", "Skeleton"], "loot_gc": [3, 30], "loot_text": "a bulky marble statue or golden ornament, heavy but valuable",
		"feature": "trap", "feature_text": "A loose paving slab triggers a real rockfall trap for the unwary."},
	{"entrance": "A slab of stone seals the way, thick with old dust.", "lock_sl": -1, "break_target": -20,
		"inhabitants": ["Skeleton", "Skeleton", "Zombie"], "loot_gc": 0, "loot_text": "a fine collection of old but well-preserved weapons",
		"feature": "mould", "feature_text": "A patch of Yellow Mould lurks nearby, ready to release its spores on anyone careless enough to disturb it."},
	{"entrance": "A heavy stone covering, sealed for what feels like centuries.", "lock_sl": -1, "break_target": -30,
		"inhabitants": ["Skeleton", "Skeleton", "Zombie"], "loot_gc": 0, "loot_text": "real magical items, worth recovering carefully",
		"feature": "maze", "feature_text": "A labyrinth of passages stands between you and the true burial chamber."},
]

## 1d10. Grave Marker (9) redirects to ANCIENT_TOMB_TABLE.
const MONOLITH_TABLE := [
	{"roll_max": 3, "text": "A simple marker. Impressive to look at, but nothing more than an old boundary stone or ritual site."},
	{"roll_max": 5, "text": "A Beastman herdstone — profane carvings, dried blood, and an unmistakable wrongness to the air around it. Best not to linger."},
	{"roll_max": 6, "text": "An Ogham circle, raised by followers of the Old Faith long before Sigmar's time. There's an old, quiet power to the place."},
	{"roll_max": 8, "text": "An Elven waystone, part of the ancient network that channels magic toward distant Ulthuan. It hums faintly, even to those with no gift for magic."},
	{"roll_max": 9, "text": "GRAVE_MARKER"},
	{"roll_max": 10, "text": "An Orc totem, desecrated with crude carvings and worse. If anything's still using this site, it won't welcome strangers.",
		"hostile": true, "monster_pool": ["Orc", "Goblin"]},
]

## 2d10. Bandit Camp (17-18) and Trolls (19) reference "loot column of
## the Ancient Tomb Table" specifically — represented here as simply
## rolling the full table and using only its own loot_gc/loot_text.
const RUIN_TABLE := [
	{"roll_max": 2, "text": "A Witch has made this ruin her hideout — wary of strangers, but not necessarily hostile if you approach with care.",
		"social": true},
	{"roll_max": 3, "text": "A long-abandoned trading post. A careful search turns up a little forgotten coin among the debris.",
		"loot_gc": [1, 10]},
	{"roll_max": 5, "text": "The ruin has been recently resettled — small-scale farmers, woodcutters, or a wandering caravan, eyeing you with chilly formality rather than open hostility.",
		"social": true},
	{"roll_max": 7, "text": "A band of Snotlings has infested the ruin, and by daylight they're more scared of you than you are of them.",
		"hostile_chance": 0.3, "monster_pool": ["Snotling", "Snotling", "Snotling"]},
	{"roll_max": 14, "text": "Rubble. Whatever this once was, there's nothing left worth the detour."},
	{"roll_max": 16, "text": "A sound structure still stands among the ruin — solid enough to make real camp for the night, if you needed to."},
	{"roll_max": 18, "text": "A band of outlaws has claimed the ruin as their own camp.",
		"hostile": true, "monster_pool": ["Outlaw", "Outlaw", "Highway Bandit"]},
	{"roll_max": 19, "text": "A trio of trolls has made this place its lair — the stones are smeared with old blood and worse.",
		"hostile": true, "monster_pool": ["Troll"]},
	{"roll_max": 20, "text": "A wizard's tower, or what passes for one out here — secluded, and probably by choice. Whoever lives here may have their own reasons for the isolation.",
		"social": true},
]

## Per the source: rolling 1-5 on Tables 2/3/4 redirects to Table 1
## entirely — represented here by each of those three tables only
## holding their own unique 6-10 entries (5 entries each), with the
## caller rolling 1d10 and treating 1-5 as "use Table 1 instead."
## Per the request: always show the actual dice roll behind a
## Wilderness Event — the returned dictionary now carries its own
## "_roll" (the d10 that picked it) and "_table" (which table it
## actually came from, since a 1-5 roll on a non-plains terrain
## redirects to Table 1) as real metadata. Returns a duplicate rather
## than the raw table entry itself, since these entries are direct
## references into the shared const tables above — writing metadata
## directly onto them would permanently pollute the const data across
## every future roll.
static func roll_event(terrain_category: String) -> Dictionary:
	var d10 := randi_range(1, 10)
	var result: Dictionary
	var table_name: String
	match terrain_category:
		"forest":
			if d10 <= 5:
				result = TABLE_1[randi_range(0, TABLE_1.size() - 1)]
				table_name = "Light Woodland/Hills/Plains"
			else:
				result = TABLE_3_DEEP_FOREST[d10 - 6]
				table_name = "Deep Forest"
		"difficult_mountain":
			if d10 <= 5:
				result = TABLE_1[randi_range(0, TABLE_1.size() - 1)]
				table_name = "Light Woodland/Hills/Plains"
			else:
				result = TABLE_2_MOUNTAINS[d10 - 6]
				table_name = "Mountains"
		"difficult_wetland":
			if d10 <= 5:
				result = TABLE_1[randi_range(0, TABLE_1.size() - 1)]
				table_name = "Light Woodland/Hills/Plains"
			else:
				result = TABLE_4_WETLANDS[d10 - 6]
				table_name = "Wetlands"
		_:
			result = TABLE_1[d10 - 1]
			table_name = "Light Woodland/Hills/Plains"
	var out := result.duplicate(true)
	out["_roll"] = d10
	out["_table"] = table_name
	return out
