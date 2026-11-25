class_name Meteor
extends Node2D

# Метеор, видимый сквозь толщу воды: тонкий дрожащий след света
# в верхней части экрана, с искрами позади.

var _v := Vector2(-260.0, 120.0)
var _life := 1.7
var _t := 0.0
var _w := 1280.0


func _ready() -> void:
        material = Paint.add_mat()
        z_index = 3


func setup(width: float) -> void:
        _w = width
        var side := randi() % 2
        var x := randf_range(_w * 0.15, _w * 0.95)
        var y := randf_range(30.0, 130.0)
        if side == 0:
                _v = Vector2(-randf_range(220.0, 340.0), randf_range(90.0, 150.0))
                position = Vector2(x, y)
        else:
                _v = Vector2(randf_range(220.0, 340.0), randf_range(90.0, 150.0))
                position = Vector2(_w - x, y)


func _process(delta: float) -> void:
        _t += delta
        position += _v * delta
        if _t > _life:
                queue_free()
                return
        queue_redraw()


func _draw() -> void:
        var a := sin(PI * clampf(_t / _life, 0.0, 1.0))
        var back := -_v.normalized()
        for k in 9:
                var f := float(k) / 8.0
                var p := back * (f * 95.0) + Vector2(0.0, sin(_t * 18.0 + f * 5.0) * 2.0)
                var c := Color(0.8, 0.95, 1.0, a * (0.10 + 0.40 * (1.0 - f)))
                Paint.blob(self, p, 2.5 + 4.5 * (1.0 - f), c)
        Paint.blob(self, Vector2.ZERO, 7.0, Color(0.95, 1.0, 1.0, a * 0.85))
