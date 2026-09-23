extends Resource
class_name QuestTimelineEvent
## Per the request: a generic, data-driven ticking-clock event — one
## entry in a QuestDefinition's own timeline_events list. Multiple of
## these register independently against the same quest, each firing
## on its own schedule, each cancelable on its own the moment the
## player genuinely intervenes (by resolving the specific NPC named
## in cancel_if_npc_id) — matching the source adventure this system
## was designed against, where several disasters tick down in
## parallel unless the party stops each one individually.

## Unique within its own quest — never shown to the player.
@export var event_id: String = ""

## How many real, in-game minutes after the quest's own timeline
## starts (recorded once, the moment the quest itself starts — see
## Character.start_scripted_quest()) this event fires, if nothing
## cancels it first.
@export var trigger_minutes: int = 0

## Posted as a real journal entry the moment this event fires — the
## player's own record of what happened while they were elsewhere,
## since there's deliberately no popup interrupting whatever else
## they're doing at the time.
@export_multiline var description: String = ""

## Real consequences applied to the player's own Character the moment
## this event fires — matches the same Condition-application shape
## already used by QuestNPCDefinition and Wilderness Events, so the
## firing code can share logic rather than reinventing it. Empty
## apply_condition means no Condition is applied, just the journal
## entry itself.
@export var apply_condition: String = ""
@export var apply_condition_stacks: int = 1

## Per the request: cancelable independently the moment the player
## intervenes — if the named NPC (by their own npc_id, within this
## same quest) has reached cancel_if_npc_state ("pass" by default; a
## disaster is not usually canceled merely by an NPC's own crisis
## ending badly) by the time this event's trigger_minutes is reached,
## the event does not fire at all. Leave cancel_if_npc_id empty for
## an event nothing can prevent.
@export var cancel_if_npc_id: String = ""
@export var cancel_if_npc_state: String = "pass"

## Per the request's own healing-over-time requirement: if set, this
## event heals a quest monster (by its own monster_id, from
## QuestDefinition.monsters) by this many Wounds the moment it fires —
## matches the source adventure's own boss monster recovering from
## specific named injuries at specific times as real in-game time
## passes, whether or not the player has intervened elsewhere on the
## same quest. Independent of cancel_if_npc_id — a healing event can
## have its own, unrelated cancel condition, or none at all.
@export var heal_monster_id: String = ""
@export var heal_wounds_amount: int = 0

## Per the request: an absolute target Wounds value, for a source
## timeline given in exact stages (18, 25, 31...) rather than
## incremental heals — when >= 0, this is used instead of
## heal_wounds_amount (which stays available for the simpler relative
## case). -1 (the default) means "use heal_wounds_amount as normal."
@export var heal_monster_set_wounds: int = -1

## Per the request: a specific injury healing removes exactly that
## many stacks of the matching Condition (e.g. the Jabberslythe's own
## Broken Jaw healing removes 2 Fatigued) — independent of
## apply_condition above, which only ever adds.
@export var heal_monster_remove_condition: String = ""
@export var heal_monster_remove_condition_stacks: int = 0

## Per the request: the villagers/NPCs named here (by their own
## npc_id, within this same quest) are lost the moment this event
## fires — marked "fail" the same way a failed Test would, so they
## stop being visible and accessible on the map and any further
## interaction correctly shows their own already-resolved/quest-
## concluded text instead. Matches the source adventure's own
## "the men there are all killed in the blaze" — several NPCs can be
## lost to a single event at once, not just one.
@export var kills_npc_ids: Array[String] = []

## Per the request: this specific event is the map-wide flood — when
## true, the whole village map is transformed the moment this fires
## (most of it becomes real, walkable floodwater; every remaining NPC
## marker is lost), handled directly in Overworld rather than through
## the generic per-NPC/Condition mechanisms above, since flooding a
## whole map is a different kind of consequence entirely.
@export var triggers_flood: bool = false
