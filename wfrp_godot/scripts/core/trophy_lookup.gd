extends RefCounted
class_name TrophyLookup
## Extracted out of field_encounter_screen.gd's own loot generation so
## Overworld.gd can ALSO determine what trophy a given monster would
## drop, without duplicating the mapping — needed for the gather-task
## gold-marker coloring (see Overworld._spawn_ambush_marker).

## A small, documented homebrew mapping since the book has no "sell an
## animal's trophy" table (see gen_items.py's own comment on this).
## Covers every Animal-type monster currently in the bestiary.
static func pick_trophy_for(monster_name: String) -> String:
	if "Rat" in monster_name:
		return "Rat Pelt"
	elif "Boar" in monster_name:
		return "Boar Tusks"
	elif "Wolf" in monster_name:
		return "Wolf Pelt"
	elif "Bear" in monster_name:
		return "Bear Pelt"
	elif "Spider" in monster_name:
		return "Spider Fang"
	elif "Snake" in monster_name:
		return "Snake Skin"
	elif "Vulture" in monster_name:
		return "Vulture Feathers"
	elif "Cat" in monster_name:
		return "Cat Pelt"
	elif "Bat" in monster_name:
		return "Bat Wing"
	elif "Troll" in monster_name:
		return "Troll Hide"
	elif "Ogre" in monster_name:
		return "Ogre Tooth"
	elif "Giant" in monster_name and "Giant Spider" not in monster_name and "Giant Rat" not in monster_name and "Giant Bat" not in monster_name:
		return "Giant's Tooth"
	elif "Dog" in monster_name:
		return "Dog Pelt"
	elif "Goblin" in monster_name:
		return "Goblin Ear"
	return ""

## A faction-wide trophy — Greenskin, Skaven, Undead, Beastmen, and
## Cultist all have real monsters in the bestiary now; Daemon still
## has none. Beast and Human are deliberately excluded — Beast has its
## own per-species table above, and Human is covered by a defeated
## Humanoid's existing gear-and-coin loot instead.
static func pick_faction_trophy_for(faction: String) -> String:
	match faction:
		"Greenskin":
			return "Greenskin Ear"
		"Skaven":
			return "Skaven Teeth"
		"Undead":
			return "Undead Bones"
		"Daemon":
			return "Demon Heart"
		"Beastmen":
			return "Beastman Head"
		"Cultist":
			return "Cultist's Sigil"
		_:
			return ""

## The trophy a MonsterDefinition would actually drop, combining both
## tables above the same way field_encounter_screen.gd's own
## _generate_loot does. Animal always uses the per-species table.
## Humanoid/Monster try the per-faction table first (Skaven, Undead,
## Greenskin, Daemon, Beastmen all have one); if that comes back empty
## — as it does for Beast-faction Monster-type creatures like Troll
## and Giant, since Beast has no faction-wide trophy of its own, only
## the per-species one — falls back to the per-species table too,
## the same way an Animal would. A real bug this fixes: Troll and
## Giant (Monster type, Beast faction) were dropping no trophy at all
## before this fallback existed.
static func pick_trophy_for_monster(mdef: MonsterDefinition) -> String:
	if mdef.creature_type == "Animal":
		return pick_trophy_for(mdef.monster_name)
	elif mdef.creature_type == "Humanoid" or mdef.creature_type == "Monster":
		var faction_trophy := pick_faction_trophy_for(mdef.faction)
		if faction_trophy != "":
			return faction_trophy
		return pick_trophy_for(mdef.monster_name)
	return ""
