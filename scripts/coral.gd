class_name Coral
extends Node2D

# Кораллы — тёплый акцент на холодном дне. Стебли растут и раскачиваются,
# кончики вспыхивают светом. Спит: короткие тёмные стебли со слабым
# пульсом на бутонах. Просыпается: стебли разворачиваются, бутоны загораются.

signal awakened

var awake := false
var _wake_t := 0.0
var _t := randf() * 10.0
var _hue := Color("ffb27a")
var _R := randf_range(46.0, 70.0)
var _strands: Array = []
var _rock: Array = []
var _sparks: Array = []
var _glow: GlowLayer


func _ready() -> void:
        _hue = [Color("ffb27a"), Color("ff8fc9"), Color("ffd489"), Color("ff9a76")][randi() % 4]
        for i in 6:
                _strands.append({
                        "dir": lerpf(-0.9, 0.9, float(i) / 5.0) + randf_range(-0.12, 0.12),
                        "len": randf_range(55.0, 115.0),
                        "curve": randf_range(-0.5, 0.5),
                        "ph": randf() * TAU,
                        "wt": 0.0,
                        "delay": float(i) * 0.16,
                })
        for i in 14:
                _rock.append(randf_range(0.75, 1.15))
        _glow = GlowLayer.new()
        _glow.painter = self
        _glow.material = Paint.add_mat()
        add_child(_glow)


func wake() -> void:
        if awake:
                return
        awake = true
        awakened.emit()
        for i in 12:
                var a := TAU * float(i) / 12.0 + randf() * 0.4
                _sparks.append({
                        "p": Vector2(randf_range(-20.0, 20.0), randf_range(-30.0, 0.0)),
                        "v": Vector2.from_angle(a) * randf_range(40.0, 120.0) + Vector2(0, -40),
                        "t": 0.0,
                })


func _process(delta: float) -> void:
        _t += delta
        if awake:
                _wake_t = minf(_wake_t + delta / 1.8, 1.0)
        for s in _strands:
                if awake and float(s["delay"]) > 0.0:
                        s["delay"] = maxf(float(s["delay"]) - delta, 0.0)
                elif awake:
                        s["wt"] = minf(float(s["wt"]) + delta * 0.9, 1.0)
        for e in _sparks:
                e["t"] = float(e["t"]) + delta
                e["p"] = e["p"] + e["v"] * delta
                e["v"] = e["v"] * (1.0 - minf(delta * 1.8, 0.6))
        for i in range(_sparks.size() - 1, -1, -1):
                if float(_sparks[i]["t"]) > 1.3:
                        _sparks.erase(_sparks[i])
        queue_redraw()
        _glow.queue_redraw()


func _draw() -> void:
        # камень-основание: неровный «живописный» полигон
        var pts := PackedVector2Array()
        var cols := PackedColorArray()
        var n := _rock.size()
        for i in n:
                var a := PI + PI * float(i) / float(n - 1)
                var rr := _R * 0.55 * float(_rock[i])
                pts.append(Vector2(cos(a) * rr, absf(sin(a)) * rr * 0.45 + 6.0))
                var c := Color("123044").lerp(Color("0a1424"), float(i) / float(n - 1))
                c.a = 1.0
                cols.append(c)
        draw_polygon(pts, cols)
        # стебли — линии с градиентом толщины и цвета
        for s in _strands:
                var wt: float = s["wt"]
                var ln: float = float(s["len"]) * (0.45 + 0.55 * wt)
                var ph: float = s["ph"]
                var sway := Paint.wobble(_t * 0.5, ph) * (0.06 + 0.14 * wt)
                var prev := Vector2.ZERO
                for seg in 8:
                        var t := float(seg) / 7.0
                        var ang := float(s["dir"]) * 0.8 * t + float(s["curve"]) * t * t + sway * t
                        var pnt := Vector2(sin(ang) * ln * t, -cos(ang) * ln * t)
                        if seg > 0:
                                var lc := Color("16323e").lerp(_hue.darkened(0.25), t * (0.35 + 0.65 * wt))
                                lc.a = 0.85
                                draw_line(prev, pnt, lc, 4.5 - 2.6 * t, true)
                        prev = pnt


func _paint_glow(ci: CanvasItem) -> void:
        # мягкая тёплая подсветка основания
        var base := _hue
        base.a = 0.06 + 0.10 * _wake_t
        Paint.blob(ci, Vector2(0.0, 0.0), _R * 0.9, base)
        # бутоны на кончиках — маячки во сне, пламя в бодрости
        for s in _strands:
                var wt: float = s["wt"]
                var ln: float = float(s["len"]) * (0.45 + 0.55 * wt)
                var ph: float = s["ph"]
                var sway := Paint.wobble(_t * 0.5, ph) * (0.06 + 0.14 * wt)
                var ang := float(s["dir"]) * 0.8 + float(s["curve"]) + sway
                var tip := Vector2(sin(ang) * ln, -cos(ang) * ln)
                var ta := 0.0
                if wt > 0.01:
                        ta = 0.12 + 0.5 * wt
                else:
                        ta = 0.10 + 0.12 * pow(0.5 + 0.5 * sin(_t * 1.1 + ph), 4.0)
                var tc := _hue.lightened(0.2)
                tc.a = ta
                Paint.blob(ci, tip, 7.0 + 6.0 * wt, tc)
        # искры пробуждения
        for e in _sparks:
                var st := float(e["t"])
                var f := 1.0 - st / 1.3
                if f <= 0.0:
                        continue
                var sc := _hue
                sc.a = 0.6 * f
                Paint.blob(ci, e["p"], 4.0 + 4.0 * f, sc)
