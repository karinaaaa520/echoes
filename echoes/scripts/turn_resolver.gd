class_name TurnResolver
extends RefCounted

## 纯逻辑回合结算器。
##
## 三条硬约束（后续改动不得破坏）：
##   1. 不继承 Node，不引用任何场景节点，不做绘制与动画。
##   2. 所有逻辑坐标一律 Vector2i（格子坐标），不出现像素坐标。
##   3. step() 是确定性的：同样的状态 + 同样的输入，永远得到同样的结果。
##
## 一拍内的结算顺序（固定）：
##   ① 影子执行"上一拍记录的方向"
##   ② 本体执行"本拍输入方向"（撞锁门 → 本拍只开门、不移动）
##   ③ 钥匙拾取（仅本体）
##   ④ 压力板结算（本体或影子 → 永久锁存）
##   ⑤ 出口开启（所需压力板全部锁存 → 永久开启）
##   ⑥ 记录本拍方向 + 通关判定
##
## 一切"开启"都不可逆，只能靠 reset() 复位。这是刻意的设计：
## 状态单调递增，不会出现"门反复开关夹住角色"这类边界情况。

const DIR_NONE := Vector2i.ZERO


## 一拍的完整结果。视图层只读它，不改它。
class StepResult extends RefCounted:
	var turn := 0                    ## 这是第几拍（从 1 开始）
	var input := Vector2i.ZERO       ## 本拍输入方向
	var recorded := Vector2i.ZERO    ## 本拍记录给下一拍影子的方向

	var player_from := Vector2i.ZERO
	var player_to := Vector2i.ZERO
	var shadow_from := Vector2i.ZERO
	var shadow_to := Vector2i.ZERO

	var player_moved := false
	var shadow_moved := false
	var player_blocked := false      ## 有输入但一步没走成
	var shadow_blocked := false      ## 有历史指令但一步没走成

	# ---- 机关事件 ----
	var key_taken := false           ## 本体捡到钥匙
	var door_opened := false         ## 本拍撞锁门并成功打开（本体不移动）
	var door_blocked := false        ## 撞到锁门但没有钥匙
	var plates_latched: Array[String] = []  ## 本拍新锁存的压力板 id
	var exit_opened := false         ## 本拍出口条件达成

	# ---- 通关 ----
	var on_exit := false             ## 本拍结束时本体站在出口格上
	var won := false                 ## 本拍触发通关
	var refused := false             ## 已经通关，本拍输入被拒绝（状态没有变化）

	func _to_string() -> String:
		if refused:
			return "T%d 已通关，输入被忽略" % turn

		var s := "T%d in=%s | P %s→%s(%s) S %s→%s(%s) rec=%s" % [
			turn,
			str(input),
			str(player_from), str(player_to), "动" if player_moved else ("挡" if player_blocked else "停"),
			str(shadow_from), str(shadow_to), "动" if shadow_moved else ("挡" if shadow_blocked else "停"),
			str(recorded),
		]
		var tags: Array[String] = []
		if key_taken:
			tags.append("拾钥匙")
		if door_opened:
			tags.append("开门")
		if door_blocked:
			tags.append("门锁着")
		if not plates_latched.is_empty():
			tags.append("压板:" + ",".join(plates_latched))
		if exit_opened:
			tags.append("出口开启")
		if won:
			tags.append("★WIN")
		if not tags.is_empty():
			s += "  [" + " ".join(tags) + "]"
		return s


var level: LevelData = null

var player := Vector2i.ZERO
var shadow := Vector2i.ZERO
var pending := Vector2i.ZERO   ## 上一拍记录的方向；ZERO 表示"无历史指令"
var turn := 0

# ---- 机关状态（全部单调递增，reset 才复位）----
var keys_left := {}      ## Vector2i -> true，仍在地上的钥匙
var has_key := false     ## 本体是否持钥匙
var doors_open := {}     ## Vector2i -> true，已开启的锁门
var latched := {}        ## String -> true，已触发过的压力板 id
var exit_open := true    ## 出口是否已开启
var won := false         ## 是否已通关

var _player_start := Vector2i.ZERO
var _shadow_start := Vector2i.ZERO


## 由关卡数据创建结算器，并立即回到该关的初始状态。
static func from_level(p_level: LevelData) -> TurnResolver:
	var r := TurnResolver.new()
	r.level = p_level
	r._player_start = p_level.player_start
	r._shadow_start = p_level.shadow_start
	r.reset()
	return r


## 回到本关初始状态：位置、方向、回合、钥匙、门、压力板、出口、通关标记全部复位。
func reset() -> void:
	player = _player_start
	shadow = _shadow_start
	pending = DIR_NONE
	turn = 0
	won = false

	has_key = false
	keys_left = {} if level == null else level.keys.duplicate()
	doors_open = {}
	latched = {}
	exit_open = level == null or level.exit_needs.is_empty()


## 推进一拍。direction 必须是四个正交方向之一（或 ZERO 表示空过）。
func step(direction: Vector2i) -> StepResult:
	# 已通关：拒绝一切方向输入，状态原地不动。回到可玩状态只能靠 reset()。
	if won:
		var stop := StepResult.new()
		stop.turn = turn
		stop.refused = true
		stop.player_from = player
		stop.player_to = player
		stop.shadow_from = shadow
		stop.shadow_to = shadow
		return stop

	# 方向合法性：只允许上下左右或 ZERO，斜向等非法值按"空过"处理并报错
	if direction != DIR_NONE and (absi(direction.x) + absi(direction.y)) != 1:
		push_error("[TurnResolver] 非法方向 %s，已按空过处理" % str(direction))
		direction = DIR_NONE

	var r := StepResult.new()
	r.turn = turn + 1
	r.input = direction
	r.player_from = player
	r.shadow_from = shadow

	# ---------- ① 影子：执行上一拍记录的方向 ----------
	var next_shadow := shadow
	if pending != DIR_NONE:
		var s_target := shadow + pending
		# 越界/墙/关闭的门 → 不动；目标格是本体的"当前"格 → 不动
		if is_wall(s_target) or is_closed_door(s_target) or s_target == player:
			r.shadow_blocked = true
		else:
			next_shadow = s_target
			r.shadow_moved = true

	# ---------- ② 本体：执行本拍输入方向 ----------
	var next_player := player
	if direction != DIR_NONE:
		var p_target := player + direction
		if is_closed_door(p_target):
			if has_key:
				# 撞门：本拍只开门，不移动；钥匙当场消耗
				doors_open[p_target] = true
				has_key = false
				r.door_opened = true
			else:
				r.door_blocked = true
				r.player_blocked = true
		elif is_wall(p_target) or p_target == next_shadow:
			# 用影子"结算后"的位置判定，所以影子刚让开的格子可以进
			r.player_blocked = true
		else:
			next_player = p_target
			r.player_moved = true

	player = next_player
	shadow = next_shadow
	r.player_to = player
	r.shadow_to = shadow

	# ---------- ③ 钥匙：只有本体能拾取 ----------
	if keys_left.has(player):
		keys_left.erase(player)
		has_key = true
		r.key_taken = true

	# ---------- ④ 压力板：本体或影子都算，压住即永久锁存 ----------
	if level != null:
		for plate_cell in level.plates:
			var plate_id: String = level.plates[plate_cell]
			if (plate_cell == player or plate_cell == shadow) and not latched.has(plate_id):
				latched[plate_id] = true
				r.plates_latched.append(plate_id)

	# ---------- ⑤ 出口：所需压力板全部锁存 → 永久开启 ----------
	if level != null and not exit_open and not level.exit_needs.is_empty():
		var all := true
		for plate_id in level.exit_needs:
			if not latched.has(plate_id):
				all = false
				break
		if all:
			exit_open = true
			r.exit_opened = true

	# ---------- ⑥ 记录本拍方向（即使被挡也记录） ----------
	pending = direction
	r.recorded = pending
	turn = r.turn

	# 不变量：两个身体永远不可能同格。触发即代码有 bug，但不打断运行。
	if player == shadow:
		push_error("[TurnResolver] 状态非法：本体与影子重叠于 %s" % str(player))

	# ---------- ⑦ 通关判定 ----------
	# 每拍结算末尾都判一次，所以"出口刚开启、而本体早已站在出口上"也能当场通关。
	# 只看本体：影子站在出口上不算。
	r.on_exit = level != null and player == level.exit_cell
	if r.on_exit and exit_open:
		won = true
		r.won = true

	return r


## 越界视为墙壁
func is_wall(c: Vector2i) -> bool:
	if level == null:
		return true
	return level.cell(c) == Grid.Cell.WALL


## 关闭的锁门：和墙一样挡人，但本体持钥匙时可以撞开
func is_closed_door(c: Vector2i) -> bool:
	if level == null:
		return false
	return level.doors.has(c) and not doors_open.has(c)


## 调试用快照
func state() -> Dictionary:
	return {
		"turn": turn,
		"player": player,
		"shadow": shadow,
		"pending": pending,
		"key": has_key,
		"keys_left": keys_left.size(),
		"doors": doors_open.size(),
		"plates": latched.size(),
		"exit": exit_open,
		"won": won,
	}
