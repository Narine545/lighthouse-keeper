class_name Ambience
extends Node

# Полностью генеративный звук «Тихой глубины» — ни одного аудиофайла.
#
# Правила смеси (перегруз устранён по построению, а не обработкой):
#  1) инфразвук запрещён: «вода» лежит в полосе 30–90 Гц. Прежний гул
#     из интеграторов жил ниже 20 Гц — ухом его не слышно, но он
#     выворачивал диффузор и «грязнил» межмодуляцией все остальные
#     голоса: именно это ощущалось как пережатый, перекачанный звук;
#  2) лимитер на мастере УДАЛЁН: вместо динамики — жёсткий бюджет
#     пиков. Сумма всех одновременных голосов не превышает ~0.8
#     по построению, поэтому нечему «дышать» и зажимать смесь;
#  3) никакой сатурации: tanh лишь добавляет грязные гармоники к
#     чистым синусам. _soft остаётся только как математическая
#     страховка от переполнения int16 — до неё смесь не доходит;
#  4) кроссфейд хвоста в голову и нормализация выполняются ПРЯМО В
#     ГЕНЕРАТОРЕ цикла, на ЛОКАЛЬНЫХ массивах (PackedFloat32Array —
#     тип-значение, правки параметра внутри отдельной функции могут
#     молча не возвращаться вызывающему коду).

const SR := 44100
const PENTA := [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25]

var _deep_p: AudioStreamPlayer
var _pad_p: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _vi := 0
var _tone_cache := {}
var _chord_cache := {}
var _whale_cache := {}
var _bubble_s: AudioStreamWAV
var _whum_s: AudioStreamWAV
var _bubble_t := 5.0
var _drift_t := 8.0


func _ready() -> void:
        _make_bus("Amb", 0.22)
        _make_bus("Music", 0.20)
        _make_bus("SFX", 0.24)
        # статическая страховка мастера: −2 дБ, НЕ динамика — ничего
        # не реагирует на сигнал и не «дышит», просто запас до стенки
        AudioServer.set_bus_volume_db(0, -2.0)

        _deep_p = AudioStreamPlayer.new()
        _deep_p.stream = _deep_loop(30.0)
        _deep_p.bus = "Amb"
        _deep_p.volume_db = -6.0
        add_child(_deep_p)
        _deep_p.play()

        _pad_p = AudioStreamPlayer.new()
        _pad_p.stream = _pad_loop(24.0)
        _pad_p.bus = "Amb"
        _pad_p.volume_db = -16.0
        add_child(_pad_p)
        _pad_p.play()

        # 16 голосов: длинные звуки (зов кита — 7 с, пад сияния — 12 с)
        # не должны отбирать голоса друг у друга: украденный голос
        # обрывается щелчком прямо посреди звука
        for i in 16:
                var p := AudioStreamPlayer.new()
                p.bus = "Music"
                add_child(p)
                _voices.append(p)

        _bubble_s = _make_bubble()
        _whum_s = _make_whum()

        # предкэш всех «дорогих» звуков: без фризов посреди ночи
        _chord([220.0, 440.0, 523.25, 659.25])
        _chord([130.81, 196.0, 261.63], 0.14)
        _motif([587.33, 739.99, 880.0])
        _motif([659.25, 783.99, 987.77, 1174.66], 0.08)
        _motif([1760.0, 2093.0, 2349.3, 2793.0, 3136.0], 0.09)
        _swell_pad([220.0, 261.63, 329.63, 392.0], 9.0, 2.5, 2.5)
        _swell_pad([261.63, 329.63, 392.0, 523.25], 12.0, 3.0, 3.5)
        _whale_call(98.0)
        _whale_call(82.0)


func _make_bus(bus_name: String, reverb_wet: float) -> void:
        var idx := AudioServer.get_bus_index(bus_name)
        if idx == -1:
                idx = AudioServer.bus_count
                AudioServer.add_bus(idx)
                AudioServer.set_bus_name(idx, bus_name)
                AudioServer.set_bus_send(idx, "Master")
                var rv := AudioEffectReverb.new()
                rv.room_size = 0.9
                rv.damping = 0.62
                rv.wet = reverb_wet
                rv.dry = 0.9
                AudioServer.add_bus_effect(idx, rv)


# Мягкое «плечо» вместо жёсткого потолка: всё до 0.78 проходит без искажений,
# верхний хвост плавно прижимается к единице через tanh — переполнение int16
# (тот самый «хрип») невозможно в принципе, а щелчков нет и на границе.
func _soft(x: float) -> float:
        var a := absf(x)
        if a <= 0.78:
                return x
        return signf(x) * (0.78 + 0.22 * tanh((a - 0.78) / 0.22))


func _to_wav_stereo(L: PackedFloat32Array, R: PackedFloat32Array, loop_start: int) -> AudioStreamWAV:
        var frames := L.size()
        var data := PackedByteArray()
        data.resize(frames * 4)
        for i in frames:
                data.encode_s16(i * 4, int(_soft(L[i]) * 32767.0))
                data.encode_s16(i * 4 + 2, int(_soft(R[i]) * 32767.0))
        var ws := AudioStreamWAV.new()
        ws.format = AudioStreamWAV.FORMAT_16_BITS
        ws.mix_rate = SR
        ws.stereo = true
        if loop_start > 0:
                ws.loop_mode = AudioStreamWAV.LOOP_FORWARD
                ws.loop_begin = loop_start
                ws.loop_end = frames
        ws.data = data
        return ws


func _to_wav_mono(L: PackedFloat32Array) -> AudioStreamWAV:
        var frames := L.size()
        var data := PackedByteArray()
        data.resize(frames * 2)
        for i in frames:
                data.encode_s16(i * 2, int(_soft(L[i]) * 32767.0))
        var ws := AudioStreamWAV.new()
        ws.format = AudioStreamWAV.FORMAT_16_BITS
        ws.mix_rate = SR
        ws.stereo = false
        ws.data = data
        return ws


# Глубина: тёмный шум воды в жёсткой полосе 30–90 Гц. Прежний каскад
# интеграторов копил инфразвук ниже 20 Гц — неслышимый, но он
# пережимал микс и качал всю сцену. Теперь — слышимый низ воды
# с медленными накатами, а верх — только лёгкий «песок» на гребне.
func _deep_loop(dur: float) -> AudioStreamWAV:
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        var R := PackedFloat32Array()
        L.resize(frames)
        R.resize(frames)
        var lp1 := 0.0
        var lp2 := 0.0
        var dc1 := 0.0
        var dc2 := 0.0
        var s1 := 0.0
        var s2 := 0.0
        for i in frames:
                var ph := TAU * float(i) / SR / dur
                var w1 := randf() * 2.0 - 1.0
                var w2 := randf() * 2.0 - 1.0
                # полосовой канал «воды»: фильтр ~90 Гц оставляет низ,
                # вычитание медленно следящей средней (срез ~30 Гц)
                # удаляет всё, что ниже слышимого диапазона
                lp1 += (w1 - lp1) * 0.013
                lp2 += (w2 - lp2) * 0.013
                dc1 += (lp1 - dc1) * 0.0043
                dc2 += (lp2 - dc2) * 0.0043
                var swell := 0.55 + 0.28 * sin(ph + 0.7) + 0.17 * sin(ph * 2.3 + 2.1) + 0.10 * sin(ph * 3.7 + 4.4)
                var swell2 := 0.55 + 0.28 * sin(ph + 2.9) + 0.17 * sin(ph * 2.3 + 0.4) + 0.10 * sin(ph * 3.7 + 1.2)
                s1 += (w1 - s1) * 0.35
                s2 += (w2 - s2) * 0.35
                var sand := swell * swell * swell * swell
                L[i] = (lp1 - dc1) * 5.0 * swell + s1 * 0.010 * sand
                R[i] = (lp2 - dc2) * 5.0 * swell2 + s2 * 0.010 * sand
        # Кроссфейд + нормализация — здесь и только здесь, на локальных массивах.
        var n := int(0.6 * SR)
        for k in n:
                var w := float(k) / float(n)
                var ti := frames - n + k
                L[ti] = lerpf(L[ti], L[k], w)
                R[ti] = lerpf(R[ti], R[k], w)
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
                mx = maxf(mx, absf(R[i]))
        if mx > 0.0001:
                var g := 0.40 / mx
                for i in frames:
                        L[i] = L[i] * g
                        R[i] = R[i] * g
        return _to_wav_stereo(L, R, n)


# Далёкий «китовый» гул: расстроенные низкие синусы, медленно дышащие.
func _pad_loop(dur: float) -> AudioStreamWAV:
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        var R := PackedFloat32Array()
        L.resize(frames)
        R.resize(frames)
        var parts := [[55.0, 1.0, 0.0], [55.33, 0.7, 1.3], [82.41, 0.5, 2.1], [82.0, 0.35, 0.7], [110.0, 0.28, 3.2], [164.81, 0.12, 1.9]]
        for i in frames:
                var ph := TAU * float(i) / SR / dur
                var breath := 0.7 + 0.3 * sin(ph * 0.5 + 1.0)
                var u := float(i) / SR
                var vl := 0.0
                var vr := 0.0
                for p in parts:
                        var f: float = float(p[0])
                        var amp: float = float(p[1])
                        var sd: float = float(p[2])
                        var drift := 0.6 + 0.4 * sin(ph * (1.0 + 0.13 * sd) + sd * 2.0)
                        vl += amp * drift * sin(TAU * f * u + sd)
                        vr += amp * drift * sin(TAU * f * 1.0015 * u + sd + 0.5)
                L[i] = vl * 0.22 * breath
                R[i] = vr * 0.22 * breath
        var n := int(0.6 * SR)
        for k in n:
                var w := float(k) / float(n)
                var ti := frames - n + k
                L[ti] = lerpf(L[ti], L[k], w)
                R[ti] = lerpf(R[ti], R[k], w)
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
                mx = maxf(mx, absf(R[i]))
        if mx > 0.0001:
                var g := 0.32 / mx
                for i in frames:
                        L[i] = L[i] * g
                        R[i] = R[i] * g
        return _to_wav_stereo(L, R, n)


# Стеклянный тон: чистые обертоны с долгим затуханием — «звенится», не шипит.
func _glass_math(freq: float, u: float) -> float:
        var v := 0.5 * sin(TAU * freq * u) * exp(-1.9 * u)
        v += 0.16 * sin(TAU * freq * 2.0 * u) * exp(-2.6 * u)
        v += 0.10 * sin(TAU * freq * 2.92 * u) * exp(-3.3 * u)
        v += 0.05 * sin(TAU * freq * 4.2 * u) * exp(-4.0 * u)
        v += 0.18 * sin(TAU * freq * 1.0035 * u) * exp(-1.4 * u)
        var env := 1.0
        if u < 0.008:
                env = u / 0.008
        return v * env


func _glass_tone(freq: float) -> AudioStreamWAV:
        var key := "t%d" % int(round(freq * 10.0))
        if _tone_cache.has(key):
                return _tone_cache[key]
        var dur := 4.5
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        for i in frames:
                var u := float(i) / SR
                L[i] = _glass_math(freq, u) * 0.6
        var wav := _to_wav_mono(L)
        _tone_cache[key] = wav
        return wav


# Аккорд: ноты вступают по очереди, каждая чуть расстроена — живой звук.
func _chord(notes: Array, gap := 0.09, dur := 5.2) -> AudioStreamWAV:
        var key := "c" + str(notes)
        if _chord_cache.has(key):
                return _chord_cache[key]
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        for k in notes.size():
                var f: float = float(notes[k]) * (1.0 + 0.003 * float(k % 3))
                var off := int(float(k) * gap * SR)
                for i in range(off, frames):
                        var u := float(i - off) / SR
                        L[i] += _glass_math(f, u) * 0.7
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
        if mx > 0.0001:
                var g := 0.50 / mx
                for i in frames:
                        L[i] = L[i] * g
        var wav := _to_wav_mono(L)
        _chord_cache[key] = wav
        return wav


# Быстрый мотив из стеклянных нот — стаи, события.
func _motif(notes: Array, gap := 0.09) -> AudioStreamWAV:
        var key := "m" + str(notes) + str(gap)
        if _chord_cache.has(key):
                return _chord_cache[key]
        var dur := float(notes.size()) * gap + 2.4
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        for k in notes.size():
                var f: float = float(notes[k])
                var off := int(float(k) * gap * SR)
                for i in range(off, frames):
                        var u := float(i - off) / SR
                        L[i] += _glass_math(f, u) * 0.55
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
        if mx > 0.0001:
                var g := 0.45 / mx
                for i in frames:
                        L[i] = L[i] * g
        var wav := _to_wav_mono(L)
        _chord_cache[key] = wav
        return wav


# Тёплый всплывающий пад — события (цветение, сияние).
func _swell_pad(notes: Array, dur: float, atk: float, rel: float) -> AudioStreamWAV:
        var key := "s" + str(notes) + str(int(dur * 10.0))
        if _chord_cache.has(key):
                return _chord_cache[key]
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        var R := PackedFloat32Array()
        L.resize(frames)
        R.resize(frames)
        for k in notes.size():
                var f: float = float(notes[k])
                var sd := float(k) * 1.7
                for i in frames:
                        var u := float(i) / SR
                        var a := clampf(u / atk, 0.0, 1.0)
                        var r := clampf((dur - u) / rel, 0.0, 1.0)
                        var env := a * a * r * r
                        var sh := 0.75 + 0.25 * sin(TAU * 0.13 * u + sd)
                        var v := sin(TAU * f * u) + 0.14 * sin(TAU * f * 2.0 * u + sd)
                        v += 0.10 * sin(TAU * f * 1.004 * u + sd * 2.0)
                        L[i] += v * env * sh * 0.30
                        R[i] += v * env * (1.1 - sh * 0.4) * 0.30
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
                mx = maxf(mx, absf(R[i]))
        if mx > 0.0001:
                var g := 0.45 / mx
                for i in frames:
                        L[i] = L[i] * g
                        R[i] = R[i] * g
        var wav := _to_wav_stereo(L, R, 0)
        _chord_cache[key] = wav
        return wav


# Песня кита — по правилам саунд-дизайна низких голосов (саб-синтез):
#  1) подгармоник ниже 45 Гц НЕТ: именно они выворачивают диффузор колонки.
#     Тембр = фундамент (82–98 Гц) + обертоны 2/3/4 с быстрым спадом;
#  2) вибрато относительное (±1.2%), а не абсолютное — спектр не расползается;
#  3) огибающая smoothstep с долгой атакой (1.8 с) — ни щелчков, ни низко-
#     частотных «кирпичей» в момент вступления;
#  4) DC-блокатор первого порядка (срез ~35 Гц) — этап не тащит постоянку
#     и инфранизкие наплывы при скольжении тона;
#  5) сатурации НЕТ: сигнал — чистый узкополосный синус, нормализация
#     на пик 0.34 по бюджету смеси. Нелинейность только добавляет грязь.
func _whale_call(f0: float) -> AudioStreamWAV:
        var key := "w%d" % int(f0)
        if _whale_cache.has(key):
                return _whale_cache[key]
        var dur := 7.0
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        var ph := 0.0
        var x_prev := 0.0
        var y_prev := 0.0
        var breath_lp := 0.0
        for i in frames:
                var u := float(i) / SR
                var f := f0 * (0.80 + 0.20 * exp(-1.2 * u))
                f *= 1.0 + 0.012 * sin(TAU * 3.4 * u) * clampf(u / 2.0, 0.0, 1.0)
                ph += TAU * f / SR
                var a := clampf(u / 1.8, 0.0, 1.0)
                a = a * a * (3.0 - 2.0 * a)
                var r := clampf((dur - u) / 2.6, 0.0, 1.0)
                r = r * r * (3.0 - 2.0 * r)
                var env := a * r
                var v := sin(ph) + 0.30 * sin(ph * 2.0 + 0.6 * u)
                v += 0.12 * sin(ph * 3.0) + 0.045 * sin(ph * 4.0)
                # дыхание: чуть тёплого отфильтрованного шума, без шипения
                var nz := (randf() * 2.0 - 1.0) * env * 0.035
                breath_lp += (nz - breath_lp) * 0.09
                var x := v * env + breath_lp
                # DC-блокатор: y[n] = x[n] - x[n-1] + R * y[n-1]
                var y := x - x_prev + 0.995 * y_prev
                x_prev = x
                y_prev = y
                L[i] = y
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
        if mx > 0.0001:
                var g := 0.34 / mx
                for i in frames:
                        L[i] = L[i] * g
        var wav := _to_wav_mono(L)
        _whale_cache[key] = wav
        return wav


# Мягкий «всплеск света» — импульс игрока: низкий тёплый выдох, без щелчка.
func _make_whum() -> AudioStreamWAV:
        var dur := 1.2
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        var ph := 0.0
        var lp := 0.0
        for i in frames:
                var u := float(i) / SR
                var f := 58.0 + 120.0 * exp(-7.0 * u)
                ph += TAU * f / SR
                var env := clampf(u / 0.03, 0.0, 1.0) * exp(-3.4 * u)
                var v := (sin(ph) * 0.85 + 0.18 * sin(ph * 2.0)) * env
                var nz := (randf() * 2.0 - 1.0) * exp(-9.0 * u) * 0.22
                lp += (nz - lp) * 0.08
                L[i] = v + lp
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
        if mx > 0.0001:
                var g := 0.55 / mx
                for i in frames:
                        L[i] = L[i] * g
        return _to_wav_mono(L)


# Пузырёк: короткий чистый подъём тона — воздух в толще воды.
func _make_bubble() -> AudioStreamWAV:
        var dur := 0.4
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        var ph := 0.0
        for i in frames:
                var u := float(i) / SR
                var f := 480.0 + 520.0 * clampf(u / 0.10, 0.0, 1.0)
                ph += TAU * f / SR
                var env := 1.0
                if u > 0.1:
                        env = exp(-12.0 * (u - 0.1))
                var v := sin(ph) * 0.5 + 0.2 * sin(ph * 1.5)
                L[i] = v * env
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
        if mx > 0.0001:
                var g := 0.50 / mx
                for i in frames:
                        L[i] = L[i] * g
        return _to_wav_mono(L)


func _play(bus: String, stream: AudioStream, vol_db: float, pitch: float = 1.0) -> void:
        var p := _voices[_vi]
        _vi = (_vi + 1) % _voices.size()
        p.stream = stream
        p.volume_db = vol_db
        p.pitch_scale = pitch
        p.bus = bus
        p.play()


func _process(delta: float) -> void:
        # редкие пузырьки и «дальние отзвуки» — глубина дышит сама
        _bubble_t -= delta
        if _bubble_t <= 0.0:
                _bubble_t = randf_range(3.5, 9.0)
                _play("SFX", _bubble_s, randf_range(-26.0, -20.0), randf_range(0.8, 1.35))
        _drift_t -= delta
        if _drift_t <= 0.0:
                _drift_t = randf_range(9.0, 17.0)
                if randf() < 0.75:
                        var f: float = PENTA[randi_range(0, PENTA.size() - 1)]
                        _play("Music", _glass_tone(f), randf_range(-24.0, -19.0), randf_range(0.98, 1.03))


# --- события и существа ---

func jelly_wake() -> void:
        _play("Music", _chord([220.0, 440.0, 523.25, 659.25]), -10.0, randf_range(0.99, 1.02))


func fish_wake() -> void:
        _play("Music", _motif([587.33, 739.99, 880.0]), -10.0, randf_range(0.98, 1.03))


func coral_wake() -> void:
        _play("Music", _chord([130.81, 196.0, 261.63], 0.14), -11.0, randf_range(0.99, 1.02))


func swirl() -> void:
        _play("Music", _motif([659.25, 783.99, 987.77, 1174.66], 0.08), -12.0)


func pulse_whum() -> void:
        _play("SFX", _whum_s, -8.0, randf_range(0.95, 1.08))


func whale_call(i: int) -> void:
        var f0 := 98.0 if i % 2 == 0 else 82.0
        _play("Music", _whale_call(f0), -10.0)


func meteor_shimmer() -> void:
        _play("Music", _motif([1760.0, 2093.0, 2349.3, 2793.0, 3136.0], 0.09), -14.0)


func bloom_swell() -> void:
        _play("Music", _swell_pad([220.0, 261.63, 329.63, 392.0], 9.0, 2.5, 2.5), -10.0)


func aurora_swell() -> void:
        _play("Music", _swell_pad([261.63, 329.63, 392.0, 523.25], 12.0, 3.0, 3.5), -11.0)
