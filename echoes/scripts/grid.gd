class_name Grid
extends RefCounted

## 全局网格常量与坐标换算。
## 约定：逻辑层只出现整数格坐标 Vector2i，像素坐标只在绘制时才算。

const TILE := 16

## 格子类型。渲染与碰撞判定共用这一套编号。
enum Cell {
	FLOOR,   ## 可通行地面
	WALL,    ## 阻挡
	DOOR,    ## 锁门（关闭时阻挡）
	PLATE,   ## 压力板
	KEY,     ## 钥匙
	EXIT,    ## 出口
}

## 格子中心点的像素坐标（精灵按中心对齐时用）
static func cell_to_px(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE, TILE) * 0.5

## 格子左上角开始的矩形（绘制地形用）
static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
