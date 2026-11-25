class_name Whale
extends Node2D

# Кит — редкое событие. Огромный тёмный силуэт плывёт вдалеке,
# задний плавник гибко машет, спину подсвечивает слабая бирюза.
# Три долгих зовa на проход — экран чуть «качается» от глубины голоса.

signal song(idx: int)
signal finished

const PTS := [
        Vector2(265, -2), Vector2(238, -26), Vector2(160, -44), Vector2(40, -54),
        Vector2(-70, -52), Vector2(-170, -36), Vector2(-242, -14),
        Vector2(-268, -2),
        Vector2(-318, -30), Vector2(-344, -6),
        Vector2(-296, 8), Vector2(-346, 26), Vector2(-322, 44),
        Vector2(-262, 14),
        Vector2(-180, 26), Vector2(-40, 40), Vector2(120, 34), Vector2(230, 18),
]

var _t := randf() * 5.0
var _x := -700.0
var _dir := 1.0
var _y0 := 300.0
var _w := 1280.0
var _glow: GlowLayer
var _sang := [false, false, false]
var _marks: Array = [0.25, 0.5, 0.72]


func _ready() -> void:
        z_index = -4
        _glow = GlowLayer.new()
        _glow.painter = self
        _glow.material = Paint.add_mat()
        add_child(_glow)


func setup(width: float, direction: int) -> void:
        _w = width
        _dir = float(direction)
        _y0 = randf_range(210.0, 330.0)
        if _dir > 0.0:
                _x = -700.0
        else:
                _x = _w + 700.0


func _process(delta: float) -> void:
        _t += delta
        _x += _dir * 34.0 * delta
        position = Vector2(_x, _y0 + sin(_t * 0.4) * 10.0)
        for i in 3:
                if not _sang[i] and _x > _w * float(_marks[i]) and _dir > 0.0:
                        _sang[i] = true
                        song.emit(i)
                if not _sang[i] and _x < _w * (1.0 - float(_marks[i])) and _dir < 0.0:
                        _sang[i] = true
                        song.emit(i)
        if (_dir > 0.0 and _x > _w + 750.0) or (_dir < 0.0 and _x < -750.0):
                finished.emit()
                queue_free()
                return
        queue_redraw()
        _glow.queue_redraw()


func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
        var t2 := t * t
        var t3 := t2 * t
        return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _sampled() -> PackedVector2Array:
        var m := PTS.size()
        var out := PackedVector2Array()
        var steps := 64
        for i in steps:
                var idx := int(float(i) / float(steps) * float(m))
                var p0: Vector2 = PTS[(idx - 1 + m) % m]
                var p1: Vector2 = PTS[idx % m]
                var p2: Vector2 = PTS[(idx + 1) % m]
                var p3: Vector2 = PTS[(idx + 2) % m]
                var lt := fmod(float(i) / float(steps) * float(m), 1.0)
                var pnt := _cr(p0, p1, p2, p3, lt)
                # гибкий хвост
                if pnt.x < -240.0:
                        pnt.y += sin(_t * 0.9 - 1.0) * 16.0 * clampf((-pnt.x - 240.0) / 110.0, 0.0, 1.4)
                out.append(pnt)
        return out


func _draw() -> void:
        # тёмный силуэт: верх — глубже, брюхо — чуть светлее (vertex-градиент)
        var pts := _sampled()
        var cols := PackedColorArray()
        for p in pts:
                var f := clampf((p.y + 54.0) / 96.0, 0.0, 1.0)
                var c := Color("0b1526").lerp(Color("13233a"), f)
                c.a = 0.94
                cols.append(c)
        draw_polygon(pts, cols)


func _paint_glow(ci: CanvasItem) -> void:
        # слабая бирюза на спине — свет воды ложится на силуэт
        for i in 6:
                var f := float(i) / 5.0
                var px := lerpf(210.0, -230.0, f)
                var py := lerpf(-30.0, -20.0, absf(f * 2.0 - 1.0)) - 14.0 * sin(f * PI)
                var rc := Color(0.35, 0.75, 0.72, 0.10 + 0.05 * sin(_t * 0.8 + f * 2.0))
                Paint.blob(ci, Vector2(px, py), 34.0, rc)
        # присутствие: едва заметный ореол всего тела
        Paint.blob(ci, Vector2(0.0, 0.0), 320.0, Color(0.20, 0.45, 0.44, 0.05))
        # глаз
        Paint.blob(ci, Vector2(196.0, -8.0), 3.5, Color(0.75, 0.95, 0.9, 0.55))
