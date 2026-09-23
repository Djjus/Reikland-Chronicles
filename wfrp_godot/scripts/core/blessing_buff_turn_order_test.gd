extends RefCounted
class_name BlessingBuffTurnOrderTest
## Regression test for the follow-up request ("move blessing buff count to
## same place as the Light spell counter and show it all the time its
## active").
##
## Before this fix, an active timed buff (add_timed_buff() — Blessing
## prayers, Cordelia's Apothecary draughts, even a fumble's own Off-
## Balance penalty; see Character.active_buffs's own comment) was shown
## as a single "Active: X (Y)" line built in _render_status(), but that
## line only ever read `player.active_buffs`. Since `player` gets
## reassigned all over field_encounter_screen.gd to whoever's turn/kill is
## currently being attributed (see _resolve_monster_free_attack's own
## comment on that), a Blessing cast on a DIFFERENT party member than
## whoever `player` happened to last point to simply never showed at all
## — the bug this test's first two checks below reproduce and confirm
## fixed. The fix moved this into _render_turn_order_panel(), pinned
## alongside the Light spell's own row (same "💡 X's Light — N" shape,
## just "✨" and looping every combatant's active_buffs instead of just
## light_spell_rounds_remaining), so it's now genuinely "shown all the
## time it's active" regardless of who `player` currently points to.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "BlessTestGrimm"

	## A second party member — Blessing of Battle will be cast on THIS
	## character, not `player`, so the fix (looping every combatant in
	## turn_order rather than only reading player.active_buffs) actually
	## gets exercised.
	var ally := Character.new()
	ally.character_name = "BlessTestAes"
	ally.race = pc.race
	ally.characteristics = pc.characteristics.duplicate()
	ally.wounds_max = 10
	ally.wounds_current = 10
	if GameState.party.size() < 2:
		GameState.party.append(ally)

	GameState.current_field_difficulty_tier = 0
	GameState.dungeon_state = {}
	GameState.dungeon_floor_states = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	checks.append(["setup: FieldEncounter entered exploration mode with a live encounter", fe._exploration_mode and fe.encounter != null])
	checks.append(["setup: the party's second member is a genuine combatant in turn_order", fe.encounter != null and fe.encounter.turn_order.has(ally)])
	if not fe._exploration_mode or fe.encounter == null or not fe.encounter.turn_order.has(ally):
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Blessing Buff Turn Order): SETUP FAILED")
		return false

	## `player` rotates to whichever party member's Turn is currently
	## active (see this test's own header comment) — genuinely `pc` OR
	## `ally` depending on initiative/dice state by this point, which
	## varies run to run and isn't this test's own concern. Pinned
	## explicitly to `pc` here so the rest of this test is deterministic
	## regardless of that — the whole point is that the buffed character
	## (`ally`) is NOT `player`, which pinning guarantees outright rather
	## than hoping turn order happened to leave it that way.
	fe.player = pc
	checks.append(["setup: `player` is not the character being buffed (the actual bug condition)", fe.player != ally])

	ally.add_timed_buff("Blessing of Battle", "Sigmar", {"weapon_skill": 10}, 3)
	checks.append(["setup: the ally genuinely holds one active timed buff now", ally.active_buffs.size() == 1])

	fe._render_status()
	await tree.process_frame   ## _clear() uses queue_free(), deferred to end of frame

	var found_buff_row := false
	for child in fe.turn_order_list.get_children():
		for grandchild in child.get_children():
			if grandchild is Label and grandchild.text.begins_with("✨") and grandchild.text.contains("BlessTestAes") and grandchild.text.contains("Blessing of Battle") and grandchild.text.contains("3"):
				found_buff_row = true
	checks.append(["THE FIX: turn order panel shows a pinned \"✨ BlessTestAes's Blessing of Battle — 3\" row even though `player` points elsewhere", found_buff_row])

	checks.append(["THE FIX: the old separate \"Active:\" status line is gone (moved into the turn order panel instead)", not fe.status_label.text.contains("Active:")])

	## --- A buff on `player` themselves still shows too (not a regression
	## on the one case the old code DID handle) -----------------------
	pc.add_timed_buff("Blessing of Courage", "Sigmar", {"weapon_skill": 5}, 2)
	fe._render_status()
	await tree.process_frame
	var found_player_buff_row := false
	for child in fe.turn_order_list.get_children():
		for grandchild in child.get_children():
			if grandchild is Label and grandchild.text.begins_with("✨") and grandchild.text.contains("BlessTestGrimm") and grandchild.text.contains("Blessing of Courage") and grandchild.text.contains("2"):
				found_player_buff_row = true
	checks.append(["a buff on `player` themselves also still shows its own pinned row", found_player_buff_row])

	## --- Both rows coexist independently --------------------------------
	var buff_row_count := 0
	for child in fe.turn_order_list.get_children():
		for grandchild in child.get_children():
			if grandchild is Label and grandchild.text.begins_with("✨"):
				buff_row_count += 1
	checks.append(["two independent active buffs on two different characters both get their own row (2 total)", buff_row_count == 2])

	## --- Ticking down to expiry removes the row, same as Light's own
	## expiry behavior -----------------------------------------------
	ally.tick_active_buffs()
	ally.tick_active_buffs()
	ally.tick_active_buffs()
	checks.append(["setup: the ally's buff has genuinely expired after 3 Round ticks", ally.active_buffs.is_empty()])
	fe._render_status()
	await tree.process_frame
	var ally_row_still_present := false
	for child in fe.turn_order_list.get_children():
		for grandchild in child.get_children():
			if grandchild is Label and grandchild.text.contains("BlessTestAes") and grandchild.text.begins_with("✨"):
				ally_row_still_present = true
	checks.append(["the expired buff's row is gone from the turn order panel, same as Light's own expiry", not ally_row_still_present])

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
	print("RESULT (Blessing Buff Turn Order): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
