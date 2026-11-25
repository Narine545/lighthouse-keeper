class_name Plankton
extends Node2D

# Планктон — «пыль» живописи: сотни светящихся точек дрейфуют по течению,
# оживают рядом со светом игрока (притягиваются и кружат), а импульс
# расталкивает их волной. Во время цветения воды вспыхивают весь.

const N := 240

var _m: Array = []
var _t := 0.0
var _player: PlayerLight = null
var _bloom := 0.0
var _rect := Rect2(0, 0, 1280, 720)
const COLORS := [Color("86f7e4"), Color("5ee8ff"), Color("a68cff"), Color("7ff0d0"), Color("9adfe0")]


func _ready() -> void:
        material = Paint.add_mat()
        z_index = -3


func setup(rect: Rect2, player: PlayerLight) -> void:
        _rect = rect
        _player = player
        for i in N:
                var c: Color = COLORS[randi() % COLORS.size()]
                _m.append({
                        "p": Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y, rect.end.y)),
                        "v": Vector2(randf_range(-8.0, 8.0), randf_range(-6.0, 6.0)),
                        "r": randf_range(2.2, 5.0),
                        "c": c,
                        "ph": randf() * TAU,
                })


func set_rect(rect: Rect2) -> void:
        _rect = rect


func set_bloom(v: float) -> void:
        _bloom = v


# Всплеск: часть планктона пересаживается к точке и разлетается искрами.
func burst(pos: Vector2, cnt := 26) -> void:
        for i in mini(cnt, _m.size()):
                var e: Dictionary = _m[randi() % _m.size()]
                var a := randf() * TAU
                e["p"] = pos + Vector2.from_angle(a) * randf_range(10.0, 70.0)
                e["v"] = Vector2.from_angle(a) * randf_range(60.0, 160.0)


func on_pulse(pos: Vector2, power: float) -> void:
        for e in _m:
                var d: Vector2 = e["p"] - pos
                var dl := d.length()
                if dl < 520.0 and dl > 1.0:
                        e["v"] = e["v"] + d / dl * (1.0 - dl / 520.0) * 260.0 * power


func _process(delta: float) -> void:
        _t += delta
        for e in _m:
                var p: Vector2 = e["p"]
                var v: Vector2 = e["v"]
                var ph: float = e["ph"]
                # течение
                v.x += 14.0 * sin(p.y * 0.006 + _t * 0.25 + ph) * delta
                v.y += 12.0 * cos(p.x * 0.005 - _t * 0.2 + ph * 1.3) * delta
                # свет игрока: притяжение + орбита
                if _player != null:
                        var d := _player.position - p
                        var dl := maxf(d.length(), 1.0)
                        var R := _player.radius() * 2.4
                        if dl < R:
                                var wake := 1.0 - dl / R
                                var dir := d / dl
                                v += dir * 220.0 * wake * delta
                                v += dir.rotated(PI / 2.0) * 180.0 * wake * delta
                # вязкость воды
                v *= 1.0 - minf(delta * 1.1, 0.5)
                var sp := v.length()
                if sp > 340.0:
                        v = v / sp * 340.0
                p += v * delta
                # мягкий перенос через края
                if p.x < _rect.position.x - 40.0:
                        p.x = _rect.end.x + 40.0
                if p.x > _rect.end.x + 40.0:
                        p.x = _rect.position.x - 40.0
                if p.y < _rect.position.y - 40.0:
                        p.y = _rect.end.y + 40.0
                if p.y > _rect.end.y + 40.0:
                        p.y = _rect.position.y - 40.0
                e["p"] = p
                e["v"] = v
        queue_redraw()


func _draw() -> void:
        for e in _m:
                var p: Vector2 = e["p"]
                var wake := 0.0
                if _player != null:
                        var dl := _player.position.distance_to(p)
                        var R := _player.radius() * 2.4
                        if dl < R:
                                wake = 1.0 - dl / R
                var boost := 0.30 + 0.70 * wake + 1.4 * _bloom
                var c: Color = e["c"]
                c.a = clampf(0.16 + 0.30 * boost, 0.0, 0.8)
                Paint.blob(self, p, float(e["r"]) * (1.0 + 0.8 * wake + 0.6 * _bloom), c)
