extends RefCounted
class_name SocialRapportPool
## The party's own banked "Rapport" resource (Design Doc "Social Combat
## — Design Doc v1", Section 3 — the user's own original "CAP" idea,
## renamed to avoid colliding with real combat's differently-behaved
## GroupAdvantagePool). Modeled on GroupAdvantagePool's own shape (a
## plain int counter, named gain/spend methods) but with Social
## Combat's own rules instead of Up in Arms':
##
## - Starts at 0.
## - Each point banked adds +10 (roll_bonus()) to every party member's
##   own social Attack rolls -- not spent to get it, just a standing
##   bonus that scales with however much is currently banked.
## - Capped by the party's best present Status Tier (max_for_party()).
## - Any party Fumble wipes it to 0 (reset()) -- screen-side, since
##   only the screen knows when a roll it just made was a Fumble.
## - An NPC's own successful attack drains it by that exchange's own
##   Net SL, floored at 0 (lose()).
## - The three Tactical Maneuvers (Distract 1, Overwhelm 2, Bring in
##   the Muscle 3 -- Design Doc Section 7) spend it directly (spend()).

var current: int = 0

## Design Doc Section 3: {1: 2, 2: 3, 3: 5} for Brass/Silver/Gold.
const MAX_BY_STATUS := {1: 2, 2: 3, 3: 5}

## The cap for a given living party (an Array[Character], allies only)
## — whichever present member has the best Status Tier sets the cap for
## the whole party's shared pool. Character.get_status_ordinal() already
## returns 1/2/3 for Brass/Silver/Gold; an empty/all-defeated party
## falls back to the Brass floor rather than an undefined cap.
static func max_for_party(party: Array) -> int:
	var best_status := 1
	for member in party:
		if member == null:
			continue
		best_status = maxi(best_status, member.get_status_ordinal())
	return MAX_BY_STATUS.get(best_status, 2)

## The standing +10-per-point bonus every party Attack roll gets right
## now, before any of it is spent.
func roll_bonus() -> int:
	return current * 10

func gain(amount: int, cap: int) -> void:
	if amount <= 0:
		return
	current = mini(cap, current + amount)

## Returns true and deducts if the pool can afford it; false (no
## change) otherwise -- same contract as GroupAdvantagePool.spend().
func spend(amount: int) -> bool:
	if current < amount:
		return false
	current -= amount
	return true

## An NPC's own successful attack draining the pool (Design Doc Section
## 3) is never a "can't afford it" situation the way a Maneuver spend
## is -- it just floors at 0.
func lose(amount: int) -> void:
	current = maxi(0, current - amount)

## Wiped by any party Fumble (Design Doc Section 3).
func reset() -> void:
	current = 0
