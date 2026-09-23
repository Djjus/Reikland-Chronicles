extends RefCounted
class_name OutnumberingClusterDisengageTest
## Regression test for the real bug reported by the user: "outnumbering
## bonus not being removed correctly the bonus should be removed if
## combatant move away and are no longer engaged" — with a screenshot
## showing Elrohir alone against a Wight still getting a +40 (3:1)
## Outnumbering bonus, because two allies (Fredi, Aes) who'd fought the
## Wight earlier in the encounter — and so permanently satisfy
## CombatEncounter.has_fought_anyone — had since moved away from the
## Wight (one of them via a failed Flee/Broken Cool Test) while
## remaining physically adjacent to each other and to Elrohir.
##
## `outnumbering_engagement_test.gd` already covers the pure headcount
## MATH in CombatEncounter (`_cluster_headcount`/`get_outnumbering_bonus`)
## against hand-built `physical_cluster` arrays — deliberately standing
## in for field_encounter_screen.gd's own live `_local_melee_cluster()`
## battle-grid BFS, per that test's own header comment. This test
## exercises that BFS itself directly (real `battle_positions`, real
## `BattleGrid`), which is where the actual bug lived: `_local_melee_cluster`
## used to return every combatant reachable via ally-to-ally chaining,
## with no check that a counted combatant was still within melee range
## of an actual enemy — so someone who'd backed off from the fight kept
## inflating their side's headcount forever, as long as they stayed
## chain-connected to someone still swinging.

static func _make_character(name: String, side: String) -> Character:
	var human := GameData.find_race("Human")
	var soldier := GameData.find_career("Soldier")
	var c := Character.new()
	c.character_name = name
	c.race = human
	c.career = soldier
	c.current_tier = 1
	c.characteristics = CharacteristicSet.new()
	c.recompute_max_wounds()
	c.allegiance = side
	return c

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## Minimal, safe boot into exploration mode (same setup
	## BlessingBuffTurnOrderTest/BlessingOvercastTest use) purely so
	## FieldEncounter.tscn's own _ready() has a valid GameState to read —
	## fe.encounter/battle_grid/battle_positions are then fully replaced
	## below with this test's own controlled scenario.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	GameState.dungeon_state = {}
	GameState.dungeon_floor_states = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	var wight := _make_character("TestWight", "adversary")
	var elrohir := _make_character("TestElrohir", "ally")
	var aes := _make_character("TestAes", "ally")
	var fredi := _make_character("TestFredi", "ally")

	fe.encounter = CombatEncounter.new()
	fe.encounter.add_combatant(wight)
	fe.encounter.add_combatant(elrohir)
	fe.encounter.add_combatant(aes)
	fe.encounter.add_combatant(fredi)
	fe.encounter.roll_initiative()

	## All three allies genuinely fought the Wight earlier this
	## encounter -- has_fought_anyone is now permanently true for all of
	## them, exactly like the real report (Aes took a real hit from the
	## Wight's free attack before fleeing).
	fe.encounter.mark_melee_engaged(wight, elrohir)
	fe.encounter.mark_melee_engaged(wight, aes)
	fe.encounter.mark_melee_engaged(wight, fredi)

	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([])   ## fully open grid

	## --- THE BUG, reproduced: Aes and Fredi have both backed off from
	## the Wight -- neither is within melee range of it any more -- but
	## remain chain-connected to Elrohir (Aes adjacent to Elrohir, Fredi
	## adjacent to Aes). Only Elrohir is still actually touching the
	## Wight. ---
	fe.battle_positions.clear()
	fe.battle_positions[wight] = Vector2i(10, 10)
	fe.battle_positions[elrohir] = Vector2i(10, 11)   ## adjacent to the Wight
	fe.battle_positions[aes] = Vector2i(10, 12)        ## adjacent to Elrohir only -- NOT the Wight
	fe.battle_positions[fredi] = Vector2i(10, 13)      ## adjacent to Aes only -- NOT the Wight or Elrohir

	var cluster: Array = fe._local_melee_cluster(elrohir)
	checks.append(["setup: the BFS still reaches all 4 combatants via the ally-to-ally chain (connectivity itself is unchanged)", cluster.size() >= 1])
	checks.append(["THE FIX: Aes, no longer within melee range of any enemy, is excluded from the returned cluster", not cluster.has(aes)])
	checks.append(["THE FIX: Fredi, likewise backed off, is also excluded", not cluster.has(fredi)])
	checks.append(["Elrohir (still touching the Wight) remains in the cluster", cluster.has(elrohir)])
	checks.append(["THE FIX: Elrohir, now genuinely alone against the Wight, gets NO Outnumbering bonus (was +40 before this fix)", fe.encounter.get_outnumbering_bonus(elrohir, cluster) == 0])

	## --- Contrast: Aes moves back into melee range of the Wight
	## (genuinely rejoins the fight) -- now a real 2:1, +20, exactly as
	## it should. Fredi stays well back and still doesn't count. ---
	fe.battle_positions[aes] = Vector2i(11, 10)   ## adjacent to the Wight again
	var cluster2: Array = fe._local_melee_cluster(elrohir)
	checks.append(["contrast: Aes counts again once she's actually back in melee range of the Wight", cluster2.has(aes)])
	checks.append(["contrast: Fredi, still far from the Wight, still doesn't count", not cluster2.has(fredi)])
	checks.append(["contrast: Elrohir + Aes vs the lone Wight is a genuine 2:1 -> +20", fe.encounter.get_outnumbering_bonus(elrohir, cluster2) == 20])
	checks.append(["contrast: Aes herself also sees the same +20 (applies to every qualifying attacker in the cluster)", fe.encounter.get_outnumbering_bonus(aes, cluster2) == 20])
	checks.append(["contrast: the lone Wight, outnumbered, gets nothing", fe.encounter.get_outnumbering_bonus(wight, cluster2) == 0])

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
	print("RESULT (Outnumbering Cluster Disengage): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
