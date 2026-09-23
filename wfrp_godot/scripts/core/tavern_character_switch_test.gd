extends RefCounted
class_name TavernCharacterSwitchTest
## Regression test for the bug report ("also switching character in
## Tavern's is not working right now"): the Tavern Activities box's own
## "As %s — [Q/E] to switch" label (see tavern_screen.gd's
## _build_tavern_activities_box) has always advertised Q/E as the way to
## change which party member is currently being served, but
## TavernScreen's own _unhandled_input() never actually implemented the
## Q/E keys — every OTHER screen with this same convention
## (city_screen.gd, overworld.gd, shop_screen.gd, healer_screen.gd,
## field_encounter_screen.gd) wires its own Q/E handling; this one was
## simply missing it, so the label was pure decoration that did nothing.
##
## The fix reuses GameState.cycle_active_party_member() — the same
## global helper Overworld's own Q/E already uses — since the Tavern's
## "active character" IS GameState.player_character directly (unlike
## Shop/Healer, which track their own screen-local `character` target).
##
## Drives a real TavernScreen instance with a real 2-member party and
## simulates real KEY_Q/KEY_E InputEventKey presses via
## ts._unhandled_input(), same "synthesize a real InputEventKey and call
## _unhandled_input() directly" convention city_screen_test.gd already
## uses (injecting a real event into an offscreen headless run is
## unreliable).
##
## Per the further follow-up request ("alot of buttons in the tavern
## screen are much bigger then the text inside them, shrink them down
## to their text sizes. And rename the short nap to Resting. also
## highlight the active character"): also confirms the Drink/Gossip
## buttons are genuinely sized to their own text (not stretched to fill
## the Activities box), that the Sleep section's own short-rest button
## now reads "(Resting)" rather than "(short nap)", and that the Party
## box belonging to whichever character is currently active gets a real
## visual highlight (a border the non-active box doesn't have) that
## moves to the newly-active character's own box the instant Q/E
## switches — a real, structural check (comparing StyleBoxFlat border
## widths), not just a colour eyeballed off a screenshot.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var first: Character = GameState.player_character
	first.character_name = "Aldric"

	var human := GameData.find_race("Human")
	var soldier := GameData.find_career("Soldier")
	var second := Character.new()
	second.character_name = "Brenna"
	second.race = human
	second.career = soldier
	second.current_tier = 1
	second.characteristics = CharacteristicSet.new()
	second.recompute_max_wounds()
	GameState.add_party_member(second)

	checks.append(["setup: the party has exactly 2 living members for a real cycle to exercise", GameState.party.size() == 2])
	checks.append(["setup: Aldric (the first member added) starts as the active/controlled character", GameState.player_character == first])

	var ts = load("res://scenes/Tavern.tscn").instantiate()
	tree.get_root().add_child(ts)
	for i in range(3):
		await tree.process_frame

	checks.append(["Before switching, the Tavern Activities box's own label names the real active character (Aldric)", _activities_box_text(ts).findn("As Aldric") != -1])

	## --- Button sizing: Drink/Gossip shrunk to their own text, not
	## stretched to fill the Activities box -----------------------------
	var drink_btn := _find_button_by_prefix(ts.content_box, "Drink (")
	checks.append(["setup: found the real Drink button to measure", drink_btn != null])
	if drink_btn != null:
		checks.append(["The Drink button is sized to its own text (shrunk), not stretched to fill the Activities box", is_equal_approx(drink_btn.size.x, drink_btn.get_minimum_size().x)])
	var gossip_btn := _find_button_by_prefix(ts.content_box, "Gossip (")
	checks.append(["setup: found the real Gossip button to measure", gossip_btn != null])
	if gossip_btn != null:
		checks.append(["The Gossip button is sized to its own text (shrunk), not stretched to fill the Activities box", is_equal_approx(gossip_btn.size.x, gossip_btn.get_minimum_size().x)])

	## --- Short-rest button renamed from "(short nap)" to "(Resting)" ---
	var sleep_text := _scrape_labels(ts.content_box, "") + _scrape_buttons(ts.content_box, "")
	checks.append(["The short-rest button now reads \"(Resting)\", not the old \"(short nap)\"", sleep_text.contains("(Resting)") and not sleep_text.contains("short nap")])

	## --- Active-character highlight: Aldric's own Party box is
	## highlighted, Brenna's is not -----------------------------------
	var aldric_box_before := _find_party_box(ts, "Aldric")
	var brenna_box_before := _find_party_box(ts, "Brenna")
	checks.append(["setup: found both party members' own boxes to check for a highlight", aldric_box_before != null and brenna_box_before != null])
	if aldric_box_before != null and brenna_box_before != null:
		checks.append(["Aldric (the active character) starts with a real highlighted box (a border the default box style doesn't have)", _box_is_highlighted(aldric_box_before)])
		checks.append(["...while Brenna (not active) has no such highlight", not _box_is_highlighted(brenna_box_before)])

	## --- KEY_E cycles forward (Aldric -> Brenna) ---------------------------
	var e_event := InputEventKey.new()
	e_event.pressed = true
	e_event.echo = false
	e_event.keycode = KEY_E
	ts._unhandled_input(e_event)
	await tree.process_frame

	checks.append(["KEY_E actually cycles GameState's own active party member forward", GameState.player_character == second])
	checks.append(["...and the Tavern screen rebuilds to show the newly-active character (Brenna)", _activities_box_text(ts).findn("As Brenna") != -1])
	checks.append(["...no longer showing the previous character (Aldric) in that same label", _activities_box_text(ts).findn("As Aldric") == -1])

	var aldric_box_after := _find_party_box(ts, "Aldric")
	var brenna_box_after := _find_party_box(ts, "Brenna")
	if aldric_box_after != null and brenna_box_after != null:
		checks.append(["The highlight itself moved: Brenna's own Party box is now highlighted", _box_is_highlighted(brenna_box_after)])
		checks.append(["...and Aldric's own Party box is no longer highlighted", not _box_is_highlighted(aldric_box_after)])

	## --- KEY_Q cycles backward (Brenna -> Aldric again) --------------------
	var q_event := InputEventKey.new()
	q_event.pressed = true
	q_event.echo = false
	q_event.keycode = KEY_Q
	ts._unhandled_input(q_event)
	await tree.process_frame

	checks.append(["KEY_Q cycles it back again (works both directions)", GameState.player_character == first])
	checks.append(["...and the Tavern screen rebuilds to show Aldric again", _activities_box_text(ts).findn("As Aldric") != -1])

	## --- No-op with only one living party member ---------------------------
	## Same guard _cycle_character() (Shop/Healer's own Q/E) already has —
	## GameState.cycle_active_party_member() itself is a no-op when
	## party.size() <= 1, so a solo adventurer's Q/E press is silently
	## harmless rather than erroring.
	GameState.party.erase(second)
	GameState.active_party_index = 0
	var solo_before: Character = GameState.player_character
	var e_event2 := InputEventKey.new()
	e_event2.pressed = true
	e_event2.echo = false
	e_event2.keycode = KEY_E
	ts._unhandled_input(e_event2)
	await tree.process_frame
	checks.append(["With only one living party member, Q/E is a harmless no-op (doesn't error or change the active character)", GameState.player_character == solo_before])

	ts.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Tavern Character Switch): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Scrapes every Label's own text under the Tavern's activities box
## (the right-hand "Tavern" panel built by _build_tavern_activities_box)
## so the "As <Name> — [Q/E] to switch" line can be found regardless of
## exactly which sibling controls surround it.
static func _activities_box_text(ts: Node) -> String:
	return _scrape_labels(ts.content_box, "")

static func _scrape_labels(root: Node, out: String) -> String:
	for child in root.get_children():
		if child is Label:
			out += child.text + "\n"
		out = _scrape_labels(child, out)
	return out

## As _scrape_labels, but for Button text (a Button isn't a Label, so
## the recursive scrape above never sees it) — used to check the Sleep
## section's own short-rest button text without needing its exact
## dynamic hour count.
static func _scrape_buttons(root: Node, out: String) -> String:
	for child in root.get_children():
		if child is Button:
			out += child.text + "\n"
		out = _scrape_buttons(child, out)
	return out

## Recursively finds the first Button anywhere under `root` whose text
## begins with `prefix` — used to find the Drink/Gossip buttons without
## needing their exact dynamic target number/price.
static func _find_button_by_prefix(root: Node, prefix: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).begins_with(prefix):
			return child
		var found := _find_button_by_prefix(child, prefix)
		if found != null:
			return found
	return null

## Finds the Party box (the PanelContainer _build_character_box builds)
## whose own name Label reads "<name_prefix> — <Career>" — used to check
## the active-character highlight without hardcoding node paths.
static func _find_party_box(ts: Node, name_prefix: String) -> PanelContainer:
	for child in ts.content_box.get_children():
		if child is HBoxContainer:
			for col in child.get_children():
				if col is VBoxContainer:
					for maybe_box in col.get_children():
						if maybe_box is PanelContainer and _scrape_labels(maybe_box, "").begins_with(name_prefix):
							return maybe_box
	return null

## A highlighted Party box gets a real border (see _build_character_box)
## the default, non-active box style never sets — checking the actual
## StyleBoxFlat's own border width is a real structural check, not just
## an eyeballed colour off a screenshot.
static func _box_is_highlighted(box: PanelContainer) -> bool:
	var style: StyleBoxFlat = box.get_theme_stylebox("panel")
	return style != null and style.border_width_left > 0
