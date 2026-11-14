class_name WorldView
extends Node2D

## 负责"把逻辑画出来"。它不参与任何规则判断，只读 LevelData。
## 现阶段全部用色块绘制，后续替换成图块时只改这个文件。

## 一拍动画播完时发出。main 收到后才会解锁输入。
signal step_animation_finished

const SHADOW_SEC := 0.06
const PLAYER_SEC := 0.06

const C_FLOOR := Color("#23232b")
const C_FLOOR_LIT := Color("#2a2a34")
const C_GRID := Color("#1b1b21")
const C_WALL := Color("#3d3d49")
const C_WALL_TOP := Color("#55555f")
const C_DOOR := Color("#c9a227")
const C_DOOR_DIM := Color("#5a4a1c")
const C_PLATE := Color("#35a08a")
const C_PLATE_LIT := Color("#7fe8cd")
const C_KEY := Color("#f2c14e")
const C_EXIT := Color("#4fd6b0")
const C_EXIT_OFF := Color("#2b6b5c")

@onready var player: Actor = $Player
@onready var shadow: Actor = $Shadow

var level: LevelData = null
var model: TurnResolver = null   ## 只读：机关状态的来源，视图不修改它
var _tween: Tween = null


## 加载关卡并刷新画面。失败时返回 false，原因已 push_error 到控制台。
func load_level(index: int = 0) -> bool:
	if index < 0 or index >= Levels.DATA.size():
		push_error("[关卡] 索引越界：%d" % index)
		return false
	return load_def(Levels.DATA[index])


## 用一份关卡定义（index 之外的方式，比如开发用的测试室）加载
func load_def(def: Dictionary) -> bool:
	var lv := LevelData.from_ascii(def["name"], def["map"], def.get("exit_needs", []))

	if not lv.is_valid():
		for e in lv.errors:
			push_error("[关卡] %s" % e)
		level = null
		model = null
		queue_redraw()
		return false

	level = lv
	model = null          # 等 main 建好 TurnResolver 后 sync_from
	player.configure("player")
	player.set_cell(lv.player_start)
	shadow.configure("shadow")
	shadow.set_cell(lv.shadow_start)
	_center_map()
	queue_redraw()
	return true


## 每拍结算后由 main 调用：把逻辑状态交给视图重画地形。
## 视图只读模型，绝不修改它——规则永远由 TurnResolver 决定。
func sync_from(m: TurnResolver) -> void:
	model = m
	queue_redraw()


## 把整张地图摆到视口正中（像素级取整，避免半像素模糊）
func _center_map() -> void:
	var view := get_viewport_rect().size
	var map_px := Vector2(level.width, level.height) * Grid.TILE
	position = ((view - map_px) * 0.5).floor()


func _draw() -> void:
	if level == null:
		return
	for y in level.height:
		for x in level.width:
			var c := Vector2i(x, y)
			_draw_cell(c, level.cell(c))


func _draw_cell(c: Vector2i, kind: int) -> void:
	var r := Grid.cell_rect(c)
	match kind:
		Grid.Cell.WALL:
			draw_rect(r, C_WALL)
			# 只有上方不是墙时才画顶面高光，避免竖直墙体被画成一节一节的梯子
			if level.cell(c + Vector2i.UP) != Grid.Cell.WALL:
				draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), C_WALL_TOP)
		Grid.Cell.DOOR:
			_draw_floor(r)
			if model != null and model.doors_open.has(c):
				# 已开启：只剩门框，读作"门不挡路了"
				draw_rect(r.grow(-1.0), C_DOOR_DIM, false, 1.0)
			else:
				for i in 3:
					var bx := r.position.x + 3.0 + float(i) * 5.0
					draw_rect(Rect2(Vector2(bx, r.position.y + 1.0), Vector2(2.0, r.size.y - 2.0)), C_DOOR)
		Grid.Cell.PLATE:
			_draw_floor(r)
			var plate_id: String = level.plates.get(c, "")
			var is_on: bool = model != null and model.latched.has(plate_id)
			var center := r.position + r.size * 0.5
			if is_on:
				draw_circle(center, 5.0, C_PLATE)
				draw_circle(center, 2.0, C_PLATE_LIT)
			else:
				draw_circle(center, 5.0, C_PLATE, false, 1.5)
		Grid.Cell.KEY:
			_draw_floor(r)
			if model == null or model.keys_left.has(c):
				var kc := r.position + r.size * 0.5
				draw_circle(kc + Vector2(0.0, -2.0), 2.5, C_KEY, false, 1.5)
				draw_rect(Rect2(kc + Vector2(-0.75, 0.5), Vector2(1.5, 4.5)), C_KEY)
		Grid.Cell.EXIT:
			var is_open: bool = model == null or model.exit_open
			_draw_floor(r, is_open)
			draw_rect(r.grow(-1.0), C_EXIT if is_open else C_EXIT_OFF, false, 1.0)
			if not is_open:
				# 未开启：中间一道横杠，读作"锁着"
				var mid := r.position + r.size * 0.5
				draw_line(mid + Vector2(-3.0, 0.0), mid + Vector2(3.0, 0.0), C_EXIT_OFF, 1.0)
		_:
			_draw_floor(r)


func _draw_floor(r: Rect2, lit: bool = false) -> void:
	draw_rect(r, C_FLOOR_LIT if lit else C_FLOOR)
	# 1px 描边做石砖缝，坐标取整避免模糊
	var x2 := r.position.x + r.size.x - 1.0
	var y2 := r.position.y + r.size.y - 1.0
	draw_line(Vector2(r.position.x, y2), Vector2(x2, y2), C_GRID, 1.0)
	draw_line(Vector2(x2, r.position.y), Vector2(x2, y2), C_GRID, 1.0)


# ------------------------------------------------------------------ 动画

## 播放一拍：影子先动 → 本体后动，播完发 step_animation_finished。
## 即使某个角色这一拍没走动，也照样走满时长——每拍节奏一致，玩家才读得懂。
func animate_step(r: TurnResolver.StepResult) -> void:
	stop_animation()

	# 逻辑格先更新（调试与后续判定用），像素位置交给 tween
	shadow.cell = r.shadow_to
	player.cell = r.player_to

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(shadow, "position", Grid.cell_to_px(r.shadow_to), SHADOW_SEC)
	_tween.tween_property(player, "position", Grid.cell_to_px(r.player_to), PLAYER_SEC)
	_tween.tween_callback(func() -> void:
		_tween = null   # 先置空，回调里再被 stop_animation 碰到就不会误 kill
		step_animation_finished.emit()
	)


## 立即摆位，不播动画（开局面 / 重置用）
func snap_actors(p: Vector2i, s: Vector2i) -> void:
	stop_animation()
	player.set_cell(p)
	shadow.set_cell(s)


## 打断动画。被 kill 的 tween 不会发出 finished 回调，所以调用方必须自己收尾。
func stop_animation() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
