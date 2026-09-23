extends RefCounted
class_name DeadMonsterRemovedFromMapTest
## Regression test for the request ("allow player to move over dead
## monsters, and when fights in a dungeon are over, remove the monsters
## from the map" -> follow-up clarification: "actually remove monster
## immediately when they die" / "still count them for loot and end of
## battle report of course"):
##
## ROOT CAUSE: a defeated monster used to stay in battle_positions
## forever (only ever erased in the one narrow Deathblow case — see its
## own "scoped to Deathblow's own move rather than a general 'remove
## every corpse' change" comment) — so BattleGrid._occupied_squares_
## excluding() (what Move-mode's reachable-squares highlight AND every
## click-to-commit check both read) kept treating a dead monster's own
## square as occupied forever, and its crossed-out token stayed drawn
## on the map indefinitely.
##
## THE FIX: _cull_dead_monsters_from_map(), called from the very top of
## _render_status() (already the established "runs after essentially
## every state-changing action" choke point), erases any adversary from
## battle_positions the instant xp_awarded_for shows its own kill has
## already been fully credited — ally corpses are deliberately left
## alone (still visible/blocking, matching the party-wipe rework's own
## "left at 0 Wounds, not removed" rule).
##
## Case 1: a monster reduced to 0 Wounds and credited via
## _check_for_kill_xp() is gone from battle_positions the instant
## _render_status() next runs.
## Case 2: its old square is genuinely walkable again immediately
## (BattleGrid._occupied_squares_excluding() no longer reports it).
## Case 3: a SECOND, still-living monster is completely unaffected —
## still present, still blocking its own square.
## Case 4: loot/XP tracking (xp_awarded_for) is untouched by the
## removal — the kill is still credited exactly once, same as before
## this fix.

static func run_test(fe) -> bool:
	var checks: Array = []

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Giant Rat", "Giant Rat"]
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	checks.append(["setup: two real monsters spawned", fe.monsters.size() >= 2])
	if fe.monsters.size() < 2:
		print("RESULT (Dead Monster Removed From Map): SETUP FAILED (need 2 monsters)")
		return false

	var doomed: Character = fe.monsters[0]
	var survivor: Character = fe.monsters[1]
	checks.append(["setup: both monsters have a real battle position", fe.battle_positions.has(doomed) and fe.battle_positions.has(survivor)])
	var doomed_square: Vector2i = fe.battle_positions.get(doomed, Vector2i(-1, -1))

	## Kill doomed directly (no need to drive a real, RNG-dependent
	## attack roll — _check_for_kill_xp() is the real, single choke
	## point every actual kill already funnels through for XP/loot/quest
	## credit, exactly the same call every real attack-resolution path
	## in this file already makes once a target's Wounds hit 0).
	doomed.wounds_current = 0
	fe._check_for_kill_xp(doomed)
	checks.append(["setup: the kill was genuinely credited (xp_awarded_for)", fe.xp_awarded_for.has(doomed)])
	checks.append(["THE FIX's own precondition: battle_positions still (briefly) has the corpse right after the kill resolves, before the next render", fe.battle_positions.has(doomed)])

	fe._render_status()
	for i in range(2):
		await fe.get_tree().process_frame

	## Case 1
	checks.append(["THE FIX: the dead monster is gone from battle_positions the instant _render_status() next runs", not fe.battle_positions.has(doomed)])

	## Case 2
	if doomed_square != Vector2i(-1, -1):
		var occupied: Dictionary = fe._occupied_squares_excluding(fe.player)
		checks.append(["THE FIX: its old square is genuinely walkable again (not in _occupied_squares_excluding)", not occupied.has(doomed_square)])

	## Case 3
	checks.append(["regression guard: the still-living second monster is completely unaffected", fe.battle_positions.has(survivor)])

	## Case 4
	checks.append(["loot/XP: the kill is still credited exactly once (xp_awarded_for still has it after the cull)", fe.xp_awarded_for.has(doomed)])
	checks.append(["loot/XP: no duplicate credit -- xp_awarded_for has doomed exactly once, not twice", fe.xp_awarded_for.count(doomed) == 1])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dead Monster Removed From Map): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
