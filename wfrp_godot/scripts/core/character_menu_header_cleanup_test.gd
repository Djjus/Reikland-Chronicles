extends RefCounted
class_name CharacterMenuHeaderCleanupTest
## Per the request ("clean up this section, first just call the button
## Esc and make it smaller, then remove the large gaps and unnecessary
## spaces in the text in the lines below. Remove the XP spent (number +
## word), rename XP available to XP unspent. and move Sin and
## corruption to the next row and place any active condition/critical
## wound data on selected character next to them in that row. Then show
## Group Coin after Enc in the top row"): confirms the Close button now
## reads plain "Esc"; HeaderLine1 renders on a single, non-wrapping
## line even with a realistic amount of content; XP shows total/unspent
## only (no "X spent"); Sin/Corruption moved off the Wounds/Movement/
## Fate line onto their own row; and active Conditions/Critical Wounds
## render alongside Sin/Corruption on that same row rather than a
## separate "Ailments:" line.
##
## Per the LATER follow-up request ("remove group coin from the menu
## header and display the character gender instead"): Group Coin no
## longer follows Enc here at all — see _gender_text() in
## character_menu_screen.gd — so the check for it (and the second party
## member this test used to add specifically to catch Group Coin
## double-counting the shared purse) are both gone. Gender's own display
## is covered in full by the dedicated character_menu_gender_header_test.gd;
## this file keeps just enough of a check to confirm Group Coin's old
## text genuinely never comes back here.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var character: Character = GameState.player_character
	character.character_name = "Eric Troller"
	character.experience_total = 1500
	character.experience_spent = 1425
	character.add_condition("Fatigued")
	character.add_condition("Fatigued")
	character.active_critical_wound_count = 1

	var menu_scene: PackedScene = load("res://scenes/CharacterMenu.tscn")
	var menu: Node = menu_scene.instantiate()
	tree.get_root().add_child.call_deferred(menu)
	await tree.process_frame
	await tree.process_frame
	menu.open()
	await tree.process_frame

	var close_button: Button = menu.get_node("%CloseButton")
	checks.append(["The Close button now reads plain 'Esc', not 'Close (Esc)'", close_button.text == "Esc"])

	var header_line1: RichTextLabel = menu.get_node("%HeaderLine1")
	var header_line2: RichTextLabel = menu.get_node("%HeaderLine2")

	checks.append(["HeaderLine1 fits on a single line — no wrap — with a realistic amount of content", header_line1.get_line_count() == 1])
	checks.append(["HeaderLine1 has no large multi-space gaps left over from the old layout", not header_line1.text.contains("  ")])
	checks.append(["XP shows the total", header_line1.text.contains("1500 total")])
	checks.append(["XP shows what's unspent, using the new 'unspent' wording", header_line1.text.contains("75 unspent")])
	checks.append(["The old 'X spent' figure is gone entirely, not just relabelled", not header_line1.text.contains("1425 spent")])
	checks.append(["Enc is still on the top row", header_line1.text.contains("Enc:")])
	checks.append(["Group Coin's old text never reappears on the top row (replaced by Gender — see character_menu_gender_header_test.gd)", not header_line1.text.contains("Group Coin")])
	checks.append(["Gender shows on the top row in Group Coin's old place", header_line1.text.contains("Gender: %s" % character.gender.capitalize())])

	checks.append(["HeaderLine2 has no large multi-space gaps left over from the old layout", not header_line2.text.contains("  ")])
	var header2_lines: PackedStringArray = header_line2.text.split("\n")
	checks.append(["HeaderLine2 now renders as (at least) two real rows -- Wounds/Movement/etc. and a separate Sin/Corruption row", header2_lines.size() >= 2])
	if header2_lines.size() >= 2:
		checks.append(["Row 1 (Wounds/Movement/Fate/Fortune/Resilience/Resolve) no longer carries Sin", not header2_lines[0].contains("Sin:")])
		checks.append(["...or Corruption", not header2_lines[0].contains("Corruption:")])
		checks.append(["Row 2 has Sin", header2_lines[1].contains("Sin:")])
		checks.append(["...and Corruption", header2_lines[1].contains("Corruption:")])
		checks.append(["...and the active Condition (Fatigued x2) right alongside them on the SAME row", header2_lines[1].contains("Fatigued x2")])
		checks.append(["...and the active Critical Wound count right alongside them too", header2_lines[1].contains("1 Critical Wound(s)")])
		checks.append(["No separate 'Ailments:' label line remains — it's merged into the Sin/Corruption row", not header_line2.text.contains("Ailments:")])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Character Menu Header Cleanup Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
