extends RefCounted
class_name CareerReentryTierTest
## Per the request ("when switching career allow character to directly
## enter higher tiers of other classes if they have already completed
## lower ones in that target career") AND the follow-up ("it should be
## an option, not forced to the higher tier"): the Career tab's Tier
## picker lets the player explicitly CHOOSE a re-entry tier rather than
## the switch auto-jumping to the top — always DEFAULTING to Tier 1
## (same as a career that's never been touched) rather than forcing the
## higher one.
##
## Per a real, confirmed bug report ("alberta has completed Thief tier 1
## and moved to duelist tier 1, but going back to thief she cant choose
## tier 2. this should now be possible with last addition") AND its
## clarifying follow-up ("she should not need to complete duelist tier 1
## to do so either"): two things were actually wrong, both covered here.
## First, Advancement.highest_tier_reached() only ever checked the
## `to_career` side of career_history entries — a character's STARTING
## career (Alberta's Thief Tier 1) is never itself logged as a
## `to_career`, only ever appearing as the `from_career` of whatever
## switch came after it, so it was invisible to the old lookup. Second,
## even once visible, the correct re-entry cap for having stood in Tier
## N of a career is Tier N+1 (the next real door), not Tier N itself —
## and this must never be gated on Advancement.has_completed_current_
## level() for either the career being left or the one being re-entered,
## matching how the ordinary "advance within your current career"
## button already works (always offered once you're in a tier; cost is
## merely higher if incomplete, nothing blocks it outright).
## Advancement.max_reentry_tier() implements this corrected cap.

static func _make_career(name: String, class_name_: String, tier_count: int) -> CareerDefinition:
	var career := CareerDefinition.new()
	career.career_name = name
	career.career_class = class_name_
	var levels: Array[CareerLevel] = []
	for t in range(1, tier_count + 1):
		var lvl := CareerLevel.new()
		lvl.tier = t
		lvl.level_name = "%s T%d" % [name, t]
		levels.append(lvl)
	career.levels = levels
	return career

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character

	var soldier := _make_career("Soldier", "Warrior", 4)
	var scholar := _make_career("Scholar", "Academic", 4)
	var thief := _make_career("Thief", "Rogue", 4)
	var duellist := _make_career("Duellist", "Warrior", 4)
	var short_career := _make_career("Short", "Peasant", 2)

	## --- A career never touched before still only reaches Tier 1 -----------
	pc.career = soldier
	pc.current_tier = 1
	pc.career_history = []
	checks.append(["A career never touched before: highest_tier_reached() is 0", Advancement.highest_tier_reached(pc, "Scholar") == 0])
	checks.append(["...so max_reentry_tier() still resolves to Tier 1 as the only option", Advancement.max_reentry_tier(pc, scholar) == 1])

	## --- Simulate a real earlier stint in Scholar up to Tier 3, then --------
	## leaving for something else, mirroring how change_career() itself
	## actually appends history entries (always sequential +1 moves).
	pc.career_history.append({"from_career": "Soldier", "from_tier": 1, "to_career": "Scholar", "to_tier": 1, "cost": 200})
	pc.career_history.append({"from_career": "Scholar", "from_tier": 1, "to_career": "Scholar", "to_tier": 2, "cost": 100})
	pc.career_history.append({"from_career": "Scholar", "from_tier": 2, "to_career": "Scholar", "to_tier": 3, "cost": 100})
	pc.career_history.append({"from_career": "Scholar", "from_tier": 3, "to_career": "Soldier", "to_tier": 1, "cost": 200})
	pc.career = soldier
	pc.current_tier = 1

	checks.append(["Earlier stint recorded up to Scholar Tier 3: highest_tier_reached() reports 3", Advancement.highest_tier_reached(pc, "Scholar") == 3])
	checks.append(["...and the career actually currently active (Soldier) still just reports its own current tier", Advancement.highest_tier_reached(pc, "Soldier") == 1])
	checks.append(["...so max_reentry_tier() offers Tier 4 (one above), since Scholar goes that high", Advancement.max_reentry_tier(pc, scholar) == 4])

	## --- Advancement.change_career() itself still happily enters ANY -------
	## valid tier up to (or below) that cap when explicitly told to —
	## the auto-jump-to-max behaviour lived only in the UI and has been
	## replaced there with an explicit picker (checked below); the
	## underlying purchase function was never the thing forcing anything.
	pc.experience_total = 10000
	pc.experience_spent = 0
	var xp_before: int = pc.get_experience_available()
	var completed_before: bool = Advancement.has_completed_current_level(pc)
	var result: Advancement.PurchaseResult = Advancement.change_career(pc, scholar, 4)
	checks.append(["change_career() explicitly given the newly-unlocked ceiling tier (4) succeeds", result.success])
	checks.append(["The character lands on Scholar Tier 4, exactly the tier explicitly requested", pc.career == scholar and pc.current_tier == 4])
	checks.append(["A NEW history entry was appended recording this re-entry", pc.career_history.size() == 5])
	var last_entry: Dictionary = pc.career_history[pc.career_history.size() - 1]
	checks.append(["The new entry's to_tier is 4", int(last_entry.get("to_tier", 0)) == 4])
	## Cost is unaffected by which tier is entered — it's governed
	## purely by completion status + class change, exactly as the book
	## table specifies, so re-entering deep into a career you've
	## already proven yourself in isn't somehow cheaper or more
	## expensive than entering at Tier 1 would have been.
	var expected_cost: int = Advancement.get_change_career_cost(completed_before, true)
	checks.append(["Cost charged matches the ordinary class-change cost, unaffected by entry tier", xp_before - pc.get_experience_available() == expected_cost])

	## --- Re-entering below the cap is still explicitly allowed too — a -----
	## player might legitimately want to re-enter lower than the cap,
	## and nothing about this feature should prevent that.
	pc.career = soldier
	pc.current_tier = 1
	var result2: Advancement.PurchaseResult = Advancement.change_career(pc, scholar, 2)
	checks.append(["change_career() still permits explicitly choosing a lower already-qualified tier (2)", result2.success and pc.current_tier == 2])

	## --- A tier beyond what's ever been reached (and beyond what the -------
	## career even has) still correctly fails, same as before this change.
	var result3: Advancement.PurchaseResult = Advancement.change_career(pc, scholar, 99)
	checks.append(["A tier that doesn't exist on the career still fails cleanly", not result3.success])

	## --- Alberta repro: the exact real bug report reproduced faithfully ----
	## from her actual Career History screenshot — started in Thief Tier
	## 1 (her character's starting career, never itself logged as a
	## to_career entry), then switched straight to Duellist Tier 1.
	pc.career = thief
	pc.current_tier = 1
	pc.career_history = []
	pc.career_history.append({"from_career": "Thief", "from_tier": 1, "to_career": "Duellist", "to_tier": 1, "cost": 200})
	pc.career = duellist
	pc.current_tier = 1
	checks.append(["Alberta repro: highest_tier_reached() for Thief (stood in Tier 1 only) is 1, not 0", Advancement.highest_tier_reached(pc, "Thief") == 1])
	checks.append(["Alberta repro: max_reentry_tier() for Thief is 2 -- Tier 2 is now a real re-entry option", Advancement.max_reentry_tier(pc, thief) == 2])
	checks.append(["Alberta repro: her current career/tier is genuinely incomplete here, confirming the unlock above didn't depend on it", not Advancement.has_completed_current_level(pc)])
	pc.experience_total = 10000
	pc.experience_spent = 0
	var alberta_result: Advancement.PurchaseResult = Advancement.change_career(pc, thief, 2)
	checks.append(["Alberta repro: change_career() to Thief Tier 2 (the newly-unlocked ceiling) succeeds", alberta_result.success])
	checks.append(["Alberta repro: she actually lands on Thief Tier 2", pc.career == thief and pc.current_tier == 2])

	## --- Reaching the TOP tier of a short career caps max_reentry_tier() ---
	## at that same top tier, not one past it -- a career that's shorter
	## than reached-tier-plus-one can't be asked for a tier it doesn't have.
	pc.career = soldier
	pc.current_tier = 1
	pc.career_history = []
	pc.career_history.append({"from_career": "Soldier", "from_tier": 1, "to_career": "Short", "to_tier": 1, "cost": 200})
	pc.career_history.append({"from_career": "Short", "from_tier": 1, "to_career": "Short", "to_tier": 2, "cost": 100})
	pc.career_history.append({"from_career": "Short", "from_tier": 2, "to_career": "Soldier", "to_tier": 1, "cost": 200})
	checks.append(["Reaching the TOP tier of a short career caps max_reentry_tier() at that same top tier, not one past it", Advancement.max_reentry_tier(pc, short_career) == 2])

	## --- Screen-level check: the real Career tab's Tier picker defaults ----
	## to Tier 1 (never auto-selects the cap) and only actually enters a
	## higher tier once the player explicitly picks one — using real
	## GameData careers rather than the synthetic ones above, so this
	## also confirms _rebuild_career() wires everything through end to
	## end, not just that the underlying Advancement functions work in
	## isolation. Requires a real career with 3+ tiers so the "reached
	## Tier 2, cap becomes Tier 3" case (Alberta's actual shape) is what
	## gets exercised, not just the "reached Tier 1, cap Tier 2" case
	## already covered above.
	if GameData.careers.size() >= 2:
		var real_target: CareerDefinition = null
		for c in GameData.careers:
			if pc.career == null or c.career_name != pc.career.career_name:
				if c.levels.size() >= 3:
					real_target = c
					break
		if real_target == null:
			print("SKIP (Career Re-entry Tier / screen check): no other real career with 3+ tiers found to test against")
		else:
			GameState.reset_world_state()
			GameState.player_character = null
			GameState.ensure_player_character()
			var pc2: Character = GameState.player_character
			pc2.experience_total = 10000
			pc2.experience_spent = 0
			## A prior real stint that reached this target career's Tier 2.
			pc2.career_history = [{
				"from_career": pc2.career.career_name if pc2.career != null else "",
				"from_tier": 1,
				"to_career": real_target.career_name,
				"to_tier": 2,
				"cost": 200,
			}]

			var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
			var menu: Node = menu_scene.instantiate()
			tree.get_root().add_child.call_deferred(menu)
			await tree.process_frame
			await tree.process_frame
			menu.open()
			await tree.process_frame

			## career_box's children, in build order: "Current Career"
			## header/status, the same-career advance row or "maxed"
			## label, the "Change to a Different Career" header, then the
			## switch_row HBoxContainer (career picker + Tier picker +
			## Switch button) — found by shape rather than index, so this
			## doesn't break if an earlier row's own child count changes
			## for unrelated reasons.
			var switch_row: HBoxContainer = null
			for child in menu.career_box.get_children():
				if child is HBoxContainer:
					var kids := (child as HBoxContainer).get_children()
					if kids.size() == 3 and kids[0] is OptionButton and kids[1] is OptionButton and kids[2] is Button:
						switch_row = child
						break
			checks.append(["Screen check: the Career tab's switch row (career picker + Tier picker + Switch button) was found", switch_row != null])

			if switch_row != null:
				var career_picker: OptionButton = switch_row.get_child(0)
				var tier_picker: OptionButton = switch_row.get_child(1)
				var switch_btn: Button = switch_row.get_child(2)
				var found_target_idx := -1
				for i in range(career_picker.item_count):
					if career_picker.get_item_text(i) == real_target.career_name:
						found_target_idx = i
						break
				checks.append(["Screen check: the previously-reached career appears in the picker", found_target_idx != -1])
				if found_target_idx != -1:
					career_picker.selected = found_target_idx
					career_picker.item_selected.emit(found_target_idx)

					checks.append(["Screen check: the Tier picker becomes visible once a career with a real cap above 1 is selected", tier_picker.visible])
					checks.append(["Screen check: the Tier picker offers exactly 3 choices (Tier 1, 2, and the newly-unlocked Tier 3)", tier_picker.item_count == 3])
					checks.append(["Screen check: the Tier picker DEFAULTS to Tier 1 -- NOT auto-forced to the higher tier", tier_picker.selected == 0])
					checks.append(["Screen check: Switch button text defaults to naming Tier 1, matching the picker's default", switch_btn.text.contains("Tier 1") and not switch_btn.text.contains("Tier 3")])

					## Now the player explicitly opts INTO the newly-unlocked tier.
					tier_picker.selected = 2
					tier_picker.item_selected.emit(2)
					checks.append(["Screen check: after explicitly picking Tier 3, the Switch button text updates to name Tier 3", switch_btn.text.contains("Tier 3")])
					switch_btn.pressed.emit()
					await tree.process_frame
					checks.append(["Screen check: pressing Switch actually lands the character on the EXPLICITLY chosen Tier 3 of the target career", pc2.career != null and pc2.career.career_name == real_target.career_name and pc2.current_tier == 3])

			if is_instance_valid(menu):
				menu.queue_free()
				await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Career Re-entry Tier): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
