class_name LevelData
extends RefCounted

## 把 ASCII 关卡解析成网格 + 对象表，并在解析时做严格校验。
## 校验失败不会崩溃，而是把原因写进 errors，由调用方决定怎么报。

var level_name := ""
var width := 0
var height := 0

## cells[y][x] = Grid.Cell 常量
var cells: Array[PackedInt32Array] = []

var player_start := Vector2i.ZERO
var shadow_start := Vector2i.ZERO
var exit_cell := Vector2i(-1, -1)

var plates := {}   ## Vector2i -> String（"a" / "b" / "p"）
var doors := {}    ## Vector2i -> true
var keys := {}     ## Vector2i -> true
var exit_needs: Array[String] = []

var errors: Array[String] = []

const CHAR_MAP := {
	".": Grid.Cell.FLOOR,
	"#": Grid.Cell.WALL,
	"D": Grid.Cell.DOOR,
	"E": Grid.Cell.EXIT,
	"K": Grid.Cell.KEY,
	"a": Grid.Cell.PLATE,
	"b": Grid.Cell.PLATE,
	"p": Grid.Cell.PLATE,
	"P": Grid.Cell.FLOOR,
	"S": Grid.Cell.FLOOR,
}


static func from_ascii(p_name: String, rows: Array, p_exit_needs: Array = []) -> LevelData:
	var lv := LevelData.new()
	lv.level_name = p_name
	lv.exit_needs.assign(p_exit_needs)

	if rows.is_empty():
		lv.errors.append("地图为空")
		return lv

	# --- 第一步：行宽必须全部相等，否则后面所有坐标都是错的 ---
	var w: int = (rows[0] as String).length()
	for i in rows.size():
		var row: String = rows[i]
		if row.length() != w:
			lv.errors.append("第 %d 行宽度 %d，期望 %d —— 地图必须是矩形" % [i + 1, row.length(), w])
	if not lv.errors.is_empty():
		return lv

	# --- 第二步：逐字符建网格 ---
	lv.width = w
	lv.height = rows.size()
	var count_p := 0
	var count_s := 0
	var count_e := 0

	for y in lv.height:
		var row: String = rows[y]
		var line := PackedInt32Array()
		line.resize(w)
		for x in w:
			var ch := row[x]
			var c := Vector2i(x, y)
			if not CHAR_MAP.has(ch):
				lv.errors.append("第 %d 行第 %d 列出现未知字符 '%s'" % [y + 1, x + 1, ch])
				line[x] = Grid.Cell.WALL
				continue
			line[x] = CHAR_MAP[ch]
			match ch:
				"P":
					count_p += 1
					lv.player_start = c
				"S":
					count_s += 1
					lv.shadow_start = c
				"E":
					count_e += 1
					lv.exit_cell = c
				"D":
					lv.doors[c] = true
				"K":
					lv.keys[c] = true
				"a", "b", "p":
					lv.plates[c] = ch
		lv.cells.append(line)

	# --- 第三步：必备元素唯一性 ---
	if count_p != 1:
		lv.errors.append("本体起点 P 必须恰好 1 个，实际 %d 个" % count_p)
	if count_s != 1:
		lv.errors.append("影子起点 S 必须恰好 1 个，实际 %d 个" % count_s)
	if count_e != 1:
		lv.errors.append("出口 E 必须恰好 1 个，实际 %d 个" % count_e)

	# --- 第四步：出口要求的压力板必须真的存在 ---
	for id in lv.exit_needs:
		var found := false
		for c in lv.plates:
			if lv.plates[c] == id:
				found = true
				break
		if not found:
			lv.errors.append("出口条件引用了不存在的压力板 '%s'" % id)

	return lv


func is_valid() -> bool:
	return errors.is_empty()


## 越界一律当墙，避免每处都写边界判断
func cell(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return Grid.Cell.WALL
	return cells[c.y][c.x]


func size() -> Vector2i:
	return Vector2i(width, height)
