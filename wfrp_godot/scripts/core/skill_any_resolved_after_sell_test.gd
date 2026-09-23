extends RefCounted
class_name SkillAnyResolvedAfterSellTest
## Real, confirmed bug report ("using the cheat button, selling a skill
## to 0 advances removes it from the skill list" — reported specifically
## for Ride (Any), a learnable skill of the character's current career):
## once an "(Any)" qualifier slot (e.g. "Ride (Any)") is resolved to a
## specific skill (e.g. "Ride (Horse)"), the ONLY place that choice was
## ever remembered was skill_advances having a nonzero entry for "Ride
## (Horse)". Selling that skill's very last advance erases its
## skill_advances entry entirely — the same as selling any skill — which
## made Advancement.find_all_chosen_skill_variants() forget the choice
## was ever made. The resolved row vanished from the Skills tab
## entirely, AND the slot didn't reopen either (skill_any_purchases
## still correctly counts it as spent), so the skill just disappeared
## with no way to see, rebuy, or even re-pick it.
##
## Fixed by Character.skill_any_resolved — a permanent record of every
## display name an "(Any)" slot has ever been resolved to, independent
## of skill_advances/the current advance count — which
## find_chosen_skill_variant()/find_all_chosen_skill_variants() now
## check alongside skill_advances.has(). This test covers both the
## Advancement layer directly and the real Character Menu screen,
## reproducing the exact reported case: Entertainer's own Tier 2 grants
## "Ride (Any)", resolved here to "Horse" — same skill/qualifier named
## in the bug report.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var entertainer: CareerDefinition = load("res://data/careers/entertainer.tres")
	var ride_def: SkillDefinition = GameData.skill_db.find_by_name("Ride")
	checks.append(["Setup: Entertainer career and Ride skill definition both loaded", entertainer != null and ride_def != null])
	if entertainer == null or ride_def == null:
		print("FAIL  Setup: Entertainer career and Ride skill definition both loaded")
		print("RESULT (Skill (Any) Survives Selling To 0): SOME FAILED")
		return false

	## --- Advancement-layer repro: resolve Ride (Any) -> Ride (Horse), --------
	## sell its only advance back to 0, confirm the choice is still
	## remembered (not forgotten) by the lookup helpers the UI relies on.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.career = entertainer
	pc.current_tier = 2
	pc.experience_total = 10000
	pc.experience_spent = 0

	checks.append(["Ride (Any) not yet resolved: find_chosen_skill_variant() returns empty", Advancement.find_chosen_skill_variant(pc, "Ride (Any)") == ""])

	var buy_result: Advancement.PurchaseResult = Advancement.purchase_skill_advance(pc, ride_def, "Horse", false, "Ride (Any)")
	checks.append(["Buying Ride (Horse) through the Ride (Any) slot succeeds", buy_result.success])
	checks.append(["Ride (Horse) now has exactly 1 advance", int(pc.skill_advances.get("Ride (Horse)", 0)) == 1])
	checks.append(["skill_any_resolved records \"Ride (Horse)\" as this slot's resolved choice", pc.skill_any_resolved.has("Ride (Horse)")])

	var sell_result: Advancement.PurchaseResult = Advancement.sell_skill_advance(pc, ride_def, "Horse")
	checks.append(["Selling Ride (Horse)'s only advance succeeds", sell_result.success])
	checks.append(["Ride (Horse) is genuinely back to 0 -- no longer a key in skill_advances at all", not pc.skill_advances.has("Ride (Horse)")])

	## The real bug: these two lookups used to return "" / [] the moment
	## skill_advances lost its entry, which is exactly what made the row
	## disappear from the Skills tab.
	checks.append(["Real bug fix: find_chosen_skill_variant() STILL reports \"Ride (Horse)\" after selling to 0", Advancement.find_chosen_skill_variant(pc, "Ride (Any)") == "Ride (Horse)"])
	var all_chosen: Array[String] = Advancement.find_all_chosen_skill_variants(pc, "Ride (Any)")
	checks.append(["Real bug fix: find_all_chosen_skill_variants() STILL includes \"Ride (Horse)\" after selling to 0", all_chosen.has("Ride (Horse)")])

	## The slot itself must stay spent (not reopen as a fresh pick) --
	## unchanged from before this fix, since skill_any_purchases already
	## handled that correctly and this fix doesn't touch it.
	checks.append(["The slot still counts as spent (skill_any_purchases unaffected by the sell)", int(pc.skill_any_purchases.get("Ride (Any)", 0)) == 1])

	## Re-buying the first advance back should work cleanly too -- the
	## remembered choice isn't a dead end, just a 0-advance row exactly
	## like any other known-but-untrained skill.
	var rebuy_result: Advancement.PurchaseResult = Advancement.purchase_skill_advance(pc, ride_def, "Horse")
	checks.append(["Re-buying Ride (Horse)'s first advance back (as an ordinary, already-in-scope skill) succeeds", rebuy_result.success])
	checks.append(["Ride (Horse) is back to 1 advance", int(pc.skill_advances.get("Ride (Horse)", 0)) == 1])

	## --- Screen-level check: the real Character Menu, real Sell button. -----
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc2: Character = GameState.player_character
	pc2.career = entertainer
	pc2.current_tier = 2
	pc2.experience_total = 10000
	pc2.experience_spent = 0

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	## Per a documented pre-existing test-harness timing quirk (see
	## encounter_time_advance_v0.3.47's own note on SocialCombatScreenTest
	## hitting the same thing): add_child() as the very first thing in a
	## fresh scene tree, with no frame processed yet, can fail with
	## "Parent node is busy setting up children". This is the very first
	## screen touched in this test file, so it needs the same one-frame
	## wait first; nothing later in this file (or in the data-layer
	## checks above, which never touch a scene tree) needs it.
	await tree.process_frame
	tree.get_root().add_child(menu)
	menu.open()
	await tree.process_frame

	var skills_box: VBoxContainer = menu.get_node("%SkillsBox")

	var find_any_picker := func(qualifier_prefix: String) -> Array:
		for row in _skills_grid_rows(skills_box):
			if (row["name"] as String).begins_with(qualifier_prefix) and row["picker"] != null:
				return [row["picker"], row["buy_btn"]]
		return [null, null]

	var picker_pair: Array = find_any_picker.call("Ride (Any)")
	var picker: OptionButton = picker_pair[0]
	var buy_btn: Button = picker_pair[1]
	checks.append(["Screen check: found the Ride (Any) picker row", picker != null])

	if picker != null:
		var horse_idx := -1
		for i in range(picker.item_count):
			if picker.get_item_text(i) == "Horse":
				horse_idx = i
		checks.append(["Screen check: \"Horse\" is offered as a choice", horse_idx != -1])
		if horse_idx != -1:
			picker.select(horse_idx)
			picker.item_selected.emit(horse_idx)
			await tree.process_frame
			buy_btn.pressed.emit()
			await tree.process_frame

			var find_resolved_row := func() -> Dictionary:
				for row in _skills_grid_rows(skills_box):
					if (row["name"] as String) == "Ride (Horse)":
						return row
				return {}

			var resolved_row: Dictionary = find_resolved_row.call()
			checks.append(["Screen check: \"Ride (Horse)\" shows as its own resolved row after buying", not resolved_row.is_empty()])

			if not resolved_row.is_empty() and resolved_row.get("sell_btn") != null:
				var sell_btn: Button = resolved_row["sell_btn"]
				sell_btn.pressed.emit()
				await tree.process_frame

				checks.append(["Screen check: Ride (Horse) is genuinely back to 0 advances", int(pc2.skill_advances.get("Ride (Horse)", 0)) == 0])

				var row_after_sell: Dictionary = find_resolved_row.call()
				checks.append(["Real bug fix, real screen: \"Ride (Horse)\" row is STILL PRESENT after selling its only advance to 0 -- it does not disappear", not row_after_sell.is_empty()])
			else:
				checks.append(["Screen check: found the resolved row's own Sell button to press", false])

	menu.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Skill (Any) Survives Selling To 0): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass

## Mirrors SkillAnyDedupTest's own grid walker (see its comment there for
## the full rationale on the grid shape) -- kept as a self-contained copy
## here rather than a cross-test-file call, matching this project's
## convention of each test file being independently runnable.
static func _find_all_grids(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is GridContainer:
			found.append(child)
		found.append_array(_find_all_grids(child))
	return found

static func _skills_grid_rows(skills_box: VBoxContainer) -> Array:
	var rows: Array = []
	for grid in _find_all_grids(skills_box):
		var cols: int = (grid as GridContainer).columns
		var cells := (grid as GridContainer).get_children()
		var i := cols
		while i + cols <= cells.size():
			var name_cell: PanelContainer = cells[i + 1]
			var value_cell: PanelContainer = cells[i + 2]
			var actions_cell: PanelContainer = cells[i + 4]

			var name_text := ""
			var name_inner: Control = name_cell.get_child(0) if name_cell.get_child_count() > 0 else null
			if name_inner is Label:
				name_text = (name_inner as Label).text
			elif name_inner is HBoxContainer:
				for c in name_inner.get_children():
					if c is Label:
						name_text = (c as Label).text

			var picker: OptionButton = null
			var value_inner: Control = value_cell.get_child(0) if value_cell.get_child_count() > 0 else null
			if value_inner is OptionButton:
				picker = value_inner

			var buy_btn: Button = null
			var sell_btn: Button = null
			var actions_inner: Control = actions_cell.get_child(0) if actions_cell.get_child_count() > 0 else null
			if actions_inner is HBoxContainer:
				for c in actions_inner.get_children():
					if c is Button:
						var b: Button = c
						if b.text.begins_with("Sell"):
							sell_btn = b
						else:
							buy_btn = b

			rows.append({"name": name_text, "picker": picker, "buy_btn": buy_btn, "sell_btn": sell_btn})
			i += cols
	return rows
