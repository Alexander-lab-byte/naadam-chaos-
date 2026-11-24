extends Node3D
## Bökh (wrestling) round logic.
## REAL bökh rule: you lose when your KNEE, ELBOW or BACK touches the ground.
## Your PALMS may touch it - press PUSH while tipping over to do a "palm save".
## Like real bökh there is NO ring and no ring-out: leaving the area never loses.
## If the wrestlers drift too far, the zasuul brings them back to the middle
## (a soft push back, and a quick reset if they wander far away).
##
## At the end of the match the loser is crowned BAYAN KHODOOD ("full stomach"),
## like the last horse at Naadam: celebrated, arrogant, and blessed for next time.

@export var field_radius := 7.5          ## soft edge: beyond this the wrestlers are pushed back
@export var edge_push := 30.0             ## how strongly the edge pushes back
@export var reset_radius := 11.0         ## this far out = zasuul stops the bout and brings them back
@export var touch_time := 0.12           ## a touch must last this long (seconds) - filters glitches
@export var points_to_win := 3
@export var full_stomach_mass := 1.35    ## Bayan Khodood blessing: heavier = harder to push

@onready var p1: RigidBody3D = $Player1
@onready var p2: RigidBody3D = $Player2
@onready var label: Label = $UI/Message
@onready var score_label: Label = $UI/Score
@onready var controls_label: Label = $UI/Controls

## Survives pressing R: is Player 2 the computer?
static var p2_cpu := false

## Survives pressing R (scene reload): who got the "full stomach" blessing.
static var blessed_player := ""

var scores := {"p1": 0, "p2": 0}
var last_loss_reason := ""               ## for tests / UI: "knee", "elbow", "back"
var zasuul_resets := 0                   ## for tests: how often the zasuul brought them back
var _reset_cooldown := 0.0
var _touch_timer := {"p1": 0.0, "p2": 0.0}
var _round_over := false
var _start := {}


func _ready() -> void:
	_start[p1] = p1.global_transform
	_start[p2] = p2.global_transform
	p2.is_cpu = p2_cpu
	_update_score()
	_update_controls()
	for p in [p1, p2]:
		p.anim.play_ready()                  # slap the thighs: ready!
		p.mekh_done.connect(_on_mekh)
	if blessed_player != "":
		var p := p1 if blessed_player == "p1" else p2
		p.mass *= full_stomach_mass
		p.get_node("Visual/Body").scale = Vector3(1.3, 1.0, 1.3)   # visibly round belly (placeholder)
		p.anim.set_full_stomach(1.0)                               # round belly (Blender model)
		Juice.squash(p.anim, -0.25, 0.6)   # puffs up: full stomach!
		_show("%s has a FULL STOMACH (heavier)!  BÖKH!" % _name(p), 3.0)
		blessed_player = ""
	else:
		_show("BÖKH! Knee, elbow or back on the grass = you lose. Palms are OK!", 3.0)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if Input.is_action_just_pressed("toggle_cpu"):
		p2_cpu = not p2_cpu
		p2.is_cpu = p2_cpu
		_update_controls()
		_show("Player 2 is now %s" % ("the COMPUTER" if p2_cpu else "a HUMAN"), 1.5)
	if _round_over:
		return
	_reset_cooldown = maxf(_reset_cooldown - delta, 0.0)
	for p in [p1, p2]:
		if _keep_on_field(p):
			return
	for p in [p1, p2]:
		var reason := _loss_reason(p, delta)
		if reason != "":
			var winner: RigidBody3D = p2 if p == p1 else p1
			_end_round(winner, p, reason)
			return


func _loss_reason(p: RigidBody3D, delta: float) -> String:
	var part: String = p.ground_touch()
	if part == "":
		_touch_timer[p.player_id] = 0.0
		return ""
	_touch_timer[p.player_id] += delta
	return part if _touch_timer[p.player_id] >= touch_time else ""


## Real bökh has no ring. Instead: soft push back toward the middle, and if a wrestler
## wanders far (or falls off the world) the zasuul stops the bout and brings both back.
## Returns true if it reset the wrestlers this frame.
func _keep_on_field(p: RigidBody3D) -> bool:
	if p.is_thrown:
		return false
	var flat := Vector3(p.global_position.x, 0.0, p.global_position.z)
	var d := flat.length()
	if d > field_radius:
		p.apply_central_force(-flat.normalized() * edge_push * (d - field_radius))
	if (d > reset_radius or p.global_position.y < -2.0) and _reset_cooldown <= 0.0:
		_zasuul_reset()
		return true
	return false


func _zasuul_reset() -> void:
	zasuul_resets += 1
	_reset_cooldown = 1.0
	for p in [p1, p2]:
		p.reset_state()
		p.global_transform = _start[p]
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
		p.anim.reset()
		_touch_timer[p.player_id] = 0.0
	_show("ZASUUL: back to the middle!", 1.5)


func _end_round(winner: RigidBody3D, loser: RigidBody3D, reason: String) -> void:
	_round_over = true
	last_loss_reason = reason
	loser.is_out = true
	winner.is_out = true  # freeze both until next round
	scores[winner.player_id] += 1
	_update_score()
	winner.keep_upright = true
	winner.anim.play_win()
	loser.anim.play_lose()
	Juice.dust(loser.global_position + Vector3.DOWN * 0.6, 30)
	Juice.confetti(winner.global_position + Vector3.UP * 1.5)
	Juice.shake(0.35, 0.4)
	get_tree().call_group("field", "cheer", 1.0)

	var what := {
		"knee": "KNEE touched the grass!",
		"elbow": "ELBOW touched the grass!",
		"back": "landed on the BACK!",
	}
	# was it a technique (мэх)? A throw that landed in the last 2.5 s counts.
	var mekh_id := ""
	var tb: Dictionary = loser.thrown_by
	if not tb.is_empty() and tb.by == winner and Time.get_ticks_msec() - int(tb.time) < 2500:
		mekh_id = tb.id
	var title := TitleForge.forge(scores[winner.player_id], winner.stats, mekh_id)
	Juice.pop_text(reason.to_upper() + "!", loser.global_position + Vector3.UP * 1.5, Color.ORANGE_RED)
	if mekh_id != "":
		what[reason] = "%s - thrown with %s (%s)" % [what[reason], Mekh.TABLE[mekh_id].mn, mekh_id.capitalize()]

	if scores[winner.player_id] >= points_to_win:
		# match champion gets the real tournament-winner title: Arslan (Lion)
		_crown(winner, loser, TitleForge.forge(4, winner.stats, mekh_id))
		return
	_show("%s's %s\nZasuul: \"%s, %s!\"" % [_name(loser), what[reason], _name(winner), title], 2.6)
	await get_tree().create_timer(2.6).timeout
	_reset_round()


## Match over: winner does the eagle dance, loser becomes Bayan Khodood.
func _crown(winner: RigidBody3D, loser: RigidBody3D, title: String) -> void:
	_show("%s is %s!\n... and %s is BAYAN KHODOOD (\"full stomach\") - next year's champion!" \
			% [_name(winner), title.to_upper(), _name(loser)], 0.0)
	await get_tree().create_timer(1.2).timeout
	# loser stands up proudly NEXT to the winner, like the last horse at Naadam
	loser.global_transform = Transform3D(Basis.IDENTITY, winner.global_position + Vector3(1.6, 0.2, 0.4))
	loser.linear_velocity = Vector3.ZERO
	loser.angular_velocity = Vector3.ZERO
	loser.keep_upright = true
	loser.anim.reset()
	loser.anim.play_strut()
	Juice.pop_text("BAYAN KHODOOD!", loser.global_position + Vector3.UP * 1.8, Color.GOLD, 80)
	Juice.confetti(loser.global_position + Vector3.UP * 1.5, 20)
	blessed_player = loser.player_id
	label.text += "\nPress R for a rematch (Bayan Khodood gets a full stomach)"


func _reset_round() -> void:
	for p in [p1, p2]:
		p.reset_state()
		p.global_transform = _start[p]
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
		p.anim.reset()
		p.anim.play_ready()
		_touch_timer[p.player_id] = 0.0
	_round_over = false
	_show("FIGHT!", 1.0)


func _on_mekh(_attacker: RigidBody3D, _victim: RigidBody3D, _id: String, result: String) -> void:
	get_tree().call_group("field", "cheer", 0.8 if result != "fail" else 0.4)


func _name(p: RigidBody3D) -> String:
	return "Player 1" if p.player_id == "p1" else "Player 2"


func _update_controls() -> void:
	var p2_text := "P2: COMPUTER" if p2_cpu else "P2: arrows + ENTER push + RIGHT SHIFT grab"
	controls_label.text = "P1: WASD + SPACE push + LEFT SHIFT grab    %s    C: P2 human/CPU    R: restart\n" % p2_text \
		+ "GRAB = take a grip.  With a grip: GRAB + direction = technique (мэх).  GRAB when he attacks = COUNTER.  Tipping? PUSH = palm save"


func _update_score() -> void:
	score_label.text = "P1 (red): %d    P2 (blue): %d" % [scores.p1, scores.p2]


func _show(text: String, seconds: float) -> void:
	label.text = text
	Juice.pop(label)
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if label.text == text:
			label.text = ""
