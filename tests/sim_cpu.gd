extends SceneTree
## Balance test: CPU vs CPU on the real main scene. Counts techniques (мэх) and how rounds end.
## Run:  godot --headless --fixed-fps 60 -s res://tests/sim_cpu.gd   (SIM_T=seconds, default 120)
var t := 0.0
var main: Node
var log := {"mekh": {}, "fails": 0, "ends": {}, "rounds": 0, "counters": 0, "mekh_wins": {}}
var last_scores := {"p1": 0, "p2": 0}
var was_grip := {}
var grip_len := []
var grip_start := {}
func _initialize() -> void:
	var sc: PackedScene = load("res://scenes/main.tscn")
	main = sc.instantiate()
	main.get_script().set("p2_cpu", true)
	root.add_child(main)
	await process_frame
	main.p1.is_cpu = true
	main.p2.is_cpu = true
	for p in [main.p1, main.p2]:
		p.mekh_done.connect(func(a, v, id, r):
			var k: String = id + ":" + r
			log.mekh[k] = log.mekh.get(k, 0) + 1)
func _process(delta: float) -> bool:
	t += delta
	for p in [main.p1, main.p2]:
		var g: bool = p.gripping
		if g and not was_grip.get(p, false):
			log["grips"] = log.get("grips", 0) + 1
			grip_start[p] = t
		if not g and was_grip.get(p, false):
			grip_len.append(snappedf(t - grip_start[p], 0.1))
		was_grip[p] = g
		if g:
			var tl: float = p.tilt_deg()
			log["tilt_max"] = maxf(log.get("tilt_max", 0.0), tl)
			log["tilt_sum"] = log.get("tilt_sum", 0.0) + tl
			log["tilt_n"] = log.get("tilt_n", 0) + 1
		if p.bracing and g:
			log["brace_in_grip"] = log.get("brace_in_grip", 0) + 1
	var s: Dictionary = main.scores
	if s.p1 + s.p2 != last_scores.p1 + last_scores.p2:
		log.rounds += 1
		var r: String = main.last_loss_reason
		log.ends[r] = log.ends.get(r, 0) + 1
		for p in [main.p1, main.p2]:
			var tb: Dictionary = p.thrown_by
			if p.is_out and not tb.is_empty() and Time.get_ticks_msec() - int(tb.time) < 2500 and p != (main.p1 if s.p1 > last_scores.p1 else main.p2):
				log.mekh_wins[tb.id] = log.mekh_wins.get(tb.id, 0) + 1
		last_scores = s.duplicate()
	if s.p1 >= 3 or s.p2 >= 3:
		main.scores = {"p1": 0, "p2": 0}
		last_scores = {"p1": 0, "p2": 0}
		main._round_over = true
		main._reset_round()
	if t > float(OS.get_environment("SIM_T") if OS.get_environment("SIM_T") != "" else "120"):
		log["grip_len"] = grip_len
		print("RESULT ", JSON.stringify(log))
		quit()
	return false
