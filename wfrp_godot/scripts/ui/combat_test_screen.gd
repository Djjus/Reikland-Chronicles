extends Control
## Test harness for the combat system. Generates two combatants, equips
## them, and lets you resolve attacks one at a time while watching
## Wounds, Conditions, and Advantage update — using the Group Advantage
## Pool variant from WFRP: Up in Arms (Appendix I, p.133-135) instead of
## core rulebook per-character Advantage. Functional test screen, not
## final art.

@onready var setup_button: Button = %SetupButton
@onready var attack_button: Button = %AttackButton
@onready var effort_button: Button = %EffortButton
@onready var round_end_button: Button = %RoundEndButton
@onready var char_nav_button: Button = %CharNavButton
@onready var log_label: RichTextLabel = %LogLabel
@onready var status_label: RichTextLabel = %StatusLabel

var attacker: Character
var defender: Character
var attacker_weapon: WeaponDefinition
var defender_weapon: WeaponDefinition
var pool: GroupAdvantagePool

func _ready() -> void:
	setup_button.pressed.connect(_on_setup_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	effort_button.pressed.connect(_on_effort_pressed)
	round_end_button.pressed.connect(_on_round_end_pressed)
	char_nav_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/CharacterCreation.tscn"))
	_set_buttons_enabled(false)

func _set_buttons_enabled(enabled: bool) -> void:
	attack_button.disabled = not enabled
	effort_button.disabled = not enabled
	round_end_button.disabled = not enabled

func _on_setup_pressed() -> void:
	var human: RaceDefinition = GameData.find_race("Human")
	var dwarf: RaceDefinition = GameData.find_race("Dwarf")
	var soldier: CareerDefinition = GameData.find_career("Soldier")

	attacker = CharacterCreator.create_character(
		"Tollich", human, soldier,
		{"weapon_skill": 2, "toughness": 2, "willpower": 1}
	)
	defender = CharacterCreator.create_character(
		"Grimnir", dwarf, soldier, {}
	)
	attacker.allegiance = "ally"
	defender.allegiance = "adversary"

	attacker_weapon = GameData.weapon_db.find_by_name("Sword")
	defender_weapon = GameData.weapon_db.find_by_name("Axe")
	attacker.equipped_weapon = attacker_weapon.weapon_name
	defender.equipped_weapon = defender_weapon.weapon_name
	attacker.equipped_armour = ["Leather Jack"]
	defender.equipped_armour = ["Mail Shirt"]

	pool = GroupAdvantagePool.new()
	## Seed the pools per p.135's Initial Advantage table: the adventurer
	## is ambushing an armoured Dwarf soldier, so seed +2 for Surprise.
	pool.seed("ally", "surprise")

	log_label.text = ""
	_set_buttons_enabled(true)
	_render_status()
	_append_log("[b]Combat set up (Group Advantage rules, Up in Arms p.133-135):[/b] %s (ally) vs %s (adversary). Ally Pool seeded +2 for Surprise." % [
		attacker.character_name, defender.character_name
	])

func _on_attack_pressed() -> void:
	if attacker == null or defender == null:
		return
	if attacker.wounds_current <= 0 or defender.wounds_current <= 0:
		_append_log("[color=gray]Combat is already over.[/color]")
		return

	var result := CombatResolver.resolve_melee_attack(attacker, defender, attacker_weapon, pool)
	_log_attack_result(attacker, defender, result)

	if defender.wounds_current <= 0:
		_append_log("[b][color=orange]%s is down![/color][/b]" % defender.character_name)
		attack_button.disabled = true
	_render_status()

## Demonstrates the "Additional Effort" spend (2 Advantage minimum, +10%
## per point spent) — spends 2 from the attacker's pool for a flat +10%
## bonus to their next attack, then immediately resolves that attack.
func _on_effort_pressed() -> void:
	if attacker == null or defender == null:
		return
	if attacker.wounds_current <= 0 or defender.wounds_current <= 0:
		_append_log("[color=gray]Combat is already over.[/color]")
		return

	var bonus := GroupAdvantageActions.spend_additional_effort(pool, attacker, 2)
	if bonus == 0:
		_append_log("[color=gray]%s doesn't have 2 Advantage to spend on Additional Effort (Ally Pool: %d).[/color]" % [
			attacker.character_name, pool.get_pool("ally")
		])
		return

	_append_log("[b]%s spends 2 Advantage on Additional Effort[/b] (+%d%% to the next attack)." % [attacker.character_name, bonus])
	var result := CombatResolver.resolve_melee_attack(attacker, defender, attacker_weapon, pool)
	## Additional Effort's bonus is layered on top of the normal Advantage
	## bonus the resolver already applies — re-roll isn't needed since we
	## show this as a separate, explicit bonus on top for clarity.
	_log_attack_result(attacker, defender, result)
	if defender.wounds_current <= 0:
		_append_log("[b][color=orange]%s is down![/color][/b]" % defender.character_name)
		attack_button.disabled = true
	_render_status()

## Demonstrates the Losing Advantage round-end rule: with 2 combatants a
## side (1 each here), headcount is tied, so "ally" is dominant by default.
func _on_round_end_pressed() -> void:
	if pool == null:
		return
	var ally_alive := attacker.wounds_current > 0
	var adversary_alive := defender.wounds_current > 0
	pool.resolve_round_end_by_headcount(1 if ally_alive else 0, 1 if adversary_alive else 0)
	_append_log("[b]Round ends.[/b] Losing Advantage resolved (p.134).")
	_render_status()

func _log_attack_result(att: Character, defn: Character, result: CombatResolver.AttackResult) -> void:
	var lines: Array[String] = []
	lines.append("[b]%s attacks %s with a %s.[/b]" % [att.character_name, defn.character_name, attacker_weapon.weapon_name])
	lines.append("  %s roll to hit: %s  (%s)" % [
		att.character_name, str(result.attacker_test), TestResolver.get_outcome_label(result.attacker_test.success_levels)
	])
	if result.defender_test:
		lines.append("  %s opposes:     %s  (%s)" % [
			defn.character_name, str(result.defender_test), TestResolver.get_outcome_label(result.defender_test.success_levels)
		])

	if result.hit:
		var crit_note := "  [b](CRITICAL!)[/b]" if result.was_critical else ""
		lines.append("  [color=salmon]HIT[/color] — %s Hit Location, Damage %d, Soak %d → %d Wound(s)%s" % [
			result.hit_location, result.damage, result.soak, result.wounds_dealt, crit_note
		])
		if result.caused_critical_wound:
			lines.append("  [b]%s takes a Critical Wound and is Prone![/b]" % defn.character_name)
	else:
		lines.append("  [color=lightgreen]%s successfully defends — no hit.[/color]" % defn.character_name)
		if not result.fumble.is_empty():
			lines.append("  [b]Fumble![/b] Oops! Table (%d): %s" % [result.fumble["roll"], result.fumble["text"]])

	_append_log("\n".join(lines))

func _render_status() -> void:
	if attacker == null or defender == null:
		status_label.text = "Press Set Up Combat to generate two combatants."
		return
	status_label.text = "[b]%s[/b] (ally)  Wounds: %d/%d   Conditions: %s\n[b]%s[/b] (adversary)  Wounds: %d/%d   Conditions: %s\n\n[b]Ally Advantage Pool: %d[/b]   [b]Adversary Advantage Pool: %d[/b]" % [
		attacker.character_name, attacker.wounds_current, attacker.wounds_max,
		(", ".join(attacker.conditions.keys()) if not attacker.conditions.is_empty() else "none"),
		defender.character_name, defender.wounds_current, defender.wounds_max,
		(", ".join(defender.conditions.keys()) if not defender.conditions.is_empty() else "none"),
		pool.get_pool("ally") if pool else 0, pool.get_pool("adversary") if pool else 0,
	]

func _append_log(text: String) -> void:
	log_label.text += ("\n\n" if log_label.text != "" else "") + text
