extends Node
## Autoloaded as "GameData". Loads every data file once at startup so
## Character/TestResolver/UI can all look things up by name without each
## re-reading the filesystem.
##
## Races and Careers are loaded via explicit preload() calls, one per
## file, rather than a runtime DirAccess directory scan. This matters for
## exported builds specifically: preload() uses a constant, statically-
## known path, so Godot's export step can definitively see and bundle
## every dependency at export time. A runtime directory listing
## (DirAccess.open() + list_dir_begin()) builds its file paths dynamically
## at runtime instead, which Godot's exporter can't always resolve ahead
## of time the same way — a well-known, real cause of "works in the
## editor, breaks after export" for exactly this kind of "load every file
## in a folder" pattern.

var talent_db: TalentDatabase
var creature_trait_db: CreatureTraitDatabase
var skill_db: SkillDatabase
var weapon_db: WeaponDatabase
var armour_db: ArmourDatabase
var monster_db: MonsterDatabase
var social_encounter_db: SocialEncounterDatabase
var critical_wound_db: CriticalWoundDatabase
var spell_db: SpellDatabase
var prayer_db: PrayerDatabase
var item_db: ItemDatabase
var races: Array[RaceDefinition] = []
var careers: Array[CareerDefinition] = []

## Dungeon Encounter Screen: theme_id -> DungeonThemeDefinition, same
## "explicit load(), looked up by name" convention as every other
## database here — a plain Dictionary rather than a *Database Resource
## class since only one theme ships today (see DUNGEON_THEME_FILES).
var dungeon_themes: Dictionary = {}

## Every Dungeon theme resource file, preloaded explicitly and by name —
## see the class doc comment above for why this replaced a runtime
## directory scan.
const DUNGEON_THEME_FILES: Array[DungeonThemeDefinition] = [
	preload("res://data/dungeons/sewer_dungeon_theme.tres"),
	preload("res://data/dungeons/goblin_fort_dungeon_theme.tres"),
	preload("res://data/dungeons/cave_dungeon_theme.tres"),
]

## Every Race resource file, preloaded explicitly and by name so the
## export step can see each one statically.
const RACE_FILES: Array[RaceDefinition] = [
	preload("res://data/races/dwarf.tres"),
	preload("res://data/races/gnome.tres"),
	preload("res://data/races/halfling.tres"),
	preload("res://data/races/high_elf.tres"),
	preload("res://data/races/human.tres"),
	preload("res://data/races/ogre.tres"),
	preload("res://data/races/wood_elf.tres"),
]

## Every Career resource file, preloaded explicitly and by name — see the
## class doc comment above for why this replaced a runtime directory scan.
const CAREER_FILES: Array[CareerDefinition] = [
	preload("res://data/careers/advisor.tres"),
	preload("res://data/careers/agitator.tres"),
	preload("res://data/careers/apothecary.tres"),
	preload("res://data/careers/artisan.tres"),
	preload("res://data/careers/artist.tres"),
	preload("res://data/careers/bailiff.tres"),
	preload("res://data/careers/bawd.tres"),
	preload("res://data/careers/beggar.tres"),
	preload("res://data/careers/boatman.tres"),
	preload("res://data/careers/bounty_hunter.tres"),
	preload("res://data/careers/cavalryman.tres"),
	preload("res://data/careers/charlatan.tres"),
	preload("res://data/careers/coachman.tres"),
	preload("res://data/careers/duellist.tres"),
	preload("res://data/careers/engineer.tres"),
	preload("res://data/careers/entertainer.tres"),
	preload("res://data/careers/envoy.tres"),
	preload("res://data/careers/fence.tres"),
	preload("res://data/careers/flagellant.tres"),
	preload("res://data/careers/grave_robber.tres"),
	preload("res://data/careers/guard.tres"),
	preload("res://data/careers/hedge_witch.tres"),
	preload("res://data/careers/herbalist.tres"),
	preload("res://data/careers/huffer.tres"),
	preload("res://data/careers/hunter.tres"),
	preload("res://data/careers/investigator.tres"),
	preload("res://data/careers/knight.tres"),
	preload("res://data/careers/lawyer.tres"),
	preload("res://data/careers/merchant.tres"),
	preload("res://data/careers/messenger.tres"),
	preload("res://data/careers/miner.tres"),
	preload("res://data/careers/mystic.tres"),
	preload("res://data/careers/noble.tres"),
	preload("res://data/careers/nun.tres"),
	preload("res://data/careers/outlaw.tres"),
	preload("res://data/careers/pedlar.tres"),
	preload("res://data/careers/physician.tres"),
	preload("res://data/careers/pit_fighter.tres"),
	preload("res://data/careers/priest.tres"),
	preload("res://data/careers/protagonist.tres"),
	preload("res://data/careers/racketeer.tres"),
	preload("res://data/careers/rat_catcher.tres"),
	preload("res://data/careers/riverwarden.tres"),
	preload("res://data/careers/riverwoman.tres"),
	preload("res://data/careers/road_warden.tres"),
	preload("res://data/careers/scholar.tres"),
	preload("res://data/careers/scout.tres"),
	preload("res://data/careers/seaman.tres"),
	preload("res://data/careers/servant.tres"),
	preload("res://data/careers/slayer.tres"),
	preload("res://data/careers/smuggler.tres"),
	preload("res://data/careers/soldier.tres"),
	preload("res://data/careers/spy.tres"),
	preload("res://data/careers/stevedore.tres"),
	preload("res://data/careers/thief.tres"),
	preload("res://data/careers/townsman.tres"),
	preload("res://data/careers/villager.tres"),
	preload("res://data/careers/warden.tres"),
	preload("res://data/careers/warrior_priest.tres"),
	preload("res://data/careers/watchman.tres"),
	preload("res://data/careers/witch.tres"),
	preload("res://data/careers/witch_hunter.tres"),
	preload("res://data/careers/wizard.tres"),
	preload("res://data/careers/wrecker.tres"),
]

func _ready() -> void:
	talent_db = load("res://data/talents/core_talents.tres")
	creature_trait_db = load("res://data/creature_traits/core_creature_traits.tres")
	skill_db = load("res://data/skills/core_skills.tres")
	weapon_db = load("res://data/weapons/core_weapons.tres")
	armour_db = load("res://data/armour/core_armour.tres")
	monster_db = load("res://data/monsters/core_monsters.tres")
	social_encounter_db = load("res://data/social_encounters/core_social_encounters.tres")
	critical_wound_db = load("res://data/critical_wounds.tres")
	spell_db = load("res://data/spells/core_spells.tres")
	prayer_db = load("res://data/prayers/core_prayers.tres")
	item_db = load("res://data/items/core_items.tres")
	races = RACE_FILES.duplicate()
	careers = CAREER_FILES.duplicate()
	for theme in DUNGEON_THEME_FILES:
		dungeon_themes[theme.theme_id] = theme

func find_race(race_name: String) -> RaceDefinition:
	for r in races:
		if r.race_name == race_name:
			return r
	return null

func find_career(career_name: String) -> CareerDefinition:
	for c in careers:
		if c.career_name == career_name:
			return c
	return null
