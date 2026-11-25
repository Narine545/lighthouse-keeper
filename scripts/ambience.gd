class_name Ambience
extends Node

# Полностью генеративный звук «Тихой глубины» — ни одного аудиофайла.
#
# Уроки прошлой игры учтены:
#  1) никакого шипения: сырой высокочастотный шум запрещён. Вода — это
#     «коричневый» шум через каскад низких фильтров, верхний регистр всегда
#     приглушён и «вспухает» только на гребне медленной волны;
#  2) кроссфейд хвоста в голову и нормализация выполняются ПРЯМО В
#     ГЕНЕРАТОРЕ цикла, на ЛОКАЛЬНЫХ массивах (PackedFloat32Array —
#     тип-значение, правки параметра внутри отдельной функции могут
#     молча не возвращаться вызывающему коду);
#  3) жёсткий clamp перед каждым encode_s16 — переполнение int16 (тот
#     самый «хрип») невозможно в принципе.

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
        _make_bus("Amb", 0.30)
        _make_bus("Music", 0.45)
        _make_bus("SFX", 0.35)

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

        for i in 10:
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
                rv.damping = 0.55
                rv.wet = reverb_wet
                rv.dry = 0.9
                AudioServer.add_bus_effect(idx, rv)


func _to_wav_stereo(L: PackedFloat32Array, R: PackedFloat32Array, loop_start: int) -> AudioStreamWAV:
        var frames := L.size()
        var data := PackedByteArray()
        data.resize(frames * 4)
        for i in frames:
                data.encode_s16(i * 4, int(clampf(L[i], -1.0, 1.0) * 32767.0))
                data.encode_s16(i * 4 + 2, int(clampf(R[i], -1.0, 1.0) * 32767.0))
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
                data.encode_s16(i * 2, int(clampf(L[i], -1.0, 1.0) * 32767.0))
        var ws := AudioStreamWAV.new()
        ws.format = AudioStreamWAV.FORMAT_16_BITS
        ws.mix_rate = SR
        ws.stereo = false
        ws.data = data
        return ws


# Глубина: тёмный «коричневый» шум через каскад из трёх низких фильтров.
# Три несоизмеримых медленных наката дают воду без единой слышимой частоты
# «шипения»: верх есть только в виде лёгкого «песка» на гребне волны.
func _deep_loop(dur: float) -> AudioStreamWAV:
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        var R := PackedFloat32Array()
        L.resize(frames)
        R.resize(frames)
        var b1 := 0.0
        var b2 := 0.0
        var a1 := 0.0
        var a2 := 0.0
        var a3 := 0.0
        var c1 := 0.0
        var c2 := 0.0
        var c3 := 0.0
        var s1 := 0.0
        var s2 := 0.0
        for i in frames:
                var ph := TAU * float(i) / SR / dur
                b1 += (randf() * 2.0 - 1.0) * 0.02
                b1 *= 0.998
                b2 += (randf() * 2.0 - 1.0) * 0.02
                b2 *= 0.998
                a1 += (b1 - a1) * 0.02
                a2 += (a1 - a2) * 0.045
                a3 += (a2 - a3) * 0.11
                c1 += (b2 - c1) * 0.02
                c2 += (c1 - c2) * 0.045
                c3 += (c2 - c3) * 0.11
                var swell := 0.55 + 0.28 * sin(ph + 0.7) + 0.17 * sin(ph * 2.3 + 2.1) + 0.10 * sin(ph * 3.7 + 4.4)
                var swell2 := 0.55 + 0.28 * sin(ph + 2.9) + 0.17 * sin(ph * 2.3 + 0.4) + 0.10 * sin(ph * 3.7 + 1.2)
                s1 += ((randf() * 2.0 - 1.0) - s1) * 0.35
                s2 += ((randf() * 2.0 - 1.0) - s2) * 0.35
                var sand := swell * swell * swell * swell
                L[i] = a3 * 9.0 * swell + s1 * 0.010 * sand
                R[i] = c3 * 9.0 * swell2 + s2 * 0.010 * sand
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
                var g := 0.5 / mx
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
                var g := 0.55 / mx
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
                var g := 0.5 / mx
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
                var g := 0.5 / mx
                for i in frames:
                        L[i] = L[i] * g
                        R[i] = R[i] * g
        var wav := _to_wav_stereo(L, R, 0)
        _chord_cache[key] = wav
        return wav


# Песня кита: длинный скользящий зов с вибрато и подголосками.
func _whale_call(f0: float) -> AudioStreamWAV:
        var key := "w%d" % int(f0)
        if _whale_cache.has(key):
                return _whale_cache[key]
        var dur := 7.0
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        var ph := 0.0
        for i in frames:
                var u := float(i) / SR
                var f := f0 * (0.74 + 0.26 * exp(-1.1 * u))
                f += 2.2 * sin(TAU * 3.8 * u) * clampf(u / 1.5, 0.0, 1.0)
                ph += TAU * f / SR
                var a := clampf(u / 1.3, 0.0, 1.0)
                var r := clampf((dur - u) / 2.4, 0.0, 1.0)
                var env := a * r
                var v := sin(ph) + 0.4 * sin(ph * 2.0 + 0.6 * u) + 0.16 * sin(ph * 3.0)
                v += 0.3 * sin(ph * 0.5)
                L[i] = v * env * 0.30
        var mx := 0.0
        for i in frames:
                mx = maxf(mx, absf(L[i]))
        if mx > 0.0001:
                var g := 0.55 / mx
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
                var g := 0.7 / mx
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
                var g := 0.6 / mx
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
        _play("Music", _chord([220.0, 440.0, 523.25, 659.25]), -8.0, randf_range(0.99, 1.02))


func fish_wake() -> void:
        _play("Music", _motif([587.33, 739.99, 880.0]), -10.0, randf_range(0.98, 1.03))


func coral_wake() -> void:
        _play("Music", _chord([130.81, 196.0, 261.63], 0.14), -9.0, randf_range(0.99, 1.02))


func swirl() -> void:
        _play("Music", _motif([659.25, 783.99, 987.77, 1174.66], 0.08), -12.0)


func pulse_whum() -> void:
        _play("SFX", _whum_s, -7.0, randf_range(0.95, 1.08))


func whale_call(i: int) -> void:
        var f0 := 98.0 if i % 2 == 0 else 82.0
        _play("Music", _whale_call(f0), -6.0)


func meteor_shimmer() -> void:
        _play("Music", _motif([1760.0, 2093.0, 2349.3, 2793.0, 3136.0], 0.09), -14.0)


func bloom_swell() -> void:
        _play("Music", _swell_pad([220.0, 261.63, 329.63, 392.0], 9.0, 2.5, 2.5), -9.0)


func aurora_swell() -> void:
        _play("Music", _swell_pad([261.63, 329.63, 392.0, 523.25], 12.0, 3.0, 3.5), -10.0)
