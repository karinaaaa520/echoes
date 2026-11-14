extends SceneTree

## 关卡流程与第二关机关 无头测试（P1-02）。
## 运行：godot --headless --path . --script res://tests/test_level_flow.gd
## 退出码：0 = 全过，1 = 有失败

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== 关卡流程 + 第二关 无头测试 ===")

	# A. 关卡数据
	_test_01_data_has_two_levels()
	_test_02_level1_unchanged()
	_test_03_level2_data()
	_test_04_has_next()
	_test_05_fixture_not_in_data()

	# B. 关卡切换语义
	_test_06_level1_still_wins()
	_test_07_level2_starts_clean()

	# C. 第二关机关
	_test_08_player_plate_a()
	_test_09_one_plate_not_enough()
	_test_10_shadow_plate_b()
	_test_11_both_plates_open_exit()
	_test_12_latch_survives_leaving()
	_test_13_full_solve_seven_steps()
	_test_14_no_move_after_win()
	_test_15_reset_restores_level2()

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


func _resolver_of(index: int) -> TurnResolver:
	var def: Dictionary = Levels.DATA[index]
	var lv := LevelData.from_ascii(def["name"], def["map"], def["exit_needs"])
	if not lv.is_valid():
		_failed += 1
		print("  [FAIL] 第 %d 关数据非法：%s" % [index + 1, ", ".join(lv.errors)])
	return TurnResolver.from_level(lv)


# ------------------------------------------------------------------ A. 关卡数据

func _test_01_data_has_two_levels() -> void:
	print("\n[1] 正式关卡列表恰好 2 关")
	_check(Levels.DATA.size() == 2, "DATA.size() == 2", str(Levels.DATA.size()))
	_check(Levels.DATA[0]["name"] == "回声初醒", "第 1 关仍是回声初醒", str(Levels.DATA[0]["name"]))
	_check(Levels.DATA[1]["name"] == "两处微光", "第 2 关是两处微光", str(Levels.DATA[1]["name"]))


func _test_02_level1_unchanged() -> void:
	print("\n[2] 第一关数据未被改动")
	var def: Dictionary = Levels.DATA[0]
	var lv := LevelData.from_ascii(def["name"], def["map"], def["exit_needs"])

	_check(lv.is_valid(), "第 1 关合法", ", ".join(lv.errors))
	_check(lv.width == 7 and lv.height == 5, "仍为 7×5", "%dx%d" % [lv.width, lv.height])
	_check(lv.player_start == Vector2i(1, 1), "本体起点 (1,1)", str(lv.player_start))
	_check(lv.shadow_start == Vector2i(3, 3), "影子起点 (3,3)", str(lv.shadow_start))
	_check(lv.exit_cell == Vector2i(5, 1), "出口 (5,1)", str(lv.exit_cell))
	_check(def["exit_needs"].is_empty(), "出口无开启条件")
	_check(lv.plates.is_empty() and lv.doors.is_empty() and lv.keys.is_empty(),
		"无压力板 / 门 / 钥匙")


func _test_03_level2_data() -> void:
	print("\n[3] 第二关数据与策划一致")
	var def: Dictionary = Levels.DATA[1]
	var lv := LevelData.from_ascii(def["name"], def["map"], def["exit_needs"])

	_check(lv.is_valid(), "第 2 关合法", ", ".join(lv.errors))
	_check(lv.width == 9 and lv.height == 5, "9×5", "%dx%d" % [lv.width, lv.height])
	_check(lv.player_start == Vector2i(1, 1), "本体起点 (1,1)", str(lv.player_start))
	_check(lv.shadow_start == Vector2i(3, 3), "影子起点 (3,3)", str(lv.shadow_start))
	_check(lv.exit_cell == Vector2i(7, 1), "出口 (7,1)", str(lv.exit_cell))
	_check(lv.plates.get(Vector2i(4, 1), "") == "a", "压力板 a 在 (4,1)")
	_check(lv.plates.get(Vector2i(6, 3), "") == "b", "压力板 b 在 (6,3)")
	_check(lv.plates.size() == 2, "恰好两块压力板", str(lv.plates.size()))
	_check(lv.exit_needs == ["a", "b"], "出口需要 a 与 b", str(lv.exit_needs))
	_check(lv.keys.is_empty() and lv.doors.is_empty(), "不含钥匙与锁门")


func _test_04_has_next() -> void:
	print("\n[4] 关卡推进判定")
	_check(Levels.has_next(0), "第 1 关之后还有一关")
	_check(not Levels.has_next(1), "第 2 关是最后一关")
	_check(not Levels.has_next(2), "越界索引不算有下一关")
	_check(not Levels.has_next(-1), "负索引不算有下一关")


func _test_05_fixture_not_in_data() -> void:
	print("\n[5] 机关测试室不在正式关卡列表里")
	var fixture_name: String = Levels.FIXTURE_MECHANISMS["name"]
	var found := false
	for def in Levels.DATA:
		if def["name"] == fixture_name:
			found = true
	_check(not found, "DATA 里没有「%s」" % fixture_name)
	_check(Levels.FIXTURE_MECHANISMS["map"].size() == 5, "测试室数据本身仍在（未删除）")


# ------------------------------------------------------------------ B. 切换语义

func _test_06_level1_still_wins() -> void:
	print("\n[6] 第一关仍能 4 拍通关")
	var rs := _resolver_of(0)
	for i in 4:
		rs.step(Vector2i.RIGHT)
	_check(rs.player == Vector2i(5, 1), "本体到达出口", str(rs.player))
	_check(rs.won, "通关标记置位")
	_check(rs.turn == 4, "第 4 拍通关", str(rs.turn))


func _test_07_level2_starts_clean() -> void:
	print("\n[7] 进入第二关时状态完全干净（不继承第一关）")
	# 先把第 1 关打通，制造一堆"上一关的残留"
	var lv1 := _resolver_of(0)
	for i in 4:
		lv1.step(Vector2i.RIGHT)
	_check(lv1.won and lv1.turn == 4 and lv1.pending == Vector2i.RIGHT, "第 1 关处于通关态")

	# 正式流程里切关就是新建一个 resolver
	var lv2 := _resolver_of(1)
	print("    %s" % str(lv2.state()))

	_check(lv2.turn == 0, "回合数归零", str(lv2.turn))
	_check(lv2.pending == Vector2i.ZERO, "待执行方向已清空", str(lv2.pending))
	_check(not lv2.won, "通关状态没有残留")
	_check(lv2.player == Vector2i(1, 1), "本体在第二关起点", str(lv2.player))
	_check(lv2.shadow == Vector2i(3, 3), "影子在第二关起点", str(lv2.shadow))
	_check(not lv2.exit_open, "第二关出口初始关闭")
	_check(lv2.latched.is_empty(), "压力板无残留", str(lv2.latched))
	_check(not lv2.has_key and lv2.keys_left.is_empty(), "钥匙状态干净")
	_check(lv2.doors_open.is_empty(), "门状态干净")


# ------------------------------------------------------------------ C. 第二关机关

func _test_08_player_plate_a() -> void:
	print("\n[8] 本体踩到压力板 a")
	var rs := _resolver_of(1)
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(rs.player == Vector2i(4, 1), "本体站上 a (4,1)", str(rs.player))
	_check(rs.latched.has("a"), "a 已锁存", str(rs.latched))
	_check(r.plates_latched.has("a"), "本拍记录了锁存事件")


func _test_09_one_plate_not_enough() -> void:
	print("\n[9] 只踩一块板，出口不开")
	var rs := _resolver_of(1)
	for i in 3:
		rs.step(Vector2i.RIGHT)

	_check(rs.latched.has("a") and not rs.latched.has("b"), "只有 a", str(rs.latched))
	_check(not rs.exit_open, "出口仍然关闭")


func _test_10_shadow_plate_b() -> void:
	print("\n[10] 影子踩到压力板 b")
	var rs := _resolver_of(1)
	for i in 3:
		rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.UP)          # 本体撞墙不动，影子继续向右
	print("    %s" % str(r))

	_check(rs.player == Vector2i(4, 1), "本体被上墙挡住，留在 a 上", str(rs.player))
	_check(rs.shadow == Vector2i(6, 3), "影子走到 b (6,3)", str(rs.shadow))
	_check(rs.latched.has("b"), "b 已锁存", str(rs.latched))
	_check(r.plates_latched.has("b"), "本拍记录了 b 的锁存事件")


func _test_11_both_plates_open_exit() -> void:
	print("\n[11] 两块板都触发后出口开启")
	var rs := _resolver_of(1)
	for i in 3:
		rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.UP)

	_check(rs.latched.has("a") and rs.latched.has("b"), "a、b 均已锁存", str(rs.latched))
	_check(rs.exit_open, "出口已开启")
	_check(r.exit_opened, "本拍标记出口开启")


func _test_12_latch_survives_leaving() -> void:
	print("\n[12] 离开压力板后已开启状态不回退")
	var rs := _resolver_of(1)
	for i in 4:
		rs.step(Vector2i.RIGHT if i < 3 else Vector2i.UP)   # 到第 4 拍出口已开
	var r := rs.step(Vector2i.RIGHT)                        # 本体离开 a
	print("    %s" % str(r))

	_check(rs.player == Vector2i(5, 1), "本体已离开 a", str(rs.player))
	_check(rs.latched.has("a") and rs.latched.has("b"), "锁存仍在", str(rs.latched))
	_check(rs.exit_open, "出口仍开启")


func _test_13_full_solve_seven_steps() -> void:
	print("\n[13] 第二关最短解 R R R U R R R（7 拍）")
	var rs := _resolver_of(1)
	var seq := [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT,
		Vector2i.UP, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT]
	var last: TurnResolver.StepResult = null
	for d in seq:
		last = rs.step(d)
	print("    %s" % str(last))

	_check(rs.won, "通关")
	_check(rs.player == Vector2i(7, 1), "本体到达出口 (7,1)", str(rs.player))
	_check(rs.turn == 7, "第 7 拍通关", str(rs.turn))
	_check(last.won and last.on_exit, "最后一拍标记 won / on_exit")


func _test_14_no_move_after_win() -> void:
	print("\n[14] 通关后不能继续移动")
	var rs := _resolver_of(1)
	var seq := [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT,
		Vector2i.UP, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT]
	for d in seq:
		rs.step(d)

	var before := str(rs.state())
	var r := rs.step(Vector2i.LEFT)
	_check(r.refused, "输入被拒绝", str(r))
	_check(str(rs.state()) == before, "状态零变化", "%s vs %s" % [str(rs.state()), before])


func _test_15_reset_restores_level2() -> void:
	print("\n[15] 重置后两块板与出口恢复初始状态")
	var rs := _resolver_of(1)
	for i in 3:
		rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.UP)
	_check(rs.exit_open, "先确认出口已开")

	rs.reset()
	print("    %s" % str(rs.state()))

	_check(rs.latched.is_empty(), "压力板全部复位", str(rs.latched))
	_check(not rs.exit_open, "出口恢复关闭")
	_check(not rs.won, "通关标记清除")
	_check(rs.player == Vector2i(1, 1) and rs.shadow == Vector2i(3, 3), "角色回起点")
	_check(rs.turn == 0 and rs.pending == Vector2i.ZERO, "回合与待执行方向归零")
