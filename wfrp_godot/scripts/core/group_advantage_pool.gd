extends RefCounted
class_name GroupAdvantagePool
## Optional variant Advantage system from WFRP: Up in Arms, Appendix I
## (p.133-135), checked against the sourcebook rather than reconstructed
## from memory. Instead of each combatant tracking their own Advantage,
## it's pooled per side: everything a Character (or allied NPC) generates
## goes into the Ally Pool; everything a hostile/neutral NPC generates
## goes into the Adversary Pool. This is a genuine alternative to the
## core rulebook's per-character Advantage (p.163) — the book presents it
## as something "your gaming group might be interested in," not a
## replacement everyone uses, so `CombatResolver` supports both: pass a
## GroupAdvantagePool in to use this system, or omit it for core rules.

var ally: int = 0
var adversary: int = 0

func get_pool(side: String) -> int:
	return ally if side == "ally" else adversary

func opposite(side: String) -> String:
	return "adversary" if side == "ally" else "ally"

func add(side: String, amount: int) -> void:
	if amount <= 0:
		return
	if side == "ally":
		ally += amount
	else:
		adversary += amount

## Returns true and deducts if the pool can afford it; false (no change)
## otherwise.
func spend(side: String, amount: int) -> bool:
	if get_pool(side) < amount:
		return false
	if side == "ally":
		ally -= amount
	else:
		adversary -= amount
	return true

## --- Gaining Advantage (p.133-134) --------------------------------------
## These wrap the listed ways to generate Advantage under the group
## system. Each simply routes the right amount to the right pool; calling
## code decides when the triggering circumstance has occurred.

## Attacking a Surprised enemy.
func gain_surprise(side: String) -> void:
	add(side, 1)

## Using a Skill to secure a tactical advantage (an "Assess" action);
## +3 instead of +2 if the Test succeeded by 6 or more SL.
func gain_assess(side: String, success_levels: int) -> void:
	add(side, 3 if success_levels >= 6 else 2)

## Defeating an important NPC (+1), or a party nemesis at the GM's
## discretion (+2).
func gain_victory(side: String, is_nemesis: bool = false) -> void:
	add(side, 2 if is_nemesis else 1)

## Winning an Opposed Test you initiated during combat.
func gain_winning(side: String) -> void:
	add(side, 1)

## Wounding an opponent without an Opposed Test (e.g. a successful
## unopposed ranged hit). Capped at +1 per action no matter how many
## targets were hit — callers should only invoke this once per action.
func gain_outmaneuver(side: String) -> void:
	add(side, 1)

## Note: Charging does NOT grant Advantage in this project. The core
## rulebook's version (p.165, "+1 Advantage") is explicitly superseded
## by Up in Arms (p.136): "Charging now gives you a +10 bonus to the
## first Melee Test you initiate after completing your move" — a flat
## roll modifier, applied directly to the attack Test in
## FieldEncounter/CombatResolver, not a pool gain. There's deliberately
## no gain_charging() here anymore.

## --- Losing Advantage (p.134) --------------------------------------------
## At the end of each Round, whichever side is judged dominant (more
## combatants still standing, or — if numbers are equal — whichever side
## the GM judges to hold the tactical edge) takes 1 Advantage from the
## suppressed side's pool. If the suppressed pool is empty, the dominant
## pool simply gains 1 instead.
func resolve_round_end(dominant_side: String) -> void:
	var suppressed := opposite(dominant_side)
	if get_pool(suppressed) > 0:
		spend(suppressed, 1)
	add(dominant_side, 1)

## Convenience: judge dominance by simple head-count of still-standing
## combatants per side (the book's primary rule). Per the request: a
## tied headcount — most commonly a plain 1v1 fight — genuinely grants
## no bonus to either side. Outnumbering means outnumbering; being
## evenly matched isn't a form of dominance, and the previous
## "tied_dominant_side" default silently handed the ally side a free
## +1 Advantage (and suppressed the adversary's pool) every single
## round of any 1v1 fight, which was never earned by actually
## outnumbering anyone.
func resolve_round_end_by_headcount(ally_count: int, adversary_count: int) -> void:
	if ally_count == adversary_count:
		return
	var dominant: String = "ally" if ally_count > adversary_count else "adversary"
	resolve_round_end(dominant)

## --- Seeding initial pools at the start of combat (p.135) ----------------
## Only the highest applicable modifier in each circumstance category
## should be awarded (e.g. don't stack Outnumbering 2-to-1 with the
## generic Outnumbering entry — pick the one that applies).
const CIRCUMSTANCE_TABLE := {
	"maneuverability": 2,
	"outnumbering": 1,
	"outnumbering_2_to_1": 2,
	"outnumbering_3_to_1": 3,
	"surprise": 2,
	"terrain_light_cover_or_position": 1,
	"terrain_heavy_cover_or_key_position": 2,
	"threat_dangerous": 1,
	"threat_very_dangerous": 3,
	"threat_extremely_dangerous": 5,
}

func seed(side: String, circumstance: String) -> void:
	add(side, CIRCUMSTANCE_TABLE.get(circumstance, 0))
