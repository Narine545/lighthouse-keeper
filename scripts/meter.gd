class_name MeterOrb
extends Node2D

# «Свет глубины» — мягкая сфера внизу экрана. Растёт от пробуждений,
# вспыхивает при каждом событии. Никаких полос и цифр — только свет.

var _v := 0.0
var _flash := 0.0
var _t := 0.0


func _ready() -> void:
        material = Paint.add_mat()
        z_index = 7


func set_value(v: float) -> void:
        _v = clampf(v, 0.0, 1.0)


func flash() -> void:
        _flash = 1.0


func _process(delta: float) -> void:
        _t += delta
        _flash = maxf(_flash - delta * 1.6, 0.0)
        queue_redraw()


func _draw() -> void:
        var br := 0.85 + 0.15 * sin(_t * 1.4)
        Paint.blob(self, Vector2.ZERO, 30.0 + 44.0 * _v, Color(0.30, 0.75, 0.66, 0.10 + 0.30 * _v * br))
        Paint.blob(self, Vector2.ZERO, 10.0 + 20.0 * _v, Color(0.62, 1.0, 0.92, 0.30 + 0.42 * _v * br))
        Paint.blob(self, Vector2.ZERO, 5.0 + 8.0 * _v, Color(0.95, 1.0, 0.98, 0.35 + 0.45 * _v))
        if _flash > 0.01:
                draw_arc(Vector2.ZERO, 52.0 + 30.0 * (1.0 - _flash), 0.0, TAU, 40, Color(0.6, 1.0, 0.9, _flash * 0.5), 4.0, true)
