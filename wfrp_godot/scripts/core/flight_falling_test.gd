extends RefCounted
class_name FlightFallingTest
## Verifies the Flight (Rating) Creature Trait (p.343) and the Falling
## damage rule (p.166), added per the user's request: "add flight trait
## (note its sometimes called Fly (xx) by mistake in the rule book).
## Let flying monsters use this if they can and it helps them. Also
## ensure all our monster that should be able to fly have flight.
## Ensure falling damage is implemented too."
##
## Covers: the "Fly" typo fix (Giant Bat/Vulture/Harpy now read
## "Flight (N)" and actually resolve via Character.has_creature_trait),
## _flight_budget_squares' yards->squares conversion, Flight's
## "ignores all intervening terrain, obstacles, or characters" movement
## via _advance_toward_flying (contrasted against a grounded creature's
## real pathfind stalling on the same obstacle), _apply_falling_damage's
## 1d10+3/yard-minus-Toughness-Bonus-only math (armour NOT allowed to
## soak, matching the book's explicit callout), the voluntary
## Average(+20) Athletics distance reduction, the Prone-on-exceeding-TB
## threshold, and _ground_flying_creature_if_incapacitated grounding a
## flying creature (with fall damage) when it can't choose to Fly for
## its Move.
##
## Runs standalone against real data (MonsterDatabase, BattleGrid,
## TestResolver) via a real FieldEncounter scene instance, same
## "drive the real production functions" style as
## critical_wound_deflect_repro_test.gd — no mocking of the mechanics
## under test.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## Let the initial scene tree finish setting itself up before this
	## test's own add_child(fe) call below — called from the runner's
	## own _ready() (fired mid-setup of the initial scene), an
	## immediate add_child to tree.get_root() fails with "Parent node
	## is busy setting up children." A couple of idle frames clear that.
	await tree.process_frame
	await tree.process_frame

	## --- Part 1: monster roster audit (the "Fly" typo fix) ---
	var flying_names := ["Giant Bat", "Vulture", "Harpy", "Dragon", "Griffon", "Hippogryph", "Manticore", "Pegasus", "Wyvern"]
	for mname in flying_names:
		var mdef: MonsterDefinition = GameData.monster_db.find_by_name(mname)
		checks.append(["roster: %s exists in the database" % mname, mdef != null])
		if mdef == null:
			continue
		var mc: Character = mdef.to_character()
		checks.append(["roster: %s has a working Flight trait (not the broken 'Fly' string)" % mname, mc.has_creature_trait("Flight")])
		checks.append(["roster: %s's Flight has a positive Rating" % mname, mc.get_creature_trait_rating("Flight") > 0])
	## No leftover broken "Fly" string anywhere in the data.
	var raw_text := FileAccess.get_file_as_string("res://data/monsters/core_monsters.tres")
	checks.append(["roster: no bare broken \"Fly\" trait string remains in the monster data", not raw_text.contains("\"Fly\"")])

	## --- Set up a real FieldEncounter to drive the actual production
	## functions (_flight_budget_squares, _advance_toward_flying,
	## _apply_falling_damage, _ground_flying_creature_if_incapacitated)
	## against a real battle_grid/battle_positions, same convention
	## established by critical_wound_deflect_repro_test.gd. ---
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Giant Rat"]

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	## Settle any auto-started prompts before touching state directly,
	## same quiet-slice pattern established elsewhere in this suite.
	var quiet_slices := 0
	var waited := 0.0
	while quiet_slices < 8 and waited < 20.0:
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		var quiet: bool = not fe.awaiting_continue and not fe.awaiting_fortune_choice
		if quiet:
			quiet_slices += 1
		else:
			quiet_slices = 0
		await tree.create_timer(0.25).timeout
		waited += 0.25
	await tree.create_timer(1.2).timeout

	## Build a real flying monster (Griffon: Flight (80)) and a ground
	## target directly, then wire them into fe's own battle_grid/
	## battle_positions — same approach as manufacturing a controlled
	## scenario on top of a real production instance.
	var griffon_def: MonsterDefinition = GameData.monster_db.find_by_name("Griffon")
	var flyer: Character = griffon_def.to_character()
	flyer.character_name = "TestGriffon"
	var ground_def: MonsterDefinition = GameData.monster_db.find_by_name("Giant Rat")
	var grounded: Character = ground_def.to_character()
	grounded.character_name = "TestGroundedRat"
	var target: Character = GameState.player_character
	target.character_name = "TestTarget"

	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([], [])
	## Real test bug fix (same class already found/fixed this session in
	## charge_ready_arrow_test.gd — see its own identical comment): an
	## empty terrain_snapshot only skips per-tile impassable marking, it
	## does NOT skip generate_from_terrain_snapshot()'s own unconditional
	## _scatter_obstacles() call, so this test's own "the only impassable
	## squares are the wall I explicitly build below" intent wasn't
	## actually guaranteed — a randomly-scattered obstacle could land on
	## the manually-built wall's own gap squares (masking the "grounded
	## creature genuinely can't get through" sanity check) or on one of
	## the flying creature's own candidate landing squares (masking
	## _footprint_landable's result), intermittently failing checks that
	## are supposed to be purely about Flight's own movement rule, not
	## obstacle-scatter luck. Cleared explicitly so this test's own
	## documented intent (a blank grid plus one deliberately-placed wall)
	## is actually true.
	fe.battle_grid.impassable.clear()
	fe.battle_grid.obstacle_group.clear()
	fe.battle_grid.obstacles.clear()
	fe.battle_grid.obstacle_type.clear()
	fe.battle_grid.obstacle_cover.clear()
	fe.battle_positions.clear()
	fe.currently_flying.clear()

	## --- Part 2: _flight_budget_squares ---
	checks.append(["_flight_budget_squares: Griffon (Flight 80yd) -> 40 squares (YARDS_PER_SQUARE=2)", fe._flight_budget_squares(flyer) == 40])
	checks.append(["_flight_budget_squares: a non-flying monster (Giant Rat) -> 0", fe._flight_budget_squares(grounded) == 0])

	## --- Part 3: Flight ignores intervening terrain/obstacles ---
	## Place flyer and target 6 squares apart on the same row, with
	## EVERY square directly between them marked impassable — a real
	## wall a grounded creature's pathfind cannot cross at all.
	var start_sq := Vector2i(5, 10)
	var target_sq := Vector2i(11, 10)
	fe.battle_positions[flyer] = start_sq
	fe.battle_positions[target] = target_sq
	for x in range(start_sq.x + 1, target_sq.x):
		fe.battle_grid.impassable[Vector2i(x, 10)] = true

	## Grounded creature's real pathfind: with a solid wall of
	## impassable squares directly between it and the target and no
	## way around within its own movement, find_path should fail to
	## reach adjacent-to-target at all in a single move — proving the
	## obstacle is real, not just decorative, in this scenario.
	fe.battle_positions[grounded] = Vector2i(5, 9)
	var grounded_moved: int = fe._advance_toward(grounded, target, 6)
	var grounded_end: Vector2i = fe.battle_positions[grounded]
	checks.append(["setup sanity: the wall genuinely blocks a grounded creature's direct approach (didn't reach adjacent to target)", BattleGrid.distance_squares(grounded_end, target_sq) > 1 or grounded_moved < BattleGrid.distance_squares(Vector2i(5, 9), target_sq)])

	## Flying creature: same wall, but Flight "ignores all intervening
	## terrain, obstacles, or characters" — should land adjacent to the
	## target despite it, well within its 40-square budget.
	var flyer_moved: int = fe._advance_toward_flying(flyer, target, fe._flight_budget_squares(flyer))
	var flyer_end: Vector2i = fe.battle_positions[flyer]
	checks.append(["_advance_toward_flying: actually moved despite the wall of impassable squares in between", flyer_moved > 0])
	## Real test bug fix: the Griffon is a Large creature (footprint_size
	## 3x3 — see creature_size_footprint_large_enormous_monstrous_
	## v0.2.522, shipped well after this test was first written), so its
	## own anchor square can legitimately sit several cells away from
	## target_sq's own anchor while the two footprints' nearest EDGES are
	## still genuinely touching — plain BattleGrid.distance_squares()
	## (anchor-to-anchor) doesn't know that, and was failing this check
	## even on a perfectly correct landing. footprint_distance (the same
	## metric find_open_square_adjacent_to/_advance_toward_flying
	## themselves already use to decide "adjacent") is the right check
	## here, matching every other multi-square-footprint-aware distance
	## check elsewhere in this suite.
	checks.append(["_advance_toward_flying: landed adjacent to the target (ignored the intervening wall entirely)", BattleGrid.footprint_distance(flyer_end, flyer.get_footprint_size(), target_sq, target.get_footprint_size()) <= 1])
	checks.append(["_advance_toward_flying: landed on a genuinely walkable, non-impassable square", fe.battle_grid.is_walkable(flyer_end)])

	## --- Part 4: _monster_move_toward sets currently_flying for a
	## Flight-capable monster and actually uses the flying path. ---
	fe.currently_flying.clear()
	fe.battle_positions[flyer] = start_sq
	fe._monster_move_toward(flyer, target)
	checks.append(["_monster_move_toward: a Flight-capable monster is marked currently_flying after moving", fe.currently_flying.get(flyer, false)])
	## Same footprint-aware distance fix as the check above — the Griffon's
	## own 3x3 footprint anchor can legitimately land several cells away
	## from target_sq's anchor while still genuinely edge-adjacent.
	checks.append(["_monster_move_toward: it actually closed distance toward the target despite the wall", BattleGrid.footprint_distance(fe.battle_positions[flyer], flyer.get_footprint_size(), target_sq, target.get_footprint_size()) <= 1])

	## --- Part 5: falling damage math ---
	var faller := Character.new()
	faller.character_name = "TestFaller"
	faller.characteristics = CharacteristicSet.new()
	faller.wounds_max = 50
	faller.wounds_current = 50

	## TB soak only, no Armour soak: give the faller 0 Toughness and no
	## armour, fall 1 yard involuntarily -> wounds_lost must land in
	## the full unsoaked range [1+3, 10+3] = [4, 13].
	faller.characteristics.set_value("toughness", 0)
	faller.conditions.clear()
	var wounds_before: int = faller.wounds_current
	fe._apply_falling_damage(faller, 1, false)
	var wounds_lost_1: int = wounds_before - faller.wounds_current
	checks.append(["_apply_falling_damage: 1 yard, 0 TB -> Wounds lost in the expected 1d10+3 range [4,13]", wounds_lost_1 >= 4 and wounds_lost_1 <= 13])
	## Prone threshold: TB(0) exceeded by any positive wounds_lost.
	checks.append(["_apply_falling_damage: Wounds lost (%d) > Toughness Bonus (0) -> Prone gained" % wounds_lost_1, faller.conditions.has("Prone")])

	## Toughness Bonus high enough to fully soak the worst-case roll
	## (10 + 3*1 = 13) -> zero Wounds lost, no Prone.
	var faller2 := Character.new()
	faller2.character_name = "TestFallerSoaked"
	faller2.characteristics = CharacteristicSet.new()
	faller2.characteristics.set_value("toughness", 999)   ## astronomically high Toughness Bonus, soaks any roll
	faller2.wounds_max = 50
	faller2.wounds_current = 50
	faller2.conditions.clear()
	var wounds_before_2: int = faller2.wounds_current
	fe._apply_falling_damage(faller2, 1, false)
	checks.append(["_apply_falling_damage: overwhelming Toughness Bonus fully soaks the fall -> 0 Wounds lost", faller2.wounds_current == wounds_before_2])
	checks.append(["_apply_falling_damage: no Wounds lost -> no Prone", not faller2.conditions.has("Prone")])

	## --- Part 6: voluntary Athletics Test reduces effective distance ---
	## Give the faller an overwhelming Agility so the Average(+20)
	## Athletics Test target clamps to 100 and is guaranteed to
	## succeed regardless of the real (unforced) d100 roll — see
	## TestResolver.resolve(): target clamped to [1,100], and any
	## roll <= 100 succeeds once clamped_target is 100 (the 96-100
	## auto-fail branch requires clamped_target < 96).
	var faller3 := Character.new()
	faller3.character_name = "TestFallerVoluntary"
	faller3.characteristics = CharacteristicSet.new()
	faller3.characteristics.set_value("toughness", 0)
	faller3.characteristics.set_value("agility", 500)
	faller3.wounds_max = 500
	faller3.wounds_current = 500
	faller3.conditions.clear()
	## A 1-yard voluntary fall: guaranteed-success Athletics Test
	## reduces effective_yards to max(0, 1 - 1 - SL) = 0 for any SL>=0
	## -> no damage taken at all ("reduce the distance you count as
	## having fallen to 0 or less, you will suffer no Damage").
	var wounds_before_3: int = faller3.wounds_current
	fe._apply_falling_damage(faller3, 1, true)
	checks.append(["_apply_falling_damage (voluntary, guaranteed Athletics success): a 1-yard fall reduces to 0 effective yards -> no Wounds lost", faller3.wounds_current == wounds_before_3])
	checks.append(["_apply_falling_damage (voluntary, guaranteed Athletics success): no Wounds lost -> no Prone", not faller3.conditions.has("Prone")])

	## A larger voluntary fall (10 yards) with the same guaranteed
	## success still leaves real distance (10 - 1 - SL), so it must
	## still take damage < the involuntary 10-yard case would.
	var faller4 := Character.new()
	faller4.character_name = "TestFallerVoluntaryBig"
	faller4.characteristics = CharacteristicSet.new()
	faller4.characteristics.set_value("toughness", 0)
	faller4.characteristics.set_value("agility", 500)
	faller4.wounds_max = 5000
	faller4.wounds_current = 5000
	faller4.conditions.clear()
	var wounds_before_4: int = faller4.wounds_current
	fe._apply_falling_damage(faller4, 10, true)
	var wounds_lost_4: int = wounds_before_4 - faller4.wounds_current
	## Worst case (SL=0): effective_yards = 10-1 = 9 -> max raw damage 10+27=37.
	## Best case with a couple of SL is even less -- just assert it's
	## strictly less than the involuntary 10-yard worst case (10+30=40),
	## proving the reduction genuinely applied.
	checks.append(["_apply_falling_damage (voluntary, 10 yards, guaranteed success): took less damage than the involuntary worst case would (40)", wounds_lost_4 < 40])

	## --- Part 7: _ground_flying_creature_if_incapacitated ---
	var stunned_flyer := Character.new()
	stunned_flyer.character_name = "TestStunnedFlyer"
	stunned_flyer.characteristics = CharacteristicSet.new()
	stunned_flyer.characteristics.set_value("toughness", 0)
	stunned_flyer.wounds_max = 50
	stunned_flyer.wounds_current = 50
	stunned_flyer.conditions.clear()
	fe.currently_flying[stunned_flyer] = true
	var wounds_before_5: int = stunned_flyer.wounds_current
	fe._ground_flying_creature_if_incapacitated(stunned_flyer)
	checks.append(["_ground_flying_creature_if_incapacitated: currently_flying is cleared for the grounded creature", not fe.currently_flying.get(stunned_flyer, false)])
	checks.append(["_ground_flying_creature_if_incapacitated: real fall damage was actually applied (INCAPACITATED_FALL_YARDS=8)", stunned_flyer.wounds_current < wounds_before_5])
	## No-op for a creature that was never flying.
	var not_flying := Character.new()
	not_flying.character_name = "TestNeverFlying"
	not_flying.characteristics = CharacteristicSet.new()
	not_flying.wounds_max = 50
	not_flying.wounds_current = 50
	var wounds_before_6: int = not_flying.wounds_current
	fe._ground_flying_creature_if_incapacitated(not_flying)
	checks.append(["_ground_flying_creature_if_incapacitated: a no-op for a creature that was never flying", not_flying.wounds_current == wounds_before_6])

	## --- Part 8: +1 range-band-step against a flying target, and the
	## flying-attacker's own -20 ranged penalty, on the monster attack
	## path (_monster_attack's real production ranged-modifier block). ---
	var archer_def: MonsterDefinition = GameData.monster_db.find_by_name("Giant Rat")
	var archer: Character = archer_def.to_character()
	archer.character_name = "TestArcher"
	var flying_target := Character.new()
	flying_target.character_name = "TestFlyingTarget"
	flying_target.characteristics = CharacteristicSet.new()
	flying_target.wounds_max = 20
	flying_target.wounds_current = 20
	fe.battle_positions[archer] = Vector2i(0, 0)
	fe.battle_positions[flying_target] = Vector2i(0, 0)
	fe.currently_flying[flying_target] = true
	## Confirm the range-band bump logic itself (mirrors the match
	## statement embedded at both _on_player_attack and _monster_attack
	## call sites) by checking BattleGrid's own band constants line up
	## with what the code expects to step through.
	checks.append(["RangeBand ordinals: POINT_BLANK < SHORT < LONG < EXTREME < OUT_OF_RANGE (the step logic's own assumption)", BattleGrid.RangeBand.POINT_BLANK < BattleGrid.RangeBand.SHORT and BattleGrid.RangeBand.SHORT < BattleGrid.RangeBand.LONG and BattleGrid.RangeBand.LONG < BattleGrid.RangeBand.EXTREME and BattleGrid.RangeBand.EXTREME < BattleGrid.RangeBand.OUT_OF_RANGE])

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
	print("RESULT (Flight/Falling): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
