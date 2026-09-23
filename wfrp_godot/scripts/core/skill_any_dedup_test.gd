extends RefCounted
class_name SkillAnyDedupTest
## Per the follow-up bug report ("never show the same stat twice in the
## Characteristics/Skills/Talents submenu... this happened because the
## character entered a new class which also has Melee (Brawling)... but
## do the same thing when a Melee (Any) is chosen for a previous learned
## Melee Skill, which should be an allowed option"): confirms the
## Character Menu's Skills tab never renders the same resolved skill as
## two separate rows, that an "(Any)" qualifier's picker genuinely
## offers an already-known skill as a real choice (rather than silently
## excluding it), and that the qualifier's own remaining-slot count
## stays correct once that's allowed — real end-to-end, through the
## actual CharacterMenu scene and Advancement.purchase_skill_advance(),
## not just the underlying data.
##
## Per the follow-up request ("copy the grid format in Inventory tab to
## Characteristics and Skill subtabs"): the Skills tab no longer renders
## one HBoxContainer per row — it's a GridContainer (Career / Skill /
## Advances / Train, 4 cells per row). This test walks that grid
## directly via _skills_grid_rows() below instead of scanning
## skills_box's direct children for HBoxContainer rows.
##
## Per the further follow-up request ("split basic and advanced skills
## into separate columns side by side, each using 50% of the width"):
## there are now TWO such grids (Basic/Advanced), nested inside an
## HBoxContainer of VBoxContainer columns rather than sitting as
## %SkillsBox's own direct child — _skills_grid_rows() finds both
## (via _find_all_grids()) and returns their combined rows, so every
## check below still works regardless of which column a given skill
## actually landed in.
##
## Per the further follow-up request ("replace the current Tick boxes
## ... with one that looks just like the favourite button from the
## inventory screen... Separate stats name and values into separate
## columns"): the grid grew to 5 cells per row (Career / Skill / Value
## / Advances / Train), the Career cell now holds a plain glyph Button
## (☑/☐) instead of a CheckBox, and a resolved row's Skill cell holds
## only the bare skill name (no more "Name: Value" combined label) — so
## every prefix match below against `row["name"]` now matches the bare
## name, without a trailing ":".

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character

	## Pit Fighter's own Tier 1 skill list literally contains BOTH
	## "Melee (Any)" and "Melee (Brawling)" at once — a real, direct
	## repro of the reported bug without even needing a career change.
	var pit_fighter: CareerDefinition = load("res://data/careers/pit_fighter.tres")
	character.career = pit_fighter
	character.current_tier = 1
	character.experience_total = 100000

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child(menu)
	menu.open()
	await tree.process_frame

	var skills_box: VBoxContainer = menu.get_node("%SkillsBox")

	var count_rows := func(name: String) -> int:
		var n := 0
		for row in _skills_grid_rows(skills_box):
			if (row["name"] as String) == name:
				n += 1
		return n

	## Buy ordinary Brawling advances first — the concrete route, same
	## as any normal skill purchase, before the "(Any)" slot is ever
	## touched.
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	Advancement.purchase_skill_advance(character, skill_def, "Brawling")
	Advancement.purchase_skill_advance(character, skill_def, "Brawling")
	menu._rebuild_all()
	await tree.process_frame

	checks.append(["Melee (Brawling) shows as exactly one row before the Any slot is touched", count_rows.call("Melee (Brawling)") == 1])

	## Find the "Melee (Any) — choose one:" picker row.
	var found_picker: OptionButton = null
	var found_buy_btn: Button = null
	for row in _skills_grid_rows(skills_box):
		if (row["name"] as String).begins_with("Melee (Any)") and row["picker"] != null:
			found_picker = row["picker"]
			found_buy_btn = row["buy_btn"]

	checks.append(["The Melee (Any) picker row is still offered even though Brawling (one of its own choices) is already known", found_picker != null])
	if found_picker == null:
		var all_pass_early := true
		for chk in checks:
			print(("PASS  " if chk[1] else "FAIL  ") + chk[0])
			if not chk[1]:
				all_pass_early = false
		print("RESULT (Skill (Any) Dedup — Real Character Menu Check): ", "ALL PASS" if all_pass_early else "SOME FAILED")
		return all_pass_early

	var brawling_idx := -1
	for i in range(found_picker.item_count):
		if found_picker.get_item_text(i) == "Brawling":
			brawling_idx = i
	## Per the follow-up request: an already-known skill must remain a
	## real, selectable option for a fresh "(Any)" slot.
	checks.append(["Brawling (already known) is offered as a real choice in the Melee (Any) picker", brawling_idx != -1])

	if brawling_idx != -1:
		found_picker.select(brawling_idx)
		found_picker.item_selected.emit(brawling_idx)
		await tree.process_frame
		## The Buy button's live cost should reflect Brawling's REAL next
		## advance (its 3rd — 2 already purchased), not the 0-advance
		## rookie price a brand new skill would show.
		var expected_cost := Advancement.get_skill_advance_cost(2)
		## Per the follow-up request ("remove the word Buy, only leave the
		## XP cost"): just "%d XP" now, no "Buy" prefix.
		checks.append(["The Any-slot Buy button shows the real next-advance cost for the already-known skill, not the 0-advance price", found_buy_btn.text == "%d XP" % expected_cost])
		var xp_before := character.experience_spent
		found_buy_btn.pressed.emit()
		await tree.process_frame
		checks.append(["Buying Brawling through the Any slot actually spent XP", character.experience_spent > xp_before])
		checks.append(["skill_any_purchases recorded the spend against \"Melee (Any)\"", int(character.skill_any_purchases.get("Melee (Any)", 0)) == 1])

	## Real bug fix: still exactly one "Melee (Brawling)" row after
	## resolving the Any slot to the same already-known skill — not two.
	checks.append(["Melee (Brawling) still shows as exactly one row after the Any slot resolves to it too", count_rows.call("Melee (Brawling)") == 1])

	## Pit Fighter has exactly one "Melee (Any)" grant — once it's spent,
	## no leftover picker row should remain.
	var remaining_any_pickers := 0
	for row in _skills_grid_rows(skills_box):
		if (row["name"] as String).begins_with("Melee (Any)"):
			remaining_any_pickers += 1
	checks.append(["No leftover Melee (Any) picker row remains once the one slot is spent", remaining_any_pickers == 0])

	menu.queue_free()

	## --- Real bug fix ("Dwarf Boatman changed career to Pit Fighter,
	## after selecting Melee (any) Basic - the skill moved down to the
	## outside current Career section when it shouldnt have"): a fresh
	## character on Pit Fighter's own Tier 1 ("Pugilist") resolving its
	## "Melee (Any)" grant to "Basic" — a choice that ISN'T also
	## concretely listed at Tier 1 (only "Melee (Brawling)" is; "Melee
	## (Basic)" only appears directly at Tier 2) — exactly matches the
	## report: the resolved variant never appears literally in
	## unlocked_skills(), so it used to fall through to the read-only
	## "outside current Career" section instead of staying in the living
	## "(Any)" section where it was just bought.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pf_character: Character = GameState.player_character
	pf_character.career = pit_fighter
	pf_character.current_tier = 1
	pf_character.experience_total = 100000

	var menu2: Node = menu_scene.instantiate()
	tree.get_root().add_child(menu2)
	menu2.open()
	await tree.process_frame

	var skills_box2: VBoxContainer = menu2.get_node("%SkillsBox")
	var find_any_picker := func(qualifier_prefix: String) -> Array:
		for row in _skills_grid_rows(skills_box2):
			if (row["name"] as String).begins_with(qualifier_prefix) and row["picker"] != null:
				return [row["picker"], row["buy_btn"]]
		return [null, null]

	var picker_pair: Array = find_any_picker.call("Melee (Any)")
	var basic_picker: OptionButton = picker_pair[0]
	var basic_buy_btn: Button = picker_pair[1]
	checks.append(["Pit Fighter Tier 1: found the Melee (Any) picker", basic_picker != null])
	if basic_picker != null:
		var basic_idx := -1
		for i in range(basic_picker.item_count):
			if basic_picker.get_item_text(i) == "Basic":
				basic_idx = i
		checks.append(["\"Basic\" (not concretely listed at Tier 1, unlike Brawling) is offered as a real choice", basic_idx != -1])
		if basic_idx != -1:
			basic_picker.select(basic_idx)
			basic_picker.item_selected.emit(basic_idx)
			await tree.process_frame
			basic_buy_btn.pressed.emit()
			await tree.process_frame

			var count_rows2 := func(name: String) -> int:
				var n := 0
				for row in _skills_grid_rows(skills_box2):
					if (row["name"] as String) == name:
						n += 1
				return n
			## Per the grid redesign: a still-in-Career row's Career
			## tick button is ticked (unlocked=true) -- that's now how
			## "not outside current Career" is signalled, since the Name
			## column itself no longer carries a "(+N purchased, outside
			## current Career)" suffix (that's the Advances column now).
			checks.append(["Real bug fix: Melee (Basic) shows as a normal, still-current-Career row (no \"outside current Career\" tag)", count_rows2.call("Melee (Basic)") == 1 and not _row_is_readonly(skills_box2, "Melee (Basic)")])
			checks.append(["...and it's still genuinely buyable from here (found among the real, non-read-only rows), not stuck read-only", not _row_is_readonly(skills_box2, "Melee (Basic)")])
	menu2.queue_free()

	## --- Sweep every OTHER career's own Tier 1 "(Any)" skill grants too
	## ("make sure it doesnt happen in other careers"): for each career,
	## resolve every Tier 1 "(Any)" skill qualifier to a choice that
	## ISN'T also concretely listed at that same tier (the exact
	## condition that triggers the bug), then confirm the resolved
	## variant never lands in the read-only "outside current Career"
	## section (Career checkbox unchecked, no Buy button).
	var swept := 0
	var all_swept_ok := true
	for career in GameData.careers:
		var level1: CareerLevel = career.get_level(1)
		if level1 == null:
			continue
		for entry in level1.skills:
			if not Advancement.is_any_qualifier(entry):
				continue
			var choices: Array = Advancement.get_skill_situation_choices(entry)
			var parsed3 := Advancement.parse_skill_entry(entry)
			var skill_def3: SkillDefinition = parsed3[0]
			if skill_def3 == null or choices.is_empty():
				continue
			var pick := ""
			for c in choices:
				var candidate_display: String = skill_def3.display_name(c)
				if not level1.skills.has(candidate_display):
					pick = c
					break
			if pick == "":
				continue   ## every choice is also concretely listed here -- can't isolate the bug condition on this career/tier
			GameState.reset_world_state()
			GameState.player_character = null
			GameState.ensure_player_character()
			var sweep_char: Character = GameState.player_character
			sweep_char.career = career
			sweep_char.current_tier = 1
			sweep_char.experience_total = 100000
			Advancement.purchase_skill_advance(sweep_char, skill_def3, pick, false, entry)
			var sweep_menu: Node = menu_scene.instantiate()
			tree.get_root().add_child(sweep_menu)
			sweep_menu.open()
			await tree.process_frame
			var sweep_skills_box: VBoxContainer = sweep_menu.get_node("%SkillsBox")
			var resolved_display: String = skill_def3.display_name(pick)
			var found_outside := false
			for row in _skills_grid_rows(sweep_skills_box):
				if (row["name"] as String) == resolved_display and not row["unlocked"]:
					found_outside = true
			if found_outside:
				all_swept_ok = false
				print("FAIL  %s's Tier 1 \"%s\" resolved to \"%s\" wrongly landed in outside-current-Career" % [career.career_name, entry, resolved_display])
			swept += 1
			sweep_menu.queue_free()
	checks.append(["Swept every other career's Tier 1 (Any) skill grants (%d resolvable cases) — none wrongly landed in outside-current-Career" % swept, all_swept_ok and swept > 0])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Skill (Any) Dedup — Real Character Menu Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass

## Recursively collects every GridContainer anywhere under `root`, any
## number of levels deep. Per the follow-up "split basic and advanced
## skills into separate columns side by side" request, the Skills
## sub-tab now nests TWO grids (Basic/Advanced) inside an HBoxContainer
## of VBoxContainer columns, rather than sitting as %SkillsBox's own
## single direct GridContainer child.
static func _find_all_grids(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is GridContainer:
			found.append(child)
		found.append_array(_find_all_grids(child))
	return found

## Walks every Skills grid's own GridContainer children 5-at-a-time
## (Career / Skill / Value / Advances / Train), skipping each one's
## leading header row, and returns one Dictionary per row (across BOTH
## the Basic and Advanced columns combined, in that order) — {name,
## unlocked, picker, buy_btn, sell_btn}. Mirrors the exact cell layout
## _add_stat_grid_row()/_add_any_skill_grid_rows() build in
## character_menu_screen.gd — a normal row's Skill cell holds a plain
## Label with just the bare name; an open "(Any)" slot's Skill cell
## holds a plain Label ("<qualifier> — choose one:") while its own
## Value cell holds the OptionButton picker instead.
static func _skills_grid_rows(skills_box: VBoxContainer) -> Array:
	var rows: Array = []
	for grid in _find_all_grids(skills_box):
		var cols: int = (grid as GridContainer).columns
		var cells := (grid as GridContainer).get_children()
		var i := cols  ## skip this grid's own header row cells
		while i + cols <= cells.size():
			var career_cell: PanelContainer = cells[i]
			var name_cell: PanelContainer = cells[i + 1]
			var value_cell: PanelContainer = cells[i + 2]
			var actions_cell: PanelContainer = cells[i + 4]

			var unlocked := false
			if career_cell.get_child_count() > 0 and career_cell.get_child(0) is Button:
				unlocked = (career_cell.get_child(0) as Button).text == "☑"

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

			## Per the follow-up request ("remove the word Buy, only leave
			## the XP cost"): the Train column's own purchase button no
			## longer reads "Buy (N XP)" -- just "%d XP" (or "N/A" if
			## nothing's selectable yet) -- so it can't be matched by
			## begins_with("Buy") any more. Sell still always begins with
			## "Sell", so that's identified by its own text first; Buy is
			## whatever other Button is left in the cell.
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

			rows.append({"name": name_text, "unlocked": unlocked, "picker": picker, "buy_btn": buy_btn, "sell_btn": sell_btn})
			i += cols
	return rows

## True if the given row's name (matched by prefix) has no functioning
## Buy button next to it — i.e. it's the read-only "outside current
## Career" style presentation rather than a live, purchasable row.
static func _row_is_readonly(skills_box: VBoxContainer, name_prefix: String) -> bool:
	for row in _skills_grid_rows(skills_box):
		if (row["name"] as String).begins_with(name_prefix):
			return row["buy_btn"] == null
	return true
