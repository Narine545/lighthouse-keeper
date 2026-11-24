# ship.gd — корабль: силуэт с тёплым фонарём, светящийся кильватер,
# биолюминесцентный след и мягкое поведение «за светом маяка».
extends Node2D

const ST_DRIFT := 0
const ST_DOCKING := 1

var state := ST_DRIFT
var heading := 0.0
var guided_heading := 0.0
var in_beam := false
var was_in_beam := false
var blocked = null  # Dictionary рифа или null
var glow := 0.0     # 0..1 — насколько корабль «пойман» светом

var _t := 0.0
var _seed_ph := 0.0
var _size_f := 1.0
var _cur_speed := 10.0
var _wake_t := 0.0
var _wake_pts: Array = []
var _plank: CPUParticles2D
var _lantern: Sprite2D


func _init(pos: Vector2, head: float, sc: float) -> void:
	position = pos
	heading = head
	_size_f = sc
	_seed_ph = randf() * TAU


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


func _ready() -> void:
	scale = Vector2(_size_f, _size_f)
	rotation = heading
	# тёплый фонарь (аддитивное свечение)
	_lantern = Sprite2D.new()
	_lantern.texture = _radial_tex(128, Color(1.0, 0.8, 0.45, 0.9))
	_lantern.position = Vector2(14.0, -1.0)
	_lantern.scale = Vector2(0.5, 0.5)
	var lmat := CanvasItemMaterial.new()
	lmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lantern.material = lmat
	add_child(_lantern)
	# биолюминесцентный след
	_plank = CPUParticles2D.new()
	_plank.texture = _radial_tex(32, Color(1.0, 1.0, 1.0, 1.0))
	_plank.amount = 16
	_plank.lifetime = 2.4
	_plank.local_coords = false
	_plank.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	_plank.direction = Vector2(0, 0)
	_plank.spread = 180.0
	_plank.gravity = Vector2.ZERO
	_plank.initial_velocity_min = 2.0
	_plank.initial_velocity_max = 9.0
	_plank.scale_amount_min = 0.5
	_plank.scale_amount_max = 1.3
	_plank.color = Color(0.45, 0.95, 0.88, 0.5)
	var pmat := CanvasItemMaterial.new()
	pmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_plank.material = pmat
	_plank.emitting = false
	add_child(_plank)


func _process(delta: float) -> void:
	_t += delta
	if state == ST_DOCKING:
		_plank.emitting = false
		return

	var sp := 12.0
	if in_beam:
		heading = lerp_angle(heading, guided_heading, minf(1.0, 2.6 * delta))
		sp = 36.0
		glow = minf(1.0, glow + delta * 2.5)
	else:
		glow = maxf(0.0, glow - delta * 1.5)
		# мягкое блуждание в дрейфе
		heading += sin(_t * 0.35 + _seed_ph) * 0.28 * delta

	var move_dir := Vector2.from_angle(heading)
	if blocked != null:
		var away: Vector2 = (position - Vector2(blocked["pos"])).normalized()
		if move_dir.dot(away) < 0.25:
			sp = 0.0
		else:
			blocked = null

	# держимся в границах моря
	if position.y < 360.0 or position.y > 700.0 or position.x < 45.0:
		var to_c := (Vector2(640.0, 505.0) - position).angle()
		heading = lerp_angle(heading, to_c, minf(1.0, 1.6 * delta))

	_cur_speed = lerpf(_cur_speed, sp, minf(1.0, 2.0 * delta))
	position += Vector2.from_angle(heading) * _cur_speed * delta
	rotation = heading

	# кильватер
	_wake_t += delta
	if _wake_t >= 0.12 and _cur_speed > 6.0:
		_wake_t = 0.0
		_wake_pts.append(position + Vector2.from_angle(heading) * -14.0)
		if _wake_pts.size() > 26:
			_wake_pts.pop_front()

	_plank.emitting = _cur_speed > 8.0
	var flick := 0.8 + 0.2 * sin(_t * 6.3 + _seed_ph)
	_lantern.modulate = Color(1.0, 1.0, 1.0, 0.75 + 0.25 * flick + 0.2 * glow)
	queue_redraw()


func _draw() -> void:
	var sil := Color(0.015, 0.03, 0.055)
	var hull := PackedVector2Array([
		Vector2(20.0, 0.0), Vector2(12.0, -6.0), Vector2(-4.0, -8.0),
		Vector2(-14.0, -6.0), Vector2(-16.0, 0.0), Vector2(-14.0, 5.0),
		Vector2(-4.0, 7.0), Vector2(12.0, 6.0),
	])
	# тень-отражение под корпусом
	draw_circle(Vector2(0.0, 10.0), 16.0, Color(0.0, 0.0, 0.0, 0.15))
	# кильватер
	if _wake_pts.size() > 2:
		for i in range(_wake_pts.size() - 1):
			var a := float(i) / float(_wake_pts.size())
			var p0 := to_local(_wake_pts[i])
			var p1 := to_local(_wake_pts[i + 1])
			draw_line(p0, p1, Color(0.45, 0.9, 0.85, 0.03 + 0.11 * a), 0.6 + 1.8 * a, true)
	# ореол, когда корабль ведут светом
	if glow > 0.01:
		draw_circle(Vector2(0.0, 0.0), 30.0, Color(0.4, 0.95, 0.9, 0.10 * glow))
		draw_circle(Vector2(14.0, -1.0), 22.0, Color(1.0, 0.85, 0.5, 0.10 * glow))
	draw_colored_polygon(hull, sil)
	draw_rect(Rect2(-12.0, -7.0, 12.0, 7.0), Color(0.03, 0.05, 0.085))
	draw_line(Vector2(0.0, -6.0), Vector2(0.0, -22.0), sil, 1.5, true)
	draw_circle(Vector2(-14.0, 0.0), 3.0 + glow * 4.0, Color(0.4, 0.95, 0.9, 0.16 + 0.2 * glow))
	draw_circle(Vector2(14.0, -1.0), 2.2, Color(1.0, 0.9, 0.6, 0.95))
