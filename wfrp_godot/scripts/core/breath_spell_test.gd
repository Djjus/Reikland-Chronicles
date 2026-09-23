extends RefCounted
class_name BreathSpellTest
## Real feature: correctly implement the "Breath" spell per the
## user-supplied Core Rulebook text ("this is the actual rule, it is
## not petty, its a arcane spell") — the game's own data already had
## spell_type = "Arcane" right; what was missing was any real mechanic
## at all. Breath falls into the generic is_magic_missile single-target
## branch by default (SpellDef_32: target_text = "Special", damage_flat
## = 0) — this test covers the new bespoke "Breath" branch in
## _apply_cast_spell_outcome that replaces that generic handling with
## the book's actual Breath Rating (Type) Creature Trait (p.338): a
## chosen target's line+burst area, one Ballistic Skill roll for the
## caster opposed individually by EACH struck character's own Dodge,
## Toughness Bonus Damage to everyone who fails, and — per the explicit
## follow-up request ("map each Lore to a book type", then "change
## heavens to electricity, and shadows to smoke") — a real elemental
## sub-effect keyed off the caster's own Arcane Magic Lore (see
## _breath_type_for_lore's own mapping comment for the full table).
##
## Bypasses the full _on_cast_spell() UI/Action flow entirely (same
## shortcut _offer_deathblow_chain's own test already takes) and calls
## _apply_cast_spell_outcome() directly with a synthetic always-
## successful CastResult, so every Lore/type scenario below can run
## back-to-back on one shared encounter without fighting over
## action_used_this_turn or re-instantiating the whole scene.
static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"
	## Guarantees the caster's own Ballistic Skill roll always succeeds
	## with a huge Success Level, and — combined with the low-Agility
	## targets below — always wins the opposed comparison regardless of
	## the actual d100 rolled, with no forced_roll seam needed on top of
	## resolve_characteristic_test for this.
	pc.characteristics.ballistic_skill = 200
	pc.characteristics.strength = 30   ## Strength Bonus 3 -> 3/2 = 1 square burst radius
	pc.wounds_max = 999
	pc.wounds_current = 999

	## An ally caught on the LINE between caster and target (not in the
	## burst itself) -- proves "characters between the creature and the
	## target" are struck too, not just the burst around the target, and
	## that this really can hit allies ("All characters"), not just
	## adversaries.
	var ally_line := Character.new()
	ally_line.character_name = "Fredi"
	ally_line.race = pc.race
	ally_line.characteristics = pc.characteristics.duplicate()
	ally_line.characteristics.agility = 5   ## fails its own Dodge reliably
	ally_line.wounds_max = 999
	ally_line.wounds_current = 999
	GameState.party.append(ally_line)

	GameState.pending_encounter_monster_names = ["Giant Rat", "Giant Rat", "Giant Rat", "Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	fe.player = pc
	var monsters: Array = fe.encounter.get_living("adversary")
	checks.append(["setup: four Giant Rats exist to fill target/burst/dodge/control roles", monsters.size() >= 4])
	if monsters.size() < 4:
		fe.queue_free()
		return false
	var m_target: Character = monsters[0]   ## the book's own "1 target"
	var m_burst: Character = monsters[1]    ## caught by the Strength Bonus burst around the target
	var m_dodge: Character = monsters[2]    ## also in the burst, but Dodges clear
	var m_far: Character = monsters[3]      ## nowhere near the line or burst -- must NOT be struck

	for m: Character in monsters:
		m.wounds_max = 999
		m.wounds_current = 999
	m_target.characteristics.agility = 5
	m_burst.characteristics.agility = 5
	## Deliberately huge, not just "high" -- with the attacker's own
	## Ballistic Skill target fixed at 200 above (needed so it reliably
	## BEATS the low-Agility targets too), a merely-high Dodge target
	## close to that same magnitude isn't actually a safe bet: Success
	## Levels swing with the die roll on BOTH sides of an opposed Test,
	## so two similarly-huge targets can still occasionally flip who
	## wins. Pushing this target an order of magnitude past the
	## attacker's own (no cap on a raw characteristic Test target — see
	## TestResolver.resolve()'s own comment) makes the defender's SL
	## dominate the comparison regardless of what either side rolls.
	m_dodge.characteristics.agility = 900

	fe.battle_positions[pc] = Vector2i(10, 10)
	fe.battle_positions[m_target] = Vector2i(10, 15)
	fe.battle_positions[m_burst] = Vector2i(11, 15)      ## adjacent to the target -- burst only
	fe.battle_positions[m_dodge] = Vector2i(9, 15)        ## also in the burst -- proves a genuine Dodge still saves you
	fe.battle_positions[ally_line] = Vector2i(10, 12)     ## on the direct line (10,10)->(10,15) -- line only
	fe.battle_positions[m_far] = Vector2i(25, 25)         ## nowhere near either shape

	var spell: SpellDefinition = GameData.spell_db.find_by_name("Breath")
	checks.append(["setup: 'Breath' spell data exists", spell != null])
	if spell == null:
		fe.queue_free()
		return false

	var reset_wounds := func():
		for c: Character in [m_target, m_burst, m_dodge, m_far, ally_line]:
			c.wounds_current = c.wounds_max
			c.conditions.clear()

	var do_cast := func(target: Character) -> void:
		var cast_result := MagicResolver.CastResult.new()
		cast_result.success = true
		cast_result.test_result = TestResolver.TestResult.new()
		fe._apply_cast_spell_outcome(cast_result, spell, "Breath", target, false)

	## --- Plain force (no Arcane Magic Lore talent at all) ------------------
	do_cast.call(m_target)

	checks.append(["THE FIX: the primary target (in the burst) is struck", m_target.wounds_current < 999])
	checks.append(["THE FIX: a character caught on the LINE (not the burst) is also struck", ally_line.wounds_current < 999])
	checks.append(["THE FIX: a character elsewhere in the burst is also struck", m_burst.wounds_current < 999])
	checks.append(["THE FIX: a genuine Dodge still saves a struck character", m_dodge.wounds_current == 999])
	checks.append(["THE FIX: someone nowhere near the line or burst is untouched (caster immune to its own Breath is trivial here)", m_far.wounds_current == 999])
	checks.append(["THE FIX: plain force (no Lore) applies no Condition at all", m_target.conditions.is_empty() and ally_line.conditions.is_empty()])

	reset_wounds.call()

	## --- Fire Lore -> Fire type: ignores Armour, inflicts Ablaze -----------
	pc.talents_taken.clear()
	pc.talents_taken["Arcane Magic (Fire)"] = 1
	pc.characteristics.toughness = 80   ## Toughness Bonus 8
	m_target.characteristics.toughness = 20   ## Toughness Bonus 2
	m_target.equipped_armour = ["Mail Shirt"]   ## 2 AP on Body -- real precedent (great_fires_and_firewall_lingering_hazards_test.gd) for proving "ignores Armour Points" vs. not
	do_cast.call(m_target)
	## Soak ignoring Armour = TB 2 only -> wounds = 8 - 2 = 6 (would be
	## 8 - (2+2) = 4 if Armour were NOT ignored -- the exact gap this
	## check exists to catch).
	checks.append(["THE FIX (Fire): Wounds ignore Armour Points (6, not 4)", m_target.wounds_current == m_target.wounds_max - 6])
	checks.append(["THE FIX (Fire): target gains an Ablaze Condition", m_target.conditions.get("Ablaze", 0) >= 1])

	reset_wounds.call()

	## --- Beasts Lore -> Cold type: Stunned per full 5 Wounds ----------------
	pc.talents_taken.clear()
	pc.talents_taken["Arcane Magic (Beasts)"] = 1
	pc.characteristics.toughness = 140   ## Toughness Bonus 14
	m_target.equipped_armour = []
	## Soak = TB 2 (Cold doesn't ignore Armour, but none is equipped) ->
	## wounds = 14 - 2 = 12 -> floor(12/5) = 2 Stunned stacks.
	do_cast.call(m_target)
	checks.append(["THE FIX (Cold): Stunned stacks scale with Wounds suffered (2, for 12 Wounds)", m_target.conditions.get("Stunned", 0) == 2])

	reset_wounds.call()

	## --- Metal Lore -> Corrosion type: Armour and Weapons take Damage ------
	pc.talents_taken.clear()
	pc.talents_taken["Arcane Magic (Metal)"] = 1
	pc.characteristics.toughness = 80
	m_target.equipped_weapon = "Sword"
	m_target.weapon_damage_taken.clear()
	m_target.equipped_armour = ["Mail Shirt"]
	m_target.armour_damage.clear()
	do_cast.call(m_target)
	checks.append(["THE FIX (Corrosion): the target's carried weapon suffers 1 Damage", int(m_target.weapon_damage_taken.get("Sword", 0)) >= 1])
	checks.append(["THE FIX (Corrosion): the target's worn Armour suffers 1 Damage", m_target.get_total_armour_damage("Mail Shirt") >= 1])

	reset_wounds.call()

	## --- Shadow Lore -> Smoke type: a real, if simplified, LoS-blocking
	## battlefield effect (see active_smoke_clouds' own declaration
	## comment) rather than a per-target Condition ---------------------------
	pc.talents_taken.clear()
	pc.talents_taken["Arcane Magic (Shadow)"] = 1
	pc.characteristics.toughness = 20   ## Toughness Bonus 2 -> a short, easy-to-tick-through 2-Round cloud
	do_cast.call(m_target)
	checks.append(["THE FIX (Smoke): a smoke cloud is registered", fe.active_smoke_clouds.size() == 1])
	checks.append(["THE FIX (Smoke): the target's own square is genuinely sight-blocking now", fe.battle_grid.blocks_los.has(Vector2i(10, 15))])
	fe._tick_smoke_clouds()
	checks.append(["THE FIX (Smoke): still blocking after 1 of 2 Rounds", fe.battle_grid.blocks_los.has(Vector2i(10, 15))])
	fe._tick_smoke_clouds()
	checks.append(["THE FIX (Smoke): cleared once its Toughness Bonus Rounds elapse", not fe.battle_grid.blocks_los.has(Vector2i(10, 15)) and fe.active_smoke_clouds.is_empty()])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Breath spell): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
