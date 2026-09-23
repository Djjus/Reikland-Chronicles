extends RefCounted
class_name ConditionMarkersTest
## Regression test for the request ("add visual markers for conditions on
## each combatant... create a suitable representative marker for each
## condition (ablaze/prone/bleeding/stunned/broken/blinded/fatigued/
## poisoned/surprised/deafened)"): BattleGridView's own per-token draw
## loop used to show a combatant's active Conditions nowhere at all on
## the battle map itself (only as plain text elsewhere, e.g. the ally
## roster panel's own condition_label, or the hover tooltip) — see
## BattleGridView.CONDITION_ICONS' own comment for the fix.
##
## Tests BattleGridView._condition_markers_for() directly — a plain data
## function with no dependency on this being a live, on-screen CanvasItem
## (split out from the real _draw() loop specifically so this doesn't
## need to render anything to verify) — rather than the drawing itself,
## which isn't something a headless run can inspect pixel-by-pixel
## anyway.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame

	var view := BattleGridView.new()

	## --- No matching Conditions at all -> no markers.
	var plain := Character.new()
	plain.conditions = {}
	checks.append(["a combatant with no Conditions gets no markers at all", view._condition_markers_for(plain).is_empty()])

	var unrelated := Character.new()
	unrelated.conditions = {"Unconscious": 1}   ## already has its own dedicated on-token treatment (the red X) -- not one of the ten requested here
	checks.append(["a Condition outside the requested ten (Unconscious) produces no marker", view._condition_markers_for(unrelated).is_empty()])

	## --- All ten requested Conditions get their own real, distinct glyph.
	var all_ten := ["Ablaze", "Bleeding", "Poisoned", "Stunned", "Prone", "Broken", "Blinded", "Deafened", "Fatigued", "Surprised"]
	checks.append(["all ten requested Conditions have a real CONDITION_ICONS entry", all_ten.all(func(n): return BattleGridView.CONDITION_ICONS.has(n))])
	var glyphs_seen: Dictionary = {}
	var all_distinct := true
	for n in all_ten:
		var g: String = BattleGridView.CONDITION_ICONS[n]["glyph"]
		if glyphs_seen.has(g):
			all_distinct = false
		glyphs_seen[g] = true
	checks.append(["every one of the ten Conditions gets its OWN distinct glyph (no two sharing one icon)", all_distinct])

	## --- Stacking: >1 stack shows the count; 0 or 1 stack shows the bare glyph.
	var stacked := Character.new()
	stacked.conditions = {"Ablaze": 3, "Prone": 1, "Surprised": 1}
	var stacked_markers: Array = view._condition_markers_for(stacked)
	checks.append(["three active Conditions -> three markers", stacked_markers.size() == 3])
	## Order must follow CONDITION_ICON_ORDER, not Dictionary insertion/iteration order.
	checks.append(["markers come back in the fixed CONDITION_ICON_ORDER (Ablaze, Prone, Surprised), not insertion order", (
		stacked_markers.size() == 3
		and stacked_markers[0]["text"] == "%s3" % BattleGridView.CONDITION_ICONS["Ablaze"]["glyph"]
		and stacked_markers[1]["text"] == BattleGridView.CONDITION_ICONS["Prone"]["glyph"]
		and stacked_markers[2]["text"] == BattleGridView.CONDITION_ICONS["Surprised"]["glyph"]
	)])
	checks.append(["a stacked Condition (Ablaze x3) shows its glyph WITH the stack count", stacked_markers[0]["text"] == "🔥3"])
	checks.append(["a Condition at exactly 1 stack (Prone) shows just the bare glyph, no '1' suffix", stacked_markers[1]["text"] == BattleGridView.CONDITION_ICONS["Prone"]["glyph"]])
	checks.append(["each marker carries its own real, non-default tint color", (
		stacked_markers[0]["color"] == BattleGridView.CONDITION_ICONS["Ablaze"]["color"]
		and stacked_markers[1]["color"] == BattleGridView.CONDITION_ICONS["Prone"]["color"]
	)])

	## --- Order stability regardless of Dictionary insertion order.
	var reverse_inserted := Character.new()
	reverse_inserted.conditions = {}
	reverse_inserted.conditions["Surprised"] = 1
	reverse_inserted.conditions["Prone"] = 1
	reverse_inserted.conditions["Ablaze"] = 3
	var reverse_markers: Array = view._condition_markers_for(reverse_inserted)
	var stacked_texts: Array = stacked_markers.map(func(m): return m["text"])
	var reverse_texts: Array = reverse_markers.map(func(m): return m["text"])
	checks.append(["marker order is driven by CONDITION_ICON_ORDER, not however Conditions happened to be inserted into the Dictionary", stacked_texts == reverse_texts])

	## --- Every one of the ten, all stacked at once -> ten markers, still in the fixed order.
	var everything := Character.new()
	everything.conditions = {}
	for n in all_ten:
		everything.conditions[n] = 2
	var everything_markers: Array = view._condition_markers_for(everything)
	checks.append(["a combatant with all ten active Conditions gets exactly ten markers", everything_markers.size() == 10])
	var order_matches := everything_markers.size() == BattleGridView.CONDITION_ICON_ORDER.size()
	if order_matches:
		for i in range(BattleGridView.CONDITION_ICON_ORDER.size()):
			var expected_name: String = BattleGridView.CONDITION_ICON_ORDER[i]
			var expected_text: String = "%s2" % BattleGridView.CONDITION_ICONS[expected_name]["glyph"]
			if everything_markers[i]["text"] != expected_text:
				order_matches = false
				break
	checks.append(["...each in BattleGridView's own fixed CONDITION_ICON_ORDER, with its real stack count", order_matches])

	view.free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Condition Markers): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
