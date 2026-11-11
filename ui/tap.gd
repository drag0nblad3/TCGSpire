class_name Tap
extends RefCounted
## Tap / long-press detection shared by every custom control.
## Only mouse-button events are used: on Android, touches are emulated as mouse
## events, so also handling InputEventScreenTouch would fire every tap twice
## (that was the "cards won't select" bug: select, then instantly deselect).
## A tap fires on release, and only if the finger didn't move (so scrolling
## a list of cards never selects one).

const MOVE_LIMIT := 14.0
const LONG_PRESS := 0.45

var _down := false
var _start := Vector2.ZERO
var _t := 0.0
var _long_fired := false


## Feed every _gui_input event. Returns "tap", "long" or "".
func feed(event: InputEvent) -> String:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			_long_fired = false
			_start = event.position
			_t = Time.get_ticks_msec() / 1000.0
			return ""
		var was := _down
		_down = false
		if was and not _long_fired and event.position.distance_to(_start) < MOVE_LIMIT:
			return "tap"
		return ""
	if event is InputEventMouseMotion and _down and event.position.distance_to(_start) >= MOVE_LIMIT:
		_down = false
	return ""


## Call from _process. Returns true once when a hold becomes a long press.
func poll_long() -> bool:
	if _down and not _long_fired and Time.get_ticks_msec() / 1000.0 - _t >= LONG_PRESS:
		_long_fired = true
		return true
	return false
