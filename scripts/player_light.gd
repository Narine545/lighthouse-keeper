class_name PlayerLight
extends Node2D

# Игрок — живой свет. Плывёт к мыши на мягкой пружине, дышит, оставляет
# светящийся след, а по клику посылает импульс — расширяющееся кольцо.

signal pulsed(pos: Vector2, power: float)

var _target := Vector2(640, 400)
var _trail: Array = []
var _pulse_t := 10.0
var _energy := 1.0
var _t := randf() * 10.0


func _ready() -> void:
        material = Paint.add_mat()
        z_index = 6


func set_target(p: Vector2) -> void:
        _target = p


func radius() -> float:
        return 120.0 + 34.0 * _energy + Paint.wobble(_t, 3.1) * 8.0


func strength() -> float:
        return clampf(0.55 + 0.45 * _energy, 0.0, 1.0)


func pulse() -> bool:
        if _pulse_t < 1.1:
                return false
        _pulse_t = 0.0
        _energy = 1.0
        pulsed.emit(position, 1.0)
        return true


func _process(delta: float) -> void:
        _t += delta
        var k := 1.0 - exp(-delta * 4.2)
        var prev := position
        position = position.lerp(_target, k)
        _energy = maxf(_energy - delta * 0.65, 0.0)
        _pulse_t += delta
        for e in _trail:
                e[1] = float(e[1]) + delta
        while _trail.size() > 0 and float(_trail[0][1]) > 0.9:
                _trail.pop_front()
        if _trail.size() > 60:
                _trail.pop_front()
        _trail.append([position, 0.0])
        queue_redraw()


func _draw() -> void:
        var R := radius()
        var st := strength()
        var br := 0.82 + 0.18 * sin(_t * 1.1) + 0.05 * Paint.wobble(_t * 2.0, 1.3)
        # слои света: широкий ореол — тёплая бирюза — белое ядро
        Paint.blob(self, Vector2.ZERO, R * 2.7, Color(0.16, 0.42, 0.44, 0.30 * br * st))
        Paint.blob(self, Vector2.ZERO, R * 1.25, Color(0.30, 0.75, 0.68, 0.34 * br * st))
        Paint.blob(self, Vector2.ZERO, R * 0.52, Color(0.62, 1.0, 0.92, 0.5 * br))
        Paint.blob(self, Vector2.ZERO, R * 0.20, Color(0.95, 1.0, 0.98, 0.75 * br))
        # след — затухающие мазки
        for e in _trail:
                var age := float(e[1])
                var f := 1.0 - age / 0.9
                if f <= 0.0:
                        continue
                Paint.blob(self, e[0] - position, clampf(16.0 * f, 2.0, 16.0), Color(0.45, 0.9, 0.82, 0.20 * f * f))
        # импульс — светящееся кольцо
        if _pulse_t < 1.0:
                var pt := _pulse_t
                var rr := lerpf(40.0, 430.0, 1.0 - pow(1.0 - pt, 2.0))
                var fa := (1.0 - pt) * 0.55
                draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48, Color(0.6, 1.0, 0.9, fa), 5.0, true)
                Paint.blob(self, Vector2.ZERO, 90.0, Color(0.7, 1.0, 0.94, fa * 0.8))
