extends Node
## Creates the keyboard controls for 2 players when the game starts.
## Change keys here instead of in Project Settings, so Git merges stay easy.

const CONTROLS := {
	"p1": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "push": KEY_SPACE},
	"p2": {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "push": KEY_ENTER},
}


func _ready() -> void:
	for player in CONTROLS:
		for action in CONTROLS[player]:
			var action_name: String = player + "_" + action  # e.g. "p1_up"
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name)
			var ev := InputEventKey.new()
			ev.physical_keycode = CONTROLS[player][action]
			InputMap.action_add_event(action_name, ev)
	if not InputMap.has_action("restart"):
		InputMap.add_action("restart")
		var r := InputEventKey.new()
		r.physical_keycode = KEY_R
		InputMap.action_add_event("restart", r)
