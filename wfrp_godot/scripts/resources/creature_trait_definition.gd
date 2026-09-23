extends Resource
class_name CreatureTraitDefinition
## The Creature Traits list (p.338-343), checked against the book rather
## than reconstructed — these are the monster/NPC-only equivalent of
## Talents, covering everything from natural weapons (Bite, Horns, Tail
## Attack, Weapon) to stat modifiers (Big, Brute, Hardy, Tough, Armour)
## to combat-affecting behaviour (Bestial, Frenzy, Stupid, Territorial,
## Fear, Terror). Never granted to player Characters — see
## Character.creature_traits, a separate list from talents_taken.

@export var trait_name: String = ""
@export var summary: String = ""
## Machine-readable hooks this project actually wires up mechanically
## (natural weapon damage, stat modifiers, AI behaviour) — see
## CreatureTraits.apply_stat_modifiers() and the AI checks in
## field_encounter_screen.gd. Traits without a clear single-Character
## mechanical shape (Swarm, Vomit, Petrifying Gaze, and similar) are
## included in the database for reference/flavour but have an empty
## tags list — a documented gap, not a silent omission.
@export var tags: Array[String] = []
