extends Node2D
## 舞台：背景墙 + 独立门窗构件 + 独立物件（可消失/可变鬼）+ 窗外鬼影
## 全部挂在"世界坐标"上，跟着背景一起滚，不跟镜头走。

const VW := 1280.0
const VH := 720.0
const PERIOD := 2560.0
const FLOOR_Y := 640.0

# 门窗在周期内的位置（世界偏移）
const FIXTURES := [
	{"t": "door", "x": 210.0},
	{"t": "win", "x": 690.0},
	{"t": "door", "x": 1120.0},
	{"t": "win", "x": 1610.0},
	{"t": "door", "x": 2040.0},
	{"t": "win", "x": 2370.0},
]

var scroll := 0.0
var darkness := 0.30
var red_light := false
var wet := false
var flicker := 0.0
var shake := 0.0
var day := 0

var t_wall: Texture2D
var t_wall_f: Texture2D
var t_door: Texture2D
var t_win: Texture2D
var t_props := {}
var props: Array = []          # {"tex":Texture2D,"x":float,"h":float}
var win_flash: Array = []      # {"slot":int,"life":float,"max":float}

var t_wghost: Texture2D


func _ready() -> void:
	t_wall = load("res://assets/art/wall.png")
	t_wall_f = load("res://assets/art/wall_f.png")
	t_door = load("res://assets/art/door.png")
	t_win = load("res://assets/art/window.png")
	for wn in ["g03", "g02", "g04", "g06", "g09"]:
		var wp := "res://assets/art/%s.png" % wn
		if ResourceLoader.exists(wp):
			t_wghost = load(wp)
			break
	for n in ["prop_box", "prop_mop", "prop_chairs", "prop_ext", "prop_shoes", "obox", "ochair"]:
		var p := "res://assets/art/%s.png" % n
		if ResourceLoader.exists(p):
			t_props[n] = load(p)


func set_day(d: int) -> void:
	day = d
	props.clear()
	win_flash.clear()
	# 每格物件不同；第三日起部分物件"变成鬼"
	var layout: Array = [
		[["prop_ext", 140.0], ["prop_shoes", 380.0], ["prop_box", 900.0], ["prop_mop", 1300.0],
			["prop_chairs", 1760.0], ["prop_ext", 2260.0]],
		[["prop_mop", 150.0], ["prop_box", 470.0], ["prop_chairs", 960.0], ["prop_ext", 1420.0],
			["prop_shoes", 1900.0], ["prop_mop", 2320.0]],
		[["prop_box", 130.0], ["prop_chairs", 520.0], ["prop_mop", 1000.0], ["prop_ext", 1480.0],
			["prop_shoes", 1960.0], ["prop_box", 2380.0]],
		[["prop_chairs", 160.0], ["prop_box", 600.0], ["prop_ext", 1080.0], ["prop_mop", 1560.0],
			["prop_shoes", 2040.0], ["prop_chairs", 2400.0]],
		[["prop_mop", 120.0], ["prop_chairs", 640.0], ["prop_box", 1120.0], ["prop_shoes", 1580.0],
			["prop_ext", 2060.0], ["prop_mop", 2440.0]],
	][clampi(d, 0, 4)]

	for i in range(layout.size()):
		var nm: String = layout[i][0]
		var px: float = float(layout[i][1])
		# 第 3 日起，序号为偶数的物件换成"物件鬼"
		if d >= 2 and i % 2 == 0:
			if nm == "prop_box" and t_props.has("obox"):
				nm = "obox"
			elif nm == "prop_chairs" and t_props.has("ochair"):
				nm = "ochair"
		if not t_props.has(nm):
			continue
		var tx: Texture2D = t_props[nm]
		props.append({"tex": tx, "x": px, "h": float(tx.get_height())})


func _phase() -> float:
	return fposmod(scroll, PERIOD)


func fixture_screen_x(idx: int, k: int) -> float:
	return _phase() + k * PERIOD - PERIOD + float(FIXTURES[idx]["x"])


func visible_windows() -> Array:
	var out: Array = []
	for k in range(3):
		for i in range(FIXTURES.size()):
			if FIXTURES[i]["t"] != "win":
				continue
			var sx := fixture_screen_x(i, k)
			if sx > -60.0 and sx < VW + 60.0:
				out.append({"slot": i, "k": k, "x": sx})
	return out


func flash_window(slot_idx: int) -> void:
	win_flash.append({"slot": slot_idx % FIXTURES.size(), "life": 0.0, "max": 0.95})


func tick(s: float, dt: float) -> void:
	scroll = s
	var keep: Array = []
	for w in win_flash:
		w["life"] = float(w["life"]) + dt
		if float(w["life"]) < float(w["max"]):
			keep.append(w)
	win_flash = keep
	queue_redraw()


func _draw() -> void:
	var ox := randf_range(-shake, shake)
	var base := _phase() - PERIOD

	# 1) 背景墙（正 + 镜像交替，保证无缝）
	for k in range(3):
		var x := base + k * PERIOD + ox
		draw_texture_rect(t_wall, Rect2(x, 0, VW, VH), false)
		draw_texture_rect(t_wall_f, Rect2(x + VW, 0, VW, VH), false)

	# 2) 门窗构件（贴在墙上，随背景滚）
	for k in range(3):
		for i in range(FIXTURES.size()):
			var sx := fixture_screen_x(i, k) + ox
			if sx < -300.0 or sx > VW + 300.0:
				continue
			if FIXTURES[i]["t"] == "door":
				var dh := float(t_door.get_height())
				var dw := float(t_door.get_width())
				draw_texture_rect(t_door, Rect2(sx - dw * 0.5, FLOOR_Y - dh, dw, dh), false)
			else:
				var wh := float(t_win.get_height())
				var ww := float(t_win.get_width())
				draw_texture_rect(t_win, Rect2(sx - ww * 0.5, 470.0 - wh, ww, wh), false)

	# 3) 物件（同样随背景滚；第三人称就是"地上的东西"）
	for k in range(3):
		var x0 := base + k * PERIOD + ox
		for p in props:
			var px := x0 + float(p["x"])
			if px < -240.0 or px > VW + 240.0:
				continue
			var h := float(p["h"])
			var w := float(p["tex"].get_width())
			draw_texture_rect(p["tex"], Rect2(px, FLOOR_Y - h, w, h), false,
				Color(0.72, 0.74, 0.76, 1.0))

	# 5) 压暗 + 灯 + 积水
	var d := darkness
	if flicker > 0.01:
		d = clampf(d + flicker * 0.55, 0, 0.95)
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, d))
	if red_light:
		draw_rect(Rect2(0, 0, VW, VH), Color(0.34, 0.05, 0.04, 0.22))
	if wet:
		draw_rect(Rect2(0, VH - 130, VW, 130), Color(0.20, 0.28, 0.31, 0.20))
		var y := VH - 16.0
		while y > VH - 120.0:
			draw_rect(Rect2(0, y, VW, 1), Color(0.55, 0.66, 0.70, 0.055))
			y -= 19.0
	# 4.5) 窗外鬼影：压在窗上的逆光黑影，读作玻璃外面有人
	for w in win_flash:
		var slot := int(w["slot"])
		var t := float(w["life"]) / float(w["max"])
		var a := clampf(sin(clampf(t, 0, 1) * PI) * 1.6, 0.0, 1.0)
		for k in range(3):
			var sx := fixture_screen_x(slot, k) + ox
			if sx < -420.0 or sx > VW + 420.0:
				continue
			var hh := 200.0
			var ww := float(t_wghost.get_width()) / float(t_wghost.get_height()) * hh
			var sweep := (clampf(t, 0.0, 1.0) * 2.0 - 1.0) * 46.0
			draw_texture_rect(t_wghost,
				Rect2(sx + sweep - ww * 0.5, 452.0 - hh, ww, hh), false,
				Color(0.06, 0.08, 0.11, a * 0.90))

	# 底部近景暗带（渐变，避免硬边）
	for i in range(10):
		var t := float(i) / 9.0
		draw_rect(Rect2(0, VH - 150.0 + i * 15.0, VW, 15.5),
			Color(0, 0, 0, 0.03 + 0.52 * t * t))
