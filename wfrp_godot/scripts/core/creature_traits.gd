extends RefCounted
class_name CreatureTraits
## Mechanical wiring for the Creature Traits that have a clear,
## single-Character shape: stat modifiers applied once at
## monster-creation time, and natural weapon resolution used in place
## of an equipped manufactured weapon. See creature_trait_definition.gd
## for the full reference database, most of which isn't mechanically
## wired (documented, not silent).

## Applies every "stat_mod:CHARACTERISTIC:AMOUNT" and
## "stat_mod:wounds_bonus:toughness_bonus" tag from the Character's own
## creature_traits — called once by MonsterDefinition.to_character(),
## not on every stat read, since these are permanent modifiers to the
## creature's base stats (Big, Brute, Hardy, Tough, Clever, Cunning,
## Elite, Fast, Leader), not situational bonuses.
static func apply_stat_modifiers(character: Character) -> void:
	for trait_str in character.creature_traits:
		var base_name := trait_str.split(" (")[0]
		var def: CreatureTraitDefinition = GameData.creature_trait_db.find_by_name(base_name)
		if def == null:
			continue
		for tag in def.tags:
			var parts: Array = str(tag).split(":")
			if parts[0] != "stat_mod":
				continue
			if parts[1] == "wounds_bonus" and parts.size() >= 3 and parts[2] == "toughness_bonus":
				character.wounds_max += character.get_characteristic_bonus("toughness")
				character.wounds_current = character.wounds_max
			elif parts[1] == "movement":
				character.creature_movement_bonus += int(parts[2])
			else:
				var char_key: String = parts[1]
				var amount: int = int(parts[2])
				character.characteristics.set_value(char_key, character.characteristics.get_value(char_key) + amount)

## The natural weapon a creature fights with when it has no equipped
## manufactured weapon (empty equipped_weapon) — Weapon/Bite/Horns/
## Tail Attack/Tongue Attack traits, in that priority order (Weapon is
## the book's own generic "carries a melee weapon, or uses teeth,
## claws, or similar" catch-all; the others are more specific natural
## attacks). Builds an ephemeral WeaponDefinition on the fly rather
## than requiring a database entry per monster, since the Rating (and
## so the Damage) genuinely varies creature to creature.
##
## A deliberate simplification, documented rather than silent: the
## book treats Bite/Horns/Tail Attack/Tongue Attack as Free Attacks
## usable *alongside* a normal attack at the cost of Advantage, not as
## the creature's only way to fight. This project's one-action-per-turn
## monster AI doesn't model a separate Free Attack economy for
## monsters, so here they instead stand in as the creature's normal
## attack for its Turn when nothing else applies.
const NATURAL_WEAPON_PRIORITY := ["Weapon", "Bite", "Horns", "Tail Attack", "Tongue Attack"]

static func build_natural_weapon(character: Character) -> WeaponDefinition:
	for trait_base_name in NATURAL_WEAPON_PRIORITY:
		if character.has_creature_trait(trait_base_name):
			var rating := character.get_creature_trait_rating(trait_base_name)
			var w := WeaponDefinition.new()
			w.weapon_name = trait_base_name
			w.is_ranged = false
			w.skill_group = "Brawling"
			w.damage_mode = "fixed"   ## the trait's Rating already includes Strength Bonus (p.338-341)
			w.damage_flat = max(rating, 0)
			w.reach = "Personal"
			w.summary = "Natural weapon (%s Creature Trait)." % trait_base_name
			return w
	return null

## Per the follow-up request ("if a monster has an optional trait -
## Ranged Rating (Range)... every other enemy in the group should get
## this trait activated and be able to switch to an appropriate ranged
## weapon"): the book's own Ranged Creature Trait (p.338-343) genuinely
## needs TWO numbers -- a Damage Rating and a Range in yards (e.g. the
## core rulebook's own Orc entry: "Ranged+8 (50)"; Goblin: "Ranged+7
## (25)") -- unlike every other single-number trait this project already
## parses via Character.get_creature_trait_rating() (Bite (5), Armour
## (1), etc). Stored on the Character's own creature_traits (once
## activated -- see field_encounter_screen.gd's own spawn-time
## alternating activation) as "Ranged (Rating/Range)" -- e.g. "Ranged
## (8/50)" -- a dedicated slash-separated format kept deliberately
## SEPARATE from get_creature_trait_rating()'s own single-int parser
## rather than extending that shared function, so every other existing
## caller of it (Bite/Horns/Armour/etc, all genuinely single-number)
## is completely unaffected.
##
## Builds an ephemeral natural ranged WeaponDefinition the same
## on-the-fly way build_natural_weapon() above does for Bite/Horns/etc
## -- skill_group "Throwing" (no trained Ranged specialisation is
## assumed for a monster's own natural attack, matching how Javelin/
## Rock/Throwing Axe are grouped, and "Throwing" weapons need no
## tracked ammo either, per AmmoLookup's own REQUIRED_AMMO table, so
## this needs no inventory item to back it). damage_mode "fixed" since
## the trait's own Rating, like Bite/Horns, already stands as the
## complete Damage value (p.338-341) with nothing further added.
##
## Returns null if the trait isn't present, or its stored string
## doesn't parse as two valid ints -- a handful of this project's own
## monster entries (Ungor, Night Runner) still only have the OLD,
## incomplete single-number placeholder ("Ranged (7)") left over from
## before the real book values were available; rather than guessing a
## Range for those, this deliberately produces no natural ranged
## option at all until they're corrected the same way Goblin/Forest
## Goblin/Orc already have been.
static func build_natural_ranged_weapon(character: Character) -> WeaponDefinition:
	for t in character.creature_traits:
		if not t.begins_with("Ranged ("):
			continue
		if not t.ends_with(")"):
			continue
		var inner := t.substr(8, t.length() - 9)   ## strip the leading "Ranged (" and trailing ")"
		var parts := inner.split("/")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var w := WeaponDefinition.new()
		w.weapon_name = "Ranged Attack"
		w.is_ranged = true
		w.skill_group = "Throwing"
		w.damage_mode = "fixed"
		w.damage_flat = max(int(parts[0]), 0)
		w.range_yards = max(int(parts[1]), 0)
		w.summary = "Natural ranged attack (Ranged Creature Trait)."
		return w
	return null

## Per the follow-up request ("lets do something similar with the
## Spellcaster trait, add the difficulty tier bonus on top of the
## +10's"): the book's own Spellcaster (Various) Creature Trait
## (p.338-343) reads "Add the Spellcaster or Spellcaster Lord template
## or, if that wouldn't be appropriate, add Channelling (Choose a Wind)
## (WP +10) and Language (Magick) (Int +10) as if they were Basic
## Skills." This project has no Spellcaster/Spellcaster Lord template
## system, so the fallback clause is the only path wired in here — and
## per the follow-up, the flat +10 on each now also gets the current
## field's own Difficulty Tier bonus added on top
## (DifficultyTiers.get_bonus(), the same +10-per-Tier table already
## used for a monster's base Characteristics), so a tougher-area
## spellcaster monster is a genuinely more dangerous caster too, not
## just a stronger melee/ranged threat.
##
## "(Choose a Wind)" is the book's own free-form GM choice, not a fixed
## Lore — this reuses whatever Lore the Spellcaster trait's own
## qualifier already names instead of picking arbitrarily (e.g.
## "Spellcaster (Beasts)" -> "Channelling (Beasts)", "Spellcaster
## (Chaos)" -> "Channelling (Chaos)"), so the granted skill at least
## reads consistently with the creature's own casting flavour. It
## needn't be one of Channelling's own pre-registered group_options —
## that list is a UI picker for a PLAYER levelling the skill up, not a
## runtime constraint; SkillDefinition.display_name() is plain string
## formatting either way, so an unlisted Lore name (like "Chaos",
## which this project's own Channelling group_options doesn't include
## as its own separate entry) still works fine as a skill_advances key.
##
## Only ever touches a Character whose creature_traits ALREADY has an
## active "Spellcaster (...)" entry — at the time of writing that means
## Cultist, Chaos Warrior, and Bray-Shaman, the only monsters with it
## as a base trait rather than merely optional/inert. An optional-only
## listing (Gor, Necromancer, Dragon, Fimir, Vampire) is left exactly
## as before, matching this project's own long-standing "optional
## traits are GM-reference only, never auto-applied" convention — no
## alternating per-group activation scheme was requested for this
## trait the way there was for Ranged.
static func apply_spellcaster_bonus(character: Character, tier: int) -> void:
	var lore := ""
	var active := false
	for t in character.creature_traits:
		if t == "Spellcaster":
			active = true
		elif t.begins_with("Spellcaster (") and t.ends_with(")"):
			active = true
			lore = t.substr(13, t.length() - 14)   ## strip the leading "Spellcaster (" and trailing ")"
	if not active:
		return
	var bonus := 10 + DifficultyTiers.get_bonus(tier)
	var channelling_name := "Channelling (%s)" % lore if lore != "" else "Channelling"
	character.skill_advances[channelling_name] = bonus
	character.skill_advances["Language (Magick)"] = bonus
