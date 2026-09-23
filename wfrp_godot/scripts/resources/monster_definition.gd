extends Resource
class_name MonsterDefinition
## A lightweight creature stat block for field encounters — deliberately
## simpler than a full Character (no race/career/talent-tree), just
## enough to drop straight into CombatResolver. Builds a real Character
## instance on demand via to_character() so it works with all the
## existing combat code unchanged.

@export var monster_name: String = ""
@export var characteristics: CharacteristicSet
@export var wounds_max: int = 5
@export var movement: int = 4
@export var weapon_name: String = ""      ## name into GameData.weapon_db
@export var armour: Array[String] = []    ## names into GameData.armour_db
@export var talents: Array[String] = []   ## talent names it has (rank 1 each)
## Creature Traits (p.338-343) — the real monster-specific mechanic
## this project models, distinct from talents above (which are for the
## handful of cases where a monster genuinely has a player-style
## Talent, e.g. Night Vision-as-Talent equivalents already granted a
## different way). Empty weapon_name plus a "Weapon"/"Bite"/"Horns"/
## "Tail Attack" trait here means the monster fights with natural
## weapons — see field_encounter_screen.gd's natural weapon resolution.
@export var creature_traits: Array[String] = []
## Book "Optional:" traits (p.338-343 lists these separately from a
## creature's base Traits line for almost every entry) — recorded here
## as reference data only, per the request: "record the optional
## traits for each creature in the data but do not apply them yet."
## Nothing in this project reads this array mechanically yet; it's
## intentionally inert until a later pass wires it up (e.g. as a
## GM-style "harder version of this encounter" toggle).
@export var optional_creature_traits: Array[String] = []
@export var summary: String = ""
## Location-appropriate spawning, per the request: which kinds of area
## this creature makes sense in (e.g. "forest", "cave", "open",
## "ruins", "underground"). Empty means "no particular habitat" — an
## unrestricted monster still eligible everywhere else's own rules
## (Tier, monster_pool, etc.) already allow. A monster can have more
## than one — a wolf equally at home in "forest" and "open" country,
## for instance.
@export var habitat_tags: Array[String] = []
## Per the request: "Keep the Bandits and Outlaw names for player race
## enemies... add an appropriate career template on their stats." When
## true, field_encounter_screen.gd builds this monster via
## BanditGenerator (a real Character from a random eligible Race and
## the Outlaw career, scaled by the area's Difficulty Tier) instead of
## the normal to_character() stat block below — the fields above
## (characteristics, wounds_max, etc.) are unused for an entry with
## this flag set, kept populated anyway so the resource still has sane
## defaults if the flag is ever toggled off.
@export var uses_career_template: bool = false
## Per the request: some creatures (Size Large+, Demons, other very
## dangerous types) should exist in the dataset — for reference, for
## a GM to name explicitly in a themed area's own monster_pool, or for
## a future boss encounter — without ever being picked by an
## unrestricted random draw. False means "in the data, not in the
## random pool": MonsterDatabase.random_monster() and
## random_monster_for_encounter()/random_monster_from() skip it when
## building the pool from the FULL database, but still return it
## normally if a caller names it explicitly (an area's monster_pool
## listing "Dire Wolf" by name is exactly the "unless stated"
## exception) — being named IS the explicit statement.
@export var default_spawn_eligible: bool = true
## Per the request: multi-monster encounters should only ever group
## creatures from the same faction — a Clanrat and a Snotling
## wouldn't team up on a human, but a Clanrat and a Stormvermin (both
## Skaven) would. Used by field_encounter_screen.gd's monster-spawning
## loop to constrain the second (and later) monster in an encounter to
## the same faction as the first, rather than an unrelated random pick.
@export_enum("Beast", "Greenskin", "Undead", "Skaven", "Human", "Beastmen", "Cultist", "Daemon") var faction: String = "Beast"
## Loot generation (see field_encounter_screen.gd's _generate_loot):
## Animals drop food/trophies; Humanoids drop a little of their own gear
## plus Status-appropriate coin. Not every monster needs to be one or
## the other — "Monster" is for things (constructs, Daemons, etc.)
## that shouldn't sensibly drop either.
@export_enum("Animal", "Humanoid", "Monster") var creature_type: String = "Animal"
## Only meaningful for Humanoid — used to roll Status-appropriate coin
## per the Consumers' Guide's own Status/spending guidance (p.289).
@export_enum("Brass", "Silver", "Gold") var status_tier: String = "Brass"
@export var status_stars: int = 1
## Victory (Up in Arms p.133): defeating an "important" NPC grants the
## winning side +1 Advantage; a party nemesis grants +2 at the GM's
## discretion. Both default false — an ordinary field-encounter monster
## isn't "important" by the book's own framing, this is for named/boss
## threats.
@export var is_important: bool = false
@export var is_nemesis: bool = false

func to_character() -> Character:
	var c := Character.new()
	c.character_name = monster_name
	c.characteristics = characteristics.duplicate_set()
	c.wounds_max = wounds_max
	c.wounds_current = wounds_max
	c.monster_movement = movement
	c.allegiance = "adversary"
	## Per the request ("monster will normally have no fate or
	## resilience unless stated"): Character's own class defaults
	## (resilience=1, resolve=1) are sane for a player character built
	## through CharacterCreator, but MonsterDefinition has no stat field
	## for either — every ordinary creature was silently inheriting
	## those player-shaped defaults instead of the book's usual "beasts
	## don't have Fate/Resilience" baseline. fate_points already
	## defaults to 0 on Character and didn't need touching; resilience/
	## resolve are zeroed here to match. A specific creature that really
	## should have some (an "important"/nemesis threat, say) is exactly
	## the "unless stated" exception — nothing here stops a later,
	## explicit override.
	c.resilience = 0
	c.resolve = 0
	c.monster_faction = faction
	c.equipped_weapon = weapon_name
	c.equipped_armour = armour.duplicate()
	c.is_important = is_important
	c.is_nemesis = is_nemesis
	c.creature_traits = creature_traits.duplicate()
	for t in talents:
		c.talents_taken[t] = 1
	CreatureTraits.apply_stat_modifiers(c)
	return c
