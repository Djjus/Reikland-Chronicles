extends RefCounted
class_name SocialRapportPoolTest
## Verifies SocialRapportPool in isolation (Design Doc "Social Combat —
## Design Doc v1", Slice 2, Section 3): the standing +10-per-point roll
## bonus, the Status-Tier cap, gain/spend/lose/reset, and
## max_for_party()'s own party-wide "best present member" rule.

static func run_test(_tree) -> bool:
	var checks: Array = []

	## --- roll_bonus() / gain() / cap ---------------------------------
	var pool := SocialRapportPool.new()
	checks.append(["Starts at 0", pool.current == 0])
	checks.append(["roll_bonus() at 0 Rapport is +0", pool.roll_bonus() == 0])
	pool.gain(1, 5)
	checks.append(["gain(1, cap 5) banks 1", pool.current == 1])
	checks.append(["roll_bonus() at 1 Rapport is +10", pool.roll_bonus() == 10])
	pool.gain(10, 5)
	checks.append(["gain() never exceeds the cap passed in, however large the amount", pool.current == 5])
	pool.gain(-3, 5)
	checks.append(["gain() with a non-positive amount is a no-op", pool.current == 5])

	## --- spend() -------------------------------------------------------
	var spend_pool := SocialRapportPool.new()
	spend_pool.gain(2, 5)
	checks.append(["spend() affording the cost deducts and returns true", spend_pool.spend(2) and spend_pool.current == 0])
	checks.append(["spend() failing to afford leaves the pool untouched and returns false", not spend_pool.spend(1) and spend_pool.current == 0])

	## --- lose() (floors at 0, unlike spend()) --------------------------
	var lose_pool := SocialRapportPool.new()
	lose_pool.gain(3, 5)
	lose_pool.lose(1)
	checks.append(["lose() drains by the given amount", lose_pool.current == 2])
	lose_pool.lose(99)
	checks.append(["lose() floors at 0 rather than going negative", lose_pool.current == 0])

	## --- reset() ---------------------------------------------------------
	var reset_pool := SocialRapportPool.new()
	reset_pool.gain(4, 5)
	reset_pool.reset()
	checks.append(["reset() wipes to 0 (a party Fumble)", reset_pool.current == 0])

	## --- max_for_party() ------------------------------------------------
	var brass := Character.new()
	## Character.get_status_ordinal() reads career.get_level(current_tier)
	## .status_tier -- a bare fresh Character with no career at all
	## should still resolve to SOME real ordinal (Brass, the floor),
	## not crash or return 0.
	var brass_status := brass.get_status_ordinal()
	checks.append(["A fresh Character resolves to a real (>=1) Status ordinal", brass_status >= 1])
	checks.append(["max_for_party([]) falls back to the Brass floor (2)", SocialRapportPool.max_for_party([]) == 2])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Rapport Pool): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
