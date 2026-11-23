extends Node
## Creates the controls for 2 players when the game starts.
## Change keys here instead of in Project Settings, so Git merges stay easy.
##
## Keyboard (2 players on one keyboard):
##   P1: WASD move, SPACE push, LEFT SHIFT grab
##   P2: arrows move, ENTER push, RIGHT SHIFT grab
## Gamepads: pad 1 = P1, pad 2 = P2. Left stick move, A = push, X = grab.

const CONTROLS := {
	"p1": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "push": KEY_SPACE, "grab": KEY_SHIFT},
	"p2": {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "push": KEY_ENTER, "grab": KEY_SHIFT},
}
## Left Shift for P1, Right Shift for P2
const KEY_SIDE := {"p1": KEY_LOCATION_LEFT, "p2": KEY_LOCATION_RIGHT}


func _ready() -> void:
	var device := 0
	for player in CONTROLS:
		for action in CONTROLS[player]:
			var action_name: String = player + "_" + action  # e.g. "p1_up"
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name, 0.3)
			var ev := InputEventKey.new()
			ev.physical_keycode = CONTROLS[player][action]
			if CONTROLS[player][action] == KEY_SHIFT:
				ev.location = KEY_SIDE[player]
			InputMap.action_add_event(action_name, ev)
		_add_pad(player, device)
		device += 1
	_add_key("toggle_cpu", KEY_C)
	_add_key("restart", KEY_R)


func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _add_pad(player: String, device: int) -> void:
	var axes := {"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
		"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0]}
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.device = device
		m.axis = axes[a][0]
		m.axis_value = axes[a][1]
		InputMap.action_add_event(player + "_" + a, m)
	for pair in [["push", JOY_BUTTON_A], ["grab", JOY_BUTTON_X]]:
		var b := InputEventJoypadButton.new()
		b.device = device
		b.button_index = pair[1]
		InputMap.action_add_event(player + "_" + pair[0], b)
