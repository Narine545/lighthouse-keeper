# main.gd — «Смотритель маяка».
# Вращай луч мышью: корабли идут за светом. Приведи их к гавани и не сажай на рифы.
# Ночные циклы сменяются рассветом; вся графика и звук процедурные.
extends Node2D

const SeaSc := preload("res://scripts/sea.gd")
const BeamSc := preload("res://scripts/beam.gd")
const ShipSc := preload("res://scripts/ship.gd")
const AudioSc := preload("res://scripts/audio_director.gd")
const PostShader := preload("res://shaders/post.gdshader")

enum Phase { NIGHT, DAWN, REST, NIGHTFALL }

const BEAM_HALF := 0.1484  # 8.5 градусов

const LAMP := Vector2(285.0, 454.0)
const ISLET_POS := Vector2(285.0, 588.0)
const ISLET_R := 55.0
const HARBOR := Vector2(1150.0, 505.0)
const DOCK_END := Vector2(1215.0, 505.0)
const BEAM_LEN := 560.0

const ROCK_POOL := [
	[460.0, 470.0, 30.0], [860.0, 520.0, 36.0], [700.0, 585.0, 26.0],
	[560.0, 380.0, 28.0], [1010.0, 430.0, 30.0], [350.0, 655.0, 34.0], [790.0, 655.0, 30.0],
]

var t := 0.0
var phase: int = Phase.NIGHT
var phase_t := 0.0
var day_phase := 0.0
var night_number := 1
var ships_per_night := 5
var docked_this_night := 0
var docked_total := 0
var ships_cap := 1
var fog_density := 0.45
var spawn_t := 4.0
var knock_cd := 0.0
var hint_t := 0.0

var sea
var beam
var audio
var ships_container: Node2D
var ships: Array = []
var obstacles: Array = []
var _visual_rocks: Array = []
var fog: CPUParticles2D
var bokes: Array = []

var ui: CanvasLayer
var night_label: Label
var counter_label: Label
var progress_label: Label
var phase_label: Label
var hint_label: Label
var pause_root: Control
var phase_tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()

	audio = AudioSc.new()
	audio.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(audio)

	sea = SeaSc.new()
	sea.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sea)

	ships_container = Node2D.new()
	ships_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ships_container)

	_build_particles()

	beam = BeamSc.new()
	beam.process_mode = Node.PROCESS_MODE_PAUSABLE
	beam.position = LAMP
	beam.setup(BEAM_LEN, BEAM_HALF, _radial_tex(32, Color(1.0, 1.0, 1.0, 1.0)))
	beam.rotation = 0.2
	add_child(beam)

	_build_rocks_initial()
	sea.setup(_visual_rocks, HARBOR)

	_build_ui()
	_build_postfx()
	_build_boke()
	_update_labels()


# ---------- мир ----------

func _radial_tex(sz: int, inner: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([inner, Color(inner.r, inner.g, inner.b, inner.a * 0.45), Color(inner.r, inner.g, inner.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = sz
	tex.height = sz
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex


func _make_rock(pos: Vector2, r: float) -> Dictionary:
	var pts := PackedVector2Array()
	for i in 8:
		var ang := TAU * float(i) / 8.0
		pts.append(pos + Vector2.from_angle(ang) * r * randf_range(0.75, 1.15))
	return {"pos": pos, "r": r, "pts": pts, "phase": randf() * TAU}


func _build_rocks_initial() -> void:
	for i in 3:
		var rp: Array = ROCK_POOL[i]
		var rk := _make_rock(Vector2(rp[0], rp[1]), rp[2])
		_visual_rocks.append(rk)
		obstacles.append(rk)
	obstacles.append({"pos": ISLET_POS, "r": ISLET_R})


func _build_particles() -> void:
	# биолюминесцентный планктон
	var pl := CPUParticles2D.new()
	pl.texture = _radial_tex(32, Color(1.0, 1.0, 1.0, 1.0))
	pl.amount = 110
	pl.lifetime = 8.0
	pl.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	pl.emission_rect_extents = Vector2(620.0, 190.0)
	pl.position = Vector2(640.0, 505.0)
	pl.direction = Vector2(1.0, 0.0)
	pl.spread = 180.0
	pl.gravity = Vector2.ZERO
	pl.initial_velocity_min = 1.0
	pl.initial_velocity_max = 6.0
	pl.scale_amount_min = 0.4
	pl.scale_amount_max = 1.5
	pl.color = Color(0.45, 0.95, 0.9, 0.30)
	var plmat := CanvasItemMaterial.new()
	plmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pl.material = plmat
	pl.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(pl)
	# туман
	fog = CPUParticles2D.new()
	fog.texture = _radial_tex(256, Color(1.0, 1.0, 1.0, 1.0))
	fog.amount = 14
	fog.lifetime = 26.0
	fog.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fog.emission_rect_extents = Vector2(680.0, 240.0)
	fog.position = Vector2(640.0, 480.0)
	fog.direction = Vector2(1.0, 0.0)
	fog.spread = 10.0
	fog.gravity = Vector2.ZERO
	fog.initial_velocity_min = 4.0
	fog.initial_velocity_max = 12.0
	fog.scale_amount_min = 1.6
	fog.scale_amount_max = 3.0
	fog.color = Color(0.7, 0.8, 0.92, 0.05 + 0.075 * fog_density)
	fog.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fog)


func _build_boke() -> void:
	for i in 6:
		var s := Sprite2D.new()
		s.texture = _radial_tex(128, Color(0.5, 0.95, 0.9, 1.0))
		s.modulate = Color(1.0, 1.0, 1.0, 0.05)
		s.scale = Vector2.ONE * randf_range(3.5, 6.5)
		var base := Vector2(randf_range(100.0, 1180.0), randf_range(340.0, 660.0))
		s.position = base
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		s.material = m
		add_child(s)
		bokes.append({"node": s, "base": base, "ph": randf() * TAU})


func _build_postfx() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PostShader
	rect.material = mat
	layer.add_child(rect)


# ---------- интерфейс ----------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 50
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)

	night_label = Label.new()
	night_label.position = Vector2(24.0, 14.0)
	night_label.add_theme_font_size_override("font_size", 24)
	night_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.97, 0.95))
	night_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	night_label.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(night_label)

	counter_label = Label.new()
	counter_label.position = Vector2(24.0, 46.0)
	counter_label.add_theme_font_size_override("font_size", 16)
	counter_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.85, 0.9))
	counter_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	ui.add_child(counter_label)

	progress_label = Label.new()
	progress_label.position = Vector2(24.0, 68.0)
	progress_label.add_theme_font_size_override("font_size", 16)
	progress_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.85, 0.9))
	progress_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	ui.add_child(progress_label)

	phase_label = Label.new()
	phase_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	phase_label.offset_top = 58.0
	phase_label.offset_bottom = 92.0
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 21)
	phase_label.add_theme_color_override("font_color", Color(0.98, 0.9, 0.78, 0.95))
	phase_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	phase_label.modulate.a = 0.0
	ui.add_child(phase_label)

	hint_label = Label.new()
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -70.0
	hint_label.offset_bottom = -16.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", Color(0.8, 0.88, 0.95, 0.9))
	hint_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	hint_label.text = "Вращай луч мышью — корабли идут за светом. Приведи их к огням гавани.\nЛКМ — всплеск планктона  •  Пробел — колокол  •  Esc — пауза"
	ui.add_child(hint_label)

	# --- меню паузы ---
	pause_root = Control.new()
	pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_root.visible = false
	ui.add_child(pause_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	pause_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_root.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.14, 0.97)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(26.0)
	sb.border_color = Color(0.3, 0.5, 0.55, 0.35)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	box.add_child(title)

	box.add_child(_make_slider_row("Море", audio.get_bus_volume("Amb"), Callable(self, "_on_sea_vol")))
	box.add_child(_make_slider_row("Мелодия", audio.get_bus_volume("Music"), Callable(self, "_on_music_vol")))

	var btn_resume := Button.new()
	btn_resume.text = "Продолжить"
	_style_button(btn_resume)
	btn_resume.pressed.connect(_resume)
	box.add_child(btn_resume)

	var btn_restart := Button.new()
	btn_restart.text = "Начать заново"
	_style_button(btn_restart)
	btn_restart.pressed.connect(_restart)
	box.add_child(btn_restart)


func _make_slider_row(caption: String, val: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lab := Label.new()
	lab.text = caption
	lab.custom_minimum_size = Vector2(110.0, 0.0)
	lab.add_theme_font_size_override("font_size", 17)
	lab.add_theme_color_override("font_color", Color(0.75, 0.85, 0.92))
	row.add_child(lab)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = val
	slider.custom_minimum_size = Vector2(230.0, 24.0)
	slider.value_changed.connect(cb)
	row.add_child(slider)
	return row


func _style_button(b: Button) -> void:
	var defs := [["normal", Color(0.12, 0.2, 0.28)], ["hover", Color(0.16, 0.27, 0.36)], ["pressed", Color(0.1, 0.16, 0.22)], ["focus", Color(0.14, 0.24, 0.32)]]
	for d in defs:
		var sb := StyleBoxFlat.new()
		sb.bg_color = d[1]
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(10.0)
		b.add_theme_stylebox_override(d[0], sb)
	b.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))


func _update_labels() -> void:
	night_label.text = "Ночь %d" % night_number
	counter_label.text = "Корабли в гавани: %d" % docked_total
	progress_label.text = "Этой ночью: %d из %d" % [docked_this_night, ships_per_night]


func _flash_phase(txt: String) -> void:
	phase_label.text = txt
	if phase_tw:
		phase_tw.kill()
	phase_tw = create_tween()
	phase_tw.tween_property(phase_label, "modulate:a", 1.0, 1.6)


func _fade_phase() -> void:
	if phase_tw:
		phase_tw.kill()
	phase_tw = create_tween()
	phase_tw.tween_property(phase_label, "modulate:a", 0.0, 2.0)


func _on_sea_vol(v: float) -> void:
	audio.set_bus_volume("Amb", v)


func _on_music_vol(v: float) -> void:
	audio.set_bus_volume("Music", v)


func _resume() -> void:
	_set_paused(false)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	pause_root.visible = p


# ---------- корабли ----------

func _spawn_ship() -> void:
	var pos: Vector2
	var v := randi_range(0, 2)
	if v == 0:
		pos = Vector2(-45.0, randf_range(360.0, 660.0))
	elif v == 1:
		pos = Vector2(randf_range(180.0, 1000.0), 312.0)
	else:
		pos = Vector2(randf_range(180.0, 900.0), 748.0)
	var tgt := Vector2(randf_range(480.0, 950.0), randf_range(430.0, 610.0))
	var head := (tgt - pos).angle() + randf_range(-0.35, 0.35)
	var s := ShipSc.new(pos, head, randf_range(0.85, 1.2))
	ships_container.add_child(s)
	ships.append(s)


func _dock_ship(s) -> void:
	s.state = s.ST_DOCKING
	s.in_beam = false
	docked_this_night += 1
	docked_total += 1
	audio.harbor_bell()
	_update_labels()
	var tw := ships_container.create_tween()
	tw.tween_property(s, "position", DOCK_END, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 2.0).set_delay(0.7)
	tw.chain().tween_callback(Callable(self, "_ship_gone").bind(s))


func _ship_gone(s) -> void:
	ships.erase(s)
	if is_instance_valid(s):
		s.queue_free()


func _click_burst(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = _radial_tex(32, Color(1.0, 1.0, 1.0, 1.0))
	p.amount = 26
	p.lifetime = 1.3
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.direction = Vector2(0.0, 0.0)
	p.spread = 180.0
	p.gravity = Vector2(0.0, 4.0)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 75.0
	p.damping_min = 40.0
	p.damping_max = 70.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.color = Color(0.45, 0.95, 0.88, 0.55)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.position = pos
	p.emitting = true
	ships_container.add_child(p)
	p.finished.connect(p.queue_free)


# ---------- игровой цикл ----------

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	t += delta

	# луч следует за мышью
	var to_m := get_global_mouse_position() - LAMP
	if to_m.length() > 8.0:
		beam.rotation = lerp_angle(beam.rotation, to_m.angle(), minf(1.0, 5.0 * delta))

	# корабли и луч
	for s in ships:
		if s.state == s.ST_DOCKING:
			continue
		var d := s.position.distance_to(LAMP)
		var rel := (s.position - LAMP).angle()
		var diff := absf(wrapf(rel - beam.rotation, -PI, PI))
		var inb := d < BEAM_LEN - 20.0 and diff < BEAM_HALF * 0.85 and d > 30.0
		s.in_beam = inb
		if inb:
			s.guided_heading = beam.rotation
		if inb and not s.was_in_beam:
			audio.beam_ping()
		s.was_in_beam = inb

	# рифы и остров
	knock_cd -= delta
	for s in ships:
		if s.state == s.ST_DOCKING:
			continue
		s.blocked = null
		for ob in obstacles:
			if s.position.distance_to(ob["pos"]) < float(ob["r"]) + 12.0:
				s.blocked = ob
				if knock_cd <= 0.0:
					audio.knock()
					knock_cd = 1.3

	# гавань
	for s in ships.duplicate():
		if s.state != s.ST_DOCKING and s.position.distance_to(HARBOR) < 52.0:
			_dock_ship(s)

	# спавн новых кораблей
	spawn_t -= delta
	if phase == Phase.NIGHT and spawn_t <= 0.0 and ships.size() < ships_cap:
		_spawn_ship()
		spawn_t = randf_range(7.0, 13.0)

	_match_phase(delta)

	# боке-частицы дрейфуют
	for b in bokes:
		var base: Vector2 = b["base"]
		var ph: float = b["ph"]
		b["node"].position = base + Vector2(sin(t * 0.05 + ph) * 30.0, cos(t * 0.04 + ph) * 20.0)

	# подсказка медленно тает
	hint_t += delta
	var ha := 1.0
	if hint_t > 18.0:
		ha = clampf(1.0 - (hint_t - 18.0) / 5.0, 0.0, 1.0)
	hint_label.modulate.a = ha

	sea.day_phase = day_phase
	audio.day_phase = day_phase


func _match_phase(delta: float) -> void:
	match phase:
		Phase.NIGHT:
			if docked_this_night >= ships_per_night:
				phase = Phase.DAWN
				phase_t = 0.0
				_flash_phase("Рассвет. Море отдыхает…")
		Phase.DAWN:
			phase_t += delta
			day_phase = clampf(phase_t / 30.0, 0.0, 1.0)
			if phase_t >= 42.0:
				phase = Phase.REST
				phase_t = 0.0
		Phase.REST:
			phase_t += delta
			if phase_t >= 10.0:
				phase = Phase.NIGHTFALL
				phase_t = 0.0
				_fade_phase()
		Phase.NIGHTFALL:
			phase_t += delta
			day_phase = clampf(1.0 - phase_t / 8.0, 0.0, 1.0)
			if phase_t >= 8.0:
				_new_night()


func _new_night() -> void:
	night_number += 1
	ships_per_night = 5 + (night_number - 1) * 2
	ships_cap = clampi(night_number, 1, 3)
	docked_this_night = 0
	fog_density = clampf(0.4 + 0.13 * float(night_number), 0.0, 1.0)
	fog.color = Color(0.7, 0.8, 0.92, 0.05 + 0.075 * fog_density)
	var idx := night_number + 1
	if idx < ROCK_POOL.size():
		var rp: Array = ROCK_POOL[idx]
		var rk := _make_rock(Vector2(rp[0], rp[1]), rp[2])
		_visual_rocks.append(rk)
		obstacles.append(rk)
	phase = Phase.NIGHT
	spawn_t = 3.0
	_update_labels()
	_flash_phase("Ночь %d. Туман густеет…" % night_number)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_paused(not get_tree().paused)
		elif event.keycode == KEY_SPACE and not get_tree().paused:
			audio.bell_small()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not get_tree().paused:
		_click_burst(get_global_mouse_position())
		audio.click_ping()
