class_name InputRouter
extends Node

## 输入路由：把"按键"变成"每拍一个方向"，并保证回合不会被重复触发。
##
## 它解决三个具体问题：
##   1. 按住方向键时浏览器/系统会疯狂产生重复事件 —— 用 is_action_pressed 的
##      默认行为（allow_echo = false）把自动重复滤掉，一次按键只出一次方向。
##   2. 动画还在播时玩家又按键 —— 用回合锁挡住，最多缓存一格，不排队。
##   3. 重置 —— R 键随时可用，不受回合锁限制。
##
## 它不碰 TurnResolver 的任何规则，只负责"什么时候把方向交出去"。

signal direction_input(dir: Vector2i)
signal reset_requested()

const DIRS := {
	"move_up": Vector2i.UP,
	"move_down": Vector2i.DOWN,
	"move_left": Vector2i.LEFT,
	"move_right": Vector2i.RIGHT,
}

var locked := false                ## true = 本拍还在结算/播动画，不收新回合
var buffered := Vector2i.ZERO      ## 锁定期内缓存的方向（只有一格）
var overwritten := 0               ## 缓存被后来者覆盖的次数，仅用于调试观察


func _unhandled_input(event: InputEvent) -> void:
	# R：随时可重置，不看回合锁
	if event.is_action_pressed("reset_level"):
		_mark_handled()
		reset_requested.emit()
		return

	for action in DIRS:
		if event.is_action_pressed(action):
			_mark_handled()
			request(DIRS[action])
			return


## 提交一个方向意图。锁着就存进缓存（覆盖旧的），否则立刻发出。
func request(dir: Vector2i) -> void:
	if locked:
		if buffered != Vector2i.ZERO:
			overwritten += 1
		buffered = dir
		return
	_fire(dir)


## 一拍播完，由外部调用：解锁，并把缓存的那一格发出去
func turn_finished() -> void:
	locked = false
	if buffered != Vector2i.ZERO:
		var d := buffered
		buffered = Vector2i.ZERO
		_fire(d)


## 重置时调用：丢弃缓存并解锁（被打断的那一拍不会再回调）
func cancel_pending() -> void:
	locked = false
	buffered = Vector2i.ZERO


func _fire(dir: Vector2i) -> void:
	locked = true
	direction_input.emit(dir)


func _mark_handled() -> void:
	# 不在场景树里时（无头测试）没有 viewport，跳过即可
	if is_inside_tree():
		get_viewport().set_input_as_handled()
