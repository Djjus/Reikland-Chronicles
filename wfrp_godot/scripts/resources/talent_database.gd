extends Resource
class_name TalentDatabase

@export var talents: Array[TalentDefinition] = []

func find_by_name(talent_name: String) -> TalentDefinition:
	for t in talents:
		if t.talent_name == talent_name:
			return t
	## Some talents (Etiquette, Bless, Invoke, Fearless...) get a
	## situational qualifier that varies by which career grants them —
	## "Etiquette (Cultists)" from one career vs "Etiquette (Nobility)"
	## from another — rather than a single fixed qualifier on the talent
	## itself. Career data and character.talents_taken store the full
	## qualified string as-is (same pattern skills already use for
	## specialisations), so falling back to a base-name match here lets
	## every existing call site resolve those without needing to know
	## about the distinction.
	var paren := talent_name.find(" (")
	if paren != -1:
		var base_name := talent_name.substr(0, paren)
		for t in talents:
			if t.talent_name == base_name:
				return t
	return null
