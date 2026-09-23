extends Resource
class_name PrayerDatabase

@export var prayers: Array[PrayerDefinition] = []

## Blessings by Cult (p.220) — each of the 10 Primary Gods grants a
## specific set of 6 Blessings (by generic name, since the same
## Blessing is shared and reflavoured across multiple cults — see the
## book's "Names" sidebar, p.221). "a character with the Bless Talent
## receives all six Blessings for their cult." Only the exact 6 for
## each god are transcribed here, checked directly against the table.
const CULT_BLESSINGS := {
	"Manann": ["Blessing of Battle", "Blessing of Breath", "Blessing of Courage", "Blessing of Hardiness", "Blessing of Savagery", "Blessing of Tenacity"],
	"Morr": ["Blessing of Breath", "Blessing of Courage", "Blessing of Fortune", "Blessing of Righteousness", "Blessing of Tenacity", "Blessing of Wisdom"],
	"Myrmidia": ["Blessing of Battle", "Blessing of Conscience", "Blessing of Courage", "Blessing of Fortune", "Blessing of Protection", "Blessing of Righteousness"],
	"Ranald": ["Blessing of Charisma", "Blessing of Conscience", "Blessing of Finesse", "Blessing of Fortune", "Blessing of Protection", "Blessing of Wit"],
	"Rhya": ["Blessing of Breath", "Blessing of Conscience", "Blessing of Grace", "Blessing of Healing", "Blessing of Protection", "Blessing of Recuperation"],
	"Shallya": ["Blessing of Breath", "Blessing of Conscience", "Blessing of Healing", "Blessing of Protection", "Blessing of Recuperation", "Blessing of Tenacity"],
	"Sigmar": ["Blessing of Battle", "Blessing of Courage", "Blessing of Hardiness", "Blessing of Might", "Blessing of Protection", "Blessing of Righteousness"],
	"Taal": ["Blessing of Battle", "Blessing of Breath", "Blessing of Conscience", "Blessing of Hardiness", "Blessing of The Hunt", "Blessing of Savagery"],
	"Ulric": ["Blessing of Battle", "Blessing of Courage", "Blessing of Hardiness", "Blessing of Might", "Blessing of Savagery", "Blessing of Tenacity"],
	"Verena": ["Blessing of Conscience", "Blessing of Courage", "Blessing of Fortune", "Blessing of Righteousness", "Blessing of Wisdom", "Blessing of Wit"],
}

func find_by_name(name: String) -> PrayerDefinition:
	for p in prayers:
		if p.prayer_name == name:
			return p
	return null

## The 6 Blessing names a character with Bless(god) automatically has —
## empty if this god's list hasn't been added to CULT_BLESSINGS yet
## (currently all 10 are populated; see the comment above).
func get_blessings_for_god(god: String) -> Array[String]:
	var result: Array[String] = []
	for n in CULT_BLESSINGS.get(god, []):
		result.append(n)
	return result

## All Miracles available to a given god, in the order they appear in
## the data — currently only Sigmar's are populated (see core_prayers.tres).
func get_miracles_for_god(god: String) -> Array[PrayerDefinition]:
	var result: Array[PrayerDefinition] = []
	for p in prayers:
		if p.prayer_type == "Miracle" and p.god == god:
			result.append(p)
	return result

