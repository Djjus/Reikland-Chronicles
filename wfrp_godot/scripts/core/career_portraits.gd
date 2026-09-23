extends RefCounted
class_name CareerPortraits

## Looks up the full-size, transparent-background AI-generated portrait for
## a specific Career (one image per named Career, e.g. "Hunter", "Duellist").
##
## Per the follow-up request ("use the new portraits in all Icon, in and
## out of combat"): this is now the single portrait lookup used
## everywhere a party member's face shows — the Overworld/City top bar
## and party panels, the Camp/Tavern roster rows, and every in-combat
## portrait in field_encounter_screen.gd (the Attacker/Defender panel,
## the party rows, and the small turn-order icons). Those screens used to
## each keep their own copy of an 8-way career_class wound-tier icon set
## (PORTRAIT_SETS / PLAYER_PORTRAITS, 40x40 generic art swapped by HP
## percentage) — that generic art and the per-tier image swap are gone
## from all of those call sites now in favour of this one specific-Career
## portrait. The low-HP visual cue itself lives on though, as a colour
## tint rather than a swapped image — see wound_modulate() below.
## FALLBACK_PATH (the old default "healthy" icon) is still used as a
## last resort for the rare case of a character with no Career assigned
## at all (e.g. before character creation finishes).
##
## Files live at res://assets/portraits/careers/<key>.png, where <key> is
## the Career's career_name lowercased with spaces turned to underscores
## (e.g. "Bounty Hunter" -> "bounty_hunter"). This matches every Career
## name in data/careers/ with no exceptions, so no hand-maintained name
## table is needed — if a future Career is added without matching art,
## get_portrait() just returns null and callers fall back to
## FALLBACK_PATH rather than erroring or showing a blank icon.
##
## Per the request ("time to add female character option"):
## res://assets/portraits/careers_female/<key>.png holds a second,
## full 64-career set for female characters (Character.gender ==
## "female"), same key convention as the original (male) set above.
## Every existing career already has a matching file in both
## directories, but get_portrait() still falls back to the male path
## whenever a female-specific file is missing (e.g. a future new
## Career added with only one set of art ready) rather than returning
## null and losing the portrait entirely.

const FALLBACK_PATH := "res://assets/sprites/portrait_healthy.png"
const FEMALE_DIR := "res://assets/portraits/careers_female/"

static func key_for(career_name: String) -> String:
	return career_name.to_lower().replace(" ", "_")

static func path_for(career_name: String, gender: String = "male") -> String:
	if gender == "female":
		var female_path := "%s%s.png" % [FEMALE_DIR, key_for(career_name)]
		if ResourceLoader.exists(female_path):
			return female_path
	return "res://assets/portraits/careers/%s.png" % key_for(career_name)

## Returns the portrait texture for the given career_name/gender, or
## null if no matching art file exists in either set. `gender` defaults
## to "male" (the original, always-present set) so every pre-existing
## call site that doesn't pass it keeps working unchanged.
static func get_portrait(career_name: String, gender: String = "male") -> Texture2D:
	if career_name == null or career_name.is_empty():
		return null
	var path := path_for(career_name, gender)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## Convenience wrapper for the common "TextureRect showing this party
## member's face" call sites: looks up the Character's current Career
## portrait (from the male or female set per Character.gender —
## defaults to "male" for a null/empty gender, matching Character's own
## field default), falling back to the old generic default icon if the
## Character has no Career yet or no matching art exists.
static func get_portrait_for_character(character: Character) -> Texture2D:
	var tex: Texture2D = null
	if character != null and character.career != null:
		var gender: String = character.gender if character.gender == "female" else "male"
		tex = get_portrait(character.career.career_name, gender)
	if tex == null:
		tex = load(FALLBACK_PATH) as Texture2D
	return tex

## Per the follow-up request ("add a red tint at low health"): since
## there's only one portrait image per Career now (no wound-tier art to
## swap between the way the old PORTRAIT_SETS/PLAYER_PORTRAITS icons
## did), a low-HP cue is applied as a colour tint instead — multiply a
## portrait's `modulate` by this Color. Same 25/50/75% Wounds brackets
## the old four-tier art used, worst-first, ramping from a heavy red
## tint at Critical up to no tint at all above 75% Wounds.
static func wound_modulate(wounds_current: int, wounds_max: int) -> Color:
	if wounds_max <= 0:
		return Color(1, 1, 1)
	var pct: float = float(wounds_current) / float(wounds_max)
	if pct <= 0.25:
		return Color(1.0, 0.32, 0.3)
	elif pct <= 0.50:
		return Color(1.0, 0.55, 0.52)
	elif pct <= 0.75:
		return Color(1.0, 0.78, 0.76)
	else:
		return Color(1, 1, 1)

## Same as wound_modulate(), but reads the current/max Wounds straight
## off a Character (and returns no tint at all for a null Character —
## e.g. an empty map-token slot — rather than erroring).
static func wound_modulate_for_character(character: Character) -> Color:
	if character == null:
		return Color(1, 1, 1)
	return wound_modulate(character.wounds_current, character.wounds_max)
