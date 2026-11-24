# beam.gd — объёмный световой конус маяка: три вложенных слоя + пылинки в свете.
extends Node2D

var length := 560.0
var half_angle := 0.15
var t := 0.0

var _motes: CPUParticles2D


func setup(len_: float, ha: float, dot_tex: Texture2D) -> void:
	length = len_
	half_angle = ha
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_motes = CPUParticles2D.new()
	_motes.position = Vector2(length * 0.45, 0.0)
	_motes.texture = dot_tex
	_motes.amount = 42
	_motes.lifetime = 7.0
	_motes.local_coords = true
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(length * 0.45, length * sin(half_angle) * 0.8)
	_motes.direction = Vector2(1.0, 0.0)
	_motes.spread = 12.0
	_motes.gravity = Vector2.ZERO
	_motes.initial_velocity_min = 3.0
	_motes.initial_velocity_max = 9.0
	_motes.scale_amount_min = 0.35
	_motes.scale_amount_max = 1.0
	_motes.color = Color(1.0, 0.9, 0.68, 0.38)
	add_child(_motes)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _cone(ha: float, ln: float, a: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	var steps := 10
	for i in steps + 1:
		var ang := -ha + (2.0 * ha) * float(i) / float(steps)
		pts.append(Vector2.from_angle(ang) * ln)
	draw_colored_polygon(pts, Color(1.0, 0.9, 0.62, a))


func _draw() -> void:
	var flick := 0.9 + 0.1 * sin(t * 9.1) * sin(t * 3.3)
	_cone(half_angle, length, 0.09 * flick)
	_cone(half_angle * 0.62, length * 0.94, 0.13 * flick)
	_cone(half_angle * 0.30, length * 0.85, 0.20 * flick)
	draw_circle(Vector2.ZERO, 30.0, Color(1.0, 0.92, 0.7, 0.10 * flick))
	draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.9, 0.65, 0.28 * flick))
	draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.95, 0.8, 0.85))
