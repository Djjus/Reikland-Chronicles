extends RefCounted
class_name CityScreenTest
## Regression/functional test for the new City Screen feature — drives
## a real CityScreen instance (per this project's established
## convention: real scene instantiation, not mocked-out pieces) and
## checks: the 71-location dataset loads with exactly the 8 requested
## starter locations unlocked (Nordwander and Son's Expeditionary
## Supplies — the shop-category POI 20, added per the City Shop
## follow-up request — plus North Gate and East Gate, POIs 1 and 2,
## hooked up per the follow-up gate request, plus The Exploding Pig —
## the tavern-category POI 42, added per the follow-up "2nd Tavern"
## request), the party group token
## starts at the South Gate, the InfoBar/party panel populate from the real party,
## clicking an unlocked marker selects it and opens its radial menu
## (Lore/Travel) rather than jumping straight to a travel offer, the
## Lore button shows real info without starting travel, clicking
## elsewhere deselects, choosing Travel from the radial menu is what
## actually offers a real distance/time-costed travel confirmation,
## confirming it actually advances the game clock and moves the token.
##
## Follow-up request ("show option at the location the player is at,
## move stay/enter to this radial, remove these while travelling —
## active POI target will still show Lore and Travel. Also allow user
## to click on travel confirmation pop ups option, and make the focused
## WASD option white"): also checks that a tavern/shop's radial only
## offers Stay/Enter once the party has actually arrived there (Travel
## instead everywhere else, regardless of category), that the Y/N
## confirm's Yes button can resolve a travel offer via a real click on
## it (not just the underlying flags), and that the WASD-focused choice
## is coloured white while the other stays muted.
##
## Follow-up request ("add a Leave City option to the north east and
## south gates... remove that option from the legend list. the only
## way to leave Ubersreik is now via the gates" + the reported bug "its
## not saving the city still, i always enter the game outside the city
## on the overworld map"): checks the legend no longer has its own
## always-visible leave button, that a gate's radial only offers Leave
## City once the party has actually walked to it, that GameState.
## last_active_city_id is set the moment CityScreen loads, and — as the
## very last thing this whole test does, since it triggers a real
## scene change (see that block's own comment) — that actually
## confirming Leave City clears both last_active_city_id and this
## city's own remembered position.
##
## Follow-up request ("always show the Leave City, Stay and Enter
## radial options when the party is at a location... trigger it after
## travel finishes. And only remove it when travel starts again to
## another location. And show click focused options Lore/Travel at the
## same time. Then always Auto focus (outline in red) and Space hotkey
## the travel option"): the single click-driven radial menu is now two
## independent ones — a persistent "home" radial (CityMapView.
## home_location/home_actions) for wherever the party is actually
## standing, up from _ready() onward and refreshed on arrival, cleared
## only at the genuine start of a walk; and a "target" radial
## (CityMapView.target_location/target_radial_open/target_actions,
## always exactly Lore+Travel) that opens on a click elsewhere and
## coexists on screen with the home radial. Checks both persist/clear
## at exactly the right moments, that the Space key fires Travel
## whenever the target radial is open (and is a safe no-op when it
## isn't), and that a distinct red focus-outline colour constant exists
## for the target radial's Travel entry.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "CityScreenTester"
	pc.characteristics.set_value("movement", 4)
	GameState.pending_city_id = "ubersreik"

	var cs = load("res://scenes/CityScreen.tscn").instantiate()
	tree.get_root().add_child(cs)
	for i in range(5):
		await tree.process_frame

	checks.append(["setup: CityScreen loaded a real location_list", cs.location_list != null])
	checks.append(["data: exactly 71 locations loaded", cs.location_list.locations.size() == 71])

	var unlocked_names := []
	for loc in cs.location_list.locations:
		if loc.unlocked:
			unlocked_names.append(loc.location_name)
	unlocked_names.sort()
	var expected := ["South Gate", "North Gate", "East Gate", "The High Temple of Sigmar", "The Red Moon Inn", "Watch Barracks", "Nordwander and Son's Expeditionary Supplies", "The Exploding Pig"]
	expected.sort()
	checks.append(["data: exactly the 8 requested locations start unlocked (%s)" % str(unlocked_names), unlocked_names == expected])

	## pending_city_id should have been consumed (read once, then reset)
	## by _ready() — a stale value would leak into whatever screen loads next.
	checks.append(["GameState.pending_city_id was consumed by _ready()", GameState.pending_city_id == ""])

	var south_gate: CityLocationDefinition = null
	for loc in cs.location_list.locations:
		if loc.location_id == 4:
			south_gate = loc
	checks.append(["setup: found South Gate (location_id 4) in the data", south_gate != null])
	if south_gate != null:
		checks.append(["party token starts at South Gate (the main road entrance)", cs.map_view.party_token_pos.distance_to(south_gate.map_position) < 0.001])
		## Follow-up request ("always show... trigger it after travel
		## finishes"): the home radial must be up from the very first
		## frame, not just after the first travel — _ready() calls
		## _refresh_home_radial() itself for exactly this reason.
		checks.append(["home radial: up immediately at _ready() for South Gate (where the party actually starts)", cs.map_view.home_location == south_gate])
		var initial_home_keys := []
		for a in cs.map_view.home_actions:
			initial_home_keys.append(a["key"])
		checks.append(["home radial: South Gate (a gate) offers Lore+Leave City from the very first frame (%s)" % str(initial_home_keys), initial_home_keys == ["lore", "leave_city"]])

	checks.append(["UI: party panel row has one panel per real party member", cs.party_panel_row.get_child_count() == GameState.party.size()])
	checks.append(["UI: time label shows a real HH:MM (not the placeholder)", cs.time_label.text != "--:--" and cs.time_label.text.length() == 5])
	## Follow-up request ("group the list by district"): title Label +
	## HSeparator + (1 district header + N location buttons) per
	## district represented among the unlocked locations. The 8 starter
	## locations now unlocked are South Gate/Walls, North Gate/Walls,
	## East Gate/Walls (all 3 gates share the Walls district — per the
	## follow-up "hook up POI North (1) and East (2) gate" request), Red
	## Moon Inn/Teubrucke, High Temple of Sigmar/Marktplatz, Watch
	## Barracks/The Precinct, Nordwander and Son's Expeditionary
	## Supplies/Dawihafen (City Shop follow-up), and — per the "add The
	## Exploding Pig as the 2nd Tavern" follow-up — The Exploding Pig/
	## Merchant Quarter: 6 distinct districts, Walls holding 3 locations
	## and the other 5 holding 1 each. Total = title(1) + sep(1) +
	## [Walls: 1 header + 3 buttons] + [5 other districts: (1 header + 1
	## button) each = 10] = 2 + 4 + 10 = 16. Follow-up request ("remove
	## that option from the legend list. the only way to leave Ubersreik
	## is now via the gates"): the trailing leave_sep/leave_btn pair that
	## used to add 2 more is gone — leaving is now a gate-only radial
	## action (see the "leave city (real gate action)" checks near the
	## end of this test).
	checks.append(["UI: legend list groups the 8 unlocked locations by district, no Leave button", cs.legend_list.get_child_count() == 16])

	## Follow-up request's own reported bug ("its not saving the city
	## still, i always enter the game outside the city on the overworld
	## map"): CityScreen._ready() should have marked this city as the
	## currently-active one — see GameState.last_active_city_id's own
	## declaration comment for the full story (this is what MainMenu's
	## Continue / CharacterMenu's Switch Character read to route back
	## into CityScreen instead of always defaulting to Overworld).
	checks.append(["GameState.last_active_city_id set to ubersreik on entry", GameState.last_active_city_id == "ubersreik"])

	## Follow-up request ("add The Exploding Pig as the 2nd Tavern... and
	## hook it up for access"): the existing dataset entry (location_id
	## 42, previously unlocked = false) is now unlocked, tavern-category,
	## and — since _radial_actions_for/_enter_tavern are both driven
	## purely by loc.category rather than any hand-picked name — needs no
	## further code changes to be a real, walkable second tavern. The
	## party hasn't walked to it in this test, so its own radial should
	## read exactly like any other not-yet-visited location: Lore+Travel.
	var exploding_pig: CityLocationDefinition = null
	for loc in cs.location_list.locations:
		if loc.location_id == 42:
			exploding_pig = loc
	checks.append(["setup: found The Exploding Pig (location_id 42) in the data, now unlocked", exploding_pig != null and exploding_pig.unlocked])
	if exploding_pig != null:
		checks.append(["data: The Exploding Pig is tavern-category", exploding_pig.category == "tavern"])
		var pig_actions: Array = cs._radial_actions_for(exploding_pig)
		var pig_keys := []
		for a in pig_actions:
			pig_keys.append(a["key"])
		checks.append(["radial (travel target): The Exploding Pig (party not there) offers Lore+Travel, same as any other tavern-category location the party hasn't reached yet (%s)" % str(pig_keys), pig_keys == ["lore", "travel"]])

	## Travel: click the Red Moon Inn marker (location 29) and confirm
	## the offer prompt shows a real distance/time estimate.
	var red_moon: CityLocationDefinition = null
	for loc in cs.location_list.locations:
		if loc.location_id == 29:
			red_moon = loc
	checks.append(["setup: found The Red Moon Inn (location_id 29) in the data", red_moon != null])

	if south_gate != null and red_moon != null:
		var time_before: int = GameState.time_minutes

		## Follow-up request ("left clicking a visible POI should not
		## trigger travel... select it, and show a radial menu... Lore...
		## and Travel"): clicking a marker now only selects it and opens
		## the radial menu — it must NOT jump straight to a travel offer
		## the way it used to.
		cs._on_location_clicked(red_moon)
		await tree.process_frame
		checks.append(["target radial: marker click opens the TARGET radial for that location, no travel offer yet", cs.map_view.target_location == red_moon and cs.map_view.target_radial_open and not cs.awaiting_travel_confirm])
		var target_keys := []
		for a in cs.map_view.target_actions:
			target_keys.append(a["key"])
		checks.append(["target radial: always exactly Lore+Travel (%s)" % str(target_keys), target_keys == ["lore", "travel"]])
		checks.append(["target radial: a distinct red focus-outline colour constant exists for its Travel entry", cs.map_view.RADIAL_FOCUS_OUTLINE_COLOR != cs.map_view.RADIAL_OUTLINE_COLOR])
		checks.append(["home radial: untouched by opening a target radial elsewhere (still South Gate)", cs.map_view.home_location == south_gate])

		## Lore button: shows real info about the clicked location without
		## starting a travel offer, dismissible without confirming/denying.
		cs._on_radial_action(red_moon, "lore")
		await tree.process_frame
		checks.append(["target radial: Lore opens a real info readout, not a travel offer", cs._lore_open and not cs.awaiting_travel_confirm])
		checks.append(["target radial: Lore text names the real location", cs.encounter_label.text.findn("Red Moon Inn") != -1])
		cs._close_lore()
		await tree.process_frame
		checks.append(["target radial: Lore closes cleanly (encounter box hidden again)", not cs._lore_open and not cs.encounter_box.visible])
		checks.append(["home radial: still untouched after Lore closes", cs.map_view.home_location == south_gate])

		## Deselect: clicking elsewhere on the map background clears only
		## the TARGET radial (re-select for the Travel check below); the
		## home radial is a completely separate piece of state and must
		## survive this untouched.
		cs._on_map_background_clicked(Vector2.ZERO)
		await tree.process_frame
		checks.append(["background click: clears only the target radial", cs.map_view.target_location == null and not cs.map_view.target_radial_open])
		checks.append(["background click: home radial persists through a target deselect", cs.map_view.home_location == south_gate])
		cs._on_location_clicked(red_moon)
		await tree.process_frame

		## Travel button: this is what actually starts the real
		## distance/time-costed offer now (marker click alone no longer
		## does).
		cs._on_radial_action(red_moon, "travel")
		await tree.process_frame
		checks.append(["travel offer: awaiting_travel_confirm is genuinely true after choosing Travel from the target radial", cs.awaiting_travel_confirm])
		checks.append(["travel offer: the TARGET radial itself closes once Travel is chosen", not cs.map_view.target_radial_open and cs.map_view.target_location == null])
		checks.append(["travel offer: the HOME radial stays up through the whole Y/N confirm — only clears once the walk genuinely starts", cs.map_view.home_location == south_gate])
		checks.append(["travel offer: the prompt names the real destination", cs.encounter_label.text.findn("Red Moon Inn") != -1])
		checks.append(["travel offer: the prompt shows a real yards estimate (not just the destination name)", cs.encounter_label.text.findn("yards") != -1])

		## Simulate the [Y] confirm the same way a real KEY_Y InputEventKey
		## would — setting the same two flags _unhandled_input's own Y
		## branch sets, since synthesizing/injecting a real InputEventKey
		## into an offscreen headless test is unreliable.
		cs._travel_confirmed = true
		cs.awaiting_travel_confirm = false
		## The offer coroutine (_offer_travel_to, still suspended on its
		## own `while awaiting_travel_confirm: await process_frame`) only
		## notices the flag flip — and only then kicks off _run_travel(),
		## which is what actually sets _travel_in_progress true — on ITS
		## own next process_frame. Wait for that transition to genuinely
		## happen before polling for it to end, or a fast scheduler could
		## see _travel_in_progress still at its default `false` and exit
		## the "wait for it to finish" loop below immediately.
		var started_frames := 0
		while not cs._travel_in_progress and started_frames < 60:
			await tree.process_frame
			started_frames += 1
		var settle := 0.0
		while cs._travel_in_progress and settle < 8.0:
			await tree.create_timer(0.05).timeout
			settle += 0.05
		## _run_travel() itself is still an in-flight coroutine at the
		## moment _travel_in_progress flips false — give it a couple more
		## frames to actually reach the GameState.advance_minutes()/
		## city_player_positions write at its own end before asserting.
		await tree.process_frame
		await tree.process_frame

		checks.append(["travel: the game clock genuinely advanced (real minutes cost)", GameState.time_minutes != time_before or GameState.day_of_year != WarhammerCalendar.CHARACTER_CREATION_START_DAY])
		checks.append(["travel: the party token actually arrived at the destination", cs.map_view.party_token_pos.distance_to(red_moon.map_position) < 0.01])
		checks.append(["travel: the new position was remembered for next time (city_player_positions)", GameState.city_player_positions.get("ubersreik", Vector2(-1, -1)).distance_to(red_moon.map_position) < 0.01])
		checks.append(["home radial: reappeared at the new destination (Red Moon Inn) once the walk actually finished", cs.map_view.home_location == red_moon])

		## Follow-up request ("show option at the location the player is
		## at, move stay/enter to this radial, remove these while
		## travelling — active POI target will still show Lore and
		## Travel"): now that the party has actually arrived at the Red
		## Moon Inn (a tavern), its OWN radial should offer Stay instead
		## of Travel; South Gate, which the party just left, is no longer
		## "here" so its radial should offer Travel instead of anything
		## tavern/shop-only.
		var here_actions: Array = cs._radial_actions_for(red_moon)
		var here_keys := []
		for a in here_actions:
			here_keys.append(a["key"])
		checks.append(["radial (current location): The Red Moon Inn (a tavern, party is standing on it) offers Lore+Stay, no Travel (%s)" % str(here_keys), here_keys == ["lore", "stay"]])

		var away_actions: Array = cs._radial_actions_for(south_gate)
		var away_keys := []
		for a in away_actions:
			away_keys.append(a["key"])
		checks.append(["radial (travel target): South Gate (party no longer there) offers Lore+Travel, no Stay/Enter (%s)" % str(away_keys), away_keys == ["lore", "travel"]])

		## Follow-up request ("have the shops (including future ones in
		## the city) close at 8pm and open at 8am, gray out the Enter
		## option and change it to Closed... show tool tip: Opening hours
		## 8am-8pm" — explicitly NOT taverns/inns): exercised end-to-end
		## against the real Nordwander and Son's location (location_id
		## 20, a real unlocked shop). Temporarily moves the party's own
		## token onto Nordwander's marker (bypassing a real walk —
		## _refresh_home_radial() only cares about party_token_pos, not
		## how it got there) and restores it back to Red Moon Inn (this
		## test's actual "current" location at this point) afterward, so
		## nothing downstream notices the detour.
		var nordwander: CityLocationDefinition = null
		for loc in cs.location_list.locations:
			if loc.location_id == 20:
				nordwander = loc
		checks.append(["setup: found Nordwander and Son's (location_id 20, the City Shop follow-up's own shop) in the data", nordwander != null])

		if nordwander != null:
			## _is_shop_open() boundary checks: open exactly at 08:00,
			## closed exactly at 20:00 (last real open minute is 19:59 —
			## "closes at 8pm" per plain English, not "closed starting
			## 8:01").
			GameState.time_minutes = 8 * 60
			checks.append(["shop hours: _is_shop_open() true at 08:00 (opens)", cs._is_shop_open()])
			GameState.time_minutes = 8 * 60 - 1
			checks.append(["shop hours: _is_shop_open() false at 07:59 (not yet open)", not cs._is_shop_open()])
			GameState.time_minutes = 20 * 60 - 1
			checks.append(["shop hours: _is_shop_open() true at 19:59 (still open)", cs._is_shop_open()])
			GameState.time_minutes = 20 * 60
			checks.append(["shop hours: _is_shop_open() false at 20:00 (closed)", not cs._is_shop_open()])

			## Move the party onto Nordwander's own marker and refresh the
			## home radial while the shop is closed (still 20:00 from above).
			var saved_party_pos: Vector2 = cs.map_view.party_token_pos
			cs.map_view.party_token_pos = nordwander.map_position
			cs._refresh_home_radial()
			await tree.process_frame
			var closed_entry: Dictionary = {}
			for a in cs.map_view.home_actions:
				if a["key"] == "enter_shop":
					closed_entry = a
			checks.append(["shop hours (closed): home radial swaps Enter for a disabled Closed entry with the right tooltip", closed_entry.get("label", "") == "Closed" and closed_entry.get("disabled", false) == true and closed_entry.get("tooltip", "") == "Opening hours 8am-8pm"])

			## CityMapView itself must actually refuse the click and
			## surface the tooltip on hover — not just CityScreen's own
			## action list.
			var closed_rect: Rect2 = cs.map_view._home_radial_rects.get("enter_shop", Rect2())
			checks.append(["shop hours (closed): CityMapView drew a real hit rect for the disabled button", closed_rect.size != Vector2.ZERO])
			var closed_center: Vector2 = closed_rect.get_center()
			checks.append(["shop hours (closed): CityMapView refuses to report a click on the disabled Closed button", cs.map_view._radial_hit_at(closed_center) == {}])
			checks.append(["shop hours (closed): CityMapView's own tooltip lookup returns the right text on hover", cs.map_view._radial_tooltip_at(closed_center) == "Opening hours 8am-8pm"])

			## The dispatcher's own defensive guard: even a direct call
			## with the shop closed must not actually enter it
			## (GameState.pending_shop_city_id is only ever set by
			## _enter_shop() — see that function's own comment).
			GameState.pending_shop_city_id = ""
			cs._on_radial_action(nordwander, "enter_shop")
			await tree.process_frame
			checks.append(["shop hours (closed): _on_radial_action's own guard refuses to enter a closed shop", GameState.pending_shop_city_id == ""])

			## Now during real opening hours: Enter is back, enabled, no
			## tooltip.
			GameState.time_minutes = 12 * 60
			cs._refresh_home_radial()
			await tree.process_frame
			var open_entry: Dictionary = {}
			for a in cs.map_view.home_actions:
				if a["key"] == "enter_shop":
					open_entry = a
			checks.append(["shop hours (open): home radial offers a real, enabled Enter button at midday", open_entry.get("label", "") == "Enter" and not open_entry.get("disabled", false) and open_entry.get("tooltip", "") == ""])

			## Restore the party to where the rest of this test still
			## expects it (Red Moon Inn) BEFORE the tavern check below —
			## _radial_actions_for()'s "here" branch (which is what
			## actually offers Stay) depends on the party's token really
			## being at the location being checked, and it's still
			## sitting on Nordwander's marker at this point.
			cs.map_view.party_token_pos = saved_party_pos
			cs._refresh_home_radial()
			await tree.process_frame

			## Follow-up's own explicit carve-out ("not the Taverns and
			## inns tho"): Red Moon Inn (a tavern) must still offer a
			## plain, always-enabled Stay regardless of the clock, even
			## at a time a shop would be shut (20:00) — proves Stay
			## really is untouched by the shop-hours gating.
			GameState.time_minutes = 20 * 60
			var tavern_actions: Array = cs._radial_actions_for(red_moon)
			var tavern_entry: Dictionary = {}
			for a in tavern_actions:
				if a["key"] == "stay":
					tavern_entry = a
			checks.append(["shop hours: taverns are explicitly untouched — Red Moon Inn's Stay stays plain and enabled even at 20:00", tavern_entry.get("label", "") == "Stay" and not tavern_entry.get("disabled", false)])

			## Restore a sane mid-afternoon clock so nothing downstream
			## (the Space hotkey/click-to-confirm/Leave City sections)
			## notices this detour.
			GameState.time_minutes = 14 * 60
			cs._refresh_home_radial()
			await tree.process_frame

		## Follow-up request ("always Auto focus (outline in red) and Space
		## hotkey the travel option when its available"): pressing Space
		## while a target radial is open fires Travel exactly like a real
		## click on it would — there's only one focusable entry (Travel)
		## since the target radial is always exactly Lore+Travel, so no
		## separate "which item is focused" state is needed. Synthesizes a
		## real InputEventKey and calls _unhandled_input() directly (same
		## approach this file already uses for open-market functions;
		## injecting a real event into an offscreen headless run is
		## unreliable) rather than setting internal flags, so the actual
		## input-handling wiring is what's under test.
		cs._on_location_clicked(south_gate)
		await tree.process_frame
		checks.append(["space hotkey: clicking South Gate (elsewhere, party is at Red Moon Inn) opens its target radial", cs.map_view.target_location == south_gate and cs.map_view.target_radial_open])
		var space_event := InputEventKey.new()
		space_event.pressed = true
		space_event.echo = false
		space_event.keycode = KEY_SPACE
		cs._unhandled_input(space_event)
		await tree.process_frame
		checks.append(["space hotkey: Space with a target radial open starts a real travel offer", cs.awaiting_travel_confirm and not cs.map_view.target_radial_open and cs.map_view.target_location == null])
		checks.append(["space hotkey: the offer it started names the real destination", cs.encounter_label.text.findn("South Gate") != -1])
		## Decline this one without walking — the click-to-confirm block
		## right below needs its own fresh South Gate offer to actually
		## complete the walk back.
		cs._travel_confirmed = false
		cs.awaiting_travel_confirm = false
		await tree.process_frame
		checks.append(["space hotkey (declined): home radial untouched — still Red Moon Inn, no walk was ever started", cs.map_view.home_location == red_moon])

		## Space with NO target radial open must be a safe no-op — no
		## crash, no false travel trigger.
		checks.append(["space hotkey: no target radial currently open (post-decline)", not cs.map_view.target_radial_open and cs.map_view.target_location == null])
		var space_event2 := InputEventKey.new()
		space_event2.pressed = true
		space_event2.echo = false
		space_event2.keycode = KEY_SPACE
		cs._unhandled_input(space_event2)
		await tree.process_frame
		checks.append(["space hotkey: no-op when no target radial is open", not cs.awaiting_travel_confirm])

		## Follow-up request ("allow user to click on travel confirmation
		## pop ups option"): walk back to South Gate, this time resolving
		## the Y/N confirm via a real click on confirm_yes_button (its
		## pressed signal) instead of setting the internal flags directly,
		## the way the Red Moon Inn confirm above did — proves the button
		## itself, not just the underlying flags, actually drives the
		## confirm.
		cs._on_location_clicked(south_gate)
		await tree.process_frame
		cs._on_radial_action(south_gate, "travel")
		await tree.process_frame
		checks.append(["click-to-confirm: travel offer to South Gate is up, choice row visible", cs.awaiting_travel_confirm and cs.confirm_choice_row.visible])

		## WASD-focus colour check ("make the focused WASD option white in
		## color to make it more distinct"): the Y (Go) side is focused by
		## default (_start_confirm_prompt always resets to yes-selected).
		checks.append(["confirm buttons: Yes starts focused (white)", cs.confirm_yes_button.get_theme_color("font_color") == cs.CONFIRM_FOCUSED_COLOR])
		checks.append(["confirm buttons: No starts unfocused (muted)", cs.confirm_no_button.get_theme_color("font_color") == cs.CONFIRM_UNFOCUSED_COLOR])
		## Simulate the same WASD toggle _unhandled_input's move_right/
		## move_down branch performs, then confirm the colours swap.
		cs._confirm_selected_yes = false
		cs._render_confirm_prompt()
		checks.append(["confirm buttons: focus colour swaps to No once WASD selects it", cs.confirm_no_button.get_theme_color("font_color") == cs.CONFIRM_FOCUSED_COLOR and cs.confirm_yes_button.get_theme_color("font_color") == cs.CONFIRM_UNFOCUSED_COLOR])
		## Put focus back on Yes before actually clicking it below, so the
		## click (not a leftover WASD state) is what's under test.
		cs._confirm_selected_yes = true
		cs._render_confirm_prompt()

		## Not checking _travel_confirmed here — _offer_travel_to's own
		## suspended coroutine consumes (resets) it the moment it wakes on
		## its next process_frame, which can easily happen before this
		## check runs; awaiting_travel_confirm flipping false is the
		## reliable, race-free signal that the click itself was what
		## resolved the wait (see the "started_frames2" wait below, which
		## is what actually proves the confirmed choice took effect).
		cs.confirm_yes_button.pressed.emit()
		checks.append(["click-to-confirm: clicking the Yes button itself resolved the confirm", not cs.awaiting_travel_confirm])

		## _travel_confirmed is consumed (and reset) by _offer_travel_to's
		## own coroutine the moment it wakes up — same "started_frames"
		## wait pattern as the Red Moon Inn travel above, so the walk
		## actually completes before this test moves on to Leave City.
		var started_frames2 := 0
		while not cs._travel_in_progress and started_frames2 < 60:
			await tree.process_frame
			started_frames2 += 1
		var settle2 := 0.0
		while cs._travel_in_progress and settle2 < 8.0:
			await tree.create_timer(0.05).timeout
			settle2 += 0.05
		await tree.process_frame
		await tree.process_frame
		checks.append(["click-to-confirm: the party actually walked back to South Gate", cs.map_view.party_token_pos.distance_to(south_gate.map_position) < 0.01])
		checks.append(["home radial: reappeared at South Gate once this second walk actually finished", cs.map_view.home_location == south_gate])

	## Follow-up request ("add a Leave City option to the north east and
	## south gates... the only way to leave Ubersreik is now via the
	## gates"): South Gate is real "here" (the party walked back to it
	## above), so its own radial should now offer Leave City instead of
	## Stay/Enter/Travel — exercised via the real radial action, not by
	## calling _offer_leave_city() directly, so the actual wiring
	## (_radial_actions_for + _on_radial_action's own "leave_city"
	## branch) is what's under test.
	if south_gate != null:
		var gate_actions: Array = cs._radial_actions_for(south_gate)
		var gate_keys := []
		for a in gate_actions:
			gate_keys.append(a["key"])
		checks.append(["radial (at a gate): South Gate offers Lore+Leave City, nothing else (%s)" % str(gate_keys), gate_keys == ["lore", "leave_city"]])

		cs._on_location_clicked(south_gate)
		await tree.process_frame
		cs._on_radial_action(south_gate, "leave_city")
		await tree.process_frame
		checks.append(["leave city offer: awaiting_travel_confirm true with the real prompt text", cs.awaiting_travel_confirm and cs.encounter_label.text.findn("open road") != -1])
		## Declined first — deliberately doesn't confirm here, since
		## confirming triggers a real change_scene_to_file() (see the
		## genuinely-confirmed version below, which is why THAT one has
		## to be the very last thing this whole test does).
		cs._travel_confirmed = false
		cs.awaiting_travel_confirm = false
		await tree.process_frame
		checks.append(["leave city offer (declined): still in the city, nothing cleared yet", GameState.last_active_city_id == "ubersreik"])

	## Every check above is computed and appended to `checks` first,
	## and printed/returned below BEFORE this final block runs — the
	## confirmed Leave City action is genuinely the last thing this test
	## does. change_scene_to_file() (inside _offer_leave_city()'s own
	## confirmed branch) frees whatever the engine considers this whole
	## test run's own current_scene, which — per this project's own
	## documented gotcha from the City Shop follow-up work — silently
	## kills any coroutine still running on it the moment a later
	## process_frame lets that deferred free actually happen. Reading
	## GameState state back immediately after the one process_frame that
	## lets the suspended _offer_leave_city() coroutine resume (with no
	## further awaits after) is what stays on the safe side of that.
	var confirm_checks: Array = []
	if south_gate != null:
		cs._on_location_clicked(south_gate)
		await tree.process_frame
		cs._on_radial_action(south_gate, "leave_city")
		await tree.process_frame
		cs._travel_confirmed = true
		cs.awaiting_travel_confirm = false

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false

	if south_gate != null:
		## This is the one await that actually lets _offer_leave_city()'s
		## suspended coroutine notice awaiting_travel_confirm == false
		## and run its whole confirmed branch (clearing
		## last_active_city_id/city_player_positions, then
		## change_scene_to_file()) — see the block comment above for why
		## nothing happens after this.
		await tree.process_frame
		confirm_checks.append(["leave city confirmed: GameState.last_active_city_id cleared", GameState.last_active_city_id == ""])
		confirm_checks.append(["leave city confirmed: this city's remembered position was erased", not GameState.city_player_positions.has("ubersreik")])
		for chk in confirm_checks:
			var label: String = chk[0]
			var passed: bool = chk[1]
			print(("PASS  " if passed else "FAIL  ") + label)
			if not passed:
				all_pass = false

	print("RESULT (City Screen): ", "ALL PASS (%d checks)" % (checks.size() + confirm_checks.size()) if all_pass else "SOME FAILED")
	return all_pass
