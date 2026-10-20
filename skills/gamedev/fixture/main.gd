extends Node3D
## Spins a mesh, prints FPS once a second and frame-time percentiles, and quits after SMOKE_SECONDS (default 5).

const RING := 8192

var seconds := float(OS.get_environment("SMOKE_SECONDS")) if OS.has_environment("SMOKE_SECONDS") else 5.0
var elapsed := 0.0
var tick := 0.0
var frames := 0
var deltas := PackedFloat32Array()

func _ready() -> void:
	deltas.resize(RING)
	print("SMOKE renderer=%s adapter=%s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])

func _process(delta: float) -> void:
	$Mesh.rotate_y(delta)
	deltas[frames % RING] = delta
	elapsed += delta
	tick += delta
	frames += 1
	if tick >= 1.0:
		print("SMOKE fps=%d t=%.1f" % [Engine.get_frames_per_second(), elapsed])
		tick = 0.0
	if elapsed >= seconds:
		print("SMOKE done frames=%d avg_fps=%.1f %s" % [frames, frames / elapsed, _frame_stats()])
		get_tree().quit()

## Frame-time p50/p95/p99 (ms, nearest rank) and 1 % low fps over the last RING frames.
func _frame_stats() -> String:
	var d := deltas.slice(0, mini(frames, RING))
	d.sort()
	var n := d.size()
	var worst := d.slice(n - maxi(1, n / 100))
	var sum := 0.0
	for x in worst:
		sum += x
	var pct := func(q: float) -> float: return d[clampi(ceili(q * n) - 1, 0, n - 1)] * 1000.0
	return "p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f low1_fps=%.1f" % [pct.call(0.5), pct.call(0.95), pct.call(0.99), worst.size() / sum]
