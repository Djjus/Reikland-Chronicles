extends Resource
class_name QuestMonsterDefinition
## Per the request: a real monster-spawn override — a starting Wounds
## value and a starting Conditions set, sourced from a quest's own
## data rather than the game always spawning every monster at full
## health. Matches the source adventure this pipeline was designed
## against directly: its boss monster begins the fight already
## wounded, with several specific named injuries — not a fresh,
## undamaged spawn.

## Unique within its own quest — never shown to the player.
@export var monster_id: String = ""

## Must match a real MonsterDefinition.monster_name exactly — this
## overrides how that monster's own starting state is set up, it
## doesn't define a new monster.
@export var monster_name: String = ""

## -1 means no override — spawns at full health, same as any ordinary
## monster. Any value >= 0 sets the monster's starting Wounds
## directly (clamped to the real MonsterDefinition's own Wounds Max
## when actually applied, so a stale or mistaken override can't spawn
## something above its own real maximum).
@export var starting_wounds: int = -1

## condition_name -> stacks, applied the moment the monster is spawned.
@export var starting_conditions: Dictionary = {}

## Per the request's own healing-over-time requirement (the source
## adventure's boss heals specific named injuries at specific times):
## the quest's own timeline can reduce how wounded this monster
## currently is, via QuestTimelineEvent's heal_monster_id/
## heal_wounds_amount fields — see Character.check_quest_timelines().
## This is the base value those heals apply on top of; the monster's
## own genuinely-current wounds (after any healing that's already
## happened) are tracked in the quest's own state, not here.
