extends Node3D
## Composition root: lit PBR arena, player, coins, HUD, audio; autoplay and SMOKE lines when SMOKE_SECONDS is set.

const COINS := 8
const ARENA := 12.0
const RING := 8192

var state := GameState.new(COINS, 60.0)
var smoke_seconds := float(OS.get_environment("SMOKE_SECONDS")) if OS.has_environment("SMOKE_SECONDS") else 0.0
var elapsed := 0.0
var tick := 0.0
var frames := 0
var deltas := PackedFloat32Array()
var coins: Array[Area3D] = []
var player: CharacterBody3D
var camera: Camera3D
var hud: Label
var banner: Label
var sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

func _ready() -> void:
	deltas.resize(RING)
	print("SMOKE renderer=%s adapter=%s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
	_build_environment()
	_build_floor()
	_build_crates()
	_build_player()
	_build_coins()
	_build_hud()
	sfx = _sound("res://assets/audio/pickup.ogg")
	win_sfx = _sound("res://assets/audio/win.ogg")

func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/sky.hdr")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

func _build_floor() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/floor/diff.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/floor/nor.jpg")
	mat.roughness_texture = load("res://assets/floor/rough.jpg")
	mat.ao_enabled = true
	mat.ao_texture = load("res://assets/floor/ao.jpg")
	mat.uv1_scale = Vector3(6, 6, 1)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ARENA * 2, ARENA * 2)
	mesh.material = mat
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ARENA * 2, 0.2, ARENA * 2)
	col.shape = box
	col.position.y = -0.1
	body.add_child(col)
	add_child(body)

func _build_crates() -> void:
	var scene: PackedScene = load("res://assets/crate.glb")
	for i in 10:
		var a := TAU * i / 10.0
		var body := StaticBody3D.new()
		var crate := scene.instantiate() as Node3D
		crate.scale = Vector3.ONE * 2.0
		body.add_child(crate)
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 1.0
		col.shape = box
		col.position.y = 0.5
		body.add_child(col)
		body.position = Vector3(cos(a), 0, sin(a)) * 10.5
		body.rotation.y = a
		add_child(body)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	var mi := MeshInstance3D.new()
	mi.mesh = CapsuleMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.45, 0.9)
	mat.roughness = 0.4
	mi.mesh.material = mat
	player.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	player.add_child(col)
	player.position = Vector3(0, 1.0, 0)
	player.autoplay = smoke_seconds > 0.0 or OS.has_environment("SLICE_AUTOPLAY")
	player.targets = _coin_positions
	add_child(player)
	camera = Camera3D.new()
	camera.fov = 55.0
	add_child(camera)
	_follow(1.0)

func _build_coins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/coin.gdshader")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = 0.1
	mesh.material = shader_mat
	for i in COINS:
		var coin := Area3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.rotation_degrees.x = 90.0
		coin.add_child(mi)
		var col := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.7
		col.shape = sphere
		coin.add_child(col)
		var a := TAU * i / COINS + rng.randf_range(-0.3, 0.3)
		coin.position = Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.0, 8.0) + Vector3.UP * 0.8
		coin.body_entered.connect(_on_coin.bind(coin))
		add_child(coin)
		coins.append(coin)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(24, 16)
	hud.add_theme_font_size_override("font_size", 28)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 64)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 10)
	layer.add_child(banner)
	add_child(layer)

func _sound(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	add_child(p)
	return p

func _coin_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in coins:
		out.append(c.global_position)
	return out

func _on_coin(body: Node3D, coin: Area3D) -> void:
	if body != player or state.is_over():
		return
	coins.erase(coin)
	coin.queue_free()
	state.collect()
	sfx.play()
	if state.won():
		win_sfx.play()

func _follow(weight: float) -> void:
	var target := player.global_position + Vector3(0, 11, 9)
	camera.global_position = camera.global_position.lerp(target, weight)
	camera.look_at(player.global_position, Vector3.UP)

func _process(delta: float) -> void:
	state.tick(delta)
	for c in coins:
		c.rotate_y(delta * 2.0)
	_follow(clampf(delta * 4.0, 0.0, 1.0))
	hud.text = "Coins %d/%d   Score %d   Time %d" % [state.collected, state.total, state.points, ceili(state.time_left)]
	if state.won():
		banner.text = "ALL COINS  %d pts" % state.points
	elif state.is_over():
		banner.text = "TIME UP  (Enter to retry)"
	if state.is_over() and Input.is_action_just_pressed("ui_accept"):
		get_tree().reload_current_scene()
	if smoke_seconds > 0.0:
		_smoke(delta)

func _smoke(delta: float) -> void:
	deltas[frames % RING] = delta
	elapsed += delta
	tick += delta
	frames += 1
	if tick >= 1.0:
		print("SMOKE fps=%d t=%.1f coins=%d" % [Engine.get_frames_per_second(), elapsed, state.collected])
		tick = 0.0
	if elapsed >= smoke_seconds:
		print("SMOKE done frames=%d avg_fps=%.1f coins=%d won=%s %s" % [frames, frames / elapsed, state.collected, state.won(), _frame_stats()])
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
