extends PopupMenu
class_name NavPopupMenu
## A PopupMenu with W (up) / S (down) / Space (accept) navigation, per
## the request. Overridden directly on the popup itself rather than
## handled by a parent node's _unhandled_input — as a Window/Popup,
## this node captures its own input once open, separately from the
## rest of the scene tree, so a parent's _unhandled_input never
## actually sees these keys while it's active. This is PopupMenu's own
## native input hook, the same mechanism its own built-in Up/Down/
## Enter handling would use.

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if item_count == 0:
		return
	if key.keycode == KEY_W or key.keycode == KEY_S:
		set_input_as_handled()
		var current := get_focused_item()
		if key.keycode == KEY_W:
			current = item_count - 1 if current < 0 else (current - 1 + item_count) % item_count
		else:
			current = 0 if current < 0 else (current + 1) % item_count
		set_focused_item(current)
	elif key.keycode == KEY_SPACE:
		set_input_as_handled()
		var current := get_focused_item()
		if current < 0:
			set_focused_item(0)
		else:
			## Matches a real click on this item — same signal a mouse
			## selection would emit, so every existing id_pressed
			## listener (see _show_name_popup) behaves identically.
			id_pressed.emit(get_item_id(current))
