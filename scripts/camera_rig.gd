extends Camera3D
## Party-game camera: follows the middle point between the wrestlers and
## zooms out when they are far apart. Shake (Juice.shake) still works,
## because it uses h_offset / v_offset.

@export var min_distance := 6.5
@export var max_distance := 11.0
@export var pitch_deg := 17.0            ## how steeply we look down
@export var follow_speed := 3.0

var _target := Vector3.ZERO


func _ready() -> void:
	_update(1.0, true)


func _process(delta: float) -> void:
	_update(delta, false)


func _update(delta: float, snap: bool) -> void:
	var players := get_tree().get_nodes_in_group("players")
	var mid := Vector3.ZERO
	var sep := 3.0
	if players.size() >= 2:
		var a: Vector3 = players[0].global_position
		var b: Vector3 = players[1].global_position
		mid = Vector3((a.x + b.x) * 0.5, 0.0, (a.z + b.z) * 0.5)
		sep = Vector2(a.x - b.x, a.z - b.z).length()
	mid = mid.limit_length(4.0)          # don't wander off the field
	var dist := clampf(5.0 + sep * 1.2, min_distance, max_distance)
	var p := deg_to_rad(pitch_deg)
	var want := mid + Vector3(0, sin(p) * dist + 1.0, cos(p) * dist)
	var k := 1.0 if snap else 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(want, k)
	_target = _target.lerp(mid + Vector3.UP * 0.9, k)
	look_at(_target, Vector3.UP)
