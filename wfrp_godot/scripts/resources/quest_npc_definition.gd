extends Resource
class_name QuestNPCDefinition
## Per the request: the data-driven half of a "scripted NPC" — the
## exact same shape the Village Elder's own quest chain already
## proved out by hand (scripts/core/elder_story.gd), generalized so a
## future adventure-import pipeline can populate one of these per
## named NPC in a book adventure, instead of hand-writing a new
## screen and a new set of Character fields for every single one.
##
## Deliberately does NOT try to cover every possible adventure NPC —
## branching dialogue trees, multi-stage relationships, and the like
## stay hand-built (like the Elder) for now. This covers the single
## most common shape found across a real adventure module: an NPC in
## a crisis, resolved (or not) by one Skill or Characteristic Test at
## a specific difficulty, with real consequences either way, and
## optionally a real time limit before the crisis resolves itself
## badly on its own.

## A stable, code-facing identifier — never shown to the player.
## Namespaced by convention as "<quest_id>_<npc_id>", e.g.
## "gotheim_wilhelm", so two different adventures' NPCs can never
## collide even if they reuse a common name.
@export var npc_id: String = ""
@export var npc_name: String = ""

## Shown once, the first time this NPC is encountered.
@export_multiline var intro_text: String = ""

## The Test that resolves this NPC's crisis. skill_name may name a
## real Skill ("Charm", "Intimidate") or a real Characteristic
## ("Strength", "Willpower") — resolved the same dual way Overworld's
## own Wilderness Events already do. An empty skill_name means no
## Test is involved at all — the encounter resolves as a pass
## automatically the moment it's engaged (matching NPCs in the source
## material, like Kai, who just needs to be spoken to, not tested).
@export var skill_name: String = ""
@export var specialisation: String = ""
## A signed WFRP-style modifier — e.g. -10 for "Difficult (-10)",
## +40 for "Easy (+40)" — added directly to the target, matching how
## every other Test in this project already applies difficulty.
@export var difficulty: int = 0

@export_multiline var pass_text: String = ""
@export_multiline var fail_text: String = ""
## Shown if the player returns to an NPC whose crisis is already
## resolved (pass or fail) — keeps a revisit from re-triggering the
## whole encounter.
@export_multiline var already_resolved_text: String = ""
## Per the request: shown instead of already_resolved_text on a
## revisit once the quest itself has actually concluded (Completed or
## Failed) — the NPC is aware the whole matter is over, not just that
## this one conversation already happened. Falls back to
## already_resolved_text (then the generic default) if left blank, so
## existing NPCs don't need this filled in to keep working.
@export_multiline var quest_concluded_text: String = ""

## Per the request: whether a "fail" outcome (a failed Test, or timing
## out) means this NPC is genuinely gone — dead, or fled — rather than
## just still present and unresolved. True for Wilhelm (his own fail/
## timeout is a fatal fall), false by default for everyone else
## (Emil failing to snap out of it doesn't mean he's died). A removed
## NPC's own map marker stops appearing at all — see
## Character.is_quest_npc_removed().
@export var fail_removes_npc: bool = false

## Real consequences, applied on pass or fail respectively — mirrors
## the same fields Wilderness Events already use for their own
## Skill Test consequences, so the resolution code can share logic
## rather than reinventing it.
@export var pass_condition: String = ""
@export var pass_condition_stacks: int = 1
@export var fail_condition: String = ""
@export var fail_condition_stacks: int = 1

## Rewards, awarded only on a genuine pass — per the request's own
## "rewards (XP, items, Coin)" requirement. reward_item names a real
## ItemDefinition by its own item_name; left empty for no item.
@export var reward_xp: int = 0
@export var reward_gold: int = 0
@export var reward_item: String = ""

## A real time limit, in in-game minutes, from the moment this NPC is
## first encountered — per the request's own timed-consequence
## requirement (Wilhelm jumping if not talked down in time, in the
## source material this was modeled on). -1 means no time limit at
## all. timeout_text is shown, and fail_condition/fail_gold/etc. are
## NOT reapplied a second time — a timeout counts as an automatic
## fail outcome using fail_text and fail_condition, exactly as if the
## Test itself had been failed.
@export var timeout_minutes: int = -1
@export_multiline var timeout_text: String = ""

## Per the request: dynamic rerouting — this NPC won't actually
## engage (no intro, no Test) until another NPC in the same quest has
## genuinely been visited first, matching the source material's own
## "if the party rushes to the lake before the temple, Gerd forgets
## what he saw and points them to someone else" GM advice. Checked
## every single visit, not just the first — as soon as the
## prerequisite NPC has been visited, this NPC proceeds normally from
## then on, with no separate flag of its own to reset. Empty
## reroute_if_npc_id means no rerouting at all, the ordinary case.
@export var reroute_if_npc_id: String = ""
@export_multiline var reroute_text: String = ""
