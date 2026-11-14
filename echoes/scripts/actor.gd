class_name Actor
extends Node2D

## 本体与影子共用的角色节点。
## 本体 = 琥珀色圆形，影子 = 蓝紫色方形。
## 形状与颜色双重编码：即使色觉受限或截图转灰度也能区分两者。

const C_PLAYER := Color("#f0a63c")
const C_SHADOW := Color("#7a6bd8")

var cell := Vector2i.ZERO
var is_shadow := false
var body_color := C_PLAYER


## 在场景里创建后由 World 调用一次
func configure(kind: String) -> void:
	is_shadow = (kind == "shadow")
	body_color = C_SHADOW if is_shadow else C_PLAYER
	queue_redraw()


## 把角色放到指定格子（逻辑坐标 → 像素坐标只在这一次发生）
func set_cell(p_cell: Vector2i) -> void:
	cell = p_cell
	position = Grid.cell_to_px(cell)
	queue_redraw()


func _draw() -> void:
	var half := Grid.TILE * 0.5
	var pad := 2.0
	if is_shadow:
		var side := Grid.TILE - pad * 2.0
		var r := Rect2(Vector2(-half + pad, -half + pad), Vector2(side, side))
		draw_rect(r, Color(body_color, 0.88))
		draw_rect(r, body_color.lightened(0.3), false, 1.0)
	else:
		draw_circle(Vector2.ZERO, half - pad, body_color)
		draw_circle(Vector2.ZERO, half - pad, body_color.lightened(0.28), false, 1.0)
