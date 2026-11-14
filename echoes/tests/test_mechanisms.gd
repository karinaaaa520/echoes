extends SceneTree

## 机关系统无头测试（P1-01）：钥匙 / 锁门 / 压力板 / 出口。
## 运行：godot --headless --path . --script res://tests/test_mechanisms.gd
## 退出码：0 = 全过，1 = 有失败

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== 机关系统 无头测试 ===")

	_test_01_player_picks_key()
	_test_02_shadow_cannot_pick_key()
	_test_03_door_needs_key()
	_test_04_bump_opens_but_no_move()
	_test_05_can_enter_next_turn()
	_test_06_player_plate()
	_test_07_shadow_plate()
	_test_08_plate_stays_latched()
	_test_09_closed_exit_no_win()
	_test_10_exit_opens_under_player()
	_test_11_shadow_on_exit_no_win()
	_test_12_reset_restores_mechanisms()

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


func _mk(rows: Array, needs: Array = []) -> TurnResolver:
	var lv := LevelData.from_ascii("t", rows, needs)
	if not lv.is_valid():
		_failed += 1
		print("  [FAIL] 测试地图非法：%s" % ", ".join(lv.errors))
	return TurnResolver.from_level(lv)


# ------------------------------------------------------------------ 钥匙

func _test_01_player_picks_key() -> void:
	print("\n[1] 玩家拾取钥匙")
	# #P.K.E#   P(1,1) K(3,1) E(5,1)
	var rs := _mk(["#######", "#P.K.E#", "#.....#", "#..S..#", "#######"])
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(rs.player == Vector2i(3, 1), "本体走到钥匙格 (3,1)", str(rs.player))
	_check(r.key_taken, "本拍标记拾取钥匙")
	_check(rs.has_key, "已持钥匙")
	_check(rs.keys_left.is_empty(), "地上钥匙已消失", str(rs.keys_left))


func _test_02_shadow_cannot_pick_key() -> void:
	print("\n[2] 影子从钥匙上走过，不能拾取")
	# 影子 (3,3) 向右走到 (4,3) 的钥匙上
	var rs := _mk(["#######", "#P...E#", "#.....#", "#..SK.#", "#######"])
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(rs.shadow == Vector2i(4, 3), "影子站在钥匙格 (4,3) 上", str(rs.shadow))
	_check(rs.keys_left.has(Vector2i(4, 3)), "钥匙仍在地上", str(rs.keys_left))
	_check(not rs.has_key, "影子没有把钥匙给本体")
	_check(not r.key_taken, "本拍没有拾取事件")


# ------------------------------------------------------------------ 锁门

func _test_03_door_needs_key() -> void:
	print("\n[3] 没有钥匙开不了锁门")
	# #P.D.E#   P(1,1) D(3,1) E(5,1)
	var rs := _mk(["#######", "#P.D.E#", "#.....#", "#..S..#", "#######"])
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(r.door_blocked, "本拍标记撞到锁门且无钥匙")
	_check(not rs.doors_open.has(Vector2i(3, 1)), "门仍然关着", str(rs.doors_open))
	_check(rs.player == Vector2i(2, 1), "本体停在门外 (2,1)", str(rs.player))
	_check(r.turn == 2, "回合照常推进", str(r.turn))


func _test_04_bump_opens_but_no_move() -> void:
	print("\n[4] 有钥匙撞门：本拍只开门，不移动")
	# #PKD.E#   P(1,1) K(2,1) D(3,1) E(5,1)
	var rs := _mk(["#######", "#PKD.E#", "#.....#", "#..S..#", "#######"])
	rs.step(Vector2i.RIGHT)                 # 走到 (2,1) 拿钥匙
	_check(rs.has_key, "先拿到钥匙")

	var r := rs.step(Vector2i.RIGHT)        # 撞门
	print("    %s" % str(r))

	_check(r.door_opened, "本拍标记开门")
	_check(rs.doors_open.has(Vector2i(3, 1)), "门已开启", str(rs.doors_open))
	_check(not r.player_moved, "本体这一步没有移动")
	_check(rs.player == Vector2i(2, 1), "本体仍站在门外 (2,1)", str(rs.player))
	_check(not rs.has_key, "开门消耗了钥匙")


func _test_05_can_enter_next_turn() -> void:
	print("\n[5] 下一拍可以进入已开启的门")
	var rs := _mk(["#######", "#PKD.E#", "#.....#", "#..S..#", "#######"])
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.RIGHT)                 # 开门，不移动
	var r := rs.step(Vector2i.RIGHT)        # 进门
	print("    %s" % str(r))

	_check(r.player_moved, "本体移动了")
	_check(rs.player == Vector2i(3, 1), "本体进入门格 (3,1)", str(rs.player))
	_check(not r.door_blocked, "没有被门挡住")


# ------------------------------------------------------------------ 压力板

func _test_06_player_plate() -> void:
	print("\n[6] 玩家踩压力板触发")
	# #P..a.# / #....E#   出口要踩 a
	var rs := _mk(["#######", "#P..a.#", "#....E#", "#..S..#", "#######"], ["a"])
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(rs.player == Vector2i(4, 1), "本体站上压力板 a", str(rs.player))
	_check(rs.latched.has("a"), "压力板已锁存", str(rs.latched))
	_check(r.plates_latched.has("a"), "本拍记录了锁存事件")
	_check(rs.exit_open, "出口随之开启")
	_check(r.exit_opened, "本拍标记出口开启")


func _test_07_shadow_plate() -> void:
	print("\n[7] 影子踩压力板同样触发")
	# 影子 (3,3) 向右走到 (5,3) 的板 a；本体走另一条路
	var rs := _mk(["#######", "#P...E#", "#.....#", "#..S.a#", "#######"], ["a"])
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(rs.shadow == Vector2i(5, 3), "影子站上压力板 a", str(rs.shadow))
	_check(rs.player != Vector2i(5, 3), "不是本体踩的")
	_check(rs.latched.has("a"), "压力板已锁存")
	_check(rs.exit_open, "出口开启")


func _test_08_plate_stays_latched() -> void:
	print("\n[8] 离开压力板后仍然保持开启")
	var rs := _mk(["#######", "#P..a.#", "#....E#", "#..S..#", "#######"], ["a"])
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.RIGHT)
	rs.step(Vector2i.RIGHT)                 # 踩上 a
	var r := rs.step(Vector2i.DOWN)         # 离开板
	print("    %s" % str(r))

	_check(rs.player == Vector2i(4, 2), "本体已离开压力板", str(rs.player))
	_check(rs.latched.has("a"), "锁存依然存在")
	_check(rs.exit_open, "出口依然开启")


# ------------------------------------------------------------------ 出口

func _test_09_closed_exit_no_win() -> void:
	print("\n[9] 出口未开启时站在上面不算通关")
	# #P.E.a#   P(1,1) E(3,1) a(5,1)，出口要求 a 但没人踩
	var rs := _mk(["#######", "#P.E.a#", "#.....#", "#..S..#", "#######"], ["a"])
	rs.step(Vector2i.RIGHT)
	var r := rs.step(Vector2i.RIGHT)
	print("    %s" % str(r))

	_check(rs.player == Vector2i(3, 1), "本体站在出口格上（允许站的）", str(rs.player))
	_check(r.on_exit, "本拍标记 on_exit")
	_check(not rs.exit_open, "出口仍是关闭的")
	_check(not rs.won, "不算通关")


func _test_10_exit_opens_under_player() -> void:
	print("\n[10] 出口开启时玩家已经站在出口格上 → 立即通关")
	# #E.a..#   E(1,1) a(3,1)
	# #P.S..#   P(1,3) S(3,3)
	# 本体向上走到出口（此时关着），继续撞墙留在原地；影子一路向上，第 3 拍踩到 a
	var rs := _mk(["#######", "#E.a..#", "#.....#", "#P.S..#", "#######"], ["a"])

	var r1 := rs.step(Vector2i.UP)
	_check(r1.shadow_to == Vector2i(3, 3), "第 1 拍影子还没有历史指令，不动", str(r1.shadow_to))

	var r2 := rs.step(Vector2i.UP)
	print("    T2 %s" % str(r2))
	_check(rs.player == Vector2i(1, 1), "第 2 拍本体站在出口格上", str(rs.player))
	_check(r2.on_exit and not r2.won, "出口还没开，先不通关")

	var r3 := rs.step(Vector2i.UP)
	print("    T3 %s" % str(r3))
	_check(rs.shadow == Vector2i(3, 1), "第 3 拍影子踩到压力板 a", str(rs.shadow))
	_check(rs.player == Vector2i(1, 1), "本体一直停在出口格上（撞墙）", str(rs.player))
	_check(rs.exit_open, "出口在本拍开启")
	_check(r3.won and rs.won, "同一拍立即判定通关")


func _test_11_shadow_on_exit_no_win() -> void:
	print("\n[11] 影子站在出口上不触发通关")
	# #P.E..#   P(1,1) E(3,1)；影子 (3,3) 一路向上走到出口
	var rs := _mk(["#######", "#P.E..#", "#.....#", "#..S..#", "#######"])
	for i in 3:
		rs.step(Vector2i.UP)
	print("    %s" % str(rs.state()))

	_check(rs.shadow == Vector2i(3, 1), "影子站在出口格上", str(rs.shadow))
	_check(rs.player != rs.level.exit_cell, "本体不在出口", str(rs.player))
	_check(not rs.won, "不触发通关")


# ------------------------------------------------------------------ 重置

func _test_12_reset_restores_mechanisms() -> void:
	print("\n[12] 重置后钥匙、门、压力板、出口全部恢复")
	var rs := _mk(Levels.FIXTURE_MECHANISMS["map"], Levels.FIXTURE_MECHANISMS["exit_needs"])
	print("    起始 %s" % str(rs.state()))
	_check(not rs.exit_open, "开局出口关闭")

	# 拾钥匙 → 撞门开门 → 进门 → 踩板
	for i in 6:
		rs.step(Vector2i.RIGHT)
	print("    六拍后 %s" % str(rs.state()))
	_check(rs.latched.has("a"), "压力板已锁存")
	_check(rs.doors_open.has(Vector2i(5, 1)), "门已开启")
	_check(rs.exit_open, "出口已开启")
	_check(rs.keys_left.is_empty(), "钥匙已被取走")
	_check(not rs.has_key, "钥匙已被门消耗")

	rs.reset()
	print("    重置后 %s" % str(rs.state()))

	_check(rs.keys_left.size() == 1, "钥匙回到地上", str(rs.keys_left.keys()))
	_check(not rs.has_key, "不再持钥匙")
	_check(rs.doors_open.is_empty(), "门恢复关闭", str(rs.doors_open))
	_check(rs.latched.is_empty(), "压力板恢复未触发", str(rs.latched))
	_check(not rs.exit_open, "出口恢复关闭")
	_check(not rs.won, "通关标记清除")
	_check(rs.player == Vector2i(1, 1) and rs.shadow == Vector2i(3, 3), "角色回起点")
	_check(rs.turn == 0, "回合归零")
