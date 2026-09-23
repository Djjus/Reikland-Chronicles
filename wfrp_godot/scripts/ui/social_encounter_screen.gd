extends Control
## Non-combat field encounter, per the request: a narrative exchange
## resolved with social Skills instead of combat rolls, presented with
## the same overall feel as FieldEncounter (a scrolling log of what
## happened, a Return button, action buttons on the left) but no
## initiative or turn order — the player always acts, immediately,
## against whatever the story currently presents.
##
## Per the follow-up request: the NPC's name/gender and the specific
## "situation" (the real secret/twist behind their behaviour) are
## randomized per playthrough — a Perception check on the marker
## (Overworld.gd) may have already locked these in via the
## GameState.pending_social_* fields; if not, they're rolled fresh
## here. Every text field in the SocialEncounterDefinition may contain
## {name}/{subj}/{subj_cap}/{obj}/{obj_cap}/{obj_lc}/{poss}/{poss_cap}
## /{situation_hook}/{opening_flavor} placeholders, substituted once
## via _substitute() before ever being shown.

@onready var title_label: Label = %TitleLabel
@onready var npc_name_label: Label = %NPCNameLabel
@onready var npc_portrait_rect: TextureRect = %NPCPortraitRect
@onready var npc_portrait_row: HBoxContainer = %NPCPortraitRow
@onready var rapport_label: Label = %RapportLabel
@onready var party_portraits_box: HFlowContainer = %PartyPortraitsBox
@onready var return_button: Button = %ReturnButton
@onready var action_container: VBoxContainer = %ActionContainer
@onready var history_list: VBoxContainer = %HistoryList
@onready var history_scroll: ScrollContainer = %HistoryScroll

## Per the request ("add window on the left side for turn order... let
## the top bar work more like the combat version of it, ie showing the
## current Attacker & Defender"): direct adaptation of FieldEncounter's
## own EnemyDisplayPanel/LeftCol turn-order layout (field_encounter_
## screen.gd's _build_combat_status_box/_refresh_enemy_display/
## _render_turn_order_panel) to Social Combat's own turn order/roster.
@onready var combat_top_row: HBoxContainer = %CombatTopRow
@onready var attacker_box_container: MarginContainer = %AttackerBoxContainer
@onready var defender_box_container: MarginContainer = %DefenderBoxContainer
@onready var vs_round_label: Label = %VsRoundLabel
@onready var vs_sl_box: HBoxContainer = %VsSlBox
@onready var turn_order_section: VBoxContainer = %TurnOrderSection
@onready var turn_order_list: VBoxContainer = %TurnOrderList

## Per the request ("NPC portraits... top bar showing PC/NPC
## portraits"): the party's own faces, same CareerPortraits art already
## shown everywhere else a party member's face appears. A fallback
## sprite for the Village Elder's own hand-authored story NPC, who
## isn't a SocialEncounterDefinition at all and so has no
## portrait_career_key to read.
const ELDER_PORTRAIT_PATH := "res://assets/sprites/npc_elder.png"
const PORTRAIT_BOX_WIDTH := 56

var encounter_def: SocialEncounterDefinition
var player: Character
var encounter_over: bool = false
var history: Array = []   ## newest at index 0 — [{"cards": [card_data,...], "notice": String}, ...], matching FieldEncounter's own convention
const MAX_HISTORY_ENTRIES := 30

var name_info: NPCNameGenerator.NameInfo
var chosen_situation: Dictionary = {}

## Per the request: each party member can lend a one-time +10 Assist
## bonus to a Skill Test made by someone else during this encounter —
## tracked here (character identity, not name, since two party members
## could in principle share a name) so someone who's already assisted
## once can't do it again later in the same encounter. A real, spendable
## resource, not a free bonus available on every single roll. Reset at
## the top of _start_encounter() along with everything else per-encounter.
var used_assistants: Array[Character] = []

## --- Social Combat state (Design Doc "Social Combat — Design Doc v1",
## Slice 1: Composure pools, the 4 Attack Types, turn order, win/lose by
## Composure, Fortune/Dark Deal on every roll — NOT the Rapport Pool,
## Maneuvers, or Conditions, which are Slices 2-3). Rebuilt fresh every
## _start_encounter() call, same as every other per-encounter field
## above. Only used for a real SocialEncounterDefinition exchange, never
## for the hand-authored Village Elder story (_start_elder_story returns
## before any of this runs).
var npc_characters: Array[Character] = []           ## the live roster, built from encounter_def.get_npcs()
var npc_portrait_key: Dictionary = {}                ## Character (adversary) -> String portrait key
var npc_status_ordinal_by_char: Dictionary = {}      ## Character (adversary) -> int (1/2/3, Brass/Silver/Gold), from SocialCombatNPCDefinition.get_status_ordinal()
var npc_etiquette_group_by_char: Dictionary = {}     ## Character (adversary) -> String (one of Etiquette's 7 groups, or "" for no match), from SocialCombatNPCDefinition.get_etiquette_group()
var npc_career_tier_by_char: Dictionary = {}         ## Character (adversary) -> int (1-4), from SocialCombatNPCDefinition.get_career_tier_level() — the Career Level its own Status derives from

## Per the request ("social encounter social armor should work by
## comparing attacker vs defender status... rather then be a fixed
## bonus"): Social Armor against a given attack is now
## max(0, npc_status - attacker_status) * ARMOR_PER_STATUS_STEP —
## a Status-equal-or-lower NPC gives 0 armor; a Brass party member vs a
## Gold NPC (the max possible gap, 2 steps) faces 4. Needle still
## bypasses Social Armor entirely regardless of this value (unchanged —
## see SocialCombatResolver.finalize_party_attack()).
const ARMOR_PER_STATUS_STEP := 2
var party_portrait_rects: Dictionary = {}            ## Character (ally) -> TextureRect, so knocked-out allies can be dimmed
var party_composure_bars: Dictionary = {}            ## Character (ally) -> ProgressBar
var party_status_labels: Dictionary = {}             ## Character (ally) -> Label, Slice 3's own condition tags (Flustered/Humiliated/Exposed)
var social_combat: SocialCombatEncounter = null
var active_social_combatant: Character = null
var selected_npc_target: Character = null            ## which living NPC the active party member is about to attack

## Per the request ("top bar work more like the combat version... showing
## the current Attacker & Defender"): who the Defender box shows during an
## NPC's own Turn — set by _run_npc_turn() the moment its target is
## chosen, mirroring FieldEncounter's own enemy_attack_focus_target. Reset
## to null at the top of every new Turn (_advance_social_combat_turn), so
## a stale NPC-turn target never lingers into the next party member's own
## Turn (whose Defender is selected_npc_target instead — see
## _current_social_defender()).
var _current_npc_turn_target: Character = null
## Per the request ("floating test SL outcome"): the same identity-gated
## chip cache FieldEncounter's own _last_opposed_sl_result is — only
## rendered by _refresh_attacker_defender_display() while it still
## matches the CURRENT Attacker/Defender pair (see that function).
var _last_social_opposed_result: Dictionary = {}

## --- Slice 2: Rapport Pool + Tactical Maneuvers (Design Doc Sections
## 3 and 7). The pool itself lives on social_combat.rapport_pool; these
## two Dictionaries are one-shot/round-scoped effects a Maneuver leaves
## behind for _run_npc_turn()/_attempt_social_attack() to notice later,
## the same "flag the state, let the normal turn logic read it" pattern
## Conditions themselves will use in Slice 3.
var distracted_npcs: Dictionary = {}          ## Character (adversary) -> bool, one-shot: redirect this NPC's next attack
var overwhelmed_until_round: Dictionary = {}  ## Character (adversary) -> int round_number: Social Armor reads as 0 through the end of that round

## Per the request ("it would be nice the conversation would evolve with
## each roll"): how many of this NPC's own encounter_def.npc_reaction_
## lines have already been shown — see _maybe_show_npc_reaction().
## Character (adversary) -> int.
var _npc_reactions_shown: Dictionary = {}

## Per the follow-up request ("NPC reaction lines only fire on your
## hits"): encounter_def.npc_reaction_lines is written per-persona and
## keyed to THIS NPC's own Composure actually dropping (see
## _maybe_show_npc_reaction() above), so it can't cover a party miss/tie
## or the NPC's own attack landing without new per-encounter content for
## all 12 encounters. These three dictionaries (Character (adversary) ->
## bool) instead gate a small pool of GENERIC, persona-agnostic quoted
## lines — see GENERIC_MISS_REACTION_LINES / GENERIC_TIE_REACTION_LINES /
## GENERIC_NPC_HIT_REACTION_LINES below — each firing at most once per
## NPC per encounter, the same "show it once" throttling
## _npc_reactions_shown already uses, so the conversation reacts to a
## resisted attack, a dead-even exchange, and the NPC's own hits landing
## on the party, not just the party's own hits.
var _npc_miss_reaction_shown: Dictionary = {}
var _npc_tie_reaction_shown: Dictionary = {}
var _npc_hit_reaction_shown: Dictionary = {}
var _npc_attack_miss_reaction_shown: Dictionary = {}

## Generic (not persona-specific) in-character lines an NPC might say
## after successfully resisting a party attack, after a dead-even
## exchange, or right after their own attack lands on a party member —
## picked at random, shown at most once per NPC per encounter (see the
## three Dictionaries just above). Deliberately tone-neutral so the same
## pool reads plausibly for every NPC persona in the game (peddler,
## watchman, priest, and so on).
const GENERIC_MISS_REACTION_LINES := [
	"You'll have to try harder than that.",
	"Nice try.",
	"Is that really the best you've got?",
	"That's not going to work on me.",
	"Try again.",
]
const GENERIC_TIE_REACTION_LINES := [
	"We could go round and round like this all day.",
	"Neither of us is getting anywhere.",
	"Stalemate, is it?",
	"You're as stubborn as I am.",
]
const GENERIC_NPC_HIT_REACTION_LINES := [
	"There. Now we understand each other.",
	"Didn't expect that, did you?",
	"That got through, didn't it.",
	"Careful, now.",
]
## Distinct from GENERIC_MISS_REACTION_LINES above: those are said BY the
## NPC after resisting a party attack, so they read as a taunt. These are
## said by the NPC after their OWN attack fails to land — an admission,
## not a taunt — so the wording has to run the other way.
const GENERIC_NPC_ATTACK_MISS_REACTION_LINES := [
	"Hmph. Not this time.",
	"You're quicker than you look.",
	"Lucky. That's all that was.",
	"Don't get used to it.",
]

## --- Slice 3: Humiliated/Exposed (Design Doc Section 5) and NPC
## momentum (Section 6, "the NPC's own version of Rapport" — its own
## +10-per-point bonus to ITS OWN attack rolls, per-NPC rather than
## party-wide). Flustered itself was already pulled forward into Slice
## 2 for Bring in the Muscle's payoff; this finishes wiring it onto
## Intimidate too (the design doc's Attack matrix calls this
## "Demoralised" for Intimidate specifically, but Section 5 never
## defines a separate "Demoralised" condition alongside Flustered/
## Humiliated/Exposed — treated here as the same drafting slip, wired
## to the same Flustered condition already fully implemented).
var npc_momentum: Dictionary = {}   ## Character (adversary) -> int, capped at 5 (this project's own judgment call — the design doc never states a cap, and an ever-growing bonus with no ceiling would eventually make a long fight unwinnable if Reason is never trained)

## Per the request: Fortune spend and Dark Deal, same mechanics
## FieldEncounter's own combat already offers — see _offer_fortune_spend
## for the full rules. _fortune_chain_active tells "a fresh roll's first
## Fortune prompt" apart from "the same reroll chain calling back in
## after a reroll," same convention as FieldEncounter's own copy of
## these three fields.
var _reroll_used_this_fortune_chain := false
var _dark_deal_used_this_fortune_chain := false
var _fortune_chain_active := false

## Fields _offer_fortune_spend's own button callbacks write to and its
## `while` wait-loop reads — MUST be script-level (member) fields, not
## locals, or the wait-loop hangs forever (see the long comment on
## _offer_fortune_spend itself for the confirmed GDScript closure bug
## this works around).
var _awaiting_fortune_choice := false
var _pending_fortune_choice_str := ""

func _ready() -> void:
	return_button.pressed.connect(_on_return_pressed)
	return_button.disabled = true
	return_button.visible = false
	## Per the request: same fix as field_encounter_screen.gd's own
	## copy — sort_children fires exactly when the log's layout has
	## genuinely finished changing.
	history_list.sort_children.connect(_do_scroll_history_to_bottom)
	_setup_wasd_navigation()
	_start_encounter()

## Per the request ("top bar showing PC/NPC portraits"): one small
## portrait per present party member, mirroring field_encounter_screen.
## gd's own _player_portrait_for()/wound_modulate_for_character()
## pattern exactly. Built once at screen open — the party doesn't
## change mid-encounter (no combat, no fleeing) so this never needs to
## be rebuilt like FieldEncounter's own player display does.
## Per the request ("top bar showing PC/NPC portraits") plus the Social
## Combat follow-up ("more like the field encounter screen"): each
## portrait now sits above a small Composure bar (Design Doc Section 10 —
## "each party portrait also gets the same small Composure bar
## underneath"). The bar itself starts hidden — Composure isn't computed
## until _start_social_combat() actually begins an exchange, so the
## Village Elder's own story (which calls this same function but never
## enters Social Combat) never shows one at all.
func _build_party_portraits() -> void:
	for child in party_portraits_box.get_children():
		child.queue_free()
	party_portrait_rects.clear()
	party_composure_bars.clear()
	party_status_labels.clear()
	for member: Character in GameState.party:
		if member.wounds_current <= 0:
			continue   ## an unconscious/dead member isn't "at the table" for a social encounter
		var vbox := VBoxContainer.new()
		vbox.custom_minimum_size = Vector2(PORTRAIT_BOX_WIDTH, 0)
		vbox.add_theme_constant_override("separation", 2)
		var portrait := TextureRect.new()
		portrait.texture = CareerPortraits.get_portrait_for_character(member)
		portrait.modulate = CareerPortraits.wound_modulate_for_character(member)
		portrait.custom_minimum_size = Vector2(PORTRAIT_BOX_WIDTH, 0)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.tooltip_text = member.character_name
		vbox.add_child(portrait)
		var bar := _build_composure_bar(member)
		bar.visible = false
		vbox.add_child(bar)
		## Slice 3: a small tag row for Flustered/Humiliated/Exposed, kept
		## live by _refresh_roster_bars() — otherwise a player has no
		## visual indicator of these conditions beyond the log text.
		var status_lbl := Label.new()
		status_lbl.text = ""
		status_lbl.add_theme_font_size_override("font_size", 8)
		status_lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 0.3))
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(status_lbl)
		party_portrait_rects[member] = portrait
		party_composure_bars[member] = bar
		party_status_labels[member] = status_lbl
		party_portraits_box.add_child(vbox)

## Composure bar, built once (both for a party member's own portrait
## column and for an NPC roster mini-panel) and kept live via
## _restyle_bar(). Deliberately blue/purple-toned rather than the
## green/amber/red HP bars use elsewhere (field_encounter_screen.gd,
## camp_screen.gd, etc.) — Composure is a different pool from Wounds and
## shouldn't read as "this character is dying" at a glance.
func _build_composure_bar(character: Character) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.6, 0.55, 0.4)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)
	_restyle_bar(bar, character.composure_current, character.composure_max)
	return bar

## Updates one Composure bar's value and fill color from a Character's
## current/max — the "recolor as it drains" behaviour mirrors the HP
## bars elsewhere in the project, just in Composure's own blue/amber/
## magenta palette rather than green/amber/red.
func _restyle_bar(bar: ProgressBar, current: int, max_value: int) -> void:
	bar.max_value = maxi(max_value, 1)
	bar.value = current
	var pct: float = float(current) / float(maxi(max_value, 1))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.4, 0.55, 0.85) if pct > 0.5 else (Color(0.8, 0.65, 0.25) if pct > 0.25 else Color(0.75, 0.25, 0.55))
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)

## Per the request ("allow WASD and Space to confirm control in social
## encounters"): WASD moves keyboard focus between whatever buttons/
## toggles are currently on offer (skill choices, Assist checkboxes,
## Roll, Back, Fortune options, Continue, Return); Space activates
## whichever one is focused. Leans on Godot's own built-in Control
## focus-neighbor system, driven by the "ui_up"/"ui_down"/"ui_left"/
## "ui_right"/"ui_accept" actions a focused Button/CheckButton already
## responds to — no hand-rolled spatial logic needed. Space is left
## untouched (already bound to ui_accept by Godot's own default, and
## this screen has no competing Enter-based hotkey system the way
## FieldEncounter does, so there's no swap to make here).
## Scoped to only this screen: events added here, removed in
## _exit_tree(), exactly mirroring field_encounter_screen.gd's own
## _setup_wasd_navigation()/_exit_tree() pair (see that file's long
## comment for why precisely undoing only these specific events —
## rather than a wholesale InputMap reload — matters).
var _wasd_nav_up_event: InputEventKey = null
var _wasd_nav_down_event: InputEventKey = null
var _wasd_nav_left_event: InputEventKey = null
var _wasd_nav_right_event: InputEventKey = null

func _setup_wasd_navigation() -> void:
	_wasd_nav_up_event = InputEventKey.new()
	_wasd_nav_up_event.keycode = KEY_W
	InputMap.action_add_event("ui_up", _wasd_nav_up_event)
	_wasd_nav_down_event = InputEventKey.new()
	_wasd_nav_down_event.keycode = KEY_S
	InputMap.action_add_event("ui_down", _wasd_nav_down_event)
	_wasd_nav_left_event = InputEventKey.new()
	_wasd_nav_left_event.keycode = KEY_A
	InputMap.action_add_event("ui_left", _wasd_nav_left_event)
	_wasd_nav_right_event = InputEventKey.new()
	_wasd_nav_right_event.keycode = KEY_D
	InputMap.action_add_event("ui_right", _wasd_nav_right_event)

func _exit_tree() -> void:
	if _wasd_nav_up_event != null:
		InputMap.action_erase_event("ui_up", _wasd_nav_up_event)
	if _wasd_nav_down_event != null:
		InputMap.action_erase_event("ui_down", _wasd_nav_down_event)
	if _wasd_nav_left_event != null:
		InputMap.action_erase_event("ui_left", _wasd_nav_left_event)
	if _wasd_nav_right_event != null:
		InputMap.action_erase_event("ui_right", _wasd_nav_right_event)

## First focusable, enabled Button (or subclass — CheckButton,
## OptionButton, etc.) found (depth-first) under `node`, visible or
## not — used to give WASD navigation somewhere to start from, and as
## the fallback default whenever no "Continue" button is on offer (see
## _auto_focus_default_button). Mirrors field_encounter_screen.gd's own
## _find_first_focusable().
func _find_first_focusable(node: Node) -> Control:
	if node is Button and (node as Control).visible and not (node as BaseButton).disabled:
		return node
	for child in node.get_children():
		var found := _find_first_focusable(child)
		if found != null:
			return found
	return null

## Per the follow-up request ("make all continue buttons in combat and
## social encounters always automatically be the WASD focus... so the
## user can just press Space to Continue"): same exact button found by
## _find_first_focusable, but restricted to one carrying literal
## "Continue" text — used first by _auto_focus_default_button so a
## Continue option (when one is on offer, e.g. the Fortune-spend
## prompt) always wins the default focus over "Spend Fortune"/other
## options that happen to render before it.
func _find_continue_button(node: Node) -> Control:
	if node is Button and (node as Control).visible and not (node as BaseButton).disabled and (node as Button).text == "Continue":
		return node
	for child in node.get_children():
		var found := _find_continue_button(child)
		if found != null:
			return found
	return null

## A disabled button still defaults to focus_mode FOCUS_ALL in Godot,
## which would let WASD navigation land on (and Space "activate") a
## visibly greyed-out control. Setting a disabled button's focus_mode
## to FOCUS_NONE removes it from Godot's own built-in focus-neighbor
## search entirely. Mirrors field_encounter_screen.gd's own
## _refresh_focus_for_disabled_buttons().
func _refresh_focus_for_disabled_buttons(node: Node) -> void:
	if node is BaseButton:
		var btn := node as BaseButton
		btn.focus_mode = Control.FOCUS_NONE if btn.disabled else Control.FOCUS_ALL
	for child in node.get_children():
		_refresh_focus_for_disabled_buttons(child)

## Called at the end of every function that (re)builds the action menu
## (or reveals the Return button), so WASD/Space always has a sensible
## default to start from without needing a first, wasted WASD press.
## Prefers a "Continue" button when one is currently on offer — same
## convention field_encounter_screen.gd's own
## _active_primary_hotkey_button/_auto_focus_default_button already use
## for every one of its own Continue prompts — falling back to the
## first focusable button otherwise (skill choices, Roll, Back,
## Return, etc., none of which are ever named "Continue").
func _auto_focus_default_button() -> void:
	if get_viewport() == null:
		return
	var target := _find_continue_button(self)
	if target == null:
		target = _find_first_focusable(self)
	if target != null:
		target.grab_focus()

func _start_encounter() -> void:
	GameState.ensure_player_character()
	player = GameState.player_character
	## Must run AFTER ensure_player_character() — on a genuinely fresh
	## session GameState.party is empty until that call seeds it, so
	## building the portrait row any earlier (e.g. from _ready()
	## directly) would silently show zero portraits.
	_build_party_portraits()
	encounter_over = false
	history.clear()
	used_assistants.clear()
	_reroll_used_this_fortune_chain = false
	_dark_deal_used_this_fortune_chain = false
	_fortune_chain_active = false
	## Social Combat state, reset every time this screen starts a fresh
	## encounter — see the field block above _on_return_pressed for what
	## each of these means. Restoring the single-portrait row's default
	## visibility here too, since a previous Social Combat exchange on
	## this same screen instance (Return -> another social encounter
	## without ever leaving the scene, if that ever becomes possible)
	## would otherwise leave the roster row shown and the single row
	## hidden for whatever comes next.
	npc_portrait_row.visible = true
	combat_top_row.visible = false
	turn_order_section.visible = false
	npc_characters.clear()
	npc_portrait_key.clear()
	npc_status_ordinal_by_char.clear()
	npc_etiquette_group_by_char.clear()
	npc_career_tier_by_char.clear()
	social_combat = null
	active_social_combatant = null
	selected_npc_target = null
	_current_npc_turn_target = null
	_last_social_opposed_result = {}
	distracted_npcs.clear()
	overwhelmed_until_round.clear()
	npc_momentum.clear()
	if is_instance_valid(rapport_label):
		rapport_label.visible = false
	## Slice 3's three Conditions (Flustered/Humiliated/Exposed) are
	## ordinary entries in the real, persistent Character.conditions
	## dictionary (Design Doc Section 5) — meaningless outside a Social
	## Combat exchange, but if a previous encounter ended (or was
	## interrupted) while a party member was still carrying one, it
	## would otherwise incorrectly carry over and fire again here. NPCs
	## never need this — they're built fresh via to_character() every
	## encounter and start with an empty conditions dict.
	for member in GameState.party:
		member.remove_condition("Flustered")
		member.remove_condition("Humiliated")
		member.remove_condition("Exposed")

	## Per the request: a hand-written story sequence for the Village
	## Elder's own quest chain, entirely separate from the random
	## SocialEncounterDefinition system below — checked first, and
	## returns immediately, since it has nothing to do with rounds,
	## situations, or the normal win/lose resolution at all.
	if GameState.pending_elder_encounter:
		GameState.pending_elder_encounter = false
		_start_elder_story()
		return

	## Per the request: a successful Perception check on the marker
	## already revealed which encounter this is (and who/what it
	## involves) — use those exact choices rather than rolling fresh,
	## potentially different ones.
	if GameState.pending_social_encounter_name != "":
		encounter_def = GameData.social_encounter_db.find_by_name(GameState.pending_social_encounter_name)
	if encounter_def == null:
		encounter_def = GameData.social_encounter_db.random_encounter()
	if encounter_def == null:
		## No encounters defined — the safest failure is to just return
		## to the Overworld rather than show a broken, empty screen.
		_on_return_pressed()
		return

	if GameState.pending_social_npc_name != "":
		name_info = NPCNameGenerator.NameInfo.new()
		name_info.full_name = GameState.pending_social_npc_name
		name_info.gender = GameState.pending_social_npc_gender
		if name_info.gender == "male":
			name_info.pronoun_subj = "he"; name_info.pronoun_obj = "him"; name_info.pronoun_poss = "his"
		else:
			name_info.pronoun_subj = "she"; name_info.pronoun_obj = "her"; name_info.pronoun_poss = "her"
	else:
		name_info = NPCNameGenerator.random_name()

	var situation_index := GameState.pending_social_situation_index
	if situation_index < 0 or situation_index >= encounter_def.situations.size():
		situation_index = randi() % encounter_def.situations.size() if not encounter_def.situations.is_empty() else -1
	chosen_situation = encounter_def.situations[situation_index] if situation_index >= 0 else {}

	var flavor_index := GameState.pending_social_opening_flavor_index
	if flavor_index < 0 or flavor_index >= encounter_def.opening_flavors.size():
		flavor_index = randi() % encounter_def.opening_flavors.size() if not encounter_def.opening_flavors.is_empty() else -1
	var opening_flavor: String = encounter_def.opening_flavors[flavor_index] if flavor_index >= 0 else ""

	GameState.pending_social_encounter_name = ""
	GameState.pending_social_npc_name = ""
	GameState.pending_social_npc_gender = ""
	GameState.pending_social_situation_index = -1
	GameState.pending_social_opening_flavor_index = -1

	title_label.text = encounter_def.encounter_name
	npc_name_label.text = "with %s" % name_info.full_name
	## get_portrait() (unlike get_portrait_for_character()) returns null
	## rather than falling back on an empty/unmatched key — fall back to
	## the same generic portrait every other screen already uses so a
	## future encounter added without art doesn't show a blank box.
	## Per the request ("wire it up to the Social NPCs too"): this NPC's
	## own rolled/forced gender (name_info.gender, already driving their
	## name and pronouns above) picks which of CareerPortraits' two art
	## sets their face comes from too.
	var npc_tex: Texture2D = CareerPortraits.get_portrait(encounter_def.portrait_career_key, name_info.gender)
	if npc_tex == null:
		npc_tex = load(CareerPortraits.FALLBACK_PATH) as Texture2D
	npc_portrait_rect.texture = npc_tex
	player.progress_task_find_encounter(encounter_def.encounter_name)
	_add_notice(_substitute(encounter_def.intro_text, opening_flavor))
	_start_social_combat()

## Fills in every placeholder this project's social encounters use.
## opening_flavor is passed separately since it's only ever relevant
## to intro_text (every other field only ever needs the name/pronoun/
## situation tokens).
## Per the request: the Village Elder's own 3-stage quest chain,
## walked through here directly rather than through the normal
## situation/round system — every branch below leads to a real
## story beat and, where relevant, real quest progression, but never
## to a fight or a "nothing happens" failure. The two Skill Tests in
## Stage 1 are flavour only, per the request's own "won't let the
## quest fail" — both branches lead to the exact same request for
## help, only the text differs.
func _start_elder_story() -> void:
	title_label.text = "The Village Elder"
	npc_name_label.text = "with %s, of %s" % [ElderStory.ELDER_NAME, ElderStory.VILLAGE_NAME]
	## The Elder is a hand-authored story NPC, not a
	## SocialEncounterDefinition, so there's no portrait_career_key to
	## read — a dedicated sprite already exists for him specifically.
	npc_portrait_rect.texture = load(ELDER_PORTRAIT_PATH) as Texture2D

	var q: Dictionary = player.get_elder_quest()

	if q.is_empty():
		_add_notice(ElderStory.STAGE_1_INTRO)
		_add_notice(ElderStory.STAGE_1_CHARM_PROMPT)
		var charm_def: SkillDefinition = GameData.skill_db.find_by_name("Charm")
		if charm_def != null:
			var result := TestResolver.resolve_skill_test(player, charm_def)
			var card_data := {
				"character_name": player.character_name, "title": "Charm", "subtitle": "Skill Test",
				"side": "ally", "test": result, "effects": (["Succeeded"] if result.success else ["Failed"]) as Array[String],
			}
			_add_history_entry([card_data], "")
			_add_notice(ElderStory.STAGE_1_CHARM_SUCCESS if result.success else ElderStory.STAGE_1_CHARM_FAIL)
		_add_notice(ElderStory.STAGE_1_REQUEST)
		player.start_elder_quest()
		GameState.autosave()
		_finish(true)
		return

	if q.get("status", "") == "Completed":
		_add_notice(ElderStory.POST_COMPLETION)
		_finish(true)
		return

	var stage: int = int(q.get("elder_stage", 1))
	var ready: bool = bool(q.get("elder_stage_ready", false))

	if stage == 1:
		if ready:
			_add_notice(ElderStory.STAGE_2_TRANSITION)
			player.advance_elder_quest_stage()
			GameState.autosave()
		else:
			_add_notice(ElderStory.STAGE_1_NOT_READY)
			var progress := int(q.get("elder_kill_progress", 0))
			_add_notice("[color=#8a7a6a](%d / 8 culled so far.)[/color]" % progress)
	elif stage == 2:
		if ready:
			_add_notice(ElderStory.STAGE_3_TRANSITION)
			player.advance_elder_quest_stage()
			GameState.autosave()
		else:
			_add_notice(ElderStory.STAGE_2_NOT_READY)
			var progress := int(q.get("elder_help_progress", 0))
			_add_notice("[color=#8a7a6a](%d / 4 helped so far.)[/color]" % progress)
	elif stage == 3:
		if player.inventory.has("Stolen Idol"):
			player.inventory.erase("Stolen Idol")
			player.gold_crowns += 10
			player.complete_elder_quest()
			GameState.autosave()
			_add_notice(ElderStory.RESOLUTION)
			_add_notice("[b][color=lightgreen]★ Resolved![/color][/b] You gained 10 GC.")
		else:
			_add_notice(ElderStory.STAGE_3_NOT_READY)

	_finish(true)

func _substitute(text: String, opening_flavor: String = "") -> String:
	var result := text
	## Per a real bug found while adding new encounter content: these
	## two get substituted in FIRST now, not last — an opening_flavor
	## or situation hook can itself contain a pronoun placeholder (e.g.
	## "{subj_cap} keeps perfect pace with you..."), and the pronoun
	## substitution below needs to run on the COMBINED text to catch
	## it, or it leaks through to the player unsubstituted.
	result = result.replace("{situation_hook}", str(chosen_situation.get("hook", "")))
	result = result.replace("{opening_flavor}", opening_flavor)
	result = result.replace("{name}", name_info.full_name)
	result = result.replace("{subj_cap}", name_info.pronoun_subj.capitalize())
	result = result.replace("{subj}", name_info.pronoun_subj)
	result = result.replace("{obj_cap}", name_info.pronoun_obj.capitalize())
	result = result.replace("{obj_lc}", name_info.pronoun_obj)
	result = result.replace("{obj}", name_info.pronoun_obj)
	result = result.replace("{poss_cap}", name_info.pronoun_poss.capitalize())
	result = result.replace("{poss}", name_info.pronoun_poss)
	return result

## --- Social Combat (Design Doc "Social Combat — Design Doc v1", Slice
## 1) replaces the old flat round1/round2 skill-choice list entirely for
## every real SocialEncounterDefinition exchange — a turn-based,
## multi-round exchange between the whole present party and every NPC
## on the roster, resolved by Composure rather than a single Skill Test.
## The Village Elder's own hand-authored story (_start_elder_story) never
## reaches any of this.

## Builds the live NPC roster from encounter_def.get_npcs() — a real
## Character per entry (SocialCombatNPCDefinition.to_character(), same
## "build a real Character on demand" pattern MonsterDefinition.to_
## character() already uses) — and the side-table Dictionary the screen
## itself needs but Character has no field for (which portrait key).
## The first entry reuses `name_info` (already rolled/locked-in above,
## and what {name}/{subj}/etc. substitution in the encounter's own text
## refers to) for BOTH its name and gender — its portrait must agree
## with the pronouns the story text already committed to. Any further
## entries in a group encounter get their own freshly-rolled name and
## gender (or npc_def's own hand-set gender/npc_display_name, if set —
## see that resource's own field comments), feeding
## CareerPortraits.get_portrait_for_character() via Character.gender
## (set inside to_character() below) per the request ("wire it up to
## the Social NPCs too").
func _build_npc_roster() -> void:
	npc_characters.clear()
	npc_portrait_key.clear()
	npc_status_ordinal_by_char.clear()
	npc_etiquette_group_by_char.clear()
	npc_career_tier_by_char.clear()
	var npc_defs := encounter_def.get_npcs()
	for i in range(npc_defs.size()):
		var npc_def: SocialCombatNPCDefinition = npc_defs[i]
		var display_name: String = npc_def.npc_display_name
		var npc_gender: String = name_info.gender
		if i > 0:
			npc_gender = npc_def.gender
			if npc_gender == "":
				var rolled := NPCNameGenerator.random_name()
				npc_gender = rolled.gender
				if display_name == "":
					display_name = rolled.full_name
		if display_name == "":
			display_name = name_info.full_name if i == 0 else NPCNameGenerator.random_name().full_name
		var npc_char := npc_def.to_character(display_name, npc_gender)
		## Per the request ("we have difficulty level in combat, let's
		## add it to social encounters too... all encounters should
		## have the same modifiers"): the same map-based Difficulty
		## Tier system field encounters already use, applied identically
		## to every NPC in every encounter — no per-encounter tuning.
		## See DifficultyTiers.apply_social_npc_tier_bonus()'s own
		## comment for why Composure gets a smaller table than the
		## Characteristics. Social Armor is no longer part of that
		## function at all — see get_status_ordinal()'s own comment on
		## SocialCombatNPCDefinition for why the Tier's whole effect on
		## Social Armor now flows through this NPC's real Career/Status
		## instead of a flat bonus number.
		DifficultyTiers.apply_social_npc_tier_bonus(npc_char, GameState.current_social_difficulty_tier)
		npc_characters.append(npc_char)
		npc_portrait_key[npc_char] = npc_def.portrait_career_key
		npc_status_ordinal_by_char[npc_char] = npc_def.get_status_ordinal(GameState.current_social_difficulty_tier)
		npc_etiquette_group_by_char[npc_char] = npc_def.get_etiquette_group()
		npc_career_tier_by_char[npc_char] = npc_def.get_career_tier_level(GameState.current_social_difficulty_tier)

## Composure's own formula (Design Doc Section 1): Willpower + Cool
## SKILL value (not raw Willpower alone) — computed fresh here, once per
## encounter, since Composure isn't persisted on Character the way
## Wounds is.
## Per the request ("social encounters have too much health (composure)
## let half the current values for everyone"): halved from the raw Cool
## skill value — see DifficultyTiers' own comment for the matching NPC-
## side halving (base 20 -> 10, its own Tier bonus table halved too), so
## both sides of the exchange get shorter, faster-resolving fights
## consistently rather than only one side.
func _init_party_composure() -> void:
	var cool_def: SkillDefinition = GameData.skill_db.find_by_name("Cool")
	for member in GameState.party:
		if member.wounds_current <= 0:
			continue
		var cool_value: int = member.get_skill_value(cool_def) if cool_def != null else member.get_effective_characteristic_value("willpower")
		member.composure_max = maxi(1, int(round(cool_value / 2.0)))
		member.composure_current = member.composure_max

## Kicks off the whole exchange: builds the roster, seats every present/
## conscious party member and every NPC into a SocialCombatEncounter
## sorted by Wit, swaps the top bar over to the multi-NPC roster display,
## and starts the turn loop.
func _start_social_combat() -> void:
	if encounter_def.round1_prompt_text != "":
		_add_notice(_substitute(encounter_def.round1_prompt_text))
	_build_npc_roster()
	_init_party_composure()
	npc_portrait_row.visible = false
	combat_top_row.visible = true
	turn_order_section.visible = true
	for member in GameState.party:
		var bar: ProgressBar = party_composure_bars.get(member, null)
		if bar != null:
			bar.visible = true
	social_combat = SocialCombatEncounter.new()
	for member in GameState.party:
		if member.wounds_current > 0:
			social_combat.add_combatant(member)
	for npc in npc_characters:
		social_combat.add_combatant(npc)
	social_combat.roll_initiative()
	if is_instance_valid(rapport_label):
		rapport_label.visible = true
	_refresh_roster_bars()
	_advance_social_combat_turn()

## Refreshes every Composure bar (party roster) and dims the portrait of
## anyone currently defeated — an out-of-the-fight NPC per Design Doc
## Section 8, or a knocked-out-of-the-conversation party member. NPCs no
## longer get a persistent mini-panel of their own (see the Attacker/
## Defender boxes below instead) — only whichever one or two are
## currently the Attacker/Defender need rendering at all.
func _refresh_roster_bars() -> void:
	for member in GameState.party:
		var bar: ProgressBar = party_composure_bars.get(member, null)
		if bar == null:
			continue
		_restyle_bar(bar, member.composure_current, member.composure_max)
		var portrait: TextureRect = party_portrait_rects.get(member, null)
		if portrait != null:
			portrait.modulate = Color(0.35, 0.35, 0.35) if member.composure_current <= 0 else CareerPortraits.wound_modulate_for_character(member)
		## Slice 3: this party member's own active condition tags.
		var member_status_lbl: Label = party_status_labels.get(member, null)
		if member_status_lbl != null:
			var member_tags: Array[String] = []
			if member.has_condition("Flustered"):
				member_tags.append("Flustered")
			if member.has_condition("Humiliated"):
				member_tags.append("Humiliated")
			member_status_lbl.text = " / ".join(member_tags)
	if is_instance_valid(rapport_label) and social_combat != null:
		rapport_label.text = "Rapport: %d/%d" % [social_combat.rapport_pool.current, social_combat.rapport_max]
	_render_social_turn_order_panel()
	_refresh_attacker_defender_display()

## --- Attacker/Defender top bar + left-side Turn Order panel (per the
## request: "let the top bar work more like the combat version of it, ie
## showing the current Attacker & Defender... add window on the left side
## for turn order like on the combat screen") — direct adaptations of
## FieldEncounterScreen's own _build_combat_status_box/
## _refresh_enemy_display/_render_turn_order_panel to Social Combat's own
## Character/SocialCombatEncounter shape. Only rendered once combat_top_
## row/turn_order_section are visible (_start_social_combat turns both
## on); harmless no-ops otherwise since social_combat is still null.

const SOCIAL_BOX_NAME_FONT_SIZE := 12
const SOCIAL_BOX_SMALL_FONT_SIZE := 10
const SOCIAL_BOX_PORTRAIT_WIDTH := 96

func _social_box_small_label(text: String, color: Color = Color(0.75, 0.72, 0.66), align_right: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", SOCIAL_BOX_SMALL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if align_right:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return lbl

## Same as _social_box_small_label but WITHOUT autowrap — for cells inside
## the 2x2 stats GridContainer, same reasoning as field's own
## _combat_box_stat_label (a wrapping label collapses the grid's own width
## computation toward 0).
func _social_box_stat_label(text: String, color: Color = Color(0.75, 0.72, 0.66), align_right: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", SOCIAL_BOX_SMALL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	if align_right:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return lbl

## Same bordered +N/-N chip FieldEncounterScreen's own _build_vs_sl_chip
## draws, colored by whether that side actually won the opposition.
func _build_social_vs_sl_chip(sl: int, won: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var accent: Color = Color(0.3, 0.85, 0.35) if won else Color(0.85, 0.3, 0.3)
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.12)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = "%+d" % sl
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", accent)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(lbl)
	return chip

## Whoever's shown in the Defender box: while it's an NPC's own Turn,
## whichever party member that NPC picked as its target (_current_npc_
## turn_target, set by _run_npc_turn the moment it's chosen); otherwise
## (a party member's own Turn) the target THEY currently have selected
## (selected_npc_target, set by the target picker in _show_attack_buttons).
func _current_social_defender() -> Character:
	if active_social_combatant != null and active_social_combatant.allegiance == "adversary":
		return _current_npc_turn_target
	return selected_npc_target

## Builds one Attacker/Defender status box — portrait, name, a full-width
## Composure bar with overlaid text, a 2x2 stats grid (ally: Status tier +
## Fortune, then Wit; adversary: Social Armor + Momentum, then Wit), and a
## Conditions line if any are active. `mirrored` flips the whole box
## left-right (portrait to the right, text right-aligned) for the
## Defender box, exactly matching field's own _build_combat_status_box.
func _build_social_combat_box(character: Character, mirrored: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.11, 0.08, 0.0)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if character.composure_current <= 0:
		panel.modulate = Color(0.55, 0.55, 0.55, 1)
	panel.add_theme_stylebox_override("panel", style)

	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 8)
	panel.add_child(outer_hbox)

	var is_ally: bool = character.allegiance == "ally"
	var portrait := TextureRect.new()
	if is_ally:
		portrait.texture = CareerPortraits.get_portrait_for_character(character)
		portrait.modulate = CareerPortraits.wound_modulate_for_character(character)
	else:
		var tex: Texture2D = CareerPortraits.get_portrait(npc_portrait_key.get(character, ""), character.gender)
		if tex == null:
			tex = load(CareerPortraits.FALLBACK_PATH) as Texture2D
		portrait.texture = tex
	portrait.custom_minimum_size = Vector2(SOCIAL_BOX_PORTRAIT_WIDTH, 0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if mirrored:
		outer_hbox.add_child(vbox)
		outer_hbox.add_child(portrait)
	else:
		outer_hbox.add_child(portrait)
		outer_hbox.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = character.character_name
	name_lbl.add_theme_font_size_override("font_size", SOCIAL_BOX_NAME_FONT_SIZE)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	name_lbl.clip_text = true
	if mirrored:
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(name_lbl)

	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(0, 16)
	bar_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bar_wrap)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_restyle_bar(bar, character.composure_current, character.composure_max)
	bar_wrap.add_child(bar)
	var bar_lbl := Label.new()
	bar_lbl.text = "Defeated" if social_combat != null and social_combat.is_defeated(character) else "%d/%d" % [character.composure_current, character.composure_max]
	bar_lbl.add_theme_font_size_override("font_size", SOCIAL_BOX_SMALL_FONT_SIZE)
	bar_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	bar_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	bar_lbl.add_theme_constant_override("outline_size", 2)
	bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(bar_lbl)

	const STAT_COLOR := Color(0.75, 0.72, 0.66)
	const DEPLETED_COLOR := Color(0.85, 0.35, 0.3)
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 6)
	stats_grid.size_flags_horizontal = Control.SIZE_SHRINK_END if mirrored else Control.SIZE_SHRINK_BEGIN
	var wit: int = character.get_effective_characteristic_value("intelligence") + character.get_effective_characteristic_value("initiative")
	var wit_lbl := _social_box_stat_label("Wit: %d" % wit, STAT_COLOR, mirrored)
	if is_ally:
		## get_status_ordinal() is only meaningful for a real party
		## member's own career — an NPC (SocialCombatNPCDefinition.
		## to_character()) never sets one, see that branch below instead.
		const STATUS_NAMES := ["", "Brass", "Silver", "Gold"]
		var status_name: String = STATUS_NAMES[clampi(character.get_status_ordinal(), 1, 3)]
		var status_lbl := _social_box_stat_label("Status: %s" % status_name, STAT_COLOR, mirrored)
		var fortune_lbl := _social_box_stat_label("Fortune %d/%d" % [character.fortune_points, character.get_max_fortune_points()],
			DEPLETED_COLOR if character.fortune_points <= 0 else STAT_COLOR, mirrored)
		## Per the request ("show attacker / defender career tier lvl in
		## the social encounter top bar"): the real Career Level
		## (current_tier) this party member's own Status above is
		## actually derived from (Character.get_status_ordinal() reads
		## career.get_level(current_tier)) — filling the grid cell that
		## used to just be blank.
		var tier_lbl := _social_box_stat_label("Career Tier: %d" % character.current_tier, STAT_COLOR, mirrored)
		if mirrored:
			stats_grid.add_child(fortune_lbl)
			stats_grid.add_child(status_lbl)
			stats_grid.add_child(tier_lbl)
			stats_grid.add_child(wit_lbl)
		else:
			stats_grid.add_child(status_lbl)
			stats_grid.add_child(fortune_lbl)
			stats_grid.add_child(wit_lbl)
			stats_grid.add_child(tier_lbl)
	else:
		## Per the request ("social encounter social armor should work
		## by comparing attacker vs defender status... rather then be a
		## fixed bonus"): Social Armor is no longer one flat number for
		## this NPC (it depends on which party member is attacking), so
		## the roster card now shows this NPC's own Status instead —
		## same "Brass/Silver/Gold" vocabulary as the ally card above —
		## letting the player read the comparison themselves. Exposed
		## (Design Doc Section 5) still reads as 0 Social Armor against
		## every attack until this NPC's own next Turn regardless of
		## Status, so it's called out here too, same as the old armor
		## label used to.
		const STATUS_NAMES := ["", "Brass", "Silver", "Gold"]
		var exposed: bool = character.has_condition("Exposed")
		var npc_status: int = npc_status_ordinal_by_char.get(character, 1)
		var status_name: String = STATUS_NAMES[clampi(npc_status, 1, 3)]
		var status_text: String = "Status: %s (Exposed)" % status_name if exposed else "Status: %s" % status_name
		var armor_lbl := _social_box_stat_label(status_text, DEPLETED_COLOR if exposed else STAT_COLOR, mirrored)
		var momentum_lbl := _social_box_stat_label("Momentum: %d" % npc_momentum.get(character, 0), STAT_COLOR, mirrored)
		## Same "show the underlying Career Level" request as the ally
		## side above — this NPC's own Status (just above) comes from
		## SocialCombatNPCDefinition.get_status_ordinal(), which derives
		## it off get_career_tier_level() (the encounter's Difficulty
		## Tier standing in as this NPC's own Career Level, clamped to
		## its real range) — cached per-NPC in npc_career_tier_by_char
		## by _build_npc_roster(), same convention as
		## npc_status_ordinal_by_char right above it.
		var npc_tier: int = npc_career_tier_by_char.get(character, 1)
		var tier_lbl := _social_box_stat_label("Career Tier: %d" % npc_tier, STAT_COLOR, mirrored)
		if mirrored:
			stats_grid.add_child(momentum_lbl)
			stats_grid.add_child(armor_lbl)
			stats_grid.add_child(tier_lbl)
			stats_grid.add_child(wit_lbl)
		else:
			stats_grid.add_child(armor_lbl)
			stats_grid.add_child(momentum_lbl)
			stats_grid.add_child(wit_lbl)
			stats_grid.add_child(tier_lbl)
	vbox.add_child(stats_grid)

	var cond_parts: Array[String] = []
	var relevant_conditions: Array[String] = []
	if is_ally:
		relevant_conditions = ["Flustered", "Humiliated"]
	else:
		relevant_conditions = ["Flustered", "Exposed"]
	for cond_name in relevant_conditions:
		if character.has_condition(cond_name):
			cond_parts.append(cond_name)
	if not cond_parts.is_empty():
		vbox.add_child(_social_box_small_label(", ".join(cond_parts), Color(0.85, 0.75, 0.5), mirrored))

	return panel

## Captures the five things a just-shown opposed roll card pair already
## computed, for the top-bar's own +N/-N SL chips — mirrors
## FieldEncounterScreen's own _record_opposed_sl_result exactly.
func _record_social_opposed_sl_result(actor: Character, actor_test: TestResolver.TestResult, actor_won: bool,
		opponent: Character, opponent_test: TestResolver.TestResult, opponent_won: bool) -> void:
	_last_social_opposed_result = {
		"attacker": actor,
		"attacker_sl": actor_test.success_levels if actor_test != null else 0,
		"attacker_won": actor_won,
		"defender": opponent,
		"defender_sl": opponent_test.success_levels if opponent_test != null else 0,
		"defender_won": opponent_won,
	}
	_refresh_attacker_defender_display()

## Rebuilds the Attacker/Defender boxes and the round/SL-chip gap between
## them — mirrors FieldEncounterScreen's own _refresh_enemy_display. The
## Attacker is always active_social_combatant; the Defender is whichever
## Character _current_social_defender() resolves to (see that function).
func _refresh_attacker_defender_display() -> void:
	if not is_instance_valid(attacker_box_container) or social_combat == null:
		return
	_clear(attacker_box_container)
	_clear(defender_box_container)
	_clear(vs_sl_box)

	var attacker: Character = active_social_combatant
	if attacker != null:
		attacker_box_container.add_child(_build_social_combat_box(attacker))

	var defender: Character = _current_social_defender()
	if defender != null:
		defender_box_container.add_child(_build_social_combat_box(defender, true))

	vs_round_label.text = "Round %d" % social_combat.round_number

	if not _last_social_opposed_result.is_empty() and attacker != null and defender != null \
			and _last_social_opposed_result.get("attacker") == attacker and _last_social_opposed_result.get("defender") == defender:
		vs_sl_box.add_child(_build_social_vs_sl_chip(_last_social_opposed_result["attacker_sl"], _last_social_opposed_result["attacker_won"]))
		vs_sl_box.add_child(_build_social_vs_sl_chip(_last_social_opposed_result["defender_sl"], _last_social_opposed_result["defender_won"]))

## Left-side scrollable Turn Order list — direct adaptation of
## FieldEncounterScreen's own _render_turn_order_panel() (minus the
## battle-map/grid_view half, which Social Combat has no equivalent of):
## current combatant first, then everyone still to act this Round, an
## "End of Round" marker, then everyone who's already acted.
func _render_social_turn_order_panel() -> void:
	if not is_instance_valid(turn_order_list) or social_combat == null:
		return
	_clear(turn_order_list)
	var current: Character = active_social_combatant
	var order: Array[Character] = social_combat.turn_order
	var idx: int = social_combat.current_turn_index
	var upcoming: Array[Character] = []
	var already_acted: Array[Character] = []
	if idx >= 0 and idx < order.size():
		upcoming = order.slice(idx + 1, order.size())
		already_acted = order.slice(0, idx)
	else:
		upcoming = order.duplicate()

	var display: Array = []
	if current != null:
		display.append(current)
	display.append_array(upcoming)
	if current != null:
		display.append(_SOCIAL_END_OF_ROUND_MARKER)
	display.append_array(already_acted)

	for entry in display:
		if entry is String and entry == _SOCIAL_END_OF_ROUND_MARKER:
			var marker_label := Label.new()
			marker_label.text = "═══ End of Round ═══"
			marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			marker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			marker_label.add_theme_font_size_override("font_size", 7)
			marker_label.add_theme_color_override("font_color", Color(0.55, 0.48, 0.35))
			turn_order_list.add_child(marker_label)
			continue
		var c: Character = entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		var defeated := social_combat.is_defeated(c)
		var side_marker := "🛡" if c.allegiance == "ally" else "☠"
		label.text = "%s %s%s" % [side_marker, c.character_name, " (out)" if defeated else ""]
		label.add_theme_font_size_override("font_size", 9)
		if defeated:
			label.add_theme_color_override("font_color", Color(0.4, 0.37, 0.33))
		elif c == current:
			label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
			label.add_theme_font_size_override("font_size", 11)
		elif c.allegiance == "ally":
			label.add_theme_color_override("font_color", Color(0.55, 0.7, 0.95))
		else:
			label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		row.add_child(label)
		turn_order_list.add_child(row)

## Sentinel value used only inside _render_social_turn_order_panel()'s own
## `display` Array — a real Character is never equal to this String, so
## `entry is String and entry == _SOCIAL_END_OF_ROUND_MARKER` never
## accidentally matches a combatant.
const _SOCIAL_END_OF_ROUND_MARKER := "__SOCIAL_END_OF_ROUND__"

## Applies Flustered's own effect (Design Doc Section 5, pulled forward
## into Slice 2 just far enough to give Bring in the Muscle a real
## payoff) if `character` currently carries it: -2 Composure, then the
## condition clears itself. A no-op (returns false) for anyone who
## isn't Flustered. Factored out of _advance_social_combat_turn() so it
## has a real, directly-testable unit shape rather than being buried
## inline in the turn loop.
func _apply_flustered_start_of_turn(character: Character) -> bool:
	if not character.has_condition("Flustered"):
		return false
	character.remove_condition("Flustered")
	character.composure_current = maxi(0, character.composure_current - 2)
	_add_notice("[color=#c76a6a]%s is still Flustered — -2 Composure (now %d/%d).[/color]" % [character.character_name, character.composure_current, character.composure_max])
	_refresh_roster_bars()
	return true

## Exposed (Design Doc Section 5): while active, this NPC's Social Armor
## reads as 0 against every party attack — see the armor computation in
## _attempt_social_attack()/_attempt_bring_the_muscle() — until its own
## next turn comes up, at which point it simply clears (no Composure
## cost of its own, unlike Flustered). Applies to either side in
## principle (Character.conditions is generic), though in practice only
## NPCs carry Social Armor at all.
func _clear_exposed_start_of_turn(character: Character) -> void:
	if not character.has_condition("Exposed"):
		return
	character.remove_condition("Exposed")
	_add_notice("[color=#8fbf6a]%s is no longer Exposed.[/color]" % character.character_name)
	_refresh_roster_bars()

## The turn loop's own heartbeat: checks both win/lose conditions first
## (Design Doc Section 8), then hands the next living combatant's turn
## to either the party-attack UI or the auto-resolved NPC turn.
func _advance_social_combat_turn() -> void:
	if encounter_over:
		return
	if social_combat.all_npcs_defeated():
		_resolve_social_combat_win()
		return
	if social_combat.all_party_defeated():
		_resolve_social_combat_failure()
		return
	active_social_combatant = social_combat.advance_turn()
	_current_npc_turn_target = null
	if active_social_combatant == null:
		_resolve_social_combat_failure()
		return
	## Per the request ("we need to limit the attempts somehow"): neither
	## side broke the other within the round cap — the conversation has
	## just gone in circles. Ends as a stalemate (same reward-nothing
	## shape as any other lost encounter, via _resolve_social_combat_
	## stalemate() below) rather than running forever.
	if social_combat.round_limit_reached():
		_resolve_social_combat_stalemate()
		return
	## Flustered (Design Doc Section 5 — pulled forward into Slice 2
	## just far enough to give Bring in the Muscle a real payoff, without
	## the other two Conditions): -2 Composure at the start of whoever
	## carries it, ally or adversary alike, then it clears itself. That
	## can end the encounter outright, or knock the very character whose
	## turn this is out of the fight -- re-check both, same guards the
	## top of this function already runs, rather than handing a turn to
	## someone (or something) that just dropped to 0.
	if _apply_flustered_start_of_turn(active_social_combatant):
		if social_combat.all_npcs_defeated():
			_resolve_social_combat_win()
			return
		if social_combat.all_party_defeated():
			_resolve_social_combat_failure()
			return
		if social_combat.is_defeated(active_social_combatant):
			_advance_social_combat_turn()
			return
	_clear_exposed_start_of_turn(active_social_combatant)
	_refresh_roster_bars()
	if active_social_combatant.allegiance == "adversary":
		_run_npc_turn(active_social_combatant)
	else:
		_show_attack_buttons(active_social_combatant)

## A simple "Continue" gate between turns, so the log has a moment to
## actually be read before the next exchange fires — the "Continue-style
## pacing beat" an auto-resolved NPC turn (and a just-resolved party
## turn) both need.
func _prompt_continue(next: Callable) -> void:
	_clear(action_container)
	var btn := Button.new()
	btn.text = "Continue"
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(next)
	action_container.add_child(btn)
	_refresh_focus_for_disabled_buttons(self)
	_auto_focus_default_button()

## Builds the active party member's own turn: pick a target (only shown
## when more than one NPC is still living — Design Doc Section 4's
## targeting note) and one of the 4 Attack Type buttons, each gated by
## SocialCombatResolver.can_use() (Reason needs real Research training).
func _show_attack_buttons(character: Character) -> void:
	_clear(action_container)
	var living_npcs := social_combat.get_living("adversary")
	if living_npcs.is_empty():
		return   ## caught by the win check the moment this turn ends
	if selected_npc_target == null or not living_npcs.has(selected_npc_target):
		selected_npc_target = living_npcs[0]
	_refresh_attacker_defender_display()

	var header := Label.new()
	header.text = "%s's turn" % character.character_name
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	action_container.add_child(header)

	if living_npcs.size() > 1:
		var target_header := Label.new()
		target_header.text = "Target:"
		target_header.add_theme_font_size_override("font_size", 8)
		target_header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
		action_container.add_child(target_header)
		var target_row := HFlowContainer.new()
		target_row.add_theme_constant_override("h_separation", 6)
		for npc in living_npcs:
			var t_btn := Button.new()
			t_btn.toggle_mode = true
			t_btn.button_pressed = (npc == selected_npc_target)
			t_btn.text = "%s (%d/%d)" % [npc.character_name, npc.composure_current, npc.composure_max]
			t_btn.add_theme_font_size_override("font_size", 10)
			t_btn.pressed.connect(func(): selected_npc_target = npc; _show_attack_buttons(character))
			target_row.add_child(t_btn)
		action_container.add_child(target_row)

	## Per the request ("split the actions bar into 2 side by side
	## sections, Action on the left, Maneuvers on the right"): the 4
	## Attack Type buttons and the Maneuvers block now live in their own
	## side-by-side column, each an equally-wide VBoxContainer under one
	## shared HBoxContainer — everything ABOVE this (the header, the
	## target picker) and BELOW it (Recompose) still spans the full
	## width, since neither is really "an Action" vs "a Maneuver" in the
	## same sense (Recompose is a Humiliated-only escape hatch, shown
	## rarely, and reads oddly squeezed into either column).
	var split_row := HBoxContainer.new()
	split_row.add_theme_constant_override("separation", 12)
	action_container.add_child(split_row)

	var actions_col := VBoxContainer.new()
	actions_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_col.add_theme_constant_override("separation", 6)
	split_row.add_child(actions_col)

	var maneuvers_col := VBoxContainer.new()
	maneuvers_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maneuvers_col.add_theme_constant_override("separation", 6)
	split_row.add_child(maneuvers_col)

	var actions_header := Label.new()
	actions_header.text = "Actions:"
	actions_header.add_theme_font_size_override("font_size", 8)
	actions_header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
	actions_col.add_child(actions_header)

	var rapport_bonus := social_combat.rapport_pool.roll_bonus()
	for attack_type in [SocialCombatResolver.AttackType.INTIMIDATE, SocialCombatResolver.AttackType.CHARM,
			SocialCombatResolver.AttackType.NEEDLE, SocialCombatResolver.AttackType.REASON]:
		var skill_def := SocialCombatResolver.attacking_skill_for(attack_type, character)
		var type_name: String = SocialCombatResolver.ATTACK_TYPE_NAMES[attack_type]
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 13)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		## Per the request ("stop the same character repeating the same
		## action... each round"), CORRECTED per a real balance bug report
		## ("momentum snowballs and... they can only pass until the NPC
		## slowly beats them all" — see SocialCombatEncounter.used_
		## attack_types' own comment for the full story): a used Attack
		## Type now comes back on cooldown after ATTACK_TYPE_REFRESH_ROUNDS
		## rounds instead of being off the table for the rest of the
		## encounter. Switching to a different living NPC (the Target row
		## above) still offers a fresh set of its own, same as before.
		var already_used := social_combat.has_used_attack_type(character, selected_npc_target, attack_type)
		if skill_def != null and SocialCombatResolver.can_use(attack_type, character) and not already_used:
			var target_num := character.get_skill_value(skill_def) + rapport_bonus
			## Slice 3: Reason now also strips 1 point of the target NPC's
			## own momentum (Design Doc Section 6) alongside its existing
			## heal-the-most-damaged-ally effect.
			var suffix := " — vs %s, restores an ally & saps its momentum" if attack_type == SocialCombatResolver.AttackType.REASON else " — vs %s"
			btn.text = ("%s (%s, Target %d)" + suffix) % [type_name, skill_def.display_name(), target_num, selected_npc_target.character_name]
			btn.disabled = false
			btn.pressed.connect(func(): _attempt_social_attack(character, attack_type, skill_def))
		elif already_used:
			var rounds_left := social_combat.rounds_until_attack_type_available(character, selected_npc_target, attack_type)
			btn.text = "%s — on cooldown, back in %d round%s (vs %s)" % [type_name, rounds_left, "" if rounds_left == 1 else "s", selected_npc_target.character_name]
			btn.disabled = true
		else:
			btn.text = "%s — untrained" % type_name
			btn.disabled = true
		actions_col.add_child(btn)

	## Safety valve for the restriction above: if every trained Attack
	## Type is spent against the current target and Rapport can't afford
	## any Maneuver either, the character would otherwise be left with no
	## pressable action at all. Shown only when it's actually needed —
	## everyone else still just sees their 4 Attack Type buttons and the
	## Maneuvers column as before.
	var any_maneuver_affordable := social_combat.rapport_pool.current >= 1
	if not social_combat.has_any_attack_type_available(character, selected_npc_target) and not any_maneuver_affordable:
		var pass_btn := Button.new()
		pass_btn.add_theme_font_size_override("font_size", 12)
		pass_btn.text = "Pass — nothing new left to try on %s" % selected_npc_target.character_name
		pass_btn.pressed.connect(func():
			_add_notice("[color=#8a7a6a]%s has nothing new left to say to %s, and lets the moment pass.[/color]" % [character.character_name, selected_npc_target.character_name])
			_prompt_continue(_advance_social_combat_turn)
		)
		actions_col.add_child(pass_btn)

	## --- Slice 2: the three Rapport-spending Tactical Maneuvers (Design
	## Doc Section 7) — alternative actions to the 4 Attack Types above,
	## greyed out until the party's own Rapport Pool can actually afford
	## them.
	var maneuver_header := Label.new()
	maneuver_header.text = "Maneuvers (Rapport %d/%d):" % [social_combat.rapport_pool.current, social_combat.rapport_max]
	maneuver_header.add_theme_font_size_override("font_size", 8)
	maneuver_header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
	maneuvers_col.add_child(maneuver_header)

	var distract_btn := Button.new()
	distract_btn.add_theme_font_size_override("font_size", 12)
	distract_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	distract_btn.text = "Distract (1 Rapport) — redirect an NPC's next attack"
	distract_btn.disabled = social_combat.rapport_pool.current < 1
	if not distract_btn.disabled:
		distract_btn.pressed.connect(func(): _use_distract(character))
	maneuvers_col.add_child(distract_btn)

	var overwhelm_btn := Button.new()
	overwhelm_btn.add_theme_font_size_override("font_size", 12)
	overwhelm_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overwhelm_btn.text = "Overwhelm (2 Rapport) — strip an NPC's Social Armor this round"
	overwhelm_btn.disabled = social_combat.rapport_pool.current < 2
	if not overwhelm_btn.disabled:
		overwhelm_btn.pressed.connect(func(): _use_overwhelm(character))
	maneuvers_col.add_child(overwhelm_btn)

	var muscle_btn := Button.new()
	muscle_btn.add_theme_font_size_override("font_size", 12)
	muscle_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	muscle_btn.text = "Bring in the Muscle (3 Rapport) — a raw Strength Intimidate"
	muscle_btn.disabled = social_combat.rapport_pool.current < 3
	if not muscle_btn.disabled:
		muscle_btn.pressed.connect(func(): _use_bring_the_muscle(character))
	maneuvers_col.add_child(muscle_btn)

	## Slice 3: Humiliated (Design Doc Section 5) doesn't clear itself —
	## it sticks around, penalising this character's own future defense
	## rolls, until they deliberately spend a whole turn Recomposing
	## instead of attacking. Shown only when it's actually relevant,
	## below the two side-by-side columns (full width) rather than
	## squeezed into either one — the character can still choose to
	## attack or Maneuver anyway and just accept the ongoing penalty.
	if character.has_condition("Humiliated"):
		var recompose_btn := Button.new()
		recompose_btn.add_theme_font_size_override("font_size", 12)
		recompose_btn.text = "Recompose — spend this turn shaking off being Humiliated"
		recompose_btn.pressed.connect(func(): _use_recompose(character))
		action_container.add_child(recompose_btn)

	_refresh_focus_for_disabled_buttons(self)
	_auto_focus_default_button()

## Recomposing (Design Doc Section 5's own escape from Humiliated): no
## roll, no cost — just spends this character's whole turn to shake the
## condition off.
func _use_recompose(character: Character) -> void:
	character.remove_condition("Humiliated")
	_add_notice("[color=#8fbf6a]%s takes a breath and recomposes themself.[/color]" % character.character_name)
	_refresh_roster_bars()
	_prompt_continue(_advance_social_combat_turn)

## Shared target-picker for a Maneuver — skipped straight to the sole
## option (no confirm screen with no real choice on it) when only one
## living NPC is present, same shortcut _choose_assistants()'s own
## eligible-list-of-one case already used pre-Social-Combat.
func _pick_living_npc(header_text: String, on_chosen: Callable) -> void:
	var living_npcs := social_combat.get_living("adversary")
	if living_npcs.size() <= 1:
		on_chosen.call(living_npcs[0] if not living_npcs.is_empty() else null)
		return
	_clear(action_container)
	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	action_container.add_child(header)
	for npc in living_npcs:
		var btn := Button.new()
		btn.text = "%s (%d/%d)" % [npc.character_name, npc.composure_current, npc.composure_max]
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): on_chosen.call(npc))
		action_container.add_child(btn)
	_refresh_focus_for_disabled_buttons(self)
	_auto_focus_default_button()

## Shared target-picker for Bring in the Muscle's own "any present party
## member" clause — same one-option shortcut as _pick_living_npc().
func _pick_living_ally(header_text: String, on_chosen: Callable) -> void:
	var living_allies := social_combat.get_living("ally")
	if living_allies.size() <= 1:
		on_chosen.call(living_allies[0] if not living_allies.is_empty() else null)
		return
	_clear(action_container)
	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	action_container.add_child(header)
	for ally in living_allies:
		var btn := Button.new()
		btn.text = "%s (Strength %d)" % [ally.character_name, ally.get_effective_characteristic_value("strength")]
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): on_chosen.call(ally))
		action_container.add_child(btn)
	_refresh_focus_for_disabled_buttons(self)
	_auto_focus_default_button()

## Distract (Design Doc Section 7, 1 Rapport): the chosen NPC's next
## attack targets whichever living ally currently has the HIGHEST
## Composure remaining instead of its normal lowest-Composure choice —
## one-shot, read and cleared by _run_npc_turn() the moment that NPC's
## turn comes up.
func _use_distract(character: Character) -> void:
	_pick_living_npc("Distract which target?", func(npc):
		if npc == null:
			_show_attack_buttons(character)
			return
		if not social_combat.rapport_pool.spend(1):
			_show_attack_buttons(character)
			return
		distracted_npcs[npc] = true
		_add_notice("[color=#8fbf6a]%s distracts %s — its next attack will go astray.[/color]" % [character.character_name, npc.character_name])
		_refresh_roster_bars()
		_prompt_continue(_advance_social_combat_turn)
	)

## Overwhelm (Design Doc Section 7, 2 Rapport): the chosen NPC's Social
## Armor reads as 0 for the rest of the current round — a per-target
## spend, not a whole-roster wipe, per the design doc's own note.
func _use_overwhelm(character: Character) -> void:
	_pick_living_npc("Overwhelm which target's Social Armor?", func(npc):
		if npc == null:
			_show_attack_buttons(character)
			return
		if not social_combat.rapport_pool.spend(2):
			_show_attack_buttons(character)
			return
		overwhelmed_until_round[npc] = social_combat.round_number
		_add_notice("[color=#8fbf6a]%s overwhelms %s — its Social Armor is stripped for the rest of the round.[/color]" % [character.character_name, npc.character_name])
		_refresh_roster_bars()
		_prompt_continue(_advance_social_combat_turn)
	)

## Bring in the Muscle (Design Doc Section 7, 3 Rapport): any present
## party member — even one with no social Skills at all — makes a raw
## Strength Test (not the trained Intimidate skill value) against the
## chosen NPC, dealing Intimidate-scale Composure damage and leaving
## the NPC Flustered on a hit. `character` (whose turn this actually
## is) picks who throws their weight around; it doesn't have to be them.
func _use_bring_the_muscle(character: Character) -> void:
	_pick_living_ally("Bring in the Muscle — who throws their weight around?", func(roller):
		if roller == null:
			_show_attack_buttons(character)
			return
		_pick_living_npc("...against which target?", func(npc):
			if npc == null:
				_show_attack_buttons(character)
				return
			_attempt_bring_the_muscle(character, roller, npc)
		)
	)

## Social Armor for one exchange, per the request ("social encounter
## social armor should work by comparing attacker vs defender status...
## rather then be a fixed bonus"): max(0, npc_status - attacker_status)
## * ARMOR_PER_STATUS_STEP — a Status-equal-or-lower NPC gives 0 armor,
## same as before. `overwhelmed_until_round`/Exposed still zero it out
## entirely regardless of Status, matching the old flat-armor behaviour
## those two conditions already had.
func _social_armor_against(attacker: Character, target_npc: Character) -> int:
	if overwhelmed_until_round.get(target_npc, -1) == social_combat.round_number:
		return 0
	## Slice 3: Exposed (Design Doc Section 5) — a critical hit's own
	## follow-through leaves the NPC's Social Armor reading as 0 too.
	if target_npc.has_condition("Exposed"):
		return 0
	var npc_status: int = npc_status_ordinal_by_char.get(target_npc, 1)
	var attacker_status: int = attacker.get_status_ordinal()
	return maxi(0, npc_status - attacker_status) * ARMOR_PER_STATUS_STEP

## `forced_attacker_roll`/`forced_defender_roll`, if >= 1, force that
## exact d100 instead of a real roll — real callers (the button in
## _use_bring_the_muscle) never pass these (default -1, unchanged
## behaviour); social_combat_conditions_test.gd uses them to exercise
## the Exposed-on-critical-hit path deterministically, since dice can't
## otherwise be forced from outside this function.
func _attempt_bring_the_muscle(character: Character, roller: Character, target_npc: Character, forced_attacker_roll: int = -1, forced_defender_roll: int = -1) -> void:
	if not social_combat.rapport_pool.spend(3):
		_show_attack_buttons(character)
		return
	_clear(action_container)
	var rapport_bonus := social_combat.rapport_pool.roll_bonus()
	var strength_val := roller.get_effective_characteristic_value("strength") + rapport_bonus
	var attacker_test := TestResolver.resolve(strength_val, 0, forced_attacker_roll)
	var defender_target := SocialCombatResolver.npc_defense_target(SocialCombatResolver.AttackType.INTIMIDATE, target_npc)
	var defender_test := TestResolver.resolve(defender_target, 0, forced_defender_roll)
	var already_won := _show_muscle_cards(roller, target_npc, attacker_test, defender_test, false)
	var choice := await _offer_fortune_spend(roller, attacker_test, already_won)
	while choice == "reroll" or choice == "sl":
		if choice == "reroll":
			attacker_test = TestResolver.resolve(strength_val, 0, forced_attacker_roll)
		already_won = _show_muscle_cards(roller, target_npc, attacker_test, defender_test, true)
		choice = await _offer_fortune_spend(roller, attacker_test, already_won)

	if attacker_test.is_fumble:
		social_combat.rapport_pool.reset()
		_add_notice("[color=#c76a6a]A Fumble scatters the party's momentum — Rapport resets to 0.[/color]")

	var armor: int = _social_armor_against(roller, target_npc)
	var exchange := SocialCombatResolver.finalize_party_attack(SocialCombatResolver.AttackType.INTIMIDATE, attacker_test, defender_test, target_npc, armor)
	_report_party_exchange(target_npc, SocialCombatResolver.AttackType.INTIMIDATE, exchange, null)
	if exchange.hit:
		target_npc.add_condition("Flustered")
		_add_notice("[color=#c76a6a]%s is left Flustered.[/color]" % target_npc.character_name)
		## Slice 3: a Critical Hit from the party (any Attack Type,
		## including Bring in the Muscle's own raw Strength Test) leaves
		## the target NPC Exposed until its own next turn (Design Doc
		## Section 5 never states a trigger for this — this project's own
		## call, for thematic parity with Humiliated's own NPC-crit
		## trigger below in _run_npc_turn()).
		if attacker_test.is_critical and not target_npc.has_condition("Exposed"):
			target_npc.add_condition("Exposed")
			_add_notice("[color=#c76a6a]%s is left Exposed![/color]" % target_npc.character_name)
	_refresh_roster_bars()
	_prompt_continue(_advance_social_combat_turn)

func _show_muscle_cards(roller: Character, target_npc: Character, attacker_test: TestResolver.TestResult,
		defender_test: TestResolver.TestResult, merge: bool) -> bool:
	var opposed := TestResolver.resolve_opposed(attacker_test, defender_test)
	var wins: bool = opposed.attacker_wins
	_record_social_opposed_sl_result(roller, attacker_test, wins, target_npc, defender_test, not wins)
	## Per the request: a genuine tie (same SL AND same Target Number)
	## reads as "Tied" rather than the binary Hit/Missed every other
	## outcome uses — see TestResolver.resolve_opposed()'s own comment.
	var attacker_effect := "Hit" if wins else ("Tied" if opposed.is_true_tie else "Missed")
	var attacker_card := {
		"character_name": roller.character_name, "title": "Bring in the Muscle", "subtitle": "Raw Strength",
		"side": "ally", "test": attacker_test, "effects": [attacker_effect] as Array[String],
		"dimmed": not wins and not opposed.is_true_tie,
	}
	var defender_card := {
		"character_name": target_npc.character_name, "title": "Resist", "subtitle": "Opposed Test",
		"side": "adversary", "test": defender_test, "effects": [] as Array[String],
		"dimmed": wins,
		"mirror_layout": true,
	}
	var notice := _party_attack_notice(wins, opposed.is_true_tie, opposed.net_success_levels)
	if merge:
		_merge_into_latest_entry([attacker_card, defender_card], notice)
	else:
		_add_history_entry([attacker_card, defender_card], notice)
	return wins

## Rolls and shows one party-member-attacks-NPC exchange, offers the
## same Fortune/Dark Deal chain every roll in this game gets (Design Doc
## Section 9), then hands the final Tests to SocialCombatResolver to
## score and apply.
## `forced_attacker_roll`/`forced_defender_roll`, if >= 1, force that
## exact d100 instead of a real roll — real callers (the Attack Type
## buttons in _show_attack_buttons()) never pass these (default -1,
## unchanged behaviour); social_combat_conditions_test.gd uses them to
## exercise the crit-triggered Exposed/Flustered/momentum paths
## deterministically.
func _attempt_social_attack(character: Character, attack_type: int, skill_def: SkillDefinition, forced_attacker_roll: int = -1, forced_defender_roll: int = -1) -> void:
	if encounter_over:
		return
	_clear(action_container)
	var target_npc := selected_npc_target
	## Per the request ("stop the same character repeating the same
	## action... each round"): the ATTEMPT is what spends this Attack
	## Type against this NPC, not just a hit — marked once, up front,
	## before any rolling (including the Fortune/Dark Deal reroll loop
	## below, which redoes THIS same attempt rather than starting a new
	## one).
	social_combat.mark_attack_type_used(character, target_npc, attack_type)
	## Slice 2: the party's own banked Rapport (Design Doc Section 3)
	## adds +10 per point to every social Attack roll, the same way an
	## Assist bonus already flows through resolve_skill_test's own
	## modifier/modifier_breakdown parameters.
	var rapport_bonus := social_combat.rapport_pool.roll_bonus()
	var modifier_breakdown: Array = []
	if rapport_bonus > 0:
		modifier_breakdown.append({"name": "Rapport (%d)" % social_combat.rapport_pool.current, "amount": rapport_bonus})
	## Etiquette (Social Group): a flat SL bonus (per rank, same amount
	## the generic Talent pipeline would give) when the target NPC's own
	## derived group (SocialCombatNPCDefinition.get_etiquette_group())
	## matches a group this character actually trained Etiquette for.
	## Checked directly against the specific qualified talent name
	## ("Etiquette (Nobles)") rather than through
	## get_test_success_level_breakdown()'s own generic scope-matching --
	## that mechanism can't tell "Etiquette (Nobles)" apart from
	## "Etiquette (Criminals)" (both resolve to the one shared
	## TalentDefinition via TalentDatabase.find_by_name()'s own
	## qualifier-stripping fallback), so matching the exact key here is
	## what stops a character who trained one group from getting credit
	## against a target belonging to a different one.
	var extra_sl_breakdown: Array = []
	if skill_def.skill_name == "Charm" or skill_def.skill_name == "Gossip":
		var npc_group: String = npc_etiquette_group_by_char.get(target_npc, "")
		if not npc_group.is_empty():
			var etiquette_key := "Etiquette (%s)" % npc_group
			if character.talents_taken.has(etiquette_key):
				var rank: int = maxi(character.talents_taken[etiquette_key], 1)
				extra_sl_breakdown.append({"name": etiquette_key, "amount": rank})
	var attacker_test := TestResolver.resolve_skill_test(character, skill_def, "", rapport_bonus, modifier_breakdown, forced_attacker_roll, extra_sl_breakdown)
	var defender_target := SocialCombatResolver.npc_defense_target(attack_type, target_npc)
	var defender_test := TestResolver.resolve(defender_target, 0, forced_defender_roll)
	## Cat-tongued (p.135): a lying Charm attack is fully unopposed -- the
	## NPC's own Initiative defense (this project's Intuition stand-in,
	## see SocialCombatResolver.npc_defense_target()'s own comment) never
	## gets a chance to contest it. Still rolled normally just above (so
	## its card shows a real number, same visual language as every other
	## defense roll) but its result is zeroed out here before it can
	## factor into the opposed comparison below.
	var unopposed_charm := attack_type == SocialCombatResolver.AttackType.CHARM and character.has_unopposed_test(["Charm"])
	if unopposed_charm:
		defender_test.success = false
		defender_test.success_levels = 0
	var already_won := _show_party_attack_cards(character, attack_type, target_npc, attacker_test, defender_test, false, unopposed_charm)
	var choice := await _offer_fortune_spend(character, attacker_test, already_won)
	while choice == "reroll" or choice == "sl":
		if choice == "reroll":
			attacker_test = TestResolver.resolve_skill_test(character, skill_def, "", rapport_bonus, modifier_breakdown, forced_attacker_roll, extra_sl_breakdown)
		already_won = _show_party_attack_cards(character, attack_type, target_npc, attacker_test, defender_test, true, unopposed_charm)
		choice = await _offer_fortune_spend(character, attacker_test, already_won)

	if attacker_test.is_fumble:
		social_combat.rapport_pool.reset()
		_add_notice("[color=#c76a6a]A Fumble scatters the party's momentum — Rapport resets to 0.[/color]")

	var heal_target: Character = null
	if attack_type == SocialCombatResolver.AttackType.REASON:
		heal_target = _most_damaged_ally()
	var armor: int = _social_armor_against(character, target_npc)
	var exchange := SocialCombatResolver.finalize_party_attack(attack_type, attacker_test, defender_test, target_npc, armor, heal_target)
	## Charm hits grow the party's own Rapport by 1 (Design Doc Section
	## 4's Attack matrix).
	if exchange.hit and attack_type == SocialCombatResolver.AttackType.CHARM:
		social_combat.rapport_pool.gain(1, social_combat.rapport_max)
		_add_notice("[color=#8fbf6a]The party's Rapport grows (now %d/%d).[/color]" % [social_combat.rapport_pool.current, social_combat.rapport_max])
	## Slice 3 (Design Doc Section 5's own "Demoralised" reference under
	## Intimidate, treated as this project's Flustered — see the
	## npc_momentum field's own comment): an Intimidate hit leaves the
	## target Flustered, same as Bring in the Muscle already does.
	if exchange.hit and attack_type == SocialCombatResolver.AttackType.INTIMIDATE:
		target_npc.add_condition("Flustered")
		_add_notice("[color=#c76a6a]%s is left Flustered.[/color]" % target_npc.character_name)
	## Slice 3 (Design Doc Section 6): a successful Reason hit also saps
	## 1 point of the target's own momentum, alongside its existing
	## heal-the-most-damaged-ally effect.
	if exchange.hit and attack_type == SocialCombatResolver.AttackType.REASON:
		if npc_momentum.get(target_npc, 0) > 0:
			npc_momentum[target_npc] = maxi(0, npc_momentum.get(target_npc, 0) - 1)
			_add_notice("[color=#8fbf6a]%s's momentum is shaken (now %d).[/color]" % [target_npc.character_name, npc_momentum.get(target_npc, 0)])
	## Slice 3: a Critical Hit from the party (any Attack Type) leaves
	## the target NPC Exposed until its own next turn — see the matching
	## comment in _attempt_bring_the_muscle().
	if exchange.hit and attacker_test.is_critical and not target_npc.has_condition("Exposed"):
		target_npc.add_condition("Exposed")
		_add_notice("[color=#c76a6a]%s is left Exposed![/color]" % target_npc.character_name)
	_report_party_exchange(target_npc, attack_type, exchange, heal_target)
	_refresh_roster_bars()
	_prompt_continue(_advance_social_combat_turn)

## Card-building for a party attack — same visual card real combat and
## the old skill-choice flow both already use (RollCardBuilder), the
## attacker's card on the left and the NPC's resistance on the right
## (mirror_layout), exactly the pairing _show_skill_roll_cards used to
## build. Returns whether the exchange, as currently rolled, would hit.
func _show_party_attack_cards(character: Character, attack_type: int, target_npc: Character,
		attacker_test: TestResolver.TestResult, defender_test: TestResolver.TestResult, merge: bool, unopposed: bool = false) -> bool:
	var opposed := TestResolver.resolve_opposed(attacker_test, defender_test)
	var wins: bool = opposed.attacker_wins
	_record_social_opposed_sl_result(character, attacker_test, wins, target_npc, defender_test, not wins)
	var type_name: String = SocialCombatResolver.ATTACK_TYPE_NAMES[attack_type]
	## Per the request: a genuine tie (same SL AND same Target Number)
	## reads as "Tied" rather than the binary Hit/Missed every other
	## outcome uses — see TestResolver.resolve_opposed()'s own comment.
	var attacker_effect := "Hit" if wins else ("Tied" if opposed.is_true_tie else "Missed")
	var attacker_card := {
		"character_name": character.character_name, "title": type_name, "subtitle": "Social Combat",
		"side": "ally", "test": attacker_test, "effects": [attacker_effect] as Array[String],
		"dimmed": not wins and not opposed.is_true_tie,
	}
	## Cat-tongued (p.135): its defender card reads "Suppressed" rather
	## than "Resist" — the roll shown is real (same defender_test rolled
	## just above in _attempt_social_attack), but its own comment there
	## explains why it's been zeroed and can no longer affect the
	## outcome; this card label is what tells the player why.
	var defender_card := {
		"character_name": target_npc.character_name,
		"title": "Suppressed" if unopposed else "Resist",
		"subtitle": "Cat-tongued" if unopposed else "Opposed Test",
		"side": "adversary", "test": defender_test, "effects": [] as Array[String],
		"dimmed": wins or unopposed,
		"mirror_layout": true,
	}
	var notice := _party_attack_notice(wins, opposed.is_true_tie, opposed.net_success_levels)
	if merge:
		_merge_into_latest_entry([attacker_card, defender_card], notice)
	else:
		_add_history_entry([attacker_card, defender_card], notice)
	return wins

## Reason's own heal target (Design Doc Section 4): whichever present
## party member has taken the most Composure damage this encounter —
## deliberately not restricted to the still-living, so a well-timed
## Reason can bring a knocked-out ally back into the conversation.
func _most_damaged_ally() -> Character:
	var best: Character = null
	var best_missing := -1
	for member in social_combat.combatants:
		if member.allegiance != "ally":
			continue
		var missing: int = member.composure_max - member.composure_current
		if missing > best_missing:
			best_missing = missing
			best = member
	return best

func _report_party_exchange(target_npc: Character, attack_type: int, exchange: SocialCombatResolver.ExchangeResult, heal_target: Character) -> void:
	if not exchange.hit:
		_add_notice("[color=#8a7a6a]No effect.[/color]")
		if exchange.opposed.is_true_tie:
			_maybe_show_tie_reaction(target_npc)
		else:
			_maybe_show_miss_reaction(target_npc)
		return
	if attack_type == SocialCombatResolver.AttackType.REASON:
		if heal_target != null:
			_add_notice("[color=#8fbf6a]%s regains %d Composure (now %d/%d).[/color]" % [heal_target.character_name, exchange.composure_healed, heal_target.composure_current, heal_target.composure_max])
		return
	var armor_note := ""
	if exchange.social_armor_reduced > 0:
		armor_note = " (Social Armor absorbed %d)" % exchange.social_armor_reduced
	elif exchange.bypassed_social_armor:
		armor_note = " (bypasses Social Armor)"
	_add_notice("[color=#c76a6a]%s loses %d Composure%s (now %d/%d).[/color]" % [target_npc.character_name, exchange.composure_damage, armor_note, target_npc.composure_current, target_npc.composure_max])
	_maybe_show_npc_reaction(target_npc)
	if target_npc.composure_current <= 0:
		_add_notice("[b][color=lightgreen]%s is out of the conversation![/color][/b]" % target_npc.character_name)

## Per the follow-up request ("the text doesn't react to how well you
## did"): every opposed exchange up to now only ever showed a flat "It
## lands!"/"It doesn't land." regardless of whether the roll won by 1 SL
## or 8 — this banding turns net_success_levels (already computed by
## every opposed exchange, win or lose) into 4 tiers of decisiveness, so
## a narrow win/loss reads differently from a crushing one.
func _sl_margin_tier(net_sl: int) -> int:
	var mag: int = absi(net_sl)
	if mag >= 6:
		return 3
	elif mag >= 4:
		return 2
	elif mag >= 2:
		return 1
	else:
		return 0

## Replaces the old flat "It lands!"/"It doesn't land." notice for a
## party-member-attacks-NPC exchange (used by both _show_party_attack_
## cards and _show_muscle_cards, which mirror the same card/notice
## shape) with SL-margin-aware phrasing — see _sl_margin_tier() above.
func _party_attack_notice(wins: bool, is_true_tie: bool, net_sl: int) -> String:
	if is_true_tie:
		return "[b]Dead even — nothing happens.[/b]"
	var tier := _sl_margin_tier(net_sl)
	if wins:
		match tier:
			3: return "[b]It overwhelms![/b]"
			2: return "[b]It lands hard![/b]"
			1: return "[b]It lands solidly.[/b]"
			_: return "[b]It barely lands.[/b]"
	else:
		match tier:
			3: return "[b]It doesn't come close.[/b]"
			2: return "[b]It's shrugged off.[/b]"
			1: return "[b]It doesn't land.[/b]"
			_: return "[b]It just misses.[/b]"

## Same idea as _party_attack_notice() above, for the NPC's own turn
## (_show_npc_attack_cards) — replaces the old flat "X holds firm."/
## "X presses Y!" with SL-margin-aware phrasing.
func _npc_attack_notice(npc_name: String, target_name: String, attacker_wins: bool, is_true_tie: bool, net_sl: int) -> String:
	if is_true_tie:
		return "[b]Dead even — nothing happens.[/b]"
	var tier := _sl_margin_tier(net_sl)
	if attacker_wins:
		match tier:
			3: return "[b]%s overwhelms %s![/b]" % [npc_name, target_name]
			2: return "[b]%s presses %s hard![/b]" % [npc_name, target_name]
			1: return "[b]%s presses %s.[/b]" % [npc_name, target_name]
			_: return "[b]%s barely gets through to %s.[/b]" % [npc_name, target_name]
	else:
		match tier:
			3: return "[b]%s shrugs it off completely.[/b]" % target_name
			2: return "[b]%s holds firm, unshaken.[/b]" % target_name
			1: return "[b]%s holds firm.[/b]" % target_name
			_: return "[b]%s barely holds firm.[/b]" % target_name

## Per the follow-up request ("NPC reaction lines only fire on your
## hits") — see the GENERIC_*_REACTION_LINES comment above. Fires at
## most once per NPC per encounter, right after a party attack on this
## NPC is resisted (not a true tie — see _maybe_show_tie_reaction for
## that case).
func _maybe_show_miss_reaction(npc: Character) -> void:
	if _npc_miss_reaction_shown.get(npc, false):
		return
	_npc_miss_reaction_shown[npc] = true
	var line: String = GENERIC_MISS_REACTION_LINES[randi() % GENERIC_MISS_REACTION_LINES.size()]
	_add_notice("[i][color=#c9a35c]“%s”[/color][/i]" % line)

## Same as _maybe_show_miss_reaction() above, for a true tie specifically.
func _maybe_show_tie_reaction(npc: Character) -> void:
	if _npc_tie_reaction_shown.get(npc, false):
		return
	_npc_tie_reaction_shown[npc] = true
	var line: String = GENERIC_TIE_REACTION_LINES[randi() % GENERIC_TIE_REACTION_LINES.size()]
	_add_notice("[i][color=#c9a35c]“%s”[/color][/i]" % line)

## Same as _maybe_show_miss_reaction() above, but for the NPC's OWN
## attack landing on a party member (its turn in the Social Combat turn
## order) — called from _report_npc_exchange().
func _maybe_show_npc_hit_reaction(npc: Character) -> void:
	if _npc_hit_reaction_shown.get(npc, false):
		return
	_npc_hit_reaction_shown[npc] = true
	var line: String = GENERIC_NPC_HIT_REACTION_LINES[randi() % GENERIC_NPC_HIT_REACTION_LINES.size()]
	_add_notice("[i][color=#c9a35c]“%s”[/color][/i]" % line)

## The mirror of _maybe_show_npc_hit_reaction() above: fires when the
## NPC's OWN attack is the one that fails to land, using
## GENERIC_NPC_ATTACK_MISS_REACTION_LINES (worded as an admission, not a
## taunt — see that const's own comment) rather than
## GENERIC_MISS_REACTION_LINES, which is worded for the opposite
## direction (the NPC resisting a party attack).
func _maybe_show_npc_attack_miss_reaction(npc: Character) -> void:
	if _npc_attack_miss_reaction_shown.get(npc, false):
		return
	_npc_attack_miss_reaction_shown[npc] = true
	var line: String = GENERIC_NPC_ATTACK_MISS_REACTION_LINES[randi() % GENERIC_NPC_ATTACK_MISS_REACTION_LINES.size()]
	_add_notice("[i][color=#c9a35c]“%s”[/color][/i]" % line)

## Per the request ("it would be nice the conversation would evolve with
## each roll rather than only take place at the start and after all
## rolls are done"): shows encounter_def.npc_reaction_lines progressively
## as THIS NPC's Composure actually drops, instead of the conversation
## going silent between intro_text and success_reveal/funny_loss_text.
## Divides the 0-100% Composure range evenly by however many lines are
## given (2 lines -> thresholds at 66% and 33% remaining) and shows each
## line at most once, the first time its threshold is crossed —
## catching up through more than one at once if a single big hit skips
## past two thresholds in the same blow. Skipped entirely once Composure
## actually hits 0 — that's success_reveal's own moment, not a reaction
## line's.
func _maybe_show_npc_reaction(npc: Character) -> void:
	var lines: Array = encounter_def.npc_reaction_lines
	if lines.is_empty() or npc.composure_current <= 0:
		return
	while _npc_reactions_shown.get(npc, 0) < lines.size():
		var next_index: int = _npc_reactions_shown.get(npc, 0)
		var threshold: float = float(lines.size() - next_index) / float(lines.size() + 1)
		var frac: float = float(npc.composure_current) / float(maxi(1, npc.composure_max))
		if frac > threshold:
			break
		_npc_reactions_shown[npc] = next_index + 1
		_add_notice("[i][color=#c9a35c]“%s”[/color][/i]" % _substitute(str(lines[next_index])))

## Auto-resolves one NPC's own turn: targets whichever living party
## member currently has the LOWEST Composure remaining (Design Doc
## Section 4's targeting rule), rolls the NPC's own attack (never
## reroll-able — NPCs carry no Fortune Points), and offers the
## DEFENDING party member the same Fortune/Dark Deal chain on their own
## Cool roll (Design Doc Section 9's confirmed split: "it does" feel
## right for the defender to spend their own Fortune here).
## `forced_npc_roll`/`forced_defender_roll`, if >= 1, force that exact
## d100 instead of a real roll — real callers (_advance_social_combat_
## turn()) never pass these (default -1, unchanged behaviour);
## social_combat_conditions_test.gd uses them to exercise the
## Humiliated-on-critical-hit path deterministically.
func _run_npc_turn(npc: Character, forced_npc_roll: int = -1, forced_defender_roll: int = -1) -> void:
	_clear(action_container)
	var living_allies := social_combat.get_living("ally")
	if living_allies.is_empty():
		return   ## caught by the loss check the moment this turn ends
	var target: Character
	if distracted_npcs.get(npc, false):
		## Distract (Design Doc Section 7): a one-shot redirect to
		## whichever living ally currently has the HIGHEST Composure
		## remaining, instead of this NPC's normal lowest-Composure
		## pick — consumed the instant it's read.
		distracted_npcs[npc] = false
		target = living_allies[0]
		for a in living_allies:
			if a.composure_current > target.composure_current:
				target = a
		_add_notice("[color=#8fbf6a]%s's attention is thrown — it goes after %s instead.[/color]" % [npc.character_name, target.character_name])
	else:
		target = living_allies[0]
		for a in living_allies:
			if a.composure_current < target.composure_current:
				target = a

	## Per the request ("top bar... showing the current Attacker &
	## Defender"): the Defender box needs to know THIS NPC's own pick the
	## moment it's made, not just once the roll resolves.
	_current_npc_turn_target = target
	_refresh_attacker_defender_display()

	## Slice 3 (Design Doc Section 6): this NPC's own momentum — "the
	## NPC's own version of Rapport" — adds +10 per point to ITS OWN
	## attack roll, mirroring the party's own Rapport bonus but tracked
	## per-NPC rather than party-wide.
	var momentum: int = npc_momentum.get(npc, 0)
	var npc_test: TestResolver.TestResult = TestResolver.resolve(SocialCombatResolver.npc_attack_target(npc) + momentum * 10, 0, forced_npc_roll)
	var defending_skill_def := SocialCombatResolver.defending_skill()
	## Slice 3 (Design Doc Section 5): Humiliated penalises this
	## defender's own Cool rolls by -20 until they spend a turn
	## Recomposing.
	var humiliated: bool = target.has_condition("Humiliated")
	var defender_modifier: int = -20 if humiliated else 0
	var defender_breakdown: Array = []
	if humiliated:
		defender_breakdown.append({"name": "Humiliated", "amount": -20})
	var defender_test: TestResolver.TestResult = TestResolver.resolve_skill_test(target, defending_skill_def, "", defender_modifier, defender_breakdown, forced_defender_roll)
	var defender_resists := _show_npc_attack_cards(npc, target, npc_test, defender_test, false)
	var choice := await _offer_fortune_spend(target, defender_test, defender_resists)
	while choice == "reroll" or choice == "sl":
		if choice == "reroll":
			defender_test = TestResolver.resolve_skill_test(target, defending_skill_def, "", defender_modifier, defender_breakdown, forced_defender_roll)
		defender_resists = _show_npc_attack_cards(npc, target, npc_test, defender_test, true)
		choice = await _offer_fortune_spend(target, defender_test, defender_resists)

	if defender_test.is_fumble:
		social_combat.rapport_pool.reset()
		_add_notice("[color=#c76a6a]A Fumble scatters the party's momentum — Rapport resets to 0.[/color]")

	## Slice 3: an NPC's own Fumble resets ITS OWN momentum to 0 —
	## mirroring the party's own Rapport-resets-on-Fumble rule (not
	## explicitly stated in the design doc; this project's own inferred
	## symmetric rule).
	if npc_test.is_fumble:
		npc_momentum[npc] = 0

	var exchange := SocialCombatResolver.finalize_npc_attack(npc_test, defender_test, target)
	if exchange.hit:
		## Design Doc Section 3: every NPC net-SL win drains that many
		## points from the party's own Rapport Pool, floored at 0.
		social_combat.rapport_pool.lose(exchange.opposed.net_success_levels)
		## Slice 3: a landed hit grows this NPC's own momentum by 1,
		## capped at 5 (this project's own judgment call — see the
		## npc_momentum field's own comment).
		npc_momentum[npc] = mini(5, npc_momentum.get(npc, 0) + 1)
		## Slice 3: an NPC's own Critical Hit leaves the target party
		## member Humiliated — thematic parity with Exposed's own
		## party-crit trigger (see _attempt_social_attack()/
		## _attempt_bring_the_muscle()).
		if npc_test.is_critical and not target.has_condition("Humiliated"):
			target.add_condition("Humiliated")
			_add_notice("[color=#c76a6a]%s is left Humiliated.[/color]" % target.character_name)
	_report_npc_exchange(npc, target, exchange)
	_refresh_roster_bars()
	_prompt_continue(_advance_social_combat_turn)

func _show_npc_attack_cards(npc: Character, target: Character, npc_test: TestResolver.TestResult,
		defender_test: TestResolver.TestResult, merge: bool) -> bool:
	var opposed := TestResolver.resolve_opposed(npc_test, defender_test)
	## defender_resists is used downstream (finalize_npc_attack's own
	## caller) as "the NPC's attack did NOT land" — a true tie counts as
	## the defender resisting (nothing happens to them either), same as
	## every other non-hit outcome.
	var defender_resists: bool = not opposed.attacker_wins
	_record_social_opposed_sl_result(npc, npc_test, opposed.attacker_wins, target, defender_test, defender_resists)
	## Per the request: a genuine tie (same SL AND same Target Number)
	## reads as "Tied" rather than the binary Resisted/Hit every other
	## outcome uses — see TestResolver.resolve_opposed()'s own comment.
	var npc_effect := "Hit" if opposed.attacker_wins else ("Tied" if opposed.is_true_tie else "Resisted")
	var npc_card := {
		"character_name": npc.character_name, "title": "Attacks", "subtitle": "Social Combat",
		"side": "adversary", "test": npc_test, "effects": [npc_effect] as Array[String],
		"dimmed": defender_resists and not opposed.is_true_tie,
	}
	var defender_card := {
		"character_name": target.character_name, "title": "Cool", "subtitle": "Defense",
		"side": "ally", "test": defender_test, "effects": [] as Array[String],
		"dimmed": not defender_resists,
		"mirror_layout": true,
	}
	var notice := _npc_attack_notice(npc.character_name, target.character_name, opposed.attacker_wins, opposed.is_true_tie, opposed.net_success_levels)
	if merge:
		_merge_into_latest_entry([npc_card, defender_card], notice)
	else:
		_add_history_entry([npc_card, defender_card], notice)
	return defender_resists

func _report_npc_exchange(npc: Character, target: Character, exchange: SocialCombatResolver.ExchangeResult) -> void:
	if not exchange.hit:
		_add_notice("[color=#8fbf6a]%s isn't rattled.[/color]" % target.character_name)
		if exchange.opposed.is_true_tie:
			_maybe_show_tie_reaction(npc)
		else:
			_maybe_show_npc_attack_miss_reaction(npc)
		return
	_add_notice("[color=#c76a6a]%s loses %d Composure (now %d/%d).[/color]" % [target.character_name, exchange.composure_damage, target.composure_current, target.composure_max])
	_maybe_show_npc_hit_reaction(npc)
	if target.composure_current <= 0:
		_add_notice("[b][color=#c76a6a]%s is knocked out of the conversation![/color][/b]" % target.character_name)

## Every NPC on the roster hit 0 Composure (Design Doc Section 8) — 100%
## reuse of the existing win path (reward, combat-handoff-on-success
## situations, _finish(true)), just gated on the whole roster now
## instead of a single flat target.
func _resolve_social_combat_win() -> void:
	var success_text: String = str(chosen_situation.get("success_reveal", ""))
	if success_text != "":
		_add_notice(_substitute(success_text))
	_resolve_win()

## Every present party member hit 0 Composure (Design Doc Section 8) —
## 100% reuse of the existing failure path (funny_loss_text, or a
## hand-off into real physical combat via combat_monster_names).
func _resolve_social_combat_failure() -> void:
	_resolve_failure()

## Neither side broke the other before SocialCombatEncounter.MAX_ROUNDS
## ran out — per the request ("we need to limit the attempts somehow").
## Reuses the same reward-nothing failure path everything else already
## goes through (funny_loss_text, or a hand-off into real combat if the
## rolled situation was combat-flagged — a conversation that drags on
## this long without resolving plausibly ends the same way a lost one
## would), just with its own notice explaining WHY it ended instead of
## a roll-driven loss.
func _resolve_social_combat_stalemate() -> void:
	_add_notice("[color=#8a7a6a]The conversation drags on and on without either side giving ground — eventually it just peters out.[/color]")
	_resolve_failure()

## Per the request: Fortune spend ("+1 SL" / "Reroll") and, once
## Fortune's exhausted, a Corruption-costing "Dark Deal" reroll — the
## same mechanics FieldEncounter's own combat rolls already offer, here
## simplified since a social encounter has none of combat's Advantage/
## Act Again/target-defeated concerns: just +1 SL, Reroll, Dark Deal
## (each gated the same way FieldEncounter's own _offer_fortune_spend
## gates them), and Continue. Applied to `roller` — whichever party
## member actually made this particular roll — not always the party
## leader. Renders as buttons in the action panel (the same area the
## skill/assist buttons already use) rather than a separate popup.
## Returns "sl", "reroll", or "" (Continue/nothing else to offer).
## `already_won`: per the request — on an OPPOSED roll, `test.success`
## (the roller's own raw half of the opposition) can be false while they
## still won the exchange outright (e.g. rolled 50 against their own
## Target of 45 — a raw failure — but the NPC's own resistance Test came
## out even worse). Reroll and Dark Deal exist to turn a loss into a
## win; if the exchange is already won, there's no upside to either —
## only a real risk of undoing an already-earned win for nothing — so
## both are withheld whenever the caller reports the roll as already
## won, regardless of what the raw `test.success` says. +1 SL stays
## available either way (never a downside). See _attempt_skill, which
## passes the real opposed-or-not `player_wins` here.
func _offer_fortune_spend(roller: Character, test: TestResolver.TestResult, already_won: bool = false) -> String:
	if not _fortune_chain_active:
		_reroll_used_this_fortune_chain = false
		_dark_deal_used_this_fortune_chain = false
	_clear(action_container)

	## Per a real, confirmed bug (the reported "social encounter gets
	## stuck and can't advance"): GDScript lambdas capture the enclosing
	## function's LOCAL variables BY VALUE at the moment the lambda is
	## created — assigning to a captured local from inside the lambda
	## does NOT propagate back out to the function that created it. The
	## original version of this function used local `var choice`/`var
	## done` set from inside each button's callback and then spun on
	## `while not done: await ...` — since the callback's assignments
	## never actually reached the outer `done`, that loop could never
	## see it become true and the whole encounter hung forever on
	## whichever roll first triggered a Fortune prompt with more than
	## one real choice on it (a Continue-only prompt was unaffected,
	## since that path skips the loop entirely — see below). Fixed by
	## using the two script-level (`self`-owned) fields below instead —
	## member variables ARE mutated correctly through a closure, since
	## the closure captures `self`, not the field by value — exactly
	## the pattern field_encounter_screen.gd's own copy of this same
	## prompt already uses (_pending_choice_str/awaiting_fortune_choice).
	_awaiting_fortune_choice = true
	_pending_fortune_choice_str = ""
	var options: Array = []
	if roller.fortune_points > 0:
		options.append({"text": "Spend Fortune: +1 SL", "callback": func():
			_pending_fortune_choice_str = "sl"
			_awaiting_fortune_choice = false
		})
	if not test.success and not already_won:
		## Bug fix: Luck has no separate reroll option — see
		## FieldEncounter's own copy of this function for the full
		## correction. It's just a bigger max Fortune Points cap
		## (Character.get_max_fortune_points), already applied wherever
		## fortune_points gets reset.
		if roller.fortune_points > 0 and not _reroll_used_this_fortune_chain:
			options.append({"text": "Spend Fortune: Reroll", "callback": func():
				_pending_fortune_choice_str = "reroll"
				_awaiting_fortune_choice = false
			})
		elif not _dark_deal_used_this_fortune_chain:
			options.append({"text": "Dark Deal: Reroll\n(1 Corruption)", "callback": func():
				_pending_fortune_choice_str = "dark_deal"
				_awaiting_fortune_choice = false
			})
	options.append({"text": "Continue", "callback": func():
		_pending_fortune_choice_str = ""
		_awaiting_fortune_choice = false
	})

	## Per the same shortcut FieldEncounter's own copy uses: when
	## Continue is the only thing on offer (no Fortune, Dark Deal already
	## spent), there's nothing left to actually decide — skip the prompt
	## and behave as if Continue had already been clicked.
	if options.size() > 1:
		for opt in options:
			var btn := Button.new()
			btn.add_theme_font_size_override("font_size", 12)
			btn.text = opt["text"]
			btn.pressed.connect(opt["callback"])
			action_container.add_child(btn)
		_refresh_focus_for_disabled_buttons(self)
		_auto_focus_default_button()
		while _awaiting_fortune_choice:
			await get_tree().process_frame
	else:
		_awaiting_fortune_choice = false
	_clear(action_container)
	var choice: String = _pending_fortune_choice_str

	if choice == "sl":
		_fortune_chain_active = true
		roller.fortune_points -= 1
		test.success_levels += 1
		test.sl_breakdown.append({"name": "Fortune Point", "amount": 1})
		_add_notice("[color=#8fbf6a]%s spends a Fortune Point: +1 SL (now %+d).[/color]" % [roller.character_name, test.success_levels])
	elif choice == "reroll":
		_fortune_chain_active = true
		_reroll_used_this_fortune_chain = true
		roller.fortune_points -= 1
		_add_notice("[color=#8fbf6a]%s spends a Fortune Point to reroll.[/color]" % roller.character_name)
	elif choice == "dark_deal":
		_fortune_chain_active = true
		_reroll_used_this_fortune_chain = true
		_dark_deal_used_this_fortune_chain = true
		roller.corruption_points += 1
		_add_notice("[color=#a05a9c]%s makes a Dark Deal with the Ruinous Powers to reroll — gains 1 Corruption point (now %d/%d).[/color]" % [roller.character_name, roller.corruption_points, roller.get_corruption_threshold()])
		var mutation_notice := CorruptionResolver.check_and_apply_threshold(roller)
		if mutation_notice != "":
			_add_notice(mutation_notice)
		## Normalised to "reroll" so the while-loop in _attempt_skill
		## treats a Dark Deal exactly like a Fortune reroll — same redo
		## behaviour, only the cost differs.
		choice = "reroll"
	else:
		_fortune_chain_active = false
	return choice

## Per the request ("No way to talk your way out of a fight"): whether a
## combat-flagged situation's win still turns physical is no longer a
## foregone conclusion — it now depends on how decisively the party won
## the Social Combat exchange itself, measured as the party's own
## aggregate Composure remaining (current/max, summed across every
## seated ally combatant, defeated-and-knocked-out members included —
## they count against how bruising the exchange was) at the moment of
## victory. Deliberately reuses Composure, a resource the player already
## watches all encounter long, rather than inventing a new hidden stat
## just for this one check. Only meaningful once `social_combat` exists
## (every win reaches this via _resolve_social_combat_win() — see that
## function's own comment); returns a neutral 1.0 (i.e. "clean") if
## there's nothing to divide by, so a malformed roster can't accidentally
## force every combat-flagged win into a fight.
func _party_composure_ratio() -> float:
	var total_current := 0
	var total_max := 0
	for member in social_combat.combatants:
		if member.allegiance != "ally":
			continue
		total_current += member.composure_current
		total_max += member.composure_max
	if total_max <= 0:
		return 1.0
	return float(total_current) / float(total_max)

## The bar for "talked down clean" below — the party's own judgment call
## (not something the request specified a number for, same spirit as the
## reaction-line thresholds and the round cap elsewhere in this file):
## keeping at least half the party's combined Composure by the time
## every NPC's own Composure hit 0 reads as a genuinely decisive win, not
## a photo finish. Easy to retune if this reads as too easy/hard to hit
## in actual play.
const COMBAT_AVOIDANCE_COMPOSURE_RATIO := 0.5

func _resolve_win() -> void:
	encounter_over = true
	## Per the request: a WIN can also reveal a combat-triggering
	## situation — the player genuinely succeeded at the task, but what
	## was really going on turns out to be dangerous (an ambush drawn
	## by the noise, something that was circling the whole time, and
	## so on). Checked here now, not just on total failure — a real,
	## confirmed bug: this branch previously never looked at
	## is_combat/combat_monster_names at all, so a situation whose own
	## success_reveal text described a fight starting never actually
	## started one.
	var is_combat: bool = bool(chosen_situation.get("is_combat", false))
	var combat_monsters: Array = chosen_situation.get("combat_monster_names", [])
	if is_combat and not combat_monsters.is_empty():
		## The reward is still genuinely earned — the player DID
		## complete the task — regardless of which of the two outcomes
		## below follows.
		player.experience_total += encounter_def.reward_xp
		player.progress_elder_help()
		if encounter_def.reward_item != "":
			player.inventory.append(encounter_def.reward_item)
		var reward_line := "You gained %d XP" % encounter_def.reward_xp
		if encounter_def.reward_item != "":
			reward_line += " and %s" % encounter_def.reward_item
		reward_line += "."
		if _party_composure_ratio() >= COMBAT_AVOIDANCE_COMPOSURE_RATIO:
			## A clean win: the threat this situation described never
			## actually materializes — same shape as any other genuine
			## win (reward line, autosave, _finish(true)), just with its
			## own notice explaining why no fight follows a combat-
			## flagged situation this time.
			_add_notice("[i][color=#8fbf6a]Whatever might have come of it, it never does — you talked your way clear before it could turn ugly.[/color][/i]")
			_add_notice("[b][color=lightgreen]★ Resolved![/color][/b] %s" % reward_line)
			GameState.autosave()
			_finish(true)
			return
		## A narrow win: the exchange itself got heated/desperate enough
		## that whatever this situation described is still coming —
		## original behaviour, unchanged, just now reached conditionally
		## instead of every single time.
		_add_notice("[i][color=#c76a6a]It was too close a thing — whatever's coming, it's still coming.[/color][/i]")
		_add_notice("[b][color=lightgreen]★ Resolved![/color][/b] %s" % reward_line)
		GameState.autosave()
		var monster_names: Array[String] = []
		for m in combat_monsters:
			monster_names.append(str(m))
		GameState.pending_encounter_monster_names = monster_names
		GameState.pending_encounter_is_player_ambush = false
		get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
		return
	player.experience_total += encounter_def.reward_xp
	## Per the request: Stage 2 of the Elder's own quest chain counts
	## real, GENUINELY won social encounters — the Roadside Peddler,
	## the Blustering Watchman, and so on — not the Elder's own story
	## conversation itself, which never calls this function at all
	## (see Overworld._show_elder_story).
	player.progress_elder_help()
	var reward_line := "You gained %d XP" % encounter_def.reward_xp
	if encounter_def.reward_item != "":
		player.inventory.append(encounter_def.reward_item)
		reward_line += " and %s" % encounter_def.reward_item
	reward_line += "."
	_add_notice("[b][color=lightgreen]★ Resolved![/color][/b] %s" % reward_line)
	GameState.autosave()
	_finish(true)

## Per the request: a total failure either ends harmlessly (a
## no-benefit "funny ending") or turns into a real fight against
## exactly the monster(s) the story already made clear were present —
## which of those two outcomes applies is now decided by the chosen
## situation, not a single fixed outcome for the whole encounter.
## Reuses the same pending_encounter_monster_names/
## pending_encounter_is_player_ambush GameState fields FieldEncounter
## already reads, with ambush explicitly false since this was never a
## surprise attack either way.
## Per the request ("losing a social encounter needs to carry some
## consequence"): monster names, present anywhere across the 12 core
## encounters' combat_monster_names, that read as genuinely Chaos-
## tainted rather than merely dangerous — checked against the LOST
## situation's own data (see _apply_social_combat_loss_consequences())
## to decide whether a bad loss risks Corruption, an ambient corrupting
## influence rather than a personal failing. Plain bandits/wolves/
## beasts don't qualify; deliberately a short, explicit list rather
## than a broader "is this a Chaos creature" lookup, since it only
## needs to cover what's actually referenced in this project's own
## encounter data.
const CORRUPTING_MONSTER_NAMES := ["Cultist", "Gor", "Clanrat"]

## Whichever present party member came off worst in the just-lost Social
## Combat (lowest Composure remaining, ties broken by whoever's checked
## first) — the target for the lingering Rattled Condition below.
## Deliberately reads from social_combat.combatants (every party member
## who was actually seated for this encounter), not get_living("ally"),
## since someone knocked out of the conversation entirely is exactly
## who came off worst.
func _worst_hit_ally() -> Character:
	var worst: Character = null
	var worst_ratio := 2.0
	for member in social_combat.combatants:
		if member.allegiance != "ally":
			continue
		var ratio: float = float(member.composure_current) / float(maxi(1, member.composure_max))
		if worst == null or ratio < worst_ratio:
			worst = member
			worst_ratio = ratio
	return worst

## Per the request ("losing a social encounter needs to carry some
## consequence") and the follow-up picks (a lingering Condition, an
## ambush on the hand-off fight, a Corruption cost for sinister
## situations, and losing money): applies real, lasting fallout to a
## just-LOST encounter, replacing the old flat "nothing lost either"
## line that was true right up until now. Called once from
## _resolve_failure() below (reached exclusively from Social Combat —
## see _resolve_social_combat_failure()/_resolve_social_combat_
## stalemate()), before it branches into the combat hand-off or the
## funny-loss-text ending, so both still get these consequences.
## Contains real `await`s (the Corruption block below offers each
## resisting character the usual Fortune/Dark Deal reroll chain) —
## _resolve_failure() awaits this directly rather than firing it and
## moving straight on to a possible scene change, since that would tear
## down this very screen mid-prompt.
func _apply_social_combat_loss_consequences() -> void:
	## Money: a flat dice-rolled loss (theft, a bribe you got talked
	## into, simply worse leverage once the conversation's gone badly) —
	## a fixed roll rather than a percentage, so it stings the same
	## whether the party's flush or nearly broke. Skipped outright if
	## there's genuinely nothing to take.
	if player.gold_crowns > 0:
		var lost_gc: int = mini(player.gold_crowns, Dice.roll_dice_string("1d10"))
		if lost_gc > 0:
			player.gold_crowns -= lost_gc
			_add_notice("[color=#c76a6a]The exchange costs you %d GC.[/color]" % lost_gc)

	## Lingering Condition: whoever came off worst carries a flat -10 to
	## their Tests out of the encounter — see Character.get_condition_
	## test_penalty_breakdown()'s own "Rattled" entry, cleared by a
	## proper rest same as Fatigued.
	var worst_ally := _worst_hit_ally()
	if worst_ally != null:
		worst_ally.add_condition("Rattled")
		_add_notice("[color=#c76a6a]%s is left Rattled by the exchange (-10 to Tests until a proper rest).[/color]" % worst_ally.character_name)

	## Corruption: only when the situation's own combat_monster_names
	## names something genuinely Chaos-tainted (see CORRUPTING_MONSTER_
	## NAMES above) — a corrupting influence, not a personal failing, so
	## every present party member is exposed. Per the Corrupting
	## Influences rule (Minor Exposure, per the rulebook page shown for
	## this fix): this is NOT an automatic gain — each exposed character
	## attempts their own Challenging (+0) Test to resist first, and only
	## gains 1 Corruption point if that Test is FAILED, rolled
	## individually per character rather than once for the whole party.
	## The rulebook leaves Endurance-vs-Cool to the GM ("usually physical
	## influences are resisted with Endurance, spiritual corruption is
	## resisted with Cool") — Cultists/Gors/Clanrats read as the latter
	## here (talk, dread, and the pull of the Ruinous Powers rather than
	## a physical taint), so this uses Cool. Each attempt gets the same
	## Fortune/Dark Deal reroll chain every other roll in Social Combat
	## offers (see _offer_fortune_spend) — a player can burn Fortune (or
	## take on MORE Corruption via a Dark Deal) trying to save a failed
	## resist roll, same as any other Test.
	var combat_monsters: Array = chosen_situation.get("combat_monster_names", [])
	var touched_by_corruption := false
	for m in combat_monsters:
		if CORRUPTING_MONSTER_NAMES.has(str(m)):
			touched_by_corruption = true
			break
	if touched_by_corruption:
		var cool_def: SkillDefinition = GameData.skill_db.find_by_name("Cool")
		for member in social_combat.combatants:
			if member.allegiance != "ally":
				continue
			var resist := TestResolver.resolve_skill_test(member, cool_def)
			_add_notice("[color=#8a8a8a]%s attempts a Challenging (+0) Cool Test to resist the taint of it (rolled %d vs %d).[/color]" % [member.character_name, resist.roll, resist.target])
			var choice := await _offer_fortune_spend(member, resist, false)
			while choice == "reroll" or choice == "sl":
				if choice == "reroll":
					resist = TestResolver.resolve_skill_test(member, cool_def)
					_add_notice("[color=#8a8a8a]%s rerolls (now %d vs %d).[/color]" % [member.character_name, resist.roll, resist.target])
				choice = await _offer_fortune_spend(member, resist, false)
			if resist.success:
				_add_notice("[color=#8fbf6a]%s shakes off the taint of it (Cool Test passed).[/color]" % member.character_name)
				continue
			member.corruption_points += 1
			_add_notice("[color=#a05a9c]%s fails to resist (Cool Test) — the taint leaves its mark, gaining 1 Corruption point (now %d/%d).[/color]" % [member.character_name, member.corruption_points, member.get_corruption_threshold()])
			var mutation_notice := CorruptionResolver.check_and_apply_threshold(member)
			if mutation_notice != "":
				_add_notice(mutation_notice)

	## Ambush: a combat-flagged loss no longer hands off to the exact
	## same fair fight a win-into-combat would — failing to talk (or
	## fight) your way clear means whatever's coming gets the drop on
	## the party instead. field_encounter_screen.gd's own _setup_battle_
	## grid() already reads Surprised directly off each Character's
	## Conditions (see that function's own comment — built with exactly
	## this "future monster-ambushes-player case" in mind), so simply
	## applying it here, before the scene change below, is enough.
	var is_combat: bool = bool(chosen_situation.get("is_combat", false))
	if is_combat and not combat_monsters.is_empty():
		for member in social_combat.combatants:
			if member.allegiance == "ally":
				member.add_condition("Surprised")

func _resolve_failure() -> void:
	encounter_over = true
	## Awaited (not fired-and-forgotten): the Corruption block inside can
	## put up its own Fortune/Dark Deal prompts, and the combat hand-off
	## just below this can change the whole scene out from under those
	## prompts if it doesn't wait for them to actually finish first.
	await _apply_social_combat_loss_consequences()
	var is_combat: bool = bool(chosen_situation.get("is_combat", false))
	var combat_monsters: Array = chosen_situation.get("combat_monster_names", [])
	if is_combat and not combat_monsters.is_empty():
		var monster_names: Array[String] = []
		for m in combat_monsters:
			monster_names.append(str(m))
		GameState.pending_encounter_monster_names = monster_names
		GameState.pending_encounter_is_player_ambush = false
		get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
		return
	var funny_text: String = str(chosen_situation.get("funny_loss_text", ""))
	if funny_text != "":
		_add_notice(_substitute(funny_text))
	_finish(false)

func _finish(_won: bool) -> void:
	## Per the request ("completing a social and combat encounter
	## should advance time by 30 mins win or lose"): this is the one
	## place every social encounter that actually concludes here (not
	## escalating into real combat — see _resolve_win()/_resolve_
	## failure()'s own change_scene_to_file("FieldEncounter.tscn")
	## branches, which hand off to that fight's own _end_battle() for
	## its own 30-minute charge instead) funnels through, win or lose
	## alike, so a flat 30 minutes is charged here exactly once.
	GameState.advance_minutes(30)
	_clear(action_container)
	return_button.disabled = false
	return_button.visible = true
	_refresh_focus_for_disabled_buttons(self)
	_auto_focus_default_button()

func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _add_notice(text: String) -> void:
	_add_history_entry([], text)

## Per the request: social encounters now show real roll cards — the
## exact same visual card combat already uses (see RollCardBuilder,
## shared between both screens) — whenever an actual roll happens,
## not just plain text. `cards` is an array of the same {character_
## name, title, subtitle, side, test, effects} dicts FieldEncounter's
## own cards use.
func _add_history_entry(cards: Array, notice: String) -> void:
	history.push_front({"cards": cards, "notice": notice})
	if history.size() > MAX_HISTORY_ENTRIES:
		history.resize(MAX_HISTORY_ENTRIES)
	_rebuild_history_display()

## Appends to the current newest entry rather than pushing a new one —
## same reasoning as FieldEncounter's own copy: a Fortune/Dark-Deal
## reroll's new card sits alongside the roll it replaced, in the same
## still-latest entry, rather than bumping the original into compact
## mode (or losing it) the instant the reroll logs.
func _merge_into_latest_entry(cards: Array, notice: String) -> void:
	var latest: Dictionary = history[0]
	var merged_cards: Array = latest.get("cards", [])
	merged_cards.append_array(cards)
	latest["cards"] = merged_cards
	var existing_notice: String = latest.get("notice", "")
	latest["notice"] = existing_notice + ("\n" if existing_notice != "" and notice != "" else "") + notice
	history[0] = latest
	_rebuild_history_display()

## Per the request: characters revealed per second for the typewriter
## effect — tuned toward natural reading pace rather than an
## instant-reveal-feels-rushed speed or a slower-than-reading crawl.
const TYPEWRITER_CHARS_PER_SECOND := 28.0
var _typewriter_tween: Tween = null

## Per the request: holding the left mouse button speeds the typewriter
## reveal up significantly (rather than skipping straight to the full
## text) — anyone who's already read a story beat, or is just impatient,
## can hold to blow through it fast without losing the effect entirely.
## Applied via Tween.set_speed_scale() so it's a live speed change on
## whichever tween is currently running, not a restart — releasing the
## button returns to the normal pace mid-reveal. See _unhandled_input().
const TYPEWRITER_FAST_FORWARD_MULTIPLIER := 8.0
var _typewriter_fast_forward_held := false

func _rebuild_history_display() -> void:
	_clear(history_list)
	## Per the request: rendered oldest-first, newest-last, matching
	## the same fix applied to FieldEncounter's own log. history[]
	## itself still stores newest at index 0 internally.
	for i in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[i]
		var is_latest := i == 0
		var entry_box := VBoxContainer.new()
		entry_box.add_theme_constant_override("separation", 4)

		var cards: Array = entry.get("cards", [])
		if not cards.is_empty():
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 10)
			row.add_theme_constant_override("v_separation", 10)
			for card_data in cards:
				row.add_child(RollCardBuilder.build_roll_card(card_data, not is_latest))
			entry_box.add_child(row)

		var notice: String = entry.get("notice", "")
		if notice != "":
			var lbl := RichTextLabel.new()
			lbl.bbcode_enabled = true
			lbl.fit_content = true
			lbl.scroll_active = false
			lbl.text = notice
			## Per the request: bigger and white, and — unlike combat's
			## own dimmed/shrunk history convention — NOT dimmed or
			## shrunk for past entries either, so earlier story beats
			## stay just as easy to read as the newest one. Explicit
			## [color=...] BBCode already present in some notices (a
			## success/failure highlight, say) still overrides this
			## same as before; this only changes the base/default colour.
			## Per a follow-up request ("log text a bit too large"): the
			## original 19 towered over every other piece of UI text on
			## this screen (buttons sit at 12-13, headers at 8-11) —
			## dialled back to 15, still clearly the biggest/most
			## readable text on screen but no longer overwhelming.
			lbl.add_theme_font_size_override("normal_font_size", 15)
			lbl.add_theme_color_override("default_color", Color(1, 1, 1))
			## Per a follow-up request ("a slightly larger gap between
			## lines"): RichTextLabel's own default line spacing reads as
			## cramped once a notice wraps across more than one line (the
			## story paragraphs above regularly do) — a few extra pixels
			## between wrapped lines makes multi-line notices noticeably
			## easier to read without changing the font size again.
			lbl.add_theme_constant_override("line_separation", 8)
			entry_box.add_child(lbl)
			if is_latest:
				_play_typewriter(lbl, notice)

		history_list.add_child(entry_box)
		if i > 0:
			history_list.add_child(HSeparator.new())
	_scroll_history_to_bottom()

## Per the request: reveals the latest notice's own text progressively,
## like it's being written, rather than appearing all at once. Only
## ever applied to the single newest entry — _rebuild_history_display()
## is called once per genuinely new entry, so this can't accidentally
## replay on older text that's already been read.
func _play_typewriter(label: RichTextLabel, full_text: String) -> void:
	if _typewriter_tween != null and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	label.visible_characters = 0
	var target_chars: int = label.get_total_character_count()
	if target_chars <= 0:
		return
	var duration: float = target_chars / TYPEWRITER_CHARS_PER_SECOND
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_property(label, "visible_characters", target_chars, duration)
	## If the button's already held down when a new line starts revealing
	## (e.g. the player kept holding through the previous line finishing),
	## the new tween should start fast too, not snap back to normal pace
	## for one line before _unhandled_input catches up.
	if _typewriter_fast_forward_held:
		_typewriter_tween.set_speed_scale(TYPEWRITER_FAST_FORWARD_MULTIPLIER)

## Per the request: the log should always focus on the newest entry,
## now at the bottom — see field_encounter_screen.gd's own copy of
## this fix for why history_list.sort_children (connected in _ready)
## is the reliable trigger, with this manual call as a safety net.
func _scroll_history_to_bottom() -> void:
	_do_scroll_history_to_bottom()

func _do_scroll_history_to_bottom() -> void:
	if is_instance_valid(history_scroll) and history_list.get_child_count() > 0:
		history_scroll.ensure_control_visible(history_list.get_child(history_list.get_child_count() - 1))
		history_scroll.scroll_vertical = int(history_scroll.get_v_scroll_bar().max_value)

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	## Per the request: held (not clicked) left mouse button fast-forwards
	## the typewriter reveal — checked before the is_pressed()-only guard
	## below since a mouse-button RELEASE (is_pressed() == false) is
	## exactly the signal that needs to bring the speed back to normal.
	## Deliberately not "handled" here (no set_input_as_handled()) so a
	## press that actually lands on a button (a skill choice, Return,
	## etc.) still reaches it normally — Control nodes consume their own
	## clicks before _unhandled_input ever sees them, so this only fires
	## for clicks on the log/background, which is exactly where holding
	## to skip through story text makes sense.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_typewriter_fast_forward_held = event.pressed
		if _typewriter_tween != null and _typewriter_tween.is_valid():
			_typewriter_tween.set_speed_scale(TYPEWRITER_FAST_FORWARD_MULTIPLIER if _typewriter_fast_forward_held else 1.0)
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if encounter_over and not return_button.disabled:
			get_viewport().set_input_as_handled()
			_on_return_pressed()
