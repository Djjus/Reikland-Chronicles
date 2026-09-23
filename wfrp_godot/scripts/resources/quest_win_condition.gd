extends Resource
class_name QuestWinCondition
## Per the request: multi-criteria win/loss evaluation, generalized
## enough to take N independent boolean conditions and a rule for
## combining them — matching the source adventure's own actual win
## condition directly: the boss must be slain (all of one thing), the
## flood must be prevented (all of another), AND at least one of three
## named disasters must be averted (a genuine "at least N of these"
## rule, not just AND). A QuestDefinition's own win_conditions list is
## itself always evaluated as AND across every group — each group here
## is where the real flexibility lives, since a group can independently
## require ALL of its own checks or only SOME of them.

@export var condition_id: String = ""
## For display/debugging only — never required to be unique or shown
## to the player automatically.
@export var group_label: String = ""

## Each entry is one independently-checkable boolean condition within
## this group. Recognized formats:
##   "npc:<npc_id>:pass"        - that NPC's own crisis was resolved as a pass
##   "npc:<npc_id>:fail"        - that NPC's own crisis was resolved as a fail
##   "npc:<npc_id>:resolved"    - that NPC's own crisis was resolved at all (pass or fail)
##   "timeline:<event_id>:fired"     - that timed event genuinely went off
##   "timeline:<event_id>:not_fired" - that timed event was genuinely prevented/never happened
##   "monster:<monster_id>:defeated" - that quest monster was genuinely defeated in combat
@export var checks: Array[String] = []

## How many of `checks` must genuinely be true for this GROUP itself
## to count as met. -1 means "all of them" (a plain AND) — the
## default, and what most groups actually want. Any value >= 1 means
## "at least this many of them" — a real, generalized threshold that
## covers a plain OR (required_count = 1) just as naturally as
## anything in between.
@export var required_count: int = -1
