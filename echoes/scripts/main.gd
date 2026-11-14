extends Node2D

## 启动入口与流程编排：把「输入 → 规则 → 画面」三块接起来。
## 这里只管接线，不写规则（规则在 TurnResolver），也不写绘制（在 WorldView）。

const SHOT_PREFIX := "--shot="
const KEYS_PREFIX := "--keys="
const DELAY_PREFIX := "--keydelay="

## 通关后自动进入下一关的等待时长（秒）
const AUTO_ADVANCE_SEC := 1.0

@onready var world: WorldView = $World
@onready var router: InputRouter = $InputRouter
@onready var debug_label: Label = $UI/Debug
@onready var win_overlay: Control = $UI/WinOverlay
@onready var win_title_label: Label = $UI/WinOverlay/Center/Box/Title
@onready var win_level_label: Label = $UI/WinOverlay/Center/Box/Level
@onready var win_hint_label: Label = $UI/WinOverlay/Center/Box/Hint

var resolver: TurnResolver = null
var level_index := 0
var is_fixture := false
var _last_result: TurnResolver.StepResult = null
var _chapter_end := false        ## true = 最后一关已通关，处于"章节结束"界面
var _advance_token := 0          ## 自动切关令牌；任何重置/切关都会让它失效


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#0e0e12"))

	router.direction_input.connect(_on_direction_input)
	router.reset_requested.connect(_on_reset_requested)
	world.step_animation_finished.connect(_on_step_animation_finished)

	# 调试标签只在 Debug 构建显示
	debug_label.visible = _dev_tools()
	print("[build] debug_build=%s dev_tools=%s debug_label=%s" % [
		str(OS.is_debug_build()), str(_dev_tools()), str(debug_label.visible)
	])

	# --fixture：加载开发自检用的机关测试室（不是正式关卡）。
	# Release 构建里 _dev_tools() 为 false，即使传了参数也只会进正式第 1 关。
	if _dev_tools() and _has_user_arg("--fixture"):
		start_fixture()
	else:
		start_level(0)

	_capture_if_requested()


## 载入一关正式关卡
func start_level(index: int) -> void:
	_load(Levels.DATA[index], index, false)


## 载入机关测试室（仅开发自检用）
func start_fixture() -> void:
	_load(Levels.FIXTURE_MECHANISMS, 0, true)


func _load(def: Dictionary, index: int, fixture: bool) -> void:
	level_index = index
	is_fixture = fixture
	_chapter_end = false
	_advance_token += 1        # 让任何在途的自动切关失效
	_hide_win()
	_last_result = null

	if not world.load_def(def):
		debug_label.text = "LEVEL DATA ERROR - see console"
		resolver = null
		return

	resolver = TurnResolver.from_level(world.level)
	world.sync_from(resolver)          # 视图只读模型，机关状态由这里灌进去
	world.snap_actors(resolver.player, resolver.shadow)
	router.cancel_pending()
	_update_debug_label()

	var lv := world.level
	print("[init] 关卡=%s 网格=%d×%d 图块=%dpx 视口=%s" % [
		lv.level_name, lv.width, lv.height, Grid.TILE, get_viewport_rect().size
	])
	print("[init] 本体=%s 影子=%s 出口=%s 出口已开启=%s 钥匙=%s 门=%s 板=%s" % [
		str(resolver.player), str(resolver.shadow), str(lv.exit_cell),
		str(resolver.exit_open), str(lv.keys.keys()), str(lv.doors.keys()), str(lv.plates.keys())
	])


func _on_direction_input(dir: Vector2i) -> void:
	if resolver == null:
		return

	# 已通关：吃掉这次输入（不再推进回合，也不播动画）。
	# 必须解锁，否则路由器会一直锁在"等待回调"的状态。
	if resolver.won:
		router.cancel_pending()
		return

	_last_result = resolver.step(dir)
	world.sync_from(resolver)          # 门/钥匙/压板/出口立刻反映到画面
	if OS.is_debug_build():
		print("[turn] %s" % str(_last_result))

	world.animate_step(_last_result)


## 一拍动画播完：先判胜，再解锁
func _on_step_animation_finished() -> void:
	# 顺序很重要：turn_finished() 可能立刻开出下一拍并覆盖 _last_result
	if _last_result != null and _last_result.won:
		_show_win()
		router.cancel_pending()
		_update_debug_label()
		return

	router.turn_finished()
	_update_debug_label()


func _on_reset_requested() -> void:
	if resolver == null:
		return

	_advance_token += 1             # 取消在途的自动切关（1 秒内按 R 不会被强行带走）

	# 章节结束界面：R = 回到第 1 关重新开始
	if _chapter_end:
		print("[reset] 章节结束 → 回到第 1 关")
		start_level(0)
		return

	world.stop_animation()          # 打断动画，回调不会再触发
	resolver.reset()                # 位置 / 方向 / 回合 / 钥匙 / 门 / 压力板 / 出口 / 通关 全部归零
	world.sync_from(resolver)
	world.snap_actors(resolver.player, resolver.shadow)
	router.cancel_pending()         # 丢弃缓存并解锁
	_last_result = null
	_hide_win()
	_update_debug_label()
	print("[reset] 回到初始状态 %s" % str(resolver.state()))


func _show_win() -> void:
	win_level_label.text = "LEVEL %d COMPLETE" % (level_index + 1)
	_chapter_end = false

	if is_fixture:
		# 自检室不属于正式流程，通关就停在这里，不往下推
		win_title_label.text = "YOU WIN"
		win_hint_label.text = "PRESS R TO RESTART"
	elif Levels.has_next(level_index):
		win_title_label.text = "YOU WIN"
		win_hint_label.text = "NEXT LEVEL..."
		_schedule_next_level()
	else:
		# 最后一关：进入章节结束占位界面
		_chapter_end = true
		win_title_label.text = "CHAPTER COMPLETE"
		win_hint_label.text = "PRESS R TO RESTART"

	win_overlay.visible = true
	# 标题长度差异大（YOU WIN / CHAPTER COMPLETE），按长度调字号，避免长标题顶满屏幕
	win_title_label.add_theme_font_size_override(
		"font_size", 18 if win_title_label.text.length() <= 8 else 14
	)
	print("[win] 通关 %s 文案=%s 标题=%s" % [
		str(resolver.state()), win_level_label.text, win_title_label.text
	])


## 通关后等 AUTO_ADVANCE_SEC 秒自动进入下一关。
## 用令牌防止"上一关的回调把下一关带跑"：期间只要发生过重置或切关，令牌就变了。
func _schedule_next_level() -> void:
	_advance_token += 1
	var token := _advance_token
	await get_tree().create_timer(AUTO_ADVANCE_SEC).timeout

	if token != _advance_token:
		return                       # 期间按过 R 或已经切过关
	if resolver == null or not resolver.won:
		return                       # 状态已经不在通关点
	if not Levels.has_next(level_index):
		return

	print("[flow] 自动进入第 %d 关" % (level_index + 2))
	start_level(level_index + 1)


func _hide_win() -> void:
	win_overlay.visible = false


func _update_debug_label() -> void:
	if resolver == null:
		return
	# 屏显用 ASCII：Godot 内置字体没有中日韩字形
	var tag := "DEMO" if is_fixture else "L%d" % (level_index + 1)
	debug_label.text = "%s T%02d P%s S%s n=%s%s%s" % [
		tag, resolver.turn,
		str(resolver.player), str(resolver.shadow), _dir_char(resolver.pending),
		"  KEY" if resolver.has_key else "",
		"  WIN" if resolver.won else "",
	]


func _dir_char(d: Vector2i) -> String:
	if d == Vector2i.UP:
		return "U"
	if d == Vector2i.DOWN:
		return "D"
	if d == Vector2i.LEFT:
		return "L"
	if d == Vector2i.RIGHT:
		return "R"
	return "-"


# ------------------------------------------------------------------ 开发期自检
# 只在 Debug 构建可用；Release 导出后 _dev_tools() 为 false，整段全部失效
# （命令行传参也无效）。发布前可以选择性删除，保留也不会被玩家触发。

## 是否允许使用开发自检功能。
## Release 导出后 OS.is_debug_build() == false，所有开关自动失效。
func _dev_tools() -> bool:
	return OS.is_debug_build()


## 开发期：判断是否带了某个开关
func _has_user_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


## --shot=<路径>          渲染若干帧后截图并退出
## --keys=<序列>          截图前按顺序注入按键，用来验证一拍一拍的行为
##                        大写 U/D/L/R = 方向键，小写 w/a/s/d = 字母键，X = 重置
##                        "." = 停顿 1.3 秒（用于等待"通关后自动切关"）
func _capture_if_requested() -> void:
	# Release 构建：截图/注入按键全部禁用
	if not _dev_tools():
		return

	var path := ""
	var keys := ""
	var delay := 0.25
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SHOT_PREFIX):
			path = arg.substr(SHOT_PREFIX.length())
		elif arg.begins_with(KEYS_PREFIX):
			keys = arg.substr(KEYS_PREFIX.length())
		elif arg.begins_with(DELAY_PREFIX):
			delay = arg.substr(DELAY_PREFIX.length()).to_float()
	if path.is_empty():
		return

	# 保底：20 秒后无论如何退出，避免命令行挂起
	get_tree().create_timer(20.0).timeout.connect(
		func() -> void: get_tree().quit(), CONNECT_ONE_SHOT
	)

	for ch in keys:
		if ch == ".":
			# 停顿：等自动切关发生（AUTO_ADVANCE_SEC = 1.0s，留 0.3s 余量）
			await get_tree().create_timer(1.3).timeout
			continue
		_tap(ch)
		await get_tree().create_timer(delay).timeout

	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[capture] %s size=%s err=%d" % [path, img.get_size(), err])
	get_tree().quit()


func _tap(ch: String) -> void:
	var code := 0
	match ch:
		"U": code = KEY_UP
		"D": code = KEY_DOWN
		"L": code = KEY_LEFT
		"R": code = KEY_RIGHT
		"w": code = KEY_W
		"a": code = KEY_A
		"s": code = KEY_S
		"d": code = KEY_D
		"X": code = KEY_R          # X = 重置（R 已经被"右"占用）
		_:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
