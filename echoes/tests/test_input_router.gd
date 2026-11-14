extends SceneTree

## InputRouter 无头单元测试。
## 运行：godot --headless --path . --script res://tests/test_input_router.gd
## 退出码：0 = 全过，1 = 有失败

var _passed := 0
var _failed := 0
var _log: Array[Vector2i] = []
var _resets := 0
var _routers: Array[InputRouter] = []


func _initialize() -> void:
	print("=== InputRouter 无头测试 ===")

	_test_01_immediate_when_unlocked()
	_test_02_buffer_keeps_only_last()
	_test_03_turn_finished_flushes_buffer()
	_test_04_mashing_does_not_queue()
	_test_05_cancel_pending()
	_test_06_arrow_keys()
	_test_07_wasd_keys()
	_test_08_reset_key()
	_test_09_echo_is_ignored()

	_cleanup()
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


func _new_router() -> InputRouter:
	_log.clear()
	_resets = 0
	var r := InputRouter.new()
	r.direction_input.connect(func(d: Vector2i) -> void: _log.append(d))
	r.reset_requested.connect(func() -> void: _resets += 1)
	_routers.append(r)
	return r


func _key(code: int, echo: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = true
	ev.echo = echo
	return ev


func _cleanup() -> void:
	for r in _routers:
		if is_instance_valid(r):
			r.free()
	_routers.clear()


# ------------------------------------------------------------------ 测试

func _test_01_immediate_when_unlocked() -> void:
	print("\n[1] 未锁定时，方向立刻发出")
	var r := _new_router()
	r.request(Vector2i.RIGHT)
	_check(_log.size() == 1 and _log[0] == Vector2i.RIGHT, "发出一次 RIGHT", str(_log))
	_check(r.locked, "发出后自动上锁")


func _test_02_buffer_keeps_only_last() -> void:
	print("\n[2] 锁定期间只缓存一格，后按的覆盖先按的")
	var r := _new_router()
	r.request(Vector2i.RIGHT)      # 发出并上锁
	r.request(Vector2i.UP)
	r.request(Vector2i.DOWN)
	r.request(Vector2i.LEFT)
	_check(_log.size() == 1, "锁定期间没有再发新方向", str(_log))
	_check(r.buffered == Vector2i.LEFT, "缓存里只留最后一个 LEFT", str(r.buffered))
	_check(r.overwritten == 2, "记录到 2 次覆盖", str(r.overwritten))


func _test_03_turn_finished_flushes_buffer() -> void:
	print("\n[3] turn_finished() 解锁并补发缓存的方向")
	var r := _new_router()
	r.request(Vector2i.RIGHT)
	r.request(Vector2i.UP)
	r.turn_finished()
	_check(_log.size() == 2 and _log[1] == Vector2i.UP, "补发了 UP", str(_log))
	_check(r.locked, "补发后又上锁（新回合开始）")
	_check(r.buffered == Vector2i.ZERO, "缓存已清空")


func _test_04_mashing_does_not_queue() -> void:
	print("\n[4] 锁定期间狂按 10 次，只会补发 1 步")
	var r := _new_router()
	r.request(Vector2i.RIGHT)
	for i in 10:
		r.request(Vector2i.RIGHT)
	_check(_log.size() == 1, "锁定期间一次都没多发", str(_log.size()))
	r.turn_finished()
	_check(_log.size() == 2, "解锁后只补发 1 步", str(_log.size()))
	r.turn_finished()
	_check(_log.size() == 2, "再解锁也不会凭空多出输入", str(_log.size()))


func _test_05_cancel_pending() -> void:
	print("\n[5] cancel_pending() 清空缓存并解锁（重置时用）")
	var r := _new_router()
	r.request(Vector2i.RIGHT)
	r.request(Vector2i.UP)
	r.cancel_pending()
	_check(not r.locked, "已解锁")
	_check(r.buffered == Vector2i.ZERO, "缓存已清空")
	r.request(Vector2i.DOWN)
	_check(_log.size() == 2 and _log[1] == Vector2i.DOWN,
		"新输入立刻生效，不会补发旧缓存", str(_log))


func _test_06_arrow_keys() -> void:
	print("\n[6] 方向键映射")
	var pairs := [[KEY_UP, Vector2i.UP], [KEY_DOWN, Vector2i.DOWN],
		[KEY_LEFT, Vector2i.LEFT], [KEY_RIGHT, Vector2i.RIGHT]]
	for p in pairs:
		var r := _new_router()
		r._unhandled_input(_key(p[0]))
		_check(_log.size() == 1 and _log[0] == p[1],
			"%s → %s" % [OS.get_keycode_string(p[0]), str(p[1])], str(_log))


func _test_07_wasd_keys() -> void:
	print("\n[7] WASD 映射")
	var pairs := [[KEY_W, Vector2i.UP], [KEY_S, Vector2i.DOWN],
		[KEY_A, Vector2i.LEFT], [KEY_D, Vector2i.RIGHT]]
	for p in pairs:
		var r := _new_router()
		r._unhandled_input(_key(p[0]))
		_check(_log.size() == 1 and _log[0] == p[1],
			"%s → %s" % [OS.get_keycode_string(p[0]), str(p[1])], str(_log))


func _test_08_reset_key() -> void:
	print("\n[8] R 键触发重置，且不受回合锁限制")
	var r := _new_router()
	r._unhandled_input(_key(KEY_R))
	_check(_resets == 1, "未锁定状态下 R 触发重置", str(_resets))
	_check(_log.is_empty(), "R 不产生方向输入", str(_log))

	r.request(Vector2i.RIGHT)      # 上锁
	r._unhandled_input(_key(KEY_R))
	_check(_resets == 2, "锁定状态下 R 依然有效", str(_resets))
	_check(r.locked, "R 没有擅自解开当前回合的锁")


func _test_09_echo_is_ignored() -> void:
	print("\n[9] 按住不放产生的自动重复（echo）被过滤")
	var r := _new_router()
	r._unhandled_input(_key(KEY_W))
	_check(_log.size() == 1, "第一次按下有效", str(_log))
	r.cancel_pending()
	r._unhandled_input(_key(KEY_W, true))
	_check(_log.size() == 1, "echo 事件不产生新输入", str(_log))
