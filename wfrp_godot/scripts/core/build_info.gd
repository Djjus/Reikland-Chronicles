extends RefCounted
class_name BuildInfo
## Version tracking, per the request: bumped by one each time a new
## build is packaged for the user, shown on the Main Menu (starting
## screen) and used in the output zip's filename, so builds can be
## told apart at a glance. Not tied to Godot's own project version —
## this is purely a "which build did I download" counter.
##
## Per the follow-up request: now formatted as v0.2.X — the middle
## "0.2" segment stays fixed until the user advises moving to the
## next release (0.3, and so on), with X continuing to increment by
## one per build exactly as before.
##
## CORRECTED per an explicit follow-up ("no start not 0.3.1"): moving
## to a new release DOES reset X back to 1 — a prior build of this
## file guessed the opposite (kept X counting straight through the
## 0.2 -> 0.3 move, landing on "v0.3.639") and was told that's wrong.
## So each release line (0.2.x, 0.3.x, ...) restarts its own build
## count at 1; only the middle segment carries forward across a move.
##
## Per the request ("let's change the way to save the project... use
## the live files... do not zip it for delivery"): this counter no
## longer only bumps when a zip gets packaged -- it still bumps by one
## for every pushed change to the live project folder, zip or not, so
## the Main Menu's own version readout stays a meaningful "what did I
## last get from Claude" marker either way.

const VERSION := "v0.3.125"
const BUILD_DATE := "2026-09-11"
