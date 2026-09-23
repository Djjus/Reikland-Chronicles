extends RefCounted
class_name CreaturePortraits

## Looks up the full-size, transparent-background AI-generated portrait for
## a specific bestiary creature (one image per creature type, e.g. "Rat
## Ogre", "Chaos Warrior"). Follows the exact same shape as
## CareerPortraits (see that file's own header comment for the full
## background on why this whole approach exists), but for monsters instead
## of player Careers — per the request ("lets move on to the new Creature
## portraits, replace them all").
##
## Unlike CareerPortraits, the in-game creature name can NOT be turned
## into a filename by a simple lowercase-and-underscore rule, because the
## 62 source images (one per bestiary entry, humanoids framed as
## head/shoulders busts, animals/monstrous beasts framed as full-body
## dynamic action poses, all on a plain black background that's been
## removed here the same way the Career portraits' backgrounds were) came
## from filenames with their own typos and naming choices independent of
## the bestiary's own names ("Ginat Spider.jpg" for Giant Spider,
## "Bug Octopus.jpg" for Bog Octopus, "Demonette of slaanesh.jpg" for
## Daemonette of Slaanesh, and two that needed the user's own
## confirmation since they don't even resemble the bestiary name:
## "Chaos Knight.jpg" -> Chaos Warrior, "Plague Rat.jpg" -> Plague Monk).
## The processing script (which already applied the same background
## removal / crop / resize pipeline used for the Career portraits) saved
## each finished PNG under the BESTIARY name's own key instead of the
## source filename's, so this class's key derivation matches
## MONSTER_ICONS_BY_TYPE's own keys exactly (field_encounter_screen.gd) —
## see key_for() below, which also folds the one hyphenated name
## ("Bray-Shaman") the same way spaces fold, so no separate table is
## needed here either.
##
## Replaces MONSTER_ICONS_BY_TYPE / _monster_icon_for()'s old small
## procedural-silhouette sprite lookup in field_encounter_screen.gd
## (that dict's own preload() calls are gone now — see this file's own
## history for the old 24x24-supersampled-to-96x96 style those replaced).
## MONSTER_ICON (the old generic red-blob fallback) is kept as the
## last-resort path here too, for the same "never silently show nothing"
## reason, though every one of the 62 bestiary entries has real art now
## so it should never actually be hit.

const FALLBACK_PATH := "res://assets/sprites/monster.png"

static func key_for(creature_name: String) -> String:
	return creature_name.to_lower().replace(" ", "_").replace("-", "_")

static func path_for(creature_name: String) -> String:
	return "res://assets/portraits/creatures/%s.png" % key_for(creature_name)

static func get_portrait(creature_name: String) -> Texture2D:
	if creature_name == null or creature_name.is_empty():
		return null
	var path := path_for(creature_name)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## display_name may still have a numeric suffix ("Wild Boar 2") when more
## than one of the same creature is in an encounter — callers strip that
## the same way _monster_icon_for()'s own _display_name() helper always
## has, so this takes the already-stripped base name, matching
## get_portrait()'s own plain lookup-by-bestiary-name contract.
static func get_portrait_or_fallback(creature_name: String) -> Texture2D:
	var tex := get_portrait(creature_name)
	if tex == null:
		tex = load(FALLBACK_PATH) as Texture2D
	return tex
