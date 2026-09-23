extends Resource
class_name PrayerDefinition
## A single prayer, checked against the rulebook's Blessings and Miracles
## rules (p.217-218). Named deities/prayers here are original compositions
## following the mechanical pattern (Blessed characters with Bless/Invoke
## enact prayers via a Pray Test) rather than transcriptions of the book's
## specific deity prayer lists.

@export var prayer_name: String = ""
@export_enum("Blessing", "Miracle") var prayer_type: String = "Blessing"
## "Any" for a generic prayer any Blessed character can learn; otherwise
## the deity it's associated with.
@export var god: String = "Any"

@export var range_text: String = "You"
@export var target_text: String = "You"
@export var duration_text: String = "Instant"

@export var summary: String = ""

func get_max_rank(_character: Character) -> int:
	return 1
