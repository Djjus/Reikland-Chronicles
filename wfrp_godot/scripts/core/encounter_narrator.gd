extends RefCounted
class_name EncounterNarrator
## Per the request: a short narrative line shown before transitioning
## from the Overworld into a combat encounter, replacing the old
## plain "An enemy approaches!" label with something that actually
## has a bit of personality — dark, cynical, occasionally crude,
## matching this project's own established grimdark-comedic tone.
## Original writing, randomly selected from a small pool rather than
## a single fixed line, so it doesn't go stale after the third fight.

const LINES := [
	"Something ahead smells like trouble, unwashed trouble, and it's coming this way.",
	"There's a rustling in the treeline that's either the wind or something that wants a bite out of you. Smart money's on the second one.",
	"A twig snaps somewhere that no twig should be snapping on its own. Wonderful.",
	"Whatever's ahead clearly didn't get the memo about minding its own business.",
	"The road narrows, the light dims, and every survival instinct you own starts screaming at once.",
	"Someone — or something — is about to have a very bad afternoon. Try to make sure it isn't you.",
	"You get the distinct, unpleasant feeling of being sized up for dinner.",
	"There's blood on the ground that isn't yours yet. Emphasis on yet.",
	"A shape moves in the gloom ahead, entirely uninterested in a polite introduction.",
	"The birds went quiet a moment ago. That's never, ever a good sign.",
]

static func random_line() -> String:
	if LINES.is_empty():
		return "An enemy approaches!"
	return LINES[randi() % LINES.size()]
