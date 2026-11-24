# sea.gd — «Живое море»: вся сцена рисуется процедурно в _draw().
# Небо, звёзды, луна с бликами на воде, волны, биолюминесцентный планктон,
# остров с маяком и хижиной смотрителя, рифы, гавань с буями.
extends Node2D

const W := 1280.0
const H := 720.0
const HZ := 300.0  # линия горизонта

const ISLET_POS := Vector2(285.0, 588.0)
const LAMP_POS := Vector2(285.0, 454.0)

const PAL_NIGHT := {
	"sky_top": Color(0.024, 0.045, 0.10),
	"sky_bottom": Color(0.075, 0.13, 0.21),
	"sea_top": Color(0.05, 0.11, 0.16),
	"sea_bottom": Color(0.015, 0.04, 0.075),
	"crest": Color(0.42, 0.72, 0.74),
	"foam": Color(0.78, 0.92, 0.94),
	"sil": Color(0.012, 0.028, 0.055),
	"cream": Color(0.44, 0.42, 0.38),
	"warm": Color(1.0, 0.76, 0.42),
	"moon": Color(0.97, 0.94, 0.85),
	"teal": Color(0.4, 0.95, 0.85),
	"cloud": Color(0.55, 0.62, 0.72),
}
const PAL_DAWN := {
	"sky_top": Color(0.30, 0.36, 0.50),
	"sky_bottom": Color(0.83, 0.53, 0.42),
	"sea_top": Color(0.18, 0.30, 0.36),
	"sea_bottom": Color(0.11, 0.19, 0.25),
	"crest": Color(0.55, 0.60, 0.62),
	"foam": Color(0.95, 0.86, 0.76),
	"sil": Color(0.13, 0.12, 0.15),
	"cream": Color(0.60, 0.57, 0.52),
	"warm": Color(1.0, 0.72, 0.38),
	"moon": Color(0.97, 0.94, 0.85),
	"teal": Color(0.55, 0.85, 0.75),
	"cloud": Color(0.85, 0.62, 0.55),
}

var t := 0.0
var day_phase := 0.0  # 0 — ночь, 1 — рассвет

var _ready_done := false
var rocks: Array = []
var harbor := Vector2(1150.0, 505.0)

var _stars: Array = []
var _big_stars: Array = []
var _dots: Array = []
var _mdash: Array = []
var _wdash: Array = []
var _clouds: Array = []
var _islet_pts := PackedVector2Array()


func setup(rocks_data: Array, harbor_pos: Vector2) -> void:
	rocks = rocks_data
	harbor = harbor_pos
	# звёзды
	for i in 130:
		_stars.append({
			"x": randf() * W,
			"y": randf() * (HZ - 12.0),
			"r": randf_range(0.7, 2.1),
			"ph": randf() * TAU,
			"sp": randf_range(0.4, 1.6),
		})
	for i in 6:
		_big_stars.append({
			"x": randf() * W,
			"y": randf() * (HZ - 30.0),
			"ph": randf() * TAU,
		})
	# биолюминесцентные искры на воде
	for i in 70:
		_dots.append({
			"x": randf_range(20.0, W - 20.0),
			"y": randf_range(HZ + 18.0, H - 14.0),
			"r": randf_range(1.0, 2.4),
			"ph": randf() * TAU,
		})
	# блики лунной дорожки
	for j in 34:
		var k := float(j) / 33.0
		_mdash.append({
			"dy": 6.0 + pow(k, 1.7) * 400.0,
			"w": 6.0 + float(j) * 1.1 + randf() * 8.0,
			"ph": randf() * TAU,
			"jx": randf_range(-14.0, 14.0) * (0.3 + k),
		})
	# тёплый отблеск маяка на воде
	for j in 14:
		var k2 := float(j) / 13.0
		_wdash.append({
			"dy": 10.0 + pow(k2, 1.6) * 170.0,
			"w": 5.0 + float(j) * 1.4 + randf() * 6.0,
			"ph": randf() * TAU,
			"jx": randf_range(-10.0, 10.0) * (0.3 + k2),
		})
	# облака
	for c in [[210.0, 160.0, 70.0], [520.0, 95.0, 55.0], [1060.0, 180.0, 75.0], [720.0, 212.0, 45.0]]:
		_clouds.append({"x": c[0], "y": c[1], "r": c[2], "ph": randf() * TAU})
	# силуэт острова
	for i in 14:
		var ang := TAU * float(i) / 14.0
		var rr := randf_range(46.0, 70.0)
		_islet_pts.append(ISLET_POS + Vector2.from_angle(ang) * rr)
	_ready_done = true


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	if not _ready_done:
		return
	var pal := {}
	for key in PAL_NIGHT:
		pal[key] = PAL_NIGHT[key].lerp(PAL_DAWN[key], day_phase)
	var sil: Color = pal["sil"]
	var foam: Color = pal["foam"]
	var crest: Color = pal["crest"]
	var warm: Color = pal["warm"]
	var moon_a := clampf(1.0 - day_phase * 0.95, 0.0, 1.0)

	# --- небо ---
	var sky := PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, HZ), Vector2(0, HZ)])
	var sky_c := PackedColorArray([pal["sky_top"], pal["sky_top"], pal["sky_bottom"], pal["sky_bottom"]])
	draw_polygon(sky, sky_c)

	# звёзды
	for s in _stars:
		var a := (0.30 + 0.55 * (0.5 + 0.5 * sin(t * float(s["sp"]) + float(s["ph"])))) * (1.0 - day_phase * 0.92)
		draw_circle(Vector2(s["x"], s["y"]), float(s["r"]), Color(0.9, 0.94, 1.0, a))
	for s2 in _big_stars:
		var a2 := (0.5 + 0.5 * sin(t * 0.8 + float(s2["ph"]))) * (1.0 - day_phase * 0.92)
		var p := Vector2(s2["x"], s2["y"])
		draw_circle(p, 2.4, Color(0.95, 0.97, 1.0, a2))
		draw_line(p + Vector2(-7, 0), p + Vector2(7, 0), Color(0.9, 0.95, 1.0, a2 * 0.4), 1.0, true)
		draw_line(p + Vector2(0, -7), p + Vector2(0, 7), Color(0.9, 0.95, 1.0, a2 * 0.4), 1.0, true)

	# облака (мягкие вытянутые)
	for c in _clouds:
		var cx := float(c["x"]) + sin(t * 0.02 + float(c["ph"])) * 38.0
		var cy := float(c["y"])
		var cr := float(c["r"])
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2(1.0, 0.38))
		draw_circle(Vector2.ZERO, cr, pal["cloud"])
		draw_circle(Vector2(cr * 0.55, 6.0), cr * 0.62, pal["cloud"])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# луна с гало
	if moon_a > 0.02:
		var mp := Vector2(890.0, 130.0)
		draw_circle(mp, 66.0, Color(pal["moon"].r, pal["moon"].g, pal["moon"].b, 0.05 * moon_a))
		draw_circle(mp, 46.0, Color(pal["moon"].r, pal["moon"].g, pal["moon"].b, 0.075 * moon_a))
		draw_circle(mp, 30.0, Color(pal["moon"].r, pal["moon"].g, pal["moon"].b, 0.11 * moon_a))
		draw_circle(mp, 21.0, Color(pal["moon"].r, pal["moon"].g, pal["moon"].b, 0.95 * moon_a))
		draw_circle(mp + Vector2(-6, -4), 4.0, Color(sil.r, sil.g, sil.b, 0.10 * moon_a))
		draw_circle(mp + Vector2(7, 3), 3.0, Color(sil.r, sil.g, sil.b, 0.08 * moon_a))
		draw_circle(mp + Vector2(-2, 8), 2.4, Color(sil.r, sil.g, sil.b, 0.07 * moon_a))

	# тёплое пятно восхода у горизонта
	if day_phase > 0.03:
		var sp := Vector2(1080.0, 293.0)
		draw_circle(sp, 60.0, Color(1.0, 0.72, 0.5, 0.12 * day_phase))
		draw_circle(sp, 30.0, Color(1.0, 0.72, 0.5, 0.30 * day_phase))

	# --- море ---
	var sea := PackedVector2Array([Vector2(0, HZ), Vector2(W, HZ), Vector2(W, H), Vector2(0, H)])
	var sea_c := PackedColorArray([pal["sea_top"], pal["sea_top"], pal["sea_bottom"], pal["sea_bottom"]])
	draw_polygon(sea, sea_c)
	draw_line(Vector2(0, HZ), Vector2(W, HZ), Color(0.5, 0.6, 0.7, 0.10), 2.0)
	if day_phase > 0.02:
		draw_line(Vector2(0, HZ), Vector2(W, HZ), Color(1.0, 0.75, 0.55, 0.08 * day_phase), 30.0)

	# волны — светящиеся гребни
	for i in 22:
		var yb := HZ + 16.0 + float(i) * 17.8
		var amp := 2.2 + float(i) * 0.32
		var s1 := 0.55 + float(i) * 0.02
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= W:
			var y := yb + sin(x * 0.011 + t * s1) * amp + sin(x * 0.023 - t * 0.8 + float(i)) * amp * 0.55
			pts.append(Vector2(x, y))
			x += 28.0
		var ca := clampf(0.045 + float(i) * 0.0042, 0.0, 0.14) * (1.0 - day_phase * 0.25)
		draw_polyline(pts, Color(crest.r, crest.g, crest.b, ca), clampf(1.5 + float(i) * 0.04, 1.5, 2.4), true)

	# искры планктона
	for d in _dots:
		var da := (0.5 + 0.5 * sin(t * 0.45 + float(d["ph"])))
		if da > 0.55:
			var al := (da - 0.55) / 0.45 * 0.35
			draw_circle(Vector2(d["x"], d["y"]), float(d["r"]), Color(0.4, 0.95, 0.85, al))

	# лунная дорожка
	if moon_a > 0.02:
		for m in _mdash:
			var my := HZ + float(m["dy"])
			var ma := (0.05 + 0.05 * sin(t * 1.3 + float(m["ph"]))) * clampf(1.0 - float(m["dy"]) / 420.0, 0.15, 1.0) * moon_a
			var mx := 890.0 + float(m["jx"])
			draw_line(Vector2(mx - float(m["w"]) * 0.5, my), Vector2(mx + float(m["w"]) * 0.5, my), Color(pal["moon"].r, pal["moon"].g, pal["moon"].b, ma), 2.2, true)

	# тёплая дорожка маяка на воде
	for wv in _wdash:
		var wy := ISLET_POS.y - 30.0 + float(wv["dy"])
		var wa := (0.045 + 0.04 * sin(t * 1.1 + float(wv["ph"]))) * clampf(1.0 - float(wv["dy"]) / 170.0, 0.2, 1.0)
		var wx := ISLET_POS.x + float(wv["jx"])
		draw_line(Vector2(wx - float(wv["w"]) * 0.5, wy), Vector2(wx + float(wv["w"]) * 0.5, wy), Color(warm.r, warm.g, warm.b, wa), 2.0, true)

	# мягкое свечение маяка над водой
	draw_circle(Vector2(ISLET_POS.x, 545.0), 90.0, Color(warm.r, warm.g, warm.b, 0.03 + 0.01 * sin(t * 2.0)))
	draw_circle(Vector2(ISLET_POS.x, 545.0), 55.0, Color(warm.r, warm.g, warm.b, 0.05 + 0.015 * sin(t * 2.0)))

	# --- остров ---
	draw_colored_polygon(_islet_pts, sil)
	draw_arc(ISLET_POS, 62.0 + sin(t * 1.6) * 2.5, 0.0, TAU, 48, Color(foam.r, foam.g, foam.b, 0.10), 2.0, true)

	var bx := ISLET_POS.x
	# башня маяка: полосы
	for b in 5:
		var y_a := 588.0 - 24.0 * float(b)
		var y_b := y_a - 24.0
		var hw_a := lerpf(21.0, 13.0, (588.0 - y_a) / 120.0)
		var hw_b := lerpf(21.0, 13.0, (588.0 - y_b) / 120.0)
		var band := PackedVector2Array([
			Vector2(bx - hw_a, y_a), Vector2(bx + hw_a, y_a),
			Vector2(bx + hw_b, y_b), Vector2(bx - hw_b, y_b),
		])
		if b % 2 == 0:
			draw_colored_polygon(band, sil)
		else:
			draw_colored_polygon(band, pal["cream"])
	# площадка фонаря и купол
	draw_rect(Rect2(bx - 16.0, 462.0, 32.0, 7.0), sil)
	draw_rect(Rect2(bx - 10.0, 447.0, 20.0, 15.0), Color(0.30, 0.28, 0.26))
	draw_arc(Vector2(bx, 447.0), 11.0, PI, TAU, 16, sil, 3.0, true)
	# лампа
	var lamp_pulse := 0.8 + 0.2 * sin(t * 2.1)
	draw_circle(LAMP_POS, 26.0, Color(warm.r, warm.g, warm.b, 0.12 * lamp_pulse))
	draw_circle(LAMP_POS, 14.0, Color(warm.r, warm.g, warm.b, 0.30 * lamp_pulse))
	draw_circle(LAMP_POS, 5.5, Color(1.0, 0.93, 0.75, 0.95))

	# хижина смотрителя
	draw_rect(Rect2(232.0, 556.0, 34.0, 32.0), sil)
	var roof := PackedVector2Array([Vector2(228.0, 556.0), Vector2(270.0, 556.0), Vector2(249.0, 540.0)])
	draw_colored_polygon(roof, sil)
	var win_flick := 0.75 + 0.25 * sin(t * 5.3 + 1.0)
	draw_rect(Rect2(242.0, 566.0, 9.0, 11.0), Color(warm.r, warm.g, warm.b, 0.85 * win_flick))
	draw_circle(Vector2(246.5, 571.5), 12.0, Color(warm.r, warm.g, warm.b, 0.14 * win_flick))

	# --- рифы ---
	for rk in rocks:
		var rp: Vector2 = rk["pos"]
		var rpts: PackedVector2Array = rk["pts"]
		draw_colored_polygon(rpts, Color(0.035, 0.05, 0.08))
		var closed := PackedVector2Array(rpts)
		closed.append(rpts[0])
		draw_polyline(closed, Color(foam.r, foam.g, foam.b, 0.13), 1.5, true)
		var rr2: float = rk["r"]
		var ph2: float = rk["phase"]
		draw_arc(rp, rr2 + 3.0 + sin(t * 2.0 + ph2) * 1.6, 0.0, TAU, 40, Color(foam.r, foam.g, foam.b, 0.10), 2.0, true)

	# --- гавань ---
	# пирсы
	var jetty_top := PackedVector2Array([Vector2(W, 468.0), Vector2(1158.0, 468.0), Vector2(1148.0, 476.0), Vector2(W, 480.0)])
	var jetty_bot := PackedVector2Array([Vector2(W, 542.0), Vector2(1156.0, 538.0), Vector2(1146.0, 530.0), Vector2(W, 526.0)])
	draw_colored_polygon(jetty_top, sil)
	draw_colored_polygon(jetty_bot, sil)
	# дуга входа в гавань
	draw_arc(harbor, 58.0, PI * 0.78, PI * 1.22, 34, Color(pal["teal"].r, pal["teal"].g, pal["teal"].b, 0.16), 2.0, true)
	# буи с тёплыми огнями
	var bl := 0.5 + 0.5 * sin(t * 1.8)
	var br := 0.5 + 0.5 * sin(t * 1.8 + 2.4)
	draw_circle(Vector2(1122.0, 478.0), 12.0, Color(warm.r, warm.g, warm.b, 0.22 * bl))
	draw_circle(Vector2(1122.0, 478.0), 3.5, Color(1.0, 0.85, 0.55, 0.4 + 0.5 * bl))
	draw_circle(Vector2(1122.0, 532.0), 12.0, Color(warm.r, warm.g, warm.b, 0.22 * br))
	draw_circle(Vector2(1122.0, 532.0), 3.5, Color(1.0, 0.85, 0.55, 0.4 + 0.5 * br))
	# маяк гавани
	draw_line(Vector2(1150.0, 470.0), Vector2(1150.0, 450.0), sil, 3.0)
	draw_circle(Vector2(1150.0, 448.0), 12.0, Color(warm.r, warm.g, warm.b, 0.25 * bl))
	draw_circle(Vector2(1150.0, 448.0), 4.0, Color(1.0, 0.88, 0.6, 0.5 + 0.4 * bl))
