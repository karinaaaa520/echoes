extends SceneTree

## 胜利判定无头测试（P0-09）。
## 运行：godot --headless --path . --script res://tests/test_win.gd
## 退出码：0 = 全过，1 = 有失败
##
## 只测逻辑层：UI 显隐由 main.gd 负责，靠实机截图验证。

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== 胜利判定 无头测试 ===")

	_test_01_level1_exit_open()
	_test_02_reach_exit_wins()
	_test_03_no_win_before_exit()
	_test_04_input_refused_after_win()
	_test_05_reset_clears_win()
	_test_06_closed_exit_blocks_win()
	_test_07_win_only_on_player()

	print("\n=== 结果：%d 通过 / %d 失败 ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ------------------------------------------------------------------ 工具

func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s    %s" % [label, detail])


func _level1() -> TurnResolver:
	var def: Dictionary = Levels.DATA[0]
	var lv := LevelData.from_ascii(def["name"], def["map"], def["exit_needs"])
	return TurnResolver.from_level(lv)


# ------------------------------------------------------------------ 测试

func _test_01_level1_exit_open() -> void:
	print("\n[1] 第一关出口初始开启")
	var rs := _level1()
	_check(rs.exit_open, "exit_needs 为空 → exit_open = true")
	_check(not rs.won, "开局未通关")
	_check(rs.level.exit_cell == Vector2i(5, 1), "出口格是 (5,1)", str(rs.level.exit_cell))


func _test_02_reach_exit_wins() -> void:
	print("\n[2] 走到出口即通关（第 1 关最短解 R R R R）")
	var rs := _level1()
	var r: TurnResolver.StepResult = null
	for i in 4:
		r = rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(rs.player == Vector2i(5, 1), "本体到达出口", str(rs.player))
	_check(r.on_exit, "最后一拍标记 on_exit")
	_check(r.won, "最后一拍标记 won")
	_check(rs.won, "结算器进入通关状态")
	_check(r.turn == 4, "第 4 拍通关", str(r.turn))


func _test_03_no_win_before_exit() -> void:
	print("\n[3] 没走到出口不会通关")
	var rs := _level1()
	var r1 := rs.step(Vector2i.RIGHT)
	_check(not r1.on_exit and not r1.won, "第 1 拍未通关", str(r1))

	rs.step(Vector2i.RIGHT)
	var r3 := rs.step(Vector2i.DOWN)
	_check(rs.player != rs.level.exit_cell, "第 3 拍本体不在出口", str(rs.player))
	_check(not r3.won and not rs.won, "第 3 拍仍未通关", str(r3))


func _test_04_input_refused_after_win() -> void:
	print("\n[4] 通关后方向输入被拒绝，状态不变")
	var rs := _level1()
	for i in 4:
		rs.step(Vector2i.RIGHT)
	var before := rs.state()

	var r := rs.step(Vector2i.LEFT)
	print("    %s" % str(r))

	_check(r.refused, "本拍被标记为拒绝", str(r))
	_check(rs.player == before["player"], "本体没动", str(rs.player))
	_check(rs.shadow == before["shadow"], "影子没动", str(rs.shadow))
	_check(rs.turn == before["turn"], "回合数没有推进", str(rs.turn))
	_check(r.turn == before["turn"], "被拒绝的结果不推进回合号", str(r.turn))

	# 连按多次也不应该有任何变化
	for i in 5:
		rs.step(Vector2i.UP)
	_check(str(rs.state()) == str(before), "连按 5 次后状态完全没变",
		"%s vs %s" % [str(rs.state()), str(before)])


func _test_05_reset_clears_win() -> void:
	print("\n[5] reset() 清除通关状态并恢复初始状态")
	var rs := _level1()
	for i in 4:
		rs.step(Vector2i.RIGHT)
	_check(rs.won, "先确认已通关")

	rs.reset()
	print("    %s" % str(rs.state()))

	_check(not rs.won, "通关标记已清除")
	_check(rs.player == Vector2i(1, 1), "本体回起点", str(rs.player))
	_check(rs.shadow == Vector2i(3, 3), "影子回起点", str(rs.shadow))
	_check(rs.turn == 0, "回合数归零", str(rs.turn))
	_check(rs.pending == Vector2i.ZERO, "待执行方向清空", str(rs.pending))

	# 重置后应该能立刻重新通关
	var r := rs.step(Vector2i.RIGHT)
	_check(not r.refused, "重置后输入不再被拒绝", str(r))


func _test_06_closed_exit_blocks_win() -> void:
	print("\n[6] 出口未开启时，站上去也不通关")
	# 出口要求踩板 a，而 a 放在本体和影子 4 拍内都到不了的位置
	# ###########
	# #P...E....#   P(1,1) E(5,1)
	# #.........#
	# #..S...a..#   S(3,3) a(7,3)
	var lv := LevelData.from_ascii("t", [
		"###########",
		"#P...E....#",
		"#.........#",
		"#..S...a..#",
		"###########",
	], ["a"])
	_check(lv.is_valid(), "测试地图合法", ", ".join(lv.errors))
	var rs := TurnResolver.from_level(lv)

	_check(not rs.exit_open, "exit_needs 非空 → exit_open = false")

	for i in 4:
		rs.step(Vector2i.RIGHT)

	_check(rs.player == Vector2i(5, 1), "本体确实站在出口格上", str(rs.player))
	_check(not rs.latched.has("a"), "压力板没有被踩到", str(rs.latched))
	_check(not rs.won, "但不算通关")


func _test_07_win_only_on_player() -> void:
	print("\n[7] 通关只看本体：影子踩到出口不算")
	# 本体左边是墙动不了，影子一路向上走到出口格 (3,1)
	var lv := LevelData.from_ascii("t", ["#######", "#P.E..#", "#.....#", "#..S..#", "#######"])
	_check(lv.is_valid(), "测试地图合法", ", ".join(lv.errors))
	var rs := TurnResolver.from_level(lv)

	for i in 3:
		rs.step(Vector2i.UP)

	_check(rs.shadow == rs.level.exit_cell, "影子站在出口格 %s 上" % str(rs.shadow),
		str(rs.shadow))
	_check(rs.player != rs.level.exit_cell, "本体不在出口", str(rs.player))
	_check(not rs.won, "影子站在出口上不触发通关")
