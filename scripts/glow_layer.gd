class_name GlowLayer
extends Node2D

# Аддитивный «световой» слой существа.
# Тело рисуется обычным смешиванием (полупрозрачная живопись),
# а свет — мягкими мазками поверх. Кисти рисует сам художник-существо:
# GlowLayer просто вызывает его метод _paint_glow.

var painter: Node2D = null


func _draw() -> void:
        if painter != null and painter.has_method("_paint_glow"):
                painter._paint_glow(self)
