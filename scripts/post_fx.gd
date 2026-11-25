class_name PostFx
extends CanvasLayer

# Верхний слой постобработки: насыщенность, виньетка, зерно.

var _mat: ShaderMaterial
var _rect: ColorRect


func _ready() -> void:
        layer = 10
        _rect = ColorRect.new()
        _rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var sh: Shader = load("res://shaders/post.gdshader")
        _mat = ShaderMaterial.new()
        _mat.shader = sh
        _rect.material = _mat
        add_child(_rect)


func sync_viewport() -> void:
        _mat.set_shader_parameter("screen_px", get_viewport().get_visible_rect().size)


func set_time(t: float) -> void:
        _mat.set_shader_parameter("time_s", t)
