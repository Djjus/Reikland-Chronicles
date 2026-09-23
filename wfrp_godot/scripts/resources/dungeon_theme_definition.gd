extends Resource
class_name DungeonThemeDefinition
## Static, hand-authored per-dungeon-biome data — the Dungeon Encounter
## Screen's analogue of LocalMapDefinition, except the tile grid itself is
## never authored here (DungeonGenerator builds a fresh one at runtime
## every time). See the project doc "Dungeon Encounter Screen Spec v1"
## for the full design.

@export var theme_id: String = ""
@export var theme_name: String = ""

## Which MonsterDefinition.faction this dungeon's inhabitants belong to —
## reference/documentation only right now (every monster here is named
## explicitly below), kept for a later habitat/faction-driven random
## encounter table.
@export var monster_faction: String = ""

@export_range(0, 5) var difficulty_tier: int = 2

## Per the request: the Goblin Fort "has no roof," so its own
## exploration/combat lighting should follow the real time of day
## (GameState.get_night_darkness()) exactly like an ordinary outdoor
## Overworld encounter, rather than every other dungeon theme's fixed
## "pitch black by nature" treatment (see FieldEncounterScreen.
## _start_exploration_mode()'s own dark/pitch-black assignment). False
## (indoor/underground, always pitch black) is the correct default for
## every existing theme (Sewer, Cave) — only an open-air/roofless theme
## should ever set this true.
@export var is_outdoor: bool = false

## Single-character tile keys, same convention as Overworld's own
## TILE_ATLAS — kept per-theme (not shared globally) since a future
## theme (crypt, cave) needs completely different art under the same
## grid-generation code.
@export var wall_char: String = "#"
@export var floor_char: String = "."
@export var door_closed_char: String = "D"
@export var door_open_char: String = "O"
@export var entrance_char: String = "E"

## char -> Texture2D, same shape as Overworld.TILE_ATLAS. Populated once
## the Sewer tile art exists (spec §11) — an entry missing here simply
## renders as a flat colour fallback in the meantime, same tolerance
## Overworld's own renderer already has for an unmapped char. Per the
## request ("remove the wall tiles completely" and "change Doors to a
## thick brown line" instead of a tile of their own): wall_char and the
## two door chars are deliberately NOT expected to have entries here any
## more — BattleGrid.generate_from_dungeon_grid() renders wall cells as
## plain void (no texture at all) and door cells as ordinary floor (see
## floor_textures below), with the door itself drawn as a line overlay,
## not a tile. Only floor_char (a single fallback, only actually used
## when floor_textures is empty) and entrance_char still belong here.
@export var tile_atlas: Dictionary = {}

## Real tile art pulled from the DungeonCrawl "Project Utumno" tileset
## (per the user's own explicit instruction to use their provided source
## file rather than hand-drawn placeholder art) — several floor
## variants so the ground reads as a real textured surface instead of
## one tile repeated everywhere. BattleGrid.generate_from_dungeon_grid()
## picks one deterministically per square (stable across re-renders —
## not re-rolled every time a door opens and the grid rebuilds) for
## every floor_char, door_closed_char, and door_open_char cell alike —
## a door is visually just floor with a line drawn across its own
## threshold, not a separate tile. Falls back to tile_atlas[floor_char]
## (a single texture) when this is empty, so older themes/tests that
## never set it keep working unchanged.
@export var floor_textures: Array[Texture2D] = []

## No longer consulted by DungeonGenerator (see that file's own v2
## header comment) — the "New Dungeon building rules" table-driven
## builder gets ALL of its randomness from explicit dice tables and
## fixed tile-module dimensions, not tunable continuous ranges/chances.
## Left in place (harmless if unread) rather than deleted, in case a
## future, differently-shaped floor wants the old random-walk generator
## back.
@export var layout: DungeonLayoutParams

## Monster Table, per the "New Dungeon building rules" request. Resolved
## by name against GameData.monster_db, same lookup every other monster
## reference in this project already uses.

## Quest room's monsters — the request's own example: 1 Rat Ogre + 1
## Stormvermin.
@export var quest_room_monster_names: Array[String] = []

## Monster Lair room's monsters — the request's own example: 4 Clanrats.
@export var monster_lair_monster_names: Array[String] = []

## Monster Patrol's monsters — the request's own example: 2 Clanrats.
## Used for BOTH the Passage Features Table's "Wandering monsters"
## outcome (spawned in the corridor itself, see
## field_encounter_screen.gd's _check_wandering_monsters()) and the
## Hazard Table's "Monster patrol" roll inside a Small+hazard room.
@export var monster_patrol_monster_names: Array[String] = []

## Chance, rolled once after the Quest room fight is won, of a bonus
## reward on top of the normal loot roll — no numeric table was given in
## the request, so this stays a flat judgment-call chance (renamed from
## the earlier boss_bonus_reward_chance now that "boss room" has been
## replaced by "Quest room").
@export_range(0.0, 1.0) var quest_bonus_reward_chance: float = 0.60
