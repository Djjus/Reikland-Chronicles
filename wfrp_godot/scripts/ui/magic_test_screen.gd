extends Control
## Test harness for the magic and prayer systems: generates a Wizard and
## a Priest, and lets you cast spells / channel / pray against real book
## mechanics (Casting Test, Channelling, Miscasts, Wrath of the Gods).

@onready var wizard_label: RichTextLabel = %WizardLabel
@onready var priest_label: RichTextLabel = %PriestLabel
@onready var spell_option: OptionButton = %SpellOption
@onready var prayer_option: OptionButton = %PrayerOption
@onready var cast_button: Button = %CastButton
@onready var channel_button: Button = %ChannelButton
@onready var pray_button: Button = %PrayButton
@onready var sin_button: Button = %SinButton
@onready var log_label: RichTextLabel = %LogLabel
@onready var nav_button: Button = %NavButton

var wizard: Character
var priest: Character
var channel_progress: MagicResolver.ChannellingProgress

func _ready() -> void:
	nav_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/CharacterCreation.tscn"))
	cast_button.pressed.connect(_on_cast_pressed)
	channel_button.pressed.connect(_on_channel_pressed)
	pray_button.pressed.connect(_on_pray_pressed)
	sin_button.pressed.connect(_on_sin_pressed)
	_setup_casters()
	_populate_spells()
	_populate_prayers()
	_render_casters()

func _setup_casters() -> void:
	var human: RaceDefinition = GameData.find_race("Human")
	var wizard_career: CareerDefinition = GameData.find_career("Wizard")
	var priest_career: CareerDefinition = GameData.find_career("Priest")

	wizard = CharacterCreator.create_character("Aldric the Apprentice", human, wizard_career,
		{"intelligence": 2, "willpower": 2, "weapon_skill": 1})
	## Give the test caster a fighting chance: a few free advances in the
	## skills their career actually trains, since character creation here
	## doesn't auto-spend starting XP (see Advancement.tscn for that flow).
	wizard.skill_advances["Language (Magick)"] = 5
	wizard.skill_advances["Channelling (Aqshy)"] = 5
	wizard.talents_taken["Arcane Magic"] = 1

	priest = CharacterCreator.create_character("Sister Elsa", human, priest_career,
		{"willpower": 2, "toughness": 2, "agility": 1})
	priest.skill_advances["Pray"] = 5
	priest.talents_taken["Bless (Sigmar)"] = 1
	priest.talents_taken["Invoke (Sigmar)"] = 1

func _populate_spells() -> void:
	spell_option.clear()
	for s in GameData.spell_db.spells:
		spell_option.add_item("%s [%s CN%d]" % [s.spell_name, s.spell_type, s.casting_number])

func _populate_prayers() -> void:
	prayer_option.clear()
	for p in GameData.prayer_db.prayers:
		prayer_option.add_item("%s [%s]" % [p.prayer_name, p.prayer_type])

func _on_cast_pressed() -> void:
	var spell: SpellDefinition = GameData.spell_db.spells[spell_option.selected]
	var result := MagicResolver.cast(wizard, spell)
	var lines: Array[String] = []
	lines.append("[b]%s casts %s[/b] (CN %d)" % [wizard.character_name, spell.spell_name, spell.casting_number])
	lines.append("  Language (Magick): %s (%s)" % [str(result.test_result), TestResolver.get_outcome_label(result.test_result.success_levels)])
	if result.success:
		lines.append("  [color=lightgreen]Cast successfully![/color]" + (" Overcast by %d SL (Winds of Magic table: %d Damage / +%d Target(s) available if the spell qualifies)." % [result.overcast_sl, MagicResolver.get_overcast_benefit("damage", result.overcast_sl), MagicResolver.get_overcast_benefit("targets", result.overcast_sl)] if result.overcast_sl > 0 else ""))
	else:
		lines.append("  [color=salmon]The spell fails to take hold.[/color]")
	if result.critical:
		lines.append("  [b](Critical Cast!)[/b]")
	if result.fumble:
		lines.append("  [b](Fumbled!)[/b]")
	if not result.miscast.is_empty():
		var tier: String = result.miscast.get("tier", "minor")
		lines.append("  [b]%s Miscast (roll %d):[/b] %s" % [tier.capitalize(), result.miscast["roll"], result.miscast["text"]])
	_append_log("\n".join(lines))
	_render_casters()

func _on_channel_pressed() -> void:
	var spell: SpellDefinition = GameData.spell_db.spells[spell_option.selected]
	if channel_progress == null or channel_progress.spell != spell:
		channel_progress = MagicResolver.ChannellingProgress.new()
		channel_progress.spell = spell
	var out := MagicResolver.channel_round(wizard, channel_progress, "Aqshy")
	var result: TestResolver.TestResult = out["test_result"]
	var lines: Array[String] = []
	lines.append("[b]%s channels the Winds of Magic[/b] for %s (CN %d)" % [wizard.character_name, spell.spell_name, spell.casting_number])
	lines.append("  Channelling: %s (%s)" % [str(result), TestResolver.get_outcome_label(result.success_levels)])
	lines.append("  Accumulated SL: %d / %d" % [channel_progress.accumulated_sl, spell.casting_number])
	if not out["miscast"].is_empty():
		var tier: String = out["miscast"].get("tier", "minor")
		lines.append("  [b]%s Miscast (roll %d):[/b] %s" % [tier.capitalize(), out["miscast"]["roll"], out["miscast"]["text"]])
	if out["ready"]:
		lines.append("  [color=lightgreen]Ready to cast next round at CN 0![/color]")
	_append_log("\n".join(lines))

func _on_pray_pressed() -> void:
	var prayer: PrayerDefinition = GameData.prayer_db.prayers[prayer_option.selected]
	var result := PrayerResolver.pray(priest, prayer)
	var lines: Array[String] = []
	lines.append("[b]%s prays for %s[/b] (%s)" % [priest.character_name, prayer.prayer_name, prayer.prayer_type])
	lines.append("  Pray: %s (%s)" % [str(result.test_result), TestResolver.get_outcome_label(result.test_result.success_levels)])
	if result.success:
		lines.append("  [color=lightgreen]%s[/color]" % prayer.summary)
	else:
		lines.append("  [color=salmon]Your god does not answer this time.[/color]")
	if not result.wrath.is_empty():
		lines.append("  [b]Wrath of the Gods (roll %d):[/b] %s" % [result.wrath["roll"], result.wrath["text"]])
	_append_log("\n".join(lines))
	_render_casters()

func _on_sin_pressed() -> void:
	priest.sin_points += 1
	_append_log("[i]%s commits a minor infraction against their Cult's Strictures — Sin points now %d.[/i]" % [priest.character_name, priest.sin_points])
	_render_casters()

func _render_casters() -> void:
	wizard_label.text = "[b]%s[/b] (Wizard) — Language (Magick): %d, Channelling (Aqshy): %d" % [
		wizard.character_name,
		wizard.get_skill_value(GameData.skill_db.find_by_name("Language (Magick)")),
		wizard.get_skill_value(GameData.skill_db.find_by_name("Channelling"), "Aqshy"),
	]
	priest_label.text = "[b]%s[/b] (Priest) — Pray: %d — Sin points: %d" % [
		priest.character_name,
		priest.get_skill_value(GameData.skill_db.find_by_name("Pray")),
		priest.sin_points,
	]

func _append_log(text: String) -> void:
	log_label.text += ("\n\n" if log_label.text != "" else "") + text
