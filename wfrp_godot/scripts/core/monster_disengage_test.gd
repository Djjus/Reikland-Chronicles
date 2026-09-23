extends RefCounted
class_name MonsterDisengageTest
## Per the request ("enemy should suffer the same penalty from
## disengaging as player, and they should not consider doing it unless
## they desperately want to change target for a good reason"):
##
## Case 1 confirms a monster with no strong reason to abandon two
## already-engaged allies for a healthy, distant, locked target
## reconsiders and redirects onto one of the allies already in its
## face instead of walking away — and that walking away never happens
## in that case (no movement, no Flee free-attack notice logged).
##
## Case 2 confirms that when the distant target genuinely IS worth it
## (near death — a real "desperately want to" reason), the monster
## does go through with abandoning its engaged allies to chase it, and
## pays the same Flee free attack (Up in Arms p.140) the player already
## pays for the same move, from every ally it walked away from.

## Real bug fix (found while re-verifying this test against the
## Engagement/Outnumbering rework, unrelated to that rework itself): a
## history entry's actual text lives in `entry["segments"]` (a list of
## `{"kind": "notice"/"cards", "text": ...}` dicts, see
## field_encounter_screen.gd's own _build_segments), not a flat
## `entry["notice"]` key — that flat-key schema predates a later refactor
## and was never updated here. Before this fix, `h.get("notice", "")`
## silently always returned "" (never found, no error), which happened to
## still pass Case 1 (which only asserts a notice is ABSENT) but made
## Case 2's real notice count permanently read as zero regardless of
## what actually happened in the fight.
static func _history_notice_text(h: Dictionary) -> String:
	var out := ""
	for seg in h.get("segments", []):
		if seg.get("kind", "") == "notice":
			out += String(seg.get("text", ""))
	return out

static func run_test(fe) -> bool:
	var checks: Array = []

	## Flakiness fix: pin Dice's own RNG stream to a fixed, verified seed
	## (per dice.gd's own doc comment: "swap the RNG's seed in tests") so
	## every roll this test's free attacks/hit checks depend on is fully
	## reproducible. Also reseeds Godot's own global RNG (the bare
	## randf()/randi() calls field_encounter_screen.gd uses elsewhere,
	## which Dice.rng does NOT cover) for the same run-order-independence
	## reason.
	Dice.rng.seed = 2
	seed(2)

	## A fresh, fully reset _start_encounter() first, exactly like
	## LastEnemyFlowTest's own setup -- whatever random encounter
	## _ready() may have already auto-started on this instance is
	## superseded by this deliberate one (monsters.clear(),
	## battle_over = false, history.clear(), etc. all reset), and
	## everything relevant is then overwritten below anyway with this
	## test's own controlled characters/positions.
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")

	## Kept as a stable local reference throughout this test -- `fe.player`
	## itself is a shared field the shipped fix now deliberately
	## reassigns mid-flow (see _resolve_monster_free_attack's own
	## `player = ally` line, for loot attribution), so re-reading
	## `fe.player` after triggering a free attack no longer reliably
	## points at this same character.
	var test_player := CharacterCreator.create_character("DisengageTestPlayer", human, soldier, {})
	fe.player = test_player
	var ally_b := CharacterCreator.create_character("DisengageTestAllyB", human, soldier, {})
	var ally_c := CharacterCreator.create_character("DisengageTestAllyC", human, soldier, {})
	for a in [test_player, ally_b, ally_c]:
		a.equipped_weapon = "Sword"
		a.allegiance = "ally"
		## Pinned identical (rather than left to random character-creation
		## rolls) so Case 1's three candidate targets are genuinely
		## equally attractive by _monster_target_weight, and the only
		## thing that ever varies between them is what each Case
		## deliberately sets (Wounds) — a random Toughness roll could
		## otherwise flake this test by making one candidate look more
		## attractive than intended, in either direction.
		a.characteristics.set_value("toughness", 40)
		a.characteristics.set_value("weapon_skill", 50)
		a.wounds_current = a.wounds_max

	var goblin_def: MonsterDefinition = GameData.monster_db.find_by_name("Goblin")
	var goblin: Character = goblin_def.to_character()
	## Pinned well above the Goblin's own real Wounds -- Case 2 below
	## deliberately provokes TWO unopposed, +20-to-hit free attacks
	## against it (Up in Arms p.140: "+1 Advantage if hit", on top of
	## the flat "+1 Advantage" every free attack grants regardless), and
	## the test needs to reliably see both actually land rather than
	## flakily depending on whether the genuine Goblin stat block
	## happens to survive the first one.
	goblin.wounds_max = 200
	goblin.wounds_current = 200
	## Pinned high Intelligence -> smart_factor pinned at its max (1.0),
	## which gives _monster_should_pursue_new_target its LOWEST
	## required_ratio (1.5x) -- the hardest case for Case 1 (even a
	## sharp creature should still decline) and the easiest case for
	## Case 2 (a sharp creature should recognize a genuinely great
	## opportunity when it sees one).
	goblin.characteristics.set_value("intelligence", 80)
	## Pinned movement so the test doesn't depend on the Goblin's own
	## stat block -- just needs to be enough to close some real
	## distance across a couple of turns' worth of checks below.
	goblin.monster_movement = 6

	var monsters_arr: Array[Character] = [goblin]
	fe.monsters = monsters_arr
	fe.monster_defs[goblin] = goblin_def
	var sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	fe.weapons[test_player] = sword
	fe.weapons[ally_b] = sword
	fe.weapons[ally_c] = sword
	var goblin_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(goblin_def.weapon_name)
	fe.weapons[goblin] = goblin_weapon if goblin_weapon != null else sword

	fe.encounter = CombatEncounter.new()
	fe.encounter.add_combatant(test_player)
	fe.encounter.add_combatant(ally_b)
	fe.encounter.add_combatant(ally_c)
	fe.encounter.add_combatant(goblin)
	## get_living() (used by _monster_engaged_allies/_choose_monster_target
	## and everything downstream of them) reads from turn_order, not
	## combatants directly -- has to be rolled at least once or every
	## "living allies" query above comes back empty.
	fe.encounter.roll_initiative()
	## Real bug fix (Engagement/Outnumbering rework): Engaged now requires
	## an actual landed/received melee hit, not mere adjacency (see
	## CombatEncounter.mark_melee_engaged/is_engaged_with) -- this test's
	## whole premise is a goblin ALREADY embroiled in melee with two
	## allies weighing whether to break off, so that premise now has to be
	## established explicitly rather than falling out of battle_positions
	## adjacency alone. Without this, _monster_engaged_allies would see
	## nobody as genuinely Engaged and the Flee free-attack checks below
	## (Case 2) would never fire.
	fe.encounter.mark_melee_engaged(goblin, test_player)
	fe.encounter.mark_melee_engaged(goblin, ally_b)

	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([])   ## fully open grid
	fe.battle_over = false
	fe.melee_has_begun = true
	fe.movement_remaining = 0
	fe.awaiting_player_target = false
	fe.awaiting_continue = false
	fe.pending_defense.clear()

	## --- Case 1: no good reason -- should redirect, not disengage ---
	fe.history.clear()
	fe.battle_positions.clear()
	fe.battle_positions[goblin] = Vector2i(15, 9)
	fe.battle_positions[test_player] = Vector2i(15, 10)   ## adjacent to goblin
	fe.battle_positions[ally_b] = Vector2i(16, 9)        ## adjacent to goblin
	fe.battle_positions[ally_c] = Vector2i(1, 1)         ## far away, but LOCKED as goblin's target below
	fe.monster_focus_target.clear()
	fe.monster_focus_target[goblin] = ally_c
	var start_pos_1: Vector2i = fe.battle_positions[goblin]

	await fe._monster_attack(goblin)
	for i in range(5):
		await fe.get_tree().process_frame

	checks.append(["Case 1: goblin's target is redirected away from the healthy, distant, locked target onto whoever's already engaging it", fe.monster_focus_target.get(goblin) != ally_c])
	checks.append(["Case 1: the redirected target is genuinely one of the two allies already adjacent to it", fe.monster_focus_target.get(goblin) == test_player or fe.monster_focus_target.get(goblin) == ally_b])
	## Defensive .has() guard (real crash once observed here: "Invalid
	## access to property or key" when battle_positions no longer had
	## goblin as a key) -- turns any future recurrence into a clean,
	## reported FAIL instead of an uncaught KeyError that aborts the
	## whole regression run.
	checks.append(["Case 1: goblin genuinely did not move -- stayed put with its engaged allies instead of chasing off", fe.battle_positions.has(goblin) and fe.battle_positions[goblin] == start_pos_1])
	var case1_flee_notice := false
	for h in fe.history:
		if _history_notice_text(h).findn("breaks off from melee") != -1:
			case1_flee_notice = true
	checks.append(["Case 1: no Flee free-attack notice was logged -- redirecting means it never actually left anyone's melee range to punish", not case1_flee_notice])

	## --- Case 2: a genuinely great opportunity -- should go for it, and pay the price ---
	fe.history.clear()
	fe.battle_positions.clear()
	fe.battle_positions[goblin] = Vector2i(15, 9)
	fe.battle_positions[test_player] = Vector2i(15, 10)
	fe.battle_positions[ally_b] = Vector2i(16, 9)
	fe.battle_positions[ally_c] = Vector2i(1, 1)
	test_player.wounds_current = test_player.wounds_max
	ally_b.wounds_current = ally_b.wounds_max
	ally_c.wounds_current = max(1, int(ally_c.wounds_max * 0.05))   ## near death -- an irresistible target
	fe.monster_focus_target.clear()
	fe.monster_focus_target[goblin] = ally_c
	fe.pending_defense.clear()
	fe.awaiting_player_target = false
	fe.awaiting_continue = false
	fe.battle_over = false
	var start_pos_2: Vector2i = fe.battle_positions[goblin]
	var start_ally_pool: int = fe.encounter.advantage_pool.get_pool("ally")

	## Fire-and-forget, like LastEnemyFlowTest's own _on_player_attack
	## call -- _monster_attack goes through a real 0.6s create_timer
	## wait and, via _resolve_monster_free_attack, real
	## awaiting_continue prompts along the way, so it can't just be
	## awaited directly from here without something clearing those
	## prompts in the meantime.
	fe._monster_attack(goblin)
	## Flakiness fix: bumped from 240 to 480 frames of real headroom —
	## this sequence chains multiple genuine 0.6s create_timer waits
	## (per free attack) plus movement/prompt-clearing, and 240 frames
	## was occasionally not enough margin under load (a real polling
	## timeout, not a wrong-outcome bug: the one observed failure showed
	## every Case 2 check failing together, i.e. the flee sequence simply
	## hadn't finished by the time the checks below ran).
	for i in range(480):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame

	checks.append(["Case 2: goblin's locked target is unchanged -- it committed to pursuing the near-death target rather than being redirected", fe.monster_focus_target.get(goblin) == ally_c])
	## Defensive .has() guard (real crash once observed here: "Invalid
	## access to property or key" when battle_positions no longer had
	## goblin as a key) -- turns any future recurrence into a clean,
	## reported FAIL instead of an uncaught KeyError that aborts the
	## whole regression run.
	var goblin_still_positioned: bool = fe.battle_positions.has(goblin)
	checks.append(["Case 2: goblin genuinely moved away from its starting square, closing on the distant target", goblin_still_positioned and fe.battle_positions[goblin] != start_pos_2])
	checks.append(["Case 2: goblin is no longer adjacent to the player -- it walked out of that melee range", goblin_still_positioned and fe.battle_grid.distance_squares(fe.battle_positions[goblin], fe.battle_positions[test_player]) > 1])
	checks.append(["Case 2: goblin is no longer adjacent to ally_b -- it walked out of that melee range too", goblin_still_positioned and fe.battle_grid.distance_squares(fe.battle_positions[goblin], fe.battle_positions[ally_b]) > 1])
	var case2_flee_notices := 0
	for h in fe.history:
		if _history_notice_text(h).findn("breaks off from melee") != -1:
			case2_flee_notices += 1
	checks.append(["Case 2: the Flee free-attack notice fired for both allies it walked away from -- the same penalty the player already pays for the same move", case2_flee_notices >= 2])
	checks.append(["Case 2: the ally Advantage Pool grew by at least the 2 unconditional +1s the Flee rule grants (one per free attack thrown, Up in Arms p.140)", fe.encounter.advantage_pool.get_pool("ally") >= start_ally_pool + 2])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Monster Disengage): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
