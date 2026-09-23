extends RefCounted
class_name MovementWalkRunTest
## Per the request ("movement walk/run should be move x2/x4, not
## x3/x6"), matching the book's own Movement table (p.164):
## Movement 3 -> Walk 6 / Run 12, Movement 4 -> Walk 8 / Run 16,
## Movement 5 -> Walk 10 / Run 20. Character.get_walk_distance()/
## get_run_distance() previously multiplied by 3/6 instead of 2/4,
## overstating both by 50%.

static func run_test() -> bool:
	var checks: Array = []

	var c := Character.new()
	c.race = GameData.find_race("Human") if GameData != null else null

	## Movement 4 (Standard Human, per the book's own example row).
	c.monster_movement = 4
	checks.append(["Movement 4 -> Walk 8 (was 12 before the fix)", c.get_walk_distance() == 8])
	checks.append(["Movement 4 -> Run 16 (was 24 before the fix)", c.get_run_distance() == 16])

	## Movement 3.
	c.monster_movement = 3
	checks.append(["Movement 3 -> Walk 6 (was 9 before the fix)", c.get_walk_distance() == 6])
	checks.append(["Movement 3 -> Run 12 (was 18 before the fix)", c.get_run_distance() == 12])

	## Movement 5.
	c.monster_movement = 5
	checks.append(["Movement 5 -> Walk 10 (was 15 before the fix)", c.get_walk_distance() == 10])
	checks.append(["Movement 5 -> Run 20 (was 30 before the fix)", c.get_run_distance() == 20])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Movement Walk/Run x2/x4 Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
