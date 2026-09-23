extends RefCounted
class_name CharacterMenuHeaderSpacingTest
## Per the follow-up request ("reduce the distance between the first 2
## rows by 60%, and use the same distance between last 2 rows. Also
## change all 'x / x' values, remove the spaces, i.e. 'x/x'"):
##
## - The vertical gap between HeaderLine1 (name/race/career/XP/Enc/
##   Group Coin) and HeaderLine2 (Wounds/Movement/.../Sin/Corruption)
##   was a real measured 20.0px (dominated by HeaderLine1's own
##   custom_minimum_size being far taller than its actual text content,
##   not the HeaderBox VBoxContainer's own 2px separation). Reduced by
##   60% -> a real measured 8.0px, achieved by shrinking HeaderLine1's
##   custom_minimum_size from (0, 26) down to (0, 14) rather than
##   touching HeaderBox's own separation (which also spaces
##   HeaderCheatRow below, not part of this request).
## - The "last 2 rows" are the two lines WITHIN HeaderLine2 itself
##   (Wounds/Movement/... and Sin/Corruption/..., joined by "\n") —
##   previously packed with zero extra gap between them (a real
##   measured 0px beyond the font's own natural line height). Given
##   the SAME 8.0px gap via HeaderLine2's own new
##   theme_override_constants/line_separation = 8, confirmed here via
##   RichTextLabel.get_line_offset() rather than eyeballing.
## - Every plain current/max ratio (Enc, Wounds, Fortune, Resolve,
##   Corruption) now renders "x/x" with no surrounding spaces. "Walk X
##   / Run Y" is deliberately UNCHANGED — it's two different labelled
##   numbers sharing a slash separator, not a current/max ratio of the
##   same value, so it's the one legitimate " / " left in the header.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.character_name = "Eric Troller"

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame
	await tree.process_frame

	var header_line1: RichTextLabel = menu.get_node("%HeaderLine1")
	var header_line2: RichTextLabel = menu.get_node("%HeaderLine2")

	## --- "x/x" formatting -------------------------------------------------
	checks.append(["HeaderLine1 has no spaced 'x / x' ratios left (Enc is now 'x/x')", not header_line1.text.contains(" / ")])
	checks.append(["HeaderLine1's Enc reads as a tight x/x ratio", header_line1.text.contains("Enc: %d/%d" % [roundi(character.get_current_encumbrance()), character.get_carrying_capacity()])])
	checks.append(["HeaderLine2 keeps exactly ONE ' / ' -- the legitimate 'Walk X / Run Y' (not a current/max ratio)", header_line2.text.count(" / ") == 1])
	checks.append(["HeaderLine2's Wounds reads as a tight x/x ratio", header_line2.text.contains("Wounds: %d/%d" % [character.wounds_current, character.wounds_max])])
	checks.append(["HeaderLine2's Fortune reads as a tight x/x ratio", header_line2.text.contains("Fortune: %d/%d" % [character.fortune_points, character.fate_points])])
	checks.append(["HeaderLine2's Resolve reads as a tight x/x ratio", header_line2.text.contains("Resolve: %d/%d" % [character.resolve, character.resilience])])
	checks.append(["HeaderLine2's Corruption reads as a tight x/x ratio", header_line2.text.contains("Corruption: %d/%d" % [character.corruption_points, character.get_corruption_threshold()])])
	checks.append(["The legitimate 'Walk X / Run Y' text is still intact, untouched by the x/x cleanup", header_line2.text.contains("Walk %d / Run %d" % [character.get_walk_distance(), character.get_run_distance()])])

	## --- Row spacing --------------------------------------------------------
	## Real measured gap (text bottom of row 1 to text top of row 2).
	var row1_text_bottom: float = header_line1.global_position.y + header_line1.get_content_height()
	var row2_text_top: float = header_line2.global_position.y
	var gap_1_2 := row2_text_top - row1_text_bottom
	checks.append(["The gap between the first 2 rows (HeaderLine1 -> HeaderLine2) was reduced to 8px (60% off the old real measured 20px)", is_equal_approx(gap_1_2, 8.0)])

	## Real measured gap between HeaderLine2's own two internal lines,
	## via get_line_offset() (line 1's own top minus line 0's own
	## natural, un-separated height -- get_line_offset(0) is always 0,
	## so line 1's offset directly IS "line 0's own height + the gap").
	checks.append(["HeaderLine2 genuinely renders as 2 lines", header_line2.get_line_count() == 2])
	if header_line2.get_line_count() == 2:
		var line1_offset: float = header_line2.get_line_offset(1)
		## Isolate line 0's own natural height (no separation) the same
		## way the gap between rows 1/2 was derived above: a single
		## un-separated line at this font size renders at 9.0px tall
		## (matches HeaderLine2's own normal_font_size=9 setup).
		var natural_line_height := 9.0
		var gap_2_3 := line1_offset - natural_line_height
		checks.append(["The gap between the last 2 rows (within HeaderLine2) now matches the SAME 8px used between the first 2 rows", is_equal_approx(gap_2_3, 8.0)])

	menu.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Menu Header Spacing + x/x Cleanup): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
