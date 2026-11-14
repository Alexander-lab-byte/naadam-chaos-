extends Node3D
## Bökh (wrestling) round logic.
## Like real Mongolian wrestling: you lose if you fall down (tip over).
## In this game you also lose if you leave the ring.

@export var ring_radius := 6.0
@export var fall_angle_deg := 65.0       ## tilt more than this = fallen
@export var fall_time := 0.4             ## must stay fallen this long (seconds)
@export var points_to_win := 3

@onready var p1: RigidBody3D = $Player1
@onready var p2: RigidBody3D = $Player2
@onready var label: Label = $UI/Message
@onready var score_label: Label = $UI/Score

var scores := {"p1": 0, "p2": 0}
var _fallen_timer := {"p1": 0.0, "p2": 0.0}
var _round_over := false
var _start := {}


func _ready() -> void:
	_start[p1] = p1.global_transform
	_start[p2] = p2.global_transform
	_update_score()
	_show("BÖKH! Push your rival down or out of the ring!", 2.5)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if _round_over:
		return
	for p in [p1, p2]:
		if _is_lost(p, delta):
			var winner: RigidBody3D = p2 if p == p1 else p1
			_end_round(winner, p)
			return


func _is_lost(p: RigidBody3D, delta: float) -> bool:
	var flat := Vector2(p.global_position.x, p.global_position.z)
	if flat.length() > ring_radius or p.global_position.y < -2.0:
		return true
	var tilt := rad_to_deg(p.global_transform.basis.y.angle_to(Vector3.UP))
	if tilt > fall_angle_deg:
		_fallen_timer[p.player_id] += delta
	else:
		_fallen_timer[p.player_id] = 0.0
	return _fallen_timer[p.player_id] >= fall_time


func _end_round(winner: RigidBody3D, loser: RigidBody3D) -> void:
	_round_over = true
	loser.is_out = true
	winner.is_out = true  # freeze both until next round
	scores[winner.player_id] += 1
	_update_score()
	var name := "Player 1" if winner.player_id == "p1" else "Player 2"
	if scores[winner.player_id] >= points_to_win:
		_show(name + " is the AVARGA (champion)!  Press R to play again", 0.0)
		return
	_show(name + " wins the round!", 2.0)
	await get_tree().create_timer(2.0).timeout
	_reset_round()


func _reset_round() -> void:
	for p in [p1, p2]:
		p.global_transform = _start[p]
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
		p.is_out = false
		_fallen_timer[p.player_id] = 0.0
	_round_over = false
	_show("FIGHT!", 1.0)


func _update_score() -> void:
	score_label.text = "P1 (red): %d    P2 (blue): %d" % [scores.p1, scores.p2]


func _show(text: String, seconds: float) -> void:
	label.text = text
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if label.text == text:
			label.text = ""
