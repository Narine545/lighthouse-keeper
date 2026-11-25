class_name DeepBg
extends CanvasLayer

# Слой фона-картины: шейдер deep.gdshader на весь экран, позади мира.

var _mat: ShaderMaterial
var _rect: ColorRect


func _ready() -> void:
        layer = -10
        _rect = ColorRect.new()
        _rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var sh: Shader = load("res://shaders/deep.gdshader")
        _mat = ShaderMaterial.new()
        _mat.shader = sh
        _rect.material = _mat
        add_child(_rect)


func _vp_size() -> Vector2:
        return get_viewport().get_visible_rect().size


func sync_viewport() -> void:
        _mat.set_shader_parameter("screen_px", _vp_size())


func set_time(t: float) -> void:
        _mat.set_shader_parameter("time_s", t)


func set_light(pos: Vector2, r: float, i: float) -> void:
        _mat.set_shader_parameter("light_pos", pos)
        _mat.set_shader_parameter("light_r", r)
        _mat.set_shader_parameter("light_i", i)


func set_bloom(v: float) -> void:
        _mat.set_shader_parameter("bloom_evt", v)


func set_aurora(v: float) -> void:
        _mat.set_shader_parameter("aurora", v)


func set_sway(dx: float, dy: float) -> void:
        _mat.set_shader_parameter("sway", Vector2(dx, dy))


# Метаболы: список [позиция: Vector2, радиус: float, сила: float, цвет: Vector3].
# Слоты сверх восьми игнорируются — шейдер держит ровно 8 шаров.
func set_balls(list: Array) -> void:
        var pr := PackedVector4Array()
        var cols := PackedVector3Array()
        for b in list:
                pr.append(Vector4(b[0].x, b[0].y, b[1], b[2]))
                cols.append(b[3])
        while pr.size() < 8:
                pr.append(Vector4(0.0, 0.0, 0.0, 0.0))
                cols.append(Vector3.ZERO)
        _mat.set_shader_parameter("balls", pr)
        _mat.set_shader_parameter("ball_cols", cols)
        _mat.set_shader_parameter("balls_n", mini(list.size(), 8))
