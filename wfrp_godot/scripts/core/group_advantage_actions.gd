extends RefCounted
class_name GroupAdvantageActions
## The "Benefits of Advantage" spend table from Up in Arms, p.134,
## checked directly against the sourcebook. Each action spends from the
## acting character's side's pool (via `allegiance`) for a specific
## effect. All of these require a GroupAdvantagePool — they don't exist
## under the core rulebook's per-character Advantage.

class ActionResult:
	var success: bool = false          ## false if the pool couldn't afford it
	var opposed_test: TestResolver.TestResult
	var opponent_test: TestResolver.TestResult
	var attacker_won: bool = false
	## Per the request: a genuine tie (same Success Level AND same Target
	## Number — see TestResolver.resolve_opposed()'s own comment) means
	## nothing happens at all, not even the usual "loser's side gains
	## Advantage" consequence.
	var is_true_tie: bool = false
	var text: String = ""

## 1 Advantage. Opposed Strength Test. On a win: the opponent gains the
## Prone Condition — but per the book's own text, the opponent's side
## ALSO gains +1 Advantage either way, and you do not get the normal
## Winning bonus for beating the Opposed Test (that's the cost of the
## guaranteed Prone). On a loss: your Action ends and the opponent's side
## still gains +1 Advantage.
static func spend_batter(pool: GroupAdvantagePool, actor: Character, opponent: Character) -> ActionResult:
	var result := ActionResult.new()
	if not pool.spend(actor.allegiance, 1):
		result.text = "Not enough Advantage (need 1)."
		return result
	result.success = true

	result.opposed_test = TestResolver.resolve_characteristic_test(actor, "strength")
	result.opponent_test = TestResolver.resolve_characteristic_test(opponent, "strength")
	var opposed := TestResolver.resolve_opposed(result.opposed_test, result.opponent_test)
	result.attacker_won = opposed.attacker_wins
	result.is_true_tie = opposed.is_true_tie

	if result.attacker_won:
		opponent.add_condition("Prone")
		pool.add(opponent.allegiance, 1)
		result.text = "%s batters %s to the ground (Prone), but the exertion costs the opening — %s's side still gains +1 Advantage." % [
			actor.character_name, opponent.character_name, opponent.character_name
		]
	elif result.is_true_tie:
		result.text = "%s and %s are evenly matched — the Batter goes nowhere, %s's Action ends, and neither side gains Advantage from it." % [
			actor.character_name, opponent.character_name, actor.character_name
		]
	else:
		pool.add(opponent.allegiance, 1)
		result.text = "%s's Batter fails; %s's side gains +1 Advantage and %s's Action ends." % [
			actor.character_name, opponent.character_name, actor.character_name
		]
	return result

## 1 Advantage. Opposed Agility Test. On a win: your side gains +1
## Advantage, and (GM's discretion) you may inflict Ablaze, Blinded, or
## Entangled. On a loss: the opponent's side gains +1 Advantage and your
## Action ends.
static func spend_trick(pool: GroupAdvantagePool, actor: Character, opponent: Character,
		inflict_condition: String = "") -> ActionResult:
	var result := ActionResult.new()
	if not pool.spend(actor.allegiance, 1):
		result.text = "Not enough Advantage (need 1)."
		return result
	result.success = true

	result.opposed_test = TestResolver.resolve_characteristic_test(actor, "agility")
	result.opponent_test = TestResolver.resolve_characteristic_test(opponent, "agility")
	var opposed := TestResolver.resolve_opposed(result.opposed_test, result.opponent_test)
	result.attacker_won = opposed.attacker_wins
	result.is_true_tie = opposed.is_true_tie

	if result.attacker_won:
		## Distract (p.142): the Trick still lands (any inflicted
		## Condition still applies), but a Distracted actor generates no
		## Advantage from it.
		var cond_note := ""
		if inflict_condition != "":
			opponent.add_condition(inflict_condition)
			cond_note = " %s is left %s." % [opponent.character_name, inflict_condition]
		if not actor.is_advantage_denied():
			pool.add(actor.allegiance, 1)
			result.text = "%s's Trick works — +1 Advantage.%s" % [actor.character_name, cond_note]
		else:
			result.text = "%s's Trick works, but generates no Advantage (Distracted).%s" % [actor.character_name, cond_note]
	elif result.is_true_tie:
		result.text = "%s and %s are evenly matched — the Trick goes nowhere, %s's Action ends, and neither side gains Advantage from it." % [
			actor.character_name, opponent.character_name, actor.character_name
		]
	else:
		pool.add(opponent.allegiance, 1)
		result.text = "%s's Trick fails; %s's side gains +1 Advantage and %s's Action ends." % [
			actor.character_name, opponent.character_name, actor.character_name
		]
	return result

## 2 Advantage minimum. +10% to a Test per 2 Advantage spent, plus +10%
## for each additional point beyond that (2 Adv = +10%, 3 Adv = +20%,
## 4 Adv = +30%, ...). Returns the bonus achieved, or 0 if unaffordable.
## Never generates Advantage for the character performing the Test.
static func spend_additional_effort(pool: GroupAdvantagePool, actor: Character, total_advantage: int) -> int:
	if total_advantage < 2:
		return 0
	if not pool.spend(actor.allegiance, total_advantage):
		return 0
	return (total_advantage - 1) * 10

## 2 Advantage (1 for a character with the Relentless Talent, p.140).
## Move away from opponents without penalty — replaces the core
## rulebook's Disengaging rules (p.165) entirely when this system is in
## use. Returns true if it could be afforded.
static func spend_flee_from_harm(pool: GroupAdvantagePool, actor: Character) -> bool:
	var cost := 1 if actor.has_talent("Relentless") else 2
	return pool.spend(actor.allegiance, cost)

## 4 Advantage. An extra Action this Turn. Never generates Advantage for
## the character performing it, and can only be used once per Turn (the
## caller is responsible for enforcing the once-per-turn limit).
static func spend_additional_action(pool: GroupAdvantagePool, actor: Character) -> bool:
	return pool.spend(actor.allegiance, 4)
