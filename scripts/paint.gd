class_name Paint
extends RefCounted

# Кисти живописи «Тихой глубины».
# В проекте нет ни одной картинки: каждый «мазок света» — радиальный
# градиент, сгенерированный кодом. Мягкие мазки, наложенные друг на друга
# с аддитивным смешиванием, дают живописный свет — как в 2D-живописи.

static var _glow: GradientTexture2D = null
static var _mat: CanvasItemMaterial = null


# Белый радиальный градиент с мягким спадом — «кисть света».
static func glow_tex() -> GradientTexture2D:
        if _glow == null:
                var g := Gradient.new()
                g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.0)])
                g.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
                var t := GradientTexture2D.new()
                t.gradient = g
                t.width = 256
                t.height = 256
                t.fill = GradientTexture2D.FILL_RADIAL
                t.fill_from = Vector2(0.5, 0.5)
                t.fill_to = Vector2(0.5, 0.0)
                _glow = t
        return _glow


# Аддитивный материал: мазки «складываются» светом, а не краской.
static func add_mat() -> CanvasItemMaterial:
        if _mat == null:
                var m := CanvasItemMaterial.new()
                m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
                _mat = m
        return _mat


# Один мазок: мягкий световой круг.
static func blob(ci: CanvasItem, pos: Vector2, r: float, color: Color) -> void:
        var s := r * 2.0
        ci.draw_texture_rect(glow_tex(), Rect2(pos.x - r, pos.y - r, s, s), false, color)


# Цепочка мазков с сужением — щупальца, шлейфы, стебли, следы.
static func chain(ci: CanvasItem, pts: Array, r0: float, r1: float, color: Color) -> void:
        var n := pts.size()
        if n < 2:
                if n == 1:
                        blob(ci, pts[0], r0, color)
                return
        for i in n:
                var t := float(i) / float(n - 1)
                var rr := lerpf(r0, r1, t)
                var c := color
                c.a = color.a * (1.0 - t * t * 0.5)
                blob(ci, pts[i], rr, c)


# Органичное дрожание: сумма несоизмеримых синусов — как дыхание воды.
static func wobble(t: float, seed_v: float) -> float:
        return 0.6 * sin(t * 0.9 + seed_v) + 0.3 * sin(t * 1.7 + seed_v * 2.3) + 0.1 * sin(t * 3.1 + seed_v * 4.1)
