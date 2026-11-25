class_name Jelly
extends Node2D

# Медуза — живописный колокол с vertex-градиентом (тело — полупрозрачная
# «акварель»), мягким световым ореолом и щупальцами-мазками.
# Спит: тусклая, медленно пульсирует слабым ореолом — маячок для игрока.
# Просыпается: расцветает своим оттенком, тянется к поверхности.

signal awakened

const HUES := [Color("86f7e4"), Color("a68cff"), Color("ff8fc9"), Color("5ee8ff"), Color("ffd489")]

var awake := false
var _wake_t := 0.0
var _t := randf() * 10.0
var _ph := randf() * TAU
var _pulse_spd := randf_range(0.8, 1.3)
var _R := randf_range(34.0, 52.0)
var _hue := Color("86f7e4")
var _home := Vector2.ZERO
var _glow: GlowLayer
var _sparks: Array = []


func _ready() -> void:
        _hue = HUES[randi() % HUES.size()]
        _home = position
        _glow = GlowLayer.new()
        _glow.painter = self
        _glow.material = Paint.add_mat()
        add_child(_glow)


func wake() -> void:
        if awake:
                return
        awake = true
        awakened.emit()
        for i in 16:
                var a := TAU * float(i) / 16.0 + randf() * 0.3
                _sparks.append({
                        "p": Vector2.ZERO,
                        "v": Vector2.from_angle(a) * randf_range(60.0, 150.0),
                        "t": 0.0,
                })


func _process(delta: float) -> void:
        _t += delta
        var spd := 1.15 if awake else 0.5
        _ph += delta * spd * _pulse_spd
        if awake:
                _wake_t = minf(_wake_t + delta / 1.8, 1.0)
                var ty := _home.y - 120.0
                var vy := (ty - position.y) * 0.12 + sin(_ph * 0.5) * 6.0
                var vx := sin(_t * 0.17 + 2.0) * 18.0
                position += Vector2(vx, vy) * delta * _wake_t
        else:
                position = _home + Vector2(Paint.wobble(_t * 0.14, _ph) * 14.0, sin(_ph * 0.35) * 8.0)
        for e in _sparks:
                e["t"] = float(e["t"]) + delta
                e["p"] = e["p"] + e["v"] * delta
                e["v"] = e["v"] * (1.0 - minf(delta * 2.0, 0.6))
        for i in range(_sparks.size() - 1, -1, -1):
                if float(_sparks[i]["t"]) > 1.1:
                        _sparks.erase(_sparks[i])
        queue_redraw()
        _glow.queue_redraw()


func _draw() -> void:
        # Колокол: верхняя дуга + пульсирующая «юбка», акварельные цвета.
        var R := _R * (0.86 + 0.14 * _wake_t)
        var sq_a := 0.14 if awake else 0.05
        var sq := 1.0 + sq_a * sin(_ph)
        var rim := _hue
        var top := _hue.darkened(0.55)
        var pts := PackedVector2Array()
        var cols := PackedColorArray()
        for i in 25:
                var a := PI - PI * float(i) / 24.0
                var rr := R * (1.0 + 0.10 * sin(a * 2.0 + _ph * 0.5))
                pts.append(Vector2(cos(a) * rr, -sin(a) * rr * sq))
                var edge := absf(cos(a))
                var c := top.lerp(rim, edge)
                c.a = 0.75
                cols.append(c)
        for j in range(1, 12):
                var t := float(j) / 12.0
                var x := R - 2.0 * R * t
                var yy := R * 0.30 * sin(PI * t) * (1.0 + 0.2 * sin(_ph)) + R * 0.06
                pts.append(Vector2(x, yy))
                var c2 := rim.darkened(0.4)
                c2.a = 0.45
                cols.append(c2)
        pts.append(Vector2(-R, 0.0))
        var cc := rim.darkened(0.4)
        cc.a = 0.45
        cols.append(cc)
        draw_polygon(pts, cols)


func _paint_glow(ci: CanvasItem) -> void:
        var R := _R * (0.86 + 0.14 * _wake_t)
        # ореол: маячок во сне, мягкое дыхание в бодрости
        var halo_a := 0.0
        if awake:
                halo_a = 0.16 + 0.06 * sin(_ph)
        else:
                halo_a = 0.05 + 0.11 * pow(0.5 + 0.5 * sin(_t * 1.3), 4.0)
        var hc := _hue
        hc.a = halo_a
        Paint.blob(ci, Vector2(0.0, -R * 0.2), R * 2.5 * (0.85 + 0.3 * _wake_t), hc)
        # внутренние органы — тёплые мазки в толще колокола
        var ic := _hue.lightened(0.35)
        ic.a = 0.16 + 0.16 * _wake_t
        Paint.blob(ci, Vector2(0.0, -R * 0.15), R * 0.32, ic)
        var ic2 := Color(0.9, 1.0, 0.97, 0.10 + 0.22 * _wake_t)
        Paint.blob(ci, Vector2(0.0, 0.0), R * 0.16, ic2)
        # щупальца — цепочки мазков с сужением
        for k in 5:
                var bx := lerpf(-R * 0.7, R * 0.7, float(k) / 4.0)
                var base := Vector2(bx, R * 0.28)
                var ln := R * (1.6 + 0.9 * _wake_t) * (0.85 + 0.15 * float(k % 3))
                var pts := []
                for s in 12:
                        var tt := float(s) / 11.0
                        var sway := sin(tt * 2.6 + _ph * (0.9 + 0.25 * tt) + float(k)) * (5.0 + 16.0 * tt) * (0.5 + 0.5 * _wake_t)
                        pts.append(base + Vector2(sway, tt * ln))
                var tc := _hue
                tc.a = 0.22 + 0.30 * _wake_t
                Paint.chain(ci, pts, R * 0.14, R * 0.03, tc)
        # искры пробуждения
        for e in _sparks:
                var st := float(e["t"])
                var f := 1.0 - st / 1.1
                if f <= 0.0:
                        continue
                var sc := _hue
                sc.a = 0.7 * f
                Paint.blob(ci, e["p"], 5.0 + 4.0 * f, sc)
