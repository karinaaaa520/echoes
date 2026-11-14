extends SceneTree

## TurnResolver 无头单元测试。
## 运行：godot --headless --path . --script res://tests/test_resolver.gd
## 退出码：0 = 全过，1 = 有失败

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TurnResolver 无头测试 ===")

	_test_01_first_turn_shadow_stays()
	_test_02_shadow_replays_previous_direction()
	_test_03_player_enters_vacated_cell()
	_test_04_shadow_cannot_enter_player_cell()
	_test_05_blocked_still_advances_turn()
	_test_06_reset_restores_initial()
	_test_07_never_same_cell()
	_test_08_player_cannot_enter_shadow_cell()
	_test_09_level1_matches_reference()

	print("\n=== 结果：%d 通过 / %d 失败 ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ------------------------------------------------------------------ 测试用工具

func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s    %s" % [label, detail])


func _lv(rows: Array) -> LevelData:
	var lv := LevelData.from_ascii("test", rows)
	if not lv.is_valid():
		_failed += 1
		print("  [FAIL] 测试地图非法：%s" % ", ".join(lv.errors))
	return lv


# ------------------------------------------------------------------ 各项测试

func _test_01_first_turn_shadow_stays() -> void:
	print("\n[1] 第一拍没有历史指令，影子不移动")
	# #P.S.E#  →  本体(1,1) 影子(3,1) 出口(5,1)
	var rs := TurnResolver.from_level(_lv(["#######", "#P.S.E#", "#######"]))
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(not r.shadow_moved, "影子未移动", str(r))
	_check(r.shadow_to == Vector2i(3, 1), "影子仍停在 (3,1)", str(r.shadow_to))
	_check(not r.shadow_blocked, "首拍不算被挡（只是没有指令）")
	_check(r.player_moved, "本体移动了")
	_check(r.player_to == Vector2i(2, 1), "本体走一格到 (2,1)", str(r.player_to))
	_check(r.recorded == Vector2i.RIGHT, "本拍方向已记录")
	_check(r.turn == 1, "回合数为 1")


func _test_02_shadow_replays_previous_direction() -> void:
	print("\n[2] 第二拍影子执行上一拍方向")
	var rs := TurnResolver.from_level(_lv(["#######", "#P.S.E#", "#######"]))
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(r.shadow_moved, "影子移动了", str(r))
	_check(r.shadow_from == Vector2i(3, 1) and r.shadow_to == Vector2i(4, 1), "影子 (3,1)→(4,1)")
	_check(r.player_from == Vector2i(2, 1) and r.player_to == Vector2i(3, 1), "本体 (2,1)→(3,1)")
	_check(r.turn == 2, "回合数为 2")


func _test_03_player_enters_vacated_cell() -> void:
	print("\n[3] 本体可以进入影子刚刚离开的格子")
	var rs := TurnResolver.from_level(_lv(["#######", "#P.S.E#", "#######"]))
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(r.player_to == r.shadow_from, "本体落点 = 影子起点（刚腾出的格子）",
		"player_to=%s shadow_from=%s" % [str(r.player_to), str(r.shadow_from)])
	_check(r.player_to != r.shadow_to, "移动后两者不在同一格")


func _test_04_shadow_cannot_enter_player_cell() -> void:
	print("\n[4] 影子不能进入本体所在格")
	# 本体左边是墙，连按左键三次：本体一直不动，影子一路向左，最后被本体挡住
	var rs := TurnResolver.from_level(_lv(["#######", "#P.S..#", "#....E#", "#######"]))
	rs.step(Vector2i.LEFT)
	rs.step(Vector2i.LEFT)
	var r := rs.step(Vector2i.LEFT)
	print("    %s" % str(r))

	_check(r.shadow_blocked, "影子被本体挡住", str(r))
	_check(r.shadow_to == Vector2i(2, 1), "影子停在 (2,1)，没有踩进本体格", str(r.shadow_to))
	_check(rs.player == Vector2i(1, 1), "本体仍被墙挡在 (1,1)")
	_check(rs.player != rs.shadow, "两者不同格")
	# 若允许交换，本体此时应在 (2,1)、影子在 (1,1)
	_check(rs.player != Vector2i(2, 1), "没有发生位置交换")


func _test_05_blocked_still_advances_turn() -> void:
	print("\n[5] 撞墙不移动，但回合仍然推进")
	var rs := TurnResolver.from_level(_lv(["#######", "#P.S..#", "#....E#", "#######"]))
	var r := rs.step(Vector2i.LEFT)
	print("    %s" % str(r))

	_check(not r.player_moved, "本体没有移动")
	_check(r.player_blocked, "本体被标记为被挡")
	_check(r.player_to == r.player_from, "位置不变")
	_check(r.turn == 1, "回合仍推进到 1")
	_check(rs.pending == Vector2i.LEFT, "被挡的输入仍被记录给下一拍影子")

	var r2 := rs.step(Vector2i.LEFT)
	_check(r2.shadow_moved and r2.shadow_to == Vector2i(2, 1),
		"下一拍影子确实执行了那次撞墙的方向", str(r2))


func _test_06_reset_restores_initial() -> void:
	print("\n[6] reset() 恢复初始状态")
	var rs := TurnResolver.from_level(_lv(["#######", "#P.S.E#", "#######"]))
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.DOWN)
	var mid := rs.state()
	print("    重置前 %s" % str(mid))

	rs.reset()
	print("    重置后 %s" % str(rs.state()))

	_check(rs.player == Vector2i(1, 1), "本体回到起点 (1,1)", str(rs.player))
	_check(rs.shadow == Vector2i(3, 1), "影子回到起点 (3,1)", str(rs.shadow))
	_check(rs.pending == Vector2i.ZERO, "待执行方向已清空", str(rs.pending))
	_check(rs.turn == 0, "回合数归零")

	var r := rs.step(Vector2i.RIGHT)
	_check(not r.shadow_moved, "重置后第一拍影子依然不动")


func _test_07_never_same_cell() -> void:
	print("\n[7] 本体与影子任何时候都不会进入同一格")
	var rs := TurnResolver.from_level(_lv(["#######", "#P...S#", "#....E#", "#######"]))
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	seed(20261113)
	var overlap_turn := -1
	for i in 300:
		var r := rs.step(dirs[randi() % 4])
		if rs.player == rs.shadow:
			overlap_turn = r.turn
			break
	print("    300 拍随机走位，最终 %s" % str(rs.state()))

	_check(overlap_turn == -1, "300 拍内从未同格", "第 %d 拍发生重叠" % overlap_turn)
	_check(rs.turn == 300, "300 次输入推进了 300 个回合", str(rs.turn))


func _test_08_player_cannot_enter_shadow_cell() -> void:
	print("\n[8] 本体不能进入影子结算后的格子")
	# 影子右边是墙，一直贴着墙不动；本体从左边追上来，第二拍会被影子挡住
	var rs := TurnResolver.from_level(_lv(["#######", "#P.S###", "#....E#", "#######"]))
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(not r.shadow_moved and r.shadow_blocked, "影子被墙挡住没动", str(r))
	_check(not r.player_moved and r.player_blocked, "本体被影子挡住没动", str(r))
	_check(rs.player == Vector2i(2, 1), "本体停在 (2,1)，没有踩进影子格", str(rs.player))
	_check(rs.player != rs.shadow, "两者不同格")


func _test_09_level1_matches_reference() -> void:
	print("\n[9] 真实第 1 关：R R R R 轨迹与 Python 参考实现（level_check.py）逐拍一致")
	var def: Dictionary = Levels.DATA[0]
	var lv := LevelData.from_ascii(def["name"], def["map"], def["exit_needs"])
	if not lv.is_valid():
		_failed += 1
		print("  [FAIL] 第 1 关数据非法：%s" % ", ".join(lv.errors))
		return

	var rs := TurnResolver.from_level(lv)
	# 期望值来自 docs/tools/level_check.py 的逐拍追踪输出
	var expect_p := [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)]
	var expect_s := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 3)]
	var ok := true
	var last: TurnResolver.StepResult = null

	for i in 4:
		last = rs.step(Vector2i.RIGHT)
		if rs.player != expect_p[i] or rs.shadow != expect_s[i]:
			ok = false
			print("    第 %d 拍不一致：本体 %s（期望 %s） 影子 %s（期望 %s）" % [
				i + 1, str(rs.player), str(expect_p[i]), str(rs.shadow), str(expect_s[i])
			])

	_check(ok, "四拍轨迹完全一致")
	_check(rs.player == lv.exit_cell, "第 4 拍本体落在出口格 %s" % str(lv.exit_cell), str(rs.player))
	_check(last != null and last.shadow_blocked, "第 4 拍影子撞右墙停住", str(last))
