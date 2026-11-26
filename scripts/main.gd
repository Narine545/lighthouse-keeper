extends Node2D

# «Тихая глубина» — режиссёр ночи.
# Собирает мир из кода: фон-картина, планктон, существа, свет игрока,
# интерфейс-пелена. Никаких провалов: глубина только ждёт, когда её
# разбудят. Каждое пробуждение питает «свет глубины» — и на его отметках
# ночь сама дарит события: цветение воды, кита, метеоры, сияние.

const MARKS := [0.34, 0.62, 0.85, 1.0]

var amb: Ambience
var player: PlayerLight
var plank: Plankton
var bg: DeepBg
var post: PostFx
var meter: MeterOrb
var sleepers: Array = []

var _vp := Vector2(1280, 720)
var _t := 0.0
var _mouse_prev := Vector2(-100, -100)
var _last_mouse_t := 0.0
var _auto_pulse_t := 0.0
var _meter_v := 0.0
var _events_done := [false, false, false, false]
var _awake_count := 0
var _click_cd := 0.0
var _pulse_boost := 0.0
var _bloom_v := 0.0
var _aurora_v := 0.0
var _aurora_hold := 0.0
var _aurora_reset_pending := false
var _meteor_left := 0
var _meteor_t := 0.0
var _shake := 0.0
var _whale: Whale = null
var _hint_stage := 0
var _click_hint_done := false
var _swirl_hint_done := true

var _ui: CanvasLayer
var _title: Label
var _hint: Label
var _hint_tween: Tween = null
var _counter: Label
var _toasts: Array = []
var _toast_next := 0
var _toast_tweens: Array = []


func _ready() -> void:
	randomize()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_vp = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_resize)

	amb = Ambience.new()
	add_child(amb)

	bg = DeepBg.new()
	add_child(bg)

	player = PlayerLight.new()
	add_child(player)
	player.position = Vector2(_vp.x * 0.5, _vp.y * 0.45)

	plank = Plankton.new()
	add_child(plank)
	plank.setup(Rect2(Vector2.ZERO, _vp), player)
	player.pulsed.connect(plank.on_pulse)
	player.pulsed.connect(_on_player_pulse)

	# кораллы на дне
	for i in 5:
		var c := Coral.new()
		c.position = Vector2(_vp.x * (0.14 + 0.18 * float(i)) + randf_range(-40.0, 40.0), _vp.y - randf_range(36.0, 92.0))
		add_child(c)
		c.awakened.connect(_on_sleeper.bind(c))
		sleepers.append(c)

	# медузы в толще воды
	for i in 7:
		var j := Jelly.new()
		j.position = Vector2(randf_range(100.0, _vp.x - 100.0), randf_range(_vp.y * 0.28, _vp.y * 0.78))
		add_child(j)
		j.awakened.connect(_on_sleeper.bind(j))
		sleepers.append(j)

	# стаи рыб-комет
	for i in 3:
		var s := School.new()
		s.setup(Vector2(randf_range(_vp.x * 0.2, _vp.x * 0.8), randf_range(_vp.y * 0.22, _vp.y * 0.72)))
		add_child(s)
		s.set_player(player)
		s.awakened.connect(_on_sleeper.bind(s))
		s.swirled.connect(_on_swirl)
		sleepers.append(s)

	meter = MeterOrb.new()
	meter.position = Vector2(_vp.x * 0.5, _vp.y - 44.0)
	add_child(meter)

	_build_ui()

	post = PostFx.new()
	add_child(post)

	bg.sync_viewport()
	post.sync_viewport()
	bg.set_light(player.position, player.radius(), player.strength())


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	_title = _mk_label(38, Color("cfeae6"), HORIZONTAL_ALIGNMENT_CENTER)
	_title.text = "Тихая глубина"
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 46.0
	_title.offset_bottom = 110.0
	_ui.add_child(_title)
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(_title, "modulate:a", 0.0, 2.5)

	_hint = _mk_label(20, Color("9fd6cd"), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.text = ""
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = _vp.y - 118.0
	_hint.offset_bottom = _vp.y - 82.0
	_hint.modulate.a = 0.0
	_ui.add_child(_hint)

	_counter = _mk_label(17, Color("7fb2ad"), HORIZONTAL_ALIGNMENT_LEFT)
	_counter.text = ""
	_counter.position = Vector2(18.0, 14.0)
	_ui.add_child(_counter)

	for i in 3:
		var lbl := _mk_label(20, Color("cfeae6"), HORIZONTAL_ALIGNMENT_CENTER)
		lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		lbl.offset_top = 120.0 + 36.0 * float(i)
		lbl.offset_bottom = 156.0 + 36.0 * float(i)
		lbl.modulate.a = 0.0
		_ui.add_child(lbl)
		_toasts.append(lbl)
		_toast_tweens.append(null)


func _mk_label(sz: int, col: Color, align: HorizontalAlignment) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.04, 0.6))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = align
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _toast(text: String) -> void:
	var idx := _toast_next
	_toast_next = (_toast_next + 1) % _toasts.size()
	var slot: Label = _toasts[idx]
	slot.text = text
	if _toast_tweens[idx] != null and _toast_tweens[idx].is_valid():
		_toast_tweens[idx].kill()
	slot.modulate.a = 0.0
	var tw := slot.create_tween()
	tw.tween_property(slot, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.8)
	tw.tween_property(slot, "modulate:a", 0.0, 1.4)
	_toast_tweens[idx] = tw


func _hint_show(text: String) -> void:
	_hint.text = text
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint.modulate.a = 0.0
	_hint_tween = _hint.create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.7)
	_hint_tween.tween_interval(4.6)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 1.6)


func _process(delta: float) -> void:
	_t += delta
	_click_cd = maxf(_click_cd - delta, 0.0)
	_pulse_boost = maxf(_pulse_boost - delta, 0.0)
	_shake *= exp(-delta * 2.0)

	# мышь или «автопилот»: если рука отдыхает, свет плавает сам —
	# глубина живёт и без игрока
	var mp := get_global_mouse_position()
	if mp.distance_to(_mouse_prev) > 1.0:
		_last_mouse_t = _t
	_mouse_prev = mp
	var tgt := mp
	if _t - _last_mouse_t > 6.0:
		tgt = Vector2(_vp.x * 0.5 + cos(_t * 0.13) * _vp.x * 0.3, _vp.y * 0.45 + sin(_t * 0.17) * _vp.y * 0.26)
		_auto_pulse_t += delta
		if _auto_pulse_t > 10.0:
			_auto_pulse_t = 0.0
			player.pulse()
	else:
		_auto_pulse_t = 0.0
	player.set_target(tgt.clamp(Vector2(24.0, 24.0), _vp - Vector2(24.0, 24.0)))

	# картина и свет
	bg.set_time(_t)
	bg.set_light(player.position, player.radius(), player.strength())
	bg.set_bloom(_bloom_v)
	bg.set_aurora(_aurora_v)
	bg.set_sway(sin(_t * 17.0) * 8.0 * _shake, cos(_t * 13.0) * 6.0 * _shake)

	# метаболы: свет игрока, кит и проснувшиеся медузы сливаются
	# в одну живую световую массу (smin-поле в шейдере фона)
	var bl: Array = []
	bl.append([player.position, 95.0, 0.85, Vector3(0.62, 0.95, 0.88)])
	if _whale != null and is_instance_valid(_whale):
		bl.append([_whale.position, 235.0, 0.4, Vector3(0.30, 0.72, 0.66)])
	for s in sleepers:
		if bl.size() >= 8:
			break
		var jelly := s as Jelly
		if jelly != null and jelly.awake:
			var jt := jelly.tint()
			var jv := 0.6 + 0.25 * sin(_t * 2.0 + jelly.position.x * 0.01)
			bl.append([jelly.position, jelly.body_r() * 1.15, jv, Vector3(jt.r, jt.g, jt.b)])
	bg.set_balls(bl)

	post.set_time(_t)
	meter.set_value(_meter_v)

	# затухания событий
	_bloom_v = maxf(_bloom_v - delta / 12.0, 0.0)
	if _aurora_hold > 0.0:
		_aurora_hold -= delta
		_aurora_v = minf(_aurora_v + delta / 3.0, 1.0)
	else:
		_aurora_v = maxf(_aurora_v - delta / 4.0, 0.0)
	if _aurora_reset_pending and _aurora_v <= 0.02:
		_aurora_reset_pending = false
		for i in 4:
			_events_done[i] = false

	# метеоры
	if _meteor_left > 0:
		_meteor_t -= delta
		if _meteor_t <= 0.0:
			_meteor_left -= 1
			_meteor_t = randf_range(0.9, 1.6)
			var m := Meteor.new()
			m.setup(_vp.x)
			add_child(m)
			amb.meteor_shimmer()

	# пробуждение: свет касается спящих
	var factor := 0.8
	if _pulse_boost > 0.0:
		factor = 1.6
	var wr := player.radius() * factor
	for s in sleepers:
		if not s.awake and player.position.distance_to(s.global_position) < wr:
			s.wake()

	# подсказки — только пока игрок не понял сам
	if _hint_stage == 0 and _t > 1.6:
		_hint_stage = 1
		_hint_show("Веди свет мышью — он живой")
	elif _hint_stage == 1 and _t > 10.0 and _awake_count == 0:
		_hint_stage = 2
		_hint_show("Коснись света того, кто слабо пульсирует в темноте")
	if _events_done[2] and not _events_done[3] and _meter_v < 0.95 and not _swirl_hint_done:
		_swirl_hint_done = true
		_hint_show("Закружи стаю рыб вокруг света — так рождается вихрь")

	# события «света глубины»: каждое расходует 40% своей отметки —
	# так до сияния можно доплыть за один полный обход всех спящих
	if _meter_v >= float(MARKS[0]) and not _events_done[0]:
		_events_done[0] = true
		_meter_v -= float(MARKS[0]) * 0.4
		_bloom_v = 1.0
		amb.bloom_swell()
		meter.flash()
		_toast("Цветение воды")
	elif _meter_v >= float(MARKS[1]) and not _events_done[1]:
		_events_done[1] = true
		_meter_v -= float(MARKS[1]) * 0.4
		var w := Whale.new()
		var dir := 1 if randf() < 0.5 else -1
		w.setup(_vp.x, dir)
		add_child(w)
		_whale = w
		w.song.connect(_on_whale_song.bind(w))
		meter.flash()
		_toast("Кто-то большой плывёт вдалеке…")
	elif _meter_v >= float(MARKS[2]) and not _events_done[2]:
		_events_done[2] = true
		_meter_v -= float(MARKS[2]) * 0.4
		_swirl_hint_done = false
		_meteor_left = 8
		_meteor_t = 0.4
		meter.flash()
		_toast("Звёзды сквозь воду")
	elif _meter_v >= float(MARKS[3]) and not _events_done[3]:
		_events_done[3] = true
		_meter_v -= float(MARKS[3]) * 0.4
		_aurora_hold = 14.0
		_aurora_reset_pending = true
		amb.aurora_swell()
		meter.flash()
		_toast("Сияние над поверхностью")


func _on_sleeper(s: Node2D) -> void:
	s.wake()
	_awake_count += 1
	_counter.text = "Пробуждено: %d" % _awake_count
	_meter_v += 0.11
	meter.flash()
	plank.burst(s.global_position)
	if s is Jelly:
		amb.jelly_wake()
		_toast("Медуза проснулась")
	elif s is School:
		amb.fish_wake()
		_toast("Стая проснулась")
	elif s is Coral:
		amb.coral_wake()
		_toast("Кораллы раскрылись")
	if _awake_count == 1 and _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
		_hint_tween = _hint.create_tween()
		_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.8)


func _on_player_pulse(_pos: Vector2, _power: float) -> void:
	amb.pulse_whum()
	_pulse_boost = 0.5
	# подсказка об импульсе — только если кликнул человек, а не автопилот
	if not _click_hint_done and _t - _last_mouse_t <= 6.0:
		_click_hint_done = true
		_hint_show("Импульс: свет вспыхнул и коснулся всего вокруг")


func _on_swirl(_pos: Vector2) -> void:
	_toast("Стая закружилась вихрем")
	amb.swirl()
	_meter_v += 0.08
	meter.flash()


func _on_whale_song(idx: int, _w: Whale) -> void:
	amb.whale_call(idx)
	_shake = 0.55
	if idx == 0:
		_toast("Кит поёт вдалеке…")


func _on_resize() -> void:
	_vp = get_viewport_rect().size
	plank.set_rect(Rect2(Vector2.ZERO, _vp))
	bg.sync_viewport()
	post.sync_viewport()
	meter.position = Vector2(_vp.x * 0.5, _vp.y - 44.0)
	_hint.offset_top = _vp.y - 118.0
	_hint.offset_bottom = _vp.y - 82.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _click_cd <= 0.0:
			_click_cd = 0.35
			player.pulse()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_M:
		AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
