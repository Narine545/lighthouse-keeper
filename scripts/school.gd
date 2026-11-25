class_name School
extends Node2D

# Стая рыб-комет: головы — мазки света, за ними тянется шлейф движения.
# Спит: тускло дрейфует, стая мерцает слабым общим ореолом.
# Просыпается: рыбы по одной оживают и кружат вокруг света игрока.
# Если собирается достаточно рыб близко к свету — стая закручивается вихрем.

signal awakened
signal swirled(pos: Vector2)

const FISH_N := 13
const HUES := [Color("8fd8ff"), Color("7ff0d0"), Color("b0e0ff"), Color("e8c0ff")]

var awake := false
var _tint := Color("8fd8ff")
var _fish: Array = []
var _spawn_center := Vector2(640, 360)
var _t := randf() * 10.0
var _swirl_t := -1.0
var _swirl_cd := 0.0
var _near_t := 0.0
var _player: PlayerLight = null


func _ready() -> void:
        material = Paint.add_mat()
        z_index = 1
        _tint = HUES[randi() % HUES.size()]
        for i in FISH_N:
                _fish.append({
                        "p": _spawn_center + Vector2(randf_range(-90.0, 90.0), randf_range(-60.0, 60.0)),
                        "v": Vector2(randf_range(-20.0, 20.0), randf_range(-14.0, 14.0)),
                        "ph": randf() * TAU,
                        "wt": 0.0,
                        "delay": float(i) * 0.05,
                })


func setup(center: Vector2) -> void:
        _spawn_center = center


func set_player(p: PlayerLight) -> void:
        _player = p


func wake() -> void:
        if awake:
                return
        awake = true
        awakened.emit()


func _process(delta: float) -> void:
        _t += delta
        _swirl_cd = maxf(_swirl_cd - delta, 0.0)
        var swirl_center := Vector2.ZERO
        var swirl_r := 90.0
        for f in _fish:
                var p: Vector2 = f["p"]
                var v: Vector2 = f["v"]
                var ph: float = f["ph"]
                var wt: float = f["wt"]
                if awake and float(f["delay"]) > 0.0:
                        f["delay"] = maxf(float(f["delay"]) - delta, 0.0)
                elif awake:
                        f["wt"] = minf(wt + delta * 1.2, 1.0)
                        wt = f["wt"]
                if wt > 0.05 and _player != null:
                        # бунт света: притяжение к свету + орбитальная сила
                        var d := _player.position - p
                        var dl := maxf(d.length(), 1.0)
                        var dir := d / dl
                        var pull := 140.0 * (1.0 - clampf(dl / 560.0, 0.0, 1.0)) + 40.0
                        v += dir * pull * delta
                        var tang := 90.0
                        if dl < 260.0:
                                tang = 260.0
                        if _swirl_t >= 0.0:
                                tang = 520.0
                                var target_r := swirl_r + 26.0 * sin(_swirl_t * 2.2 + ph)
                                v += dir * (target_r - dl) * 4.0 * delta * 10.0
                        v += dir.rotated(PI / 2.0) * tang * delta * wt
                        # расталкивание — рыбы не слипаются
                        for g in _fish:
                                if g == f:
                                        continue
                                var dp: Vector2 = g["p"] - p
                                if dp.length_squared() < 676.0 and dp.length_squared() > 0.01:
                                        v -= dp.normalized() * 300.0 * delta
                        var sp := v.length()
                        var cap := 240.0
                        if sp > cap:
                                v = v / sp * cap
                        if sp < 60.0:
                                v = v.normalized() * 60.0
                else:
                        # сон: медленный дрейф + мягкое возвращение к родному месту
                        var to_c := _spawn_center - p
                        var dc := maxf(to_c.length(), 1.0)
                        if dc > 180.0:
                                v += to_c / dc * (dc - 180.0) * 0.6 * delta
                        v.x += 10.0 * sin(_t * 0.4 + ph) * delta
                        v.y += 8.0 * cos(_t * 0.3 + ph * 1.4) * delta
                        v *= 1.0 - minf(delta * 0.8, 0.4)
                        var sp2 := v.length()
                        if sp2 > 26.0:
                                v = v / sp2 * 26.0
                p += v * delta
                f["p"] = p
                f["v"] = v
        # вихрь стаи
        if _swirl_t >= 0.0:
                _swirl_t += delta
                if _swirl_t > 3.5:
                        _swirl_t = -1.0
                        _swirl_cd = 12.0
        elif _player != null and awake:
                var near := 0
                for f in _fish:
                        if float(f["wt"]) > 0.9 and f["p"].distance_to(_player.position) < 150.0:
                                near += 1
                if near >= 10:
                        _near_t += delta
                        if _near_t > 1.0 and _swirl_cd <= 0.0:
                                _near_t = 0.0
                                _swirl_t = 0.0
                                swirled.emit(_player.position)
                else:
                        _near_t = maxf(_near_t - delta * 2.0, 0.0)
        queue_redraw()


func _draw() -> void:
        # общий ореол-маячок спящей стаи
        if not awake:
                var cx := Vector2.ZERO
                for f in _fish:
                        cx += f["p"]
                cx = cx / float(_fish.size())
                var ha := 0.05 + 0.10 * pow(0.5 + 0.5 * sin(_t * 1.2), 4.0)
                var hc := _tint
                hc.a = ha
                Paint.blob(self, cx, 120.0, hc)
        # рыбы-кометы
        for f in _fish:
                var p: Vector2 = f["p"]
                var v: Vector2 = f["v"]
                var wt: float = f["wt"]
                var ph: float = f["ph"]
                var head_a := 0.5 + 0.45 * wt
                if wt < 0.05:
                        head_a = 0.13 + 0.10 * pow(0.5 + 0.5 * sin(_t * 1.2 + ph * 2.0), 6.0)
                var c := _tint
                c.a = head_a
                var sp := v.length()
                if sp > 4.0:
                        var back := -v / sp
                        for k in 5:
                                var tk := float(k)
                                var tp := p + back * (3.0 + tk * (6.0 + sp * 0.05))
                                var tc := _tint
                                tc.a = head_a * (0.34 - 0.06 * tk)
                                Paint.blob(self, tp, 4.5 - 0.7 * tk, tc)
                var flash := 1.0 + 0.25 * sin(_t * 3.0 + ph * 3.0)
                Paint.blob(self, p, 5.5 + 2.0 * wt, c * flash)
