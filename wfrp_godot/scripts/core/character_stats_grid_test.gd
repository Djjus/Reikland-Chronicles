extends RefCounted
class_name CharacterStatsGridTest
## Per the request ("lets copy the grid format in Inventory tab to
## Characteristics and Skill subtabs. make the columns: Career
## (checkboxes, tick if available in the current career),
## Characteristic/Skill (modified values), Advances (purchased), Train
## (Buy buttons)"): confirms both sub-tabs now render the same
## Inventory-style boxed GridContainer -- 4 columns, a real header row,
## a non-interactive checkbox per row reflecting Career availability,
## the live modified value, the purchased Advances count, and Buy/Sell
## in Train -- through the real CharacterMenu scene, not just the
## underlying Advancement/Character data. Also confirms a grid row's
## own Buy button genuinely purchases an advance end-to-end.
##
## Per the follow-up request ("lets move to the talents tab, and apply
## the same stats grid format again"): also covers the Talents sub-tab,
## which now renders through the same shared grid machinery (single
## full-width grid, like Characteristics — Talents has no Basic/Advanced
## split the way Skills does).
##
## Per the further follow-up bug report ("Buy text missing on
## characteristics submenu"): every Buy-button check below also asserts
## a minimum reported width, guarding against a real regression where
## clip_text was left on unconditionally while its compensating
## custom_minimum_size was only wired up for Skills' own compact mode —
## collapsing Characteristics'/Talents' Buy buttons down to empty boxes
## with no visible text at all.
##
## Per the further follow-up request ("replace the current Tick boxes
## in the Stats sub menus with one that looks just like the favourite
## button from the inventory screen, but with a tick instead of a
## star. Separate stats name and values into separate columns"): the
## grid grew from 4 to 5 columns (Career / Name / Value / Advances /
## Train), the Career cell is now a plain Button styled like the
## Inventory tab's own favourite star (☑/☐ glyph, gold-vs-grey colour
## swap) instead of a CheckBox, and what used to be one combined "Name:
## Value" label is now two separate cells. Every check below reads
## `row["name"]`/`row["value"]` separately rather than parsing a
## combined label string, and the Career-tick checks read the new
## Button's own glyph text instead of CheckBox.button_pressed.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.experience_total = 100000

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	## --- Characteristics grid ------------------------------------------
	## Per the follow-up request ("cap the Characteristics grid to 75% of
	## the window width"): the grid is now wrapped in its own
	## MarginContainer rather than sitting as %CharacteristicsBox's own
	## direct child — a direct-child search here would find nothing, so
	## this recurses the same way the Skills grids' own lookup already
	## has to (see _find_all_grids below).
	var characteristics_box: VBoxContainer = menu.get_node("%CharacteristicsBox")
	var char_grids := _find_all_grids(characteristics_box)
	var char_grid: GridContainer = char_grids[0] if not char_grids.is_empty() else null
	checks.append(["The Characteristics sub-tab renders a real GridContainer", char_grid != null])
	if char_grid != null:
		checks.append(["It has exactly 5 columns (Career / Characteristic / Value / Advances / Train)", char_grid.columns == 5])
		var header_texts := _header_texts(char_grid)
		checks.append(["Header row reads Career / Characteristic / Value / Advances / Train", header_texts == ["Career", "Characteristic", "Value", "Advances", "Train"]])

		var unlocked := Advancement.unlocked_characteristics(character)
		var locked_key := ""
		var unlocked_key := ""
		for key in CharacteristicSet.KEYS:
			if unlocked.has(key) and unlocked_key == "":
				unlocked_key = key
			if not unlocked.has(key) and locked_key == "":
				locked_key = key
		checks.append(["Test setup: the default Soldier career leaves both an unlocked AND a locked Characteristic at Tier 1 to check both row types", unlocked_key != "" and locked_key != ""])

		var rows := _grid_rows(char_grid)
		if unlocked_key != "":
			## Per the request ("full characteristic names, not WS/BS/S
			## abbreviations, in the Characteristics grid"): the grid's own
			## Name column reads from CharacteristicSet.FULL_NAMES, not
			## SHORT_NAMES (SHORT_NAMES is still correct for the compact
			## Critical Wound penalty lines elsewhere, just not this grid).
			var full_name: String = CharacteristicSet.FULL_NAMES[unlocked_key]
			var row := _find_row(rows, full_name)
			checks.append(["An unlocked Characteristic's row was found", not row.is_empty()])
			if not row.is_empty():
				checks.append(["...its Name column holds only the full name, not a combined 'Name: Value' label", row["name"] == full_name])
				checks.append(["...its Value column holds the modified value separately", (row["value"] as String) != ""])
				checks.append(["...its Career tick button is ticked (☑, like the Inventory favourite star when set)", row["unlocked"] == true])
				checks.append(["...it shows a real Buy button", row["buy_btn"] != null])
				## Per the follow-up request ("Buy text missing on
				## characteristics submenu"): a real regression where
				## clip_text was left on unconditionally while its
				## compensating custom_minimum_size was only ever applied
				## in compact mode collapsed this exact button down to an
				## empty box with no visible text. Guards against it
				## reappearing by asserting the button's own reported
				## minimum width is wide enough to actually show "Buy (N
				## XP)", not just that the button node exists.
				if row["buy_btn"] != null:
					checks.append(["...the Buy button's own text is fully intact, not clipped away (regression guard)", (row["buy_btn"] as Button).get_combined_minimum_size().x > 40])
				var expected_already: int = character.get_characteristic_advance_count(unlocked_key)
				var expected_adv_text := "+%d" % expected_already if expected_already > 0 else "0"
				checks.append(["...its Advances column matches the real purchased count (%s)" % expected_adv_text, row["advances"] == expected_adv_text])
		if locked_key != "":
			var full_name2: String = CharacteristicSet.FULL_NAMES[locked_key]
			var row2 := _find_row(rows, full_name2)
			checks.append(["A locked Characteristic's row was found", not row2.is_empty()])
			if not row2.is_empty():
				checks.append(["...its Career tick button is UNTICKED (☐, like the Inventory favourite star when unset)", row2["unlocked"] == false])
				checks.append(["...it shows NO Buy button (can't train what's not in Career)", row2["buy_btn"] == null])

	## --- Skills grid -----------------------------------------------------
	## Per the follow-up request ("split basic and advanced skills into
	## separate columns side by side, each using 50% of the width"):
	## %SkillsBox no longer holds one GridContainer directly — it's now
	## an HBoxContainer of two VBoxContainer columns ("Basic"/
	## "Advanced" headers each followed by their own GridContainer), so
	## this recurses to find both, rather than assuming a single
	## flat/direct child.
	var skills_box: VBoxContainer = menu.get_node("%SkillsBox")
	var skill_grids := _find_all_grids(skills_box)
	checks.append(["The Skills sub-tab renders exactly 2 real GridContainers (Basic + Advanced columns)", skill_grids.size() == 2])
	for g in skill_grids:
		checks.append(["Each Skills column grid has exactly 5 columns (Career / Skill / Value / Advances / Train)", (g as GridContainer).columns == 5])
		var header_texts3 := _header_texts(g)
		## Per the follow-up request ("make sure the skill submenu does not
		## scroll sideways, make it less wide if required"): the Skills
		## grid's own header row renders in compact mode ("Car"/"Val"/"Adv"
		## instead of "Career"/"Value"/"Advances") to help claw back the
		## width margin needed to avoid horizontal overflow —
		## Characteristics and Talents stay full-width and keep the full
		## header words.
		checks.append(["...and its header row reads Car / Skill / Val / Adv / Train (compact)", header_texts3 == ["Car", "Skill", "Val", "Adv", "Train"]])

	var skills_box_text := _scrape_labels(skills_box)
	checks.append(["The two Skills columns are headed 'Basic' and 'Advanced'", skills_box_text.has("Basic") and skills_box_text.has("Advanced")])

	## Per the same request: each column's own VBoxContainer (and the
	## shared HBoxContainer row above both) should genuinely split the
	## width 50/50 via SIZE_EXPAND_FILL + equal stretch ratio, not just
	## by coincidence of content width.
	var skills_columns_row: HBoxContainer = null
	for child in skills_box.get_children():
		if child is HBoxContainer:
			skills_columns_row = child
	checks.append(["The two Skills columns share one HBoxContainer row", skills_columns_row != null])
	if skills_columns_row != null:
		var column_children := skills_columns_row.get_children()
		checks.append(["...with exactly 2 column children (Basic, Advanced)", column_children.size() == 2])
		var equal_stretch := true
		for c in column_children:
			var ctrl: Control = c
			if ctrl.size_flags_horizontal != Control.SIZE_EXPAND_FILL or ctrl.size_flags_stretch_ratio != 1.0:
				equal_stretch = false
		checks.append(["...both columns use SIZE_EXPAND_FILL with an equal (1.0) stretch ratio, so they genuinely split 50/50", equal_stretch])

	var unlocked_names := Advancement.unlocked_skills(character)
	var concrete_unlocked_name := ""
	for n in unlocked_names:
		if not Advancement.is_any_qualifier(n):
			concrete_unlocked_name = n
			break
	checks.append(["Test setup: found a concretely-unlocked Skill to check", concrete_unlocked_name != ""])
	if concrete_unlocked_name != "":
		var srow := {}
		for g in skill_grids:
			var rows2 := _grid_rows(g)
			var candidate := _find_row(rows2, concrete_unlocked_name)
			if not candidate.is_empty():
				srow = candidate
		checks.append(["The unlocked Skill's row was found (in whichever of the two columns it belongs to)", not srow.is_empty()])
		if not srow.is_empty():
			checks.append(["...its Name column holds only the skill name, not a combined 'Name: Value' label", srow["name"] == concrete_unlocked_name])
			checks.append(["...its Value column holds the skill value separately", (srow["value"] as String) != ""])
			checks.append(["...its Career tick button is ticked", srow["unlocked"] == true])
			checks.append(["...it shows a real Buy button", srow["buy_btn"] != null])
			## Same regression guard as Characteristics' own Buy button
			## check, adapted for compact mode: Skills' Buy buttons
			## deliberately shorten to just "Buy" with an explicit
			## custom_minimum_size (64px) rather than the full "Buy (N
			## XP)" text, so the bar here is "at least that reserved
			## width", not "wide enough for the full sentence".
			if srow["buy_btn"] != null:
				checks.append(["...the Buy button's own compact text is genuinely visible, not clipped to empty (regression guard)", (srow["buy_btn"] as Button).get_combined_minimum_size().x >= 64])

	## --- Talents grid ------------------------------------------------------
	## Per the follow-up request ("lets move to the talents tab, and apply
	## the same stats grid format again"): Talents now renders through the
	## same boxed GridContainer as Characteristics — a single full-width
	## grid (no Basic/Advanced split, since Talents has no such
	## dichotomy), found the same simple way as char_grid above.
	var talents_box: VBoxContainer = menu.get_node("%TalentsBox")
	var talent_grid: GridContainer = null
	for child in talents_box.get_children():
		if child is GridContainer:
			talent_grid = child
	checks.append(["The Talents sub-tab renders a real GridContainer", talent_grid != null])
	var concrete_talent_name := ""
	if talent_grid != null:
		checks.append(["It has exactly 5 columns (Career / Talent / Rank / Advances / Train)", talent_grid.columns == 5])
		var header_texts4 := _header_texts(talent_grid)
		checks.append(["Header row reads Career / Talent / Rank / Advances / Train", header_texts4 == ["Career", "Talent", "Rank", "Advances", "Train"]])

		var unlocked_talent_names := Advancement.unlocked_talents(character)
		for n in unlocked_talent_names:
			if Advancement.is_any_qualifier(n):
				continue
			var td: TalentDefinition = GameData.talent_db.find_by_name(n)
			if td == null:
				continue
			if character.get_talent_rank(n) < td.get_max_rank(character):
				concrete_talent_name = n
				break
		checks.append(["Test setup: found a concretely-unlocked, still-buyable Talent to check", concrete_talent_name != ""])
		if concrete_talent_name != "":
			var trows := _grid_rows(talent_grid)
			var trow := _find_row(trows, concrete_talent_name)
			checks.append(["An unlocked Talent's row was found", not trow.is_empty()])
			if not trow.is_empty():
				checks.append(["...its Name column holds only the talent name, not a combined 'Name (rank X / Y)' label", trow["name"] == concrete_talent_name])
				checks.append(["...its Rank column holds the 'rank X / Y' text separately", (trow["value"] as String).begins_with("rank ")])
				checks.append(["...its Career tick button is ticked", trow["unlocked"] == true])
				checks.append(["...it shows a real Buy button", trow["buy_btn"] != null])
				if trow["buy_btn"] != null:
					checks.append(["...the Buy button's own text is fully intact, not clipped away (regression guard)", (trow["buy_btn"] as Button).get_combined_minimum_size().x > 40])

	## --- Buying through the grid's own Train column actually works ------
	## Per the follow-up fix: this whole section used to be able to
	## silently no-op (a stale name lookup finding no row, or no Buy
	## button on it) without ever actually failing a check — the explicit
	## "setup" checks below guarantee the real purchase-click assertion
	## further down can't quietly stop running again without being caught.
	if char_grid != null:
		var unlocked2 := Advancement.unlocked_characteristics(character)
		var buy_key := ""
		for key in CharacteristicSet.KEYS:
			if unlocked2.has(key):
				buy_key = key
				break
		checks.append(["Test setup: found an unlocked Characteristic to test the Buy button's own click through", buy_key != ""])
		if buy_key != "":
			var rows3 := _grid_rows(char_grid)
			var full_name3: String = CharacteristicSet.FULL_NAMES[buy_key]
			var row3 := _find_row(rows3, full_name3)
			checks.append(["Test setup: that Characteristic's own grid row was found", not row3.is_empty()])
			if not row3.is_empty():
				checks.append(["Test setup: its Buy button genuinely exists to click", row3["buy_btn"] != null])
				if row3["buy_btn"] != null:
					var before := character.get_characteristic_advance_count(buy_key)
					(row3["buy_btn"] as Button).pressed.emit()
					await tree.process_frame
					var after := character.get_characteristic_advance_count(buy_key)
					checks.append(["Clicking a grid row's own Buy button actually purchases the advance", after == before + 1])

	if talent_grid != null and concrete_talent_name != "":
		var trows2 := _grid_rows(talent_grid)
		var trow2 := _find_row(trows2, concrete_talent_name)
		checks.append(["Test setup: the Talent's own grid row was found for the Buy click-through check", not trow2.is_empty()])
		if not trow2.is_empty():
			checks.append(["Test setup: its Buy button genuinely exists to click", trow2["buy_btn"] != null])
			if trow2["buy_btn"] != null:
				var before_rank := character.get_talent_rank(concrete_talent_name)
				(trow2["buy_btn"] as Button).pressed.emit()
				await tree.process_frame
				var after_rank := character.get_talent_rank(concrete_talent_name)
				checks.append(["Clicking a Talents grid row's own Buy button actually purchases a rank", after_rank == before_rank + 1])

	menu.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Menu Stats Grid Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass

## Reads the plain, unboxed header row's own cell texts (one per
## column — 5 since the Career/Name/Value/Advances/Train split).
static func _header_texts(grid: GridContainer) -> Array:
	var cols: int = grid.columns
	var cells := grid.get_children()
	var texts: Array = []
	for i in range(min(cols, cells.size())):
		var cell: Control = cells[i]
		var inner: Control = cell.get_child(0) if cell.get_child_count() > 0 else null
		texts.append((inner as Label).text if inner is Label else "")
	return texts

## Walks a Characteristics/Skills/Talents grid's own children 5-at-a-
## time, skipping the header row, returning one Dictionary per row:
## {name, value, unlocked, advances, buy_btn, sell_btn}.
## Per the follow-up request ("replace the current Tick boxes... with
## one that looks just like the favourite button from the inventory
## screen... Separate stats name and values into separate columns"):
## the Career cell now holds a plain Button (glyph text ☑/☐, same as
## the Inventory tab's own favourite star) instead of a CheckBox, and
## Name/Value are read from their own separate cells instead of being
## parsed out of one combined label.
static func _grid_rows(grid: GridContainer) -> Array:
	var cols: int = grid.columns
	var cells := grid.get_children()
	var rows: Array = []
	var i := cols
	while i + cols <= cells.size():
		var career_cell: PanelContainer = cells[i]
		var name_cell: PanelContainer = cells[i + 1]
		var value_cell: PanelContainer = cells[i + 2]
		var adv_cell: PanelContainer = cells[i + 3]
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

		var value_text := ""
		var value_inner: Control = value_cell.get_child(0) if value_cell.get_child_count() > 0 else null
		if value_inner is Label:
			value_text = (value_inner as Label).text
		elif value_inner is OptionButton:
			var ob := value_inner as OptionButton
			value_text = ob.get_item_text(ob.selected) if ob.item_count > 0 else ""

		var adv_text := ""
		if adv_cell.get_child_count() > 0 and adv_cell.get_child(0) is Label:
			adv_text = (adv_cell.get_child(0) as Label).text

		## Per the follow-up request ("remove the word Buy, and only leave
		## the XP cost, eg. 15 XP"): the Train column's own purchase button
		## no longer reads "Buy (N XP)" — just "%d XP" (compact and full
		## mode alike, see _add_stat_grid_row's own comment) — so it can no
		## longer be matched by begins_with("Buy"). Sell still always
		## begins with "Sell" ("Sell" compact / "Sell (+N XP)" full), so
		## that's identified by its own text first; Buy is then whatever
		## other Button is left in the cell (there's never more than the
		## one of each).
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

		rows.append({"name": name_text, "value": value_text, "unlocked": unlocked, "advances": adv_text, "buy_btn": buy_btn, "sell_btn": sell_btn})
		i += cols
	return rows

static func _find_row(rows: Array, name: String) -> Dictionary:
	for row in rows:
		if (row["name"] as String) == name:
			return row
	return {}

## Recursively collects every GridContainer anywhere under `root`, any
## number of levels deep — needed now that the Skills sub-tab (per the
## follow-up "split basic and advanced skills into separate columns"
## request) nests its two grids inside an HBoxContainer of
## VBoxContainer columns, rather than sitting as %SkillsBox's own
## direct children.
static func _find_all_grids(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is GridContainer:
			found.append(child)
		found.append_array(_find_all_grids(child))
	return found

## Recursively collects every Label's own text under `root`, any number
## of levels deep — used to confirm the "Basic"/"Advanced" column
## headers are genuinely present somewhere in the Skills sub-tab.
static func _scrape_labels(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_scrape_labels(child))
	return out
