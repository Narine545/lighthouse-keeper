# audio_director.gd — полностью генеративный звук: ни одного аудиофайла.
# Шум волн и ветер синтезируются как зацикленные буферы: хвост кроссфейдится в голову,
# а точка лупа стоит сразу после зоны кроссфейда — поэтому шов не щёлкает.
# Кроссфейд и нормализация выполняются прямо в генераторах, на ЛОКАЛЬНЫХ массивах:
# PackedFloat32Array в GDScript — тип-значение, и правки параметра внутри отдельной
# функции могут не возвращаться вызывающему коду. Раньше из-за этого нормализация
# молча не срабатывала: сырые пики моря (до ±4.2 при лимите ±1.0) уходили в
# encode_s16 с переполнением int16, вершины волны «складывались» с инверсией фазы —
# и слышался грубый «хрип». Жёсткий clamp при каждом encode_s16 делает такое
# переполнение невозможным в принципе.
# Ноты пентатоники и колокола — аддитивный синтез с экспоненциальным затуханием.
extends Node

const SR := 44100

var day_phase := 0.0

var _sea_p: AudioStreamPlayer
var _wind_p: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _vi := 0
var _note_cache := {}
var _bell_cache := {}
var _knock_s: AudioStreamWAV
var _ping_s: AudioStreamWAV
var _sched: Array = []
var _music_t := 2.5


func _ready() -> void:
        _make_bus("Amb", 0.15)
        _make_bus("Music", 0.35)
        _make_bus("SFX", 0.28)

        _sea_p = AudioStreamPlayer.new()
        _sea_p.stream = _sea_loop(8.0)
        _sea_p.bus = "Amb"
        _sea_p.volume_db = -7.0
        add_child(_sea_p)
        _sea_p.play()

        _wind_p = AudioStreamPlayer.new()
        _wind_p.stream = _wind_loop(7.0)
        _wind_p.bus = "Amb"
        _wind_p.volume_db = -15.0
        add_child(_wind_p)
        _wind_p.play()

        for i in 8:
                var p := AudioStreamPlayer.new()
                p.bus = "Music"
                add_child(p)
                _voices.append(p)

        _knock_s = _make_knock()
        _ping_s = _make_ping()


func _make_bus(bus_name: String, reverb_wet: float) -> void:
        var idx := AudioServer.get_bus_index(bus_name)
        if idx == -1:
                idx = AudioServer.bus_count
                AudioServer.add_bus(idx)
                AudioServer.set_bus_name(idx, bus_name)
                AudioServer.set_bus_send(idx, "Master")
                var rv := AudioEffectReverb.new()
                rv.room_size = 0.85
                rv.damping = 0.4
                rv.wet = reverb_wet
                rv.dry = 0.9
                AudioServer.add_bus_effect(idx, rv)


func _to_wav_stereo(L: PackedFloat32Array, R: PackedFloat32Array, loop_start: int) -> AudioStreamWAV:
        var frames := L.size()
        var data := PackedByteArray()
        data.resize(frames * 4)
        # Жёсткий clamp: даже при любом сбое нормализации int16-переполнение
        # (тот самый «хрип») невозможно в принципе.
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


# Море: два независимых «коричневых» пласта (Л/П) с медленным накатом волн
# и тихой «пеной», которая вспухает на гребне волны.
func _sea_loop(dur: float) -> AudioStreamWAV:
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        var R := PackedFloat32Array()
        L.resize(frames)
        R.resize(frames)
        var b1 := 0.0
        var b2 := 0.0
        var l1 := 0.0
        var l2 := 0.0
        var r1 := 0.0
        var r2 := 0.0
        var f1 := 0.0
        var f2 := 0.0
        for i in frames:
                var ph := TAU * float(i) / SR / dur
                b1 += (randf() * 2.0 - 1.0) * 0.016
                b1 *= 0.9985
                b2 += (randf() * 2.0 - 1.0) * 0.016
                b2 *= 0.9985
                l1 += (b1 - l1) * 0.04
                l2 += (l1 - l2) * 0.10
                r1 += (b2 - r1) * 0.04
                r2 += (r1 - r2) * 0.10
                f1 += ((randf() * 2.0 - 1.0) - f1) * 0.18
                f2 += ((randf() * 2.0 - 1.0) - f2) * 0.18
                var swell := 0.55 + 0.45 * sin(ph * 2.0)
                var swell2 := 0.6 + 0.4 * sin(ph * 3.0 + 1.3)
                var foam := swell * swell * swell
                var foam2 := swell2 * swell2 * swell2
                L[i] = l2 * 7.0 * swell + f1 * 0.06 * foam
                R[i] = r2 * 7.0 * swell2 + f2 * 0.06 * foam2
        # Кроссфейд и нормализация — прямо здесь, на локальных массивах.
        # PackedFloat32Array — тип-значение: правки параметра внутри отдельной
        # функции могут не возвращаться вызывающему коду, поэтому раньше
        # нормализация молча не срабатывала и звук перегружался.
        var n := int(0.35 * SR)
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
                var g := 0.8 / mx
                for i in frames:
                        L[i] = L[i] * g
                        R[i] = R[i] * g
        return _to_wav_stereo(L, R, n)


# Ветер: приглушённый рокот с порывами и едва слышным воздушным верхом.
func _wind_loop(dur: float) -> AudioStreamWAV:
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        var R := PackedFloat32Array()
        L.resize(frames)
        R.resize(frames)
        var lf1 := 0.0
        var ls1 := 0.0
        var hf1 := 0.0
        var lf2 := 0.0
        var ls2 := 0.0
        var hf2 := 0.0
        for i in frames:
                var ph := TAU * float(i) / SR / dur
                var w1 := randf() * 2.0 - 1.0
                var w2 := randf() * 2.0 - 1.0
                lf1 += (w1 - lf1) * 0.05
                ls1 += (w1 - ls1) * 0.007
                hf1 += (w1 - hf1) * 0.16
                lf2 += (w2 - lf2) * 0.05
                ls2 += (w2 - ls2) * 0.007
                hf2 += (w2 - hf2) * 0.16
                var gust := 0.55 + 0.45 * sin(ph * 2.0 + sin(ph * 3.0) * 0.6)
                var gust2 := 0.6 + 0.4 * sin(ph * 2.0 + 2.1 + sin(ph * 3.0) * 0.6)
                L[i] = (lf1 - ls1 * 1.6) * 1.8 * gust + (hf1 - lf1) * 0.06 * gust
                R[i] = (lf2 - ls2 * 1.6) * 1.8 * gust2 + (hf2 - lf2) * 0.06 * gust2
        # Тот же приём: кроссфейд + нормализация на локальных массивах.
        var n := int(0.35 * SR)
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
                var g := 0.62 / mx
                for i in frames:
                        L[i] = L[i] * g
                        R[i] = R[i] * g
        return _to_wav_stereo(L, R, n)


func _tone(freq: float) -> AudioStreamWAV:
        if _note_cache.has(freq):
                return _note_cache[freq]
        var dur := 3.5
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        var parts := [[1.0, 0.55], [2.0, 0.22], [3.0, 0.10], [4.16, 0.05]]
        for i in frames:
                var u := float(i) / SR
                var v := 0.0
                for p in parts:
                        v += float(p[1]) * sin(TAU * freq * float(p[0]) * u)
                v += 0.25 * sin(TAU * freq * 1.004 * u)
                var env := exp(-3.0 * u)
                if u < 0.012:
                        env *= u / 0.012
                L[i] = clampf(v * env * 0.5, -1.0, 1.0)
        var wav := _to_wav_mono(L)
        _note_cache[freq] = wav
        return wav


func _bell(freq: float) -> AudioStreamWAV:
        if _bell_cache.has(freq):
                return _bell_cache[freq]
        var dur := 5.0
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        var parts := [[1.0, 0.50, 1.5], [2.0, 0.12, 2.0], [2.74, 0.18, 2.6], [5.42, 0.08, 3.8], [8.9, 0.035, 5.5]]
        var strike := 0.0
        for i in frames:
                var u := float(i) / SR
                var v := 0.0
                for p in parts:
                        v += float(p[1]) * sin(TAU * freq * float(p[0]) * u) * exp(-float(p[2]) * u)
                # мягкий фильтрованный «щелчок» языка колокола вместо сырого шума
                if u < 0.02:
                        strike += ((randf() * 2.0 - 1.0) - strike) * 0.25
                        v += strike * 0.22 * (1.0 - u / 0.02)
                L[i] = clampf(v * 0.55, -1.0, 1.0)
        var wav := _to_wav_mono(L)
        _bell_cache[freq] = wav
        return wav


func _make_knock() -> AudioStreamWAV:
        var dur := 0.5
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        var lp := 0.0
        for i in frames:
                var u := float(i) / SR
                var v := sin(TAU * 85.0 * u) * exp(-16.0 * u) * 0.9
                var nz := (randf() * 2.0 - 1.0) * exp(-28.0 * u) * 0.35
                lp += (nz - lp) * 0.15
                L[i] = clampf(v + lp, -1.0, 1.0)
        return _to_wav_mono(L)


func _make_ping() -> AudioStreamWAV:
        var dur := 1.2
        var frames := int(dur * SR)
        var L := PackedFloat32Array()
        L.resize(frames)
        for i in frames:
                var u := float(i) / SR
                var v := sin(TAU * 880.0 * u) * exp(-5.0 * u) * 0.6
                v += sin(TAU * 1320.0 * u) * exp(-7.0 * u) * 0.2
                var env := 1.0
                if u < 0.008:
                        env = u / 0.008
                L[i] = clampf(v * env, -1.0, 1.0)
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
        # редкая генеративная мелодия
        _music_t -= delta
        if _music_t <= 0.0:
                _music_t = randf_range(4.5, 10.0) * (1.0 + day_phase * 0.5)
                var notes := [220.0, 261.63, 329.63, 392.0, 440.0, 523.25, 659.25]
                var f: float = notes[randi_range(0, notes.size() - 1)]
                var pitch := 1.0 + 0.1 * day_phase
                _play("Music", _tone(f), randf_range(-16.0, -10.0), pitch)
                if randf() < 0.28:
                        _sched.append({"t": 0.32, "f": f * 1.5, "v": -14.0, "pitch": pitch, "bell": false})
                if randf() < 0.12:
                        _sched.append({"t": randf_range(0.8, 1.6), "f": 130.81, "v": -16.0, "pitch": 1.0, "bell": true})
        for s in _sched:
                s["t"] = float(s["t"]) - delta
        for s in _sched.duplicate():
                if float(s["t"]) <= 0.0:
                        _sched.erase(s)
                        if bool(s["bell"]):
                                _play("SFX", _bell(float(s["f"])), float(s["v"]))
                        else:
                                _play("Music", _tone(float(s["f"])), float(s["v"]), float(s["pitch"]))
        # рассвет меняет тембр моря
        _sea_p.pitch_scale = 1.0 - 0.10 * day_phase
        _wind_p.volume_db = -15.0 - 5.0 * day_phase


func harbor_bell() -> void:
        _sched.append({"t": 0.02, "f": 392.0, "v": -7.0, "pitch": 1.0, "bell": true})
        _sched.append({"t": 0.45, "f": 523.25, "v": -7.0, "pitch": 1.0, "bell": true})
        _sched.append({"t": 0.90, "f": 659.25, "v": -8.0, "pitch": 1.0, "bell": true})
        _sched.append({"t": 0.10, "f": 130.81, "v": -10.0, "pitch": 1.0, "bell": true})


func bell_small() -> void:
        _play("SFX", _bell(440.0), -14.0)


func knock() -> void:
        _play("SFX", _knock_s, -6.0)


func beam_ping() -> void:
        _play("SFX", _ping_s, -17.0)


func click_ping() -> void:
        _play("SFX", _ping_s, -11.0, 1.3)


func set_bus_volume(bus_name: String, v: float) -> void:
        var idx := AudioServer.get_bus_index(bus_name)
        if idx == -1:
                return
        if v <= 0.001:
                AudioServer.set_bus_mute(idx, true)
        else:
                AudioServer.set_bus_mute(idx, false)
                AudioServer.set_bus_volume_db(idx, linear_to_db(v))


func get_bus_volume(bus_name: String) -> float:
        var idx := AudioServer.get_bus_index(bus_name)
        if idx == -1:
                return 0.8
        if AudioServer.is_bus_mute(idx):
                return 0.0
        return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)
