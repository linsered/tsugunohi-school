extends Node2D
## 放学后·逢魔之时 —— 主控
## 规则：只有 ← 一个键；向左走；一天固定走过 10 个不同的行人，逐日腐化成鬼。

const VW := 1280.0
const VH := 720.0
const PLAYER_X := 700.0
const PLAYER_BOTTOM := 790.0
const CHAR_H := 430.0
const SPRITE_SINK := 16.0
const WALK_SPEED := 108.0

const DAY_LEN := [4700.0, 4900.0, 5100.0, 5300.0, 5500.0]
const SCARE_POOL := ["res://assets/art/j_blank.png", "res://assets/art/js_a.png",
	"res://assets/art/js_b.png", "res://assets/art/js_c.png",
	"res://assets/art/s1.png", "res://assets/art/s2.png", "res://assets/art/s3.png"]
const CORNER_POOL := ["res://assets/art/f_ghost_tilt.png", "res://assets/art/f_ghost_veil.png"]
const SAVE_PATH := "user://ending.cfg"

# 结局判定阈值（互斥，按顺序优先）
const MIRROR_LIMIT := 2.6      # 第五日镜面区停留 >= 此值 → 留下
const BLINK_LIMIT := 15.0     # 连续静止 >= 此值 → 闭眼
const IDLE_PURE := 5.0         # 全程累计驻足 <= 此值 → 逢魔
const ENDINGS := [
	{"id": "taken", "name": "留 下", "hint": "第五日，在走廊尽头停下超过 2.6 秒"},
	{"id": "blink", "name": "闭 眼", "hint": "一直站着不动，超过 15 秒"},
	{"id": "normal", "name": "放 学", "hint": "走完五天，以上都没有发生"},
]
const DARK := [0.34, 0.44, 0.54, 0.66, 0.72]
const GHOST_MASK := [
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 1, 0, 0, 1, 0, 0, 1, 0],
	[0, 1, 0, 1, 0, 0, 1, 0, 1, 0],
	[1, 0, 1, 0, 1, 1, 0, 1, 0, 1],
	[1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
]

enum St { TITLE, GALLERY, CARD, PLAY, END }

var st: St = St.TITLE
var day := 0
var scroll := 0.0
var walking := false
var total_idle := 0.0
var mirror_timer := 0.0
var in_mirror := false
var busy := false
var ending := ""
var anim_t := 0.0
var step_t := 0.0
var ev_list: Array = []
var ev_i := 0
var ped_next := 0
var ped_t := 0.0
var forced_stop := 0.0
var scare_pool: Array = []
var run_idle := 0.0
var run_mirror := 0.0
var still_time := 0.0
var person_ghost: Array = []
var humans: Array = []
var ghosts: Array = []
var unlocked := {}
var menu_index := 0
var menu_labels: Array = []
var menu_buttons: Array = []
var gallery_back: Button
var gallery_labels: Array = []
var k_now := {}
var k_prev := {}
var corner_t := 26.0
var sub_tw: Tween
var hint_tw: Tween
var card_tw: Tween
var lid_top: ColorRect
var lid_bottom: ColorRect
var anchored: Array = []
var dev_mode := false
var verify_mode := false
var autoplay := false

var stage: Node2D
var player: Sprite2D
var peds: Array = []
var crowd_n: Array = []
var crowd_g: Array = []
var day_queue: Array = []

var ui: CanvasLayer
var art: TextureRect
var flash: ColorRect
var fade: ColorRect
var scare: TextureRect
var card_root: Control
var card_big: Label
var card_bleed: Label
var card_small: Label
var sub: Label
var hint: Label
var end_text: Label
var title_root: Control
var title_big: Label
var title_small: Label
var title_hint: Label

# 移动端触摸控制
var is_mobile := false
var touch_left := false          # ← 箭头是否被按住
var touch_root: Control
var touch_left_btn: Button

var font_ui: FontFile
var font_serif: FontFile
var tex := {}
var sb := {}
var amb: AudioStreamPlayer
var sfx: Array[AudioStreamPlayer] = []
var sfx_i := 0

const DAYS := [
	{"big": "第一日", "small": "十月十二日（星期一）　晴", "time": "放学后　16:47", "amb": "amb_day"},
	{"big": "第二日", "small": "十月十三日（星期二）　阴", "time": "放学后　17:02", "amb": "amb_day"},
	{"big": "笫三日", "small": "十月十四日（星期三）　雨", "time": "放学后　17:20", "amb": "amb_dusk"},
	{"big": "笫四曰", "small": "十月十五日（星期四）　雨", "time": "放学后　18:31", "amb": "amb_dusk"},
	{"big": "笫五曰", "small": "十月十六日（星期五）　——", "time": "放学后　　　——", "amb": "amb_night"},
]


func _ready() -> void:
	randomize()
	# 移动端检测：原生 mobile，或设备支持触摸（覆盖手机/平板浏览器，含横屏）
	# Web 上优先用浏览器 API 判断（比 Godot 触摸检测更可靠、更早生效）
	is_mobile = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	if OS.has_feature("web"):
		var touch_web: Variant = JavaScriptBridge.eval(
			"(navigator.maxTouchPoints > 0 || 'ontouchstart' in window) ? 1 : 0")
		if int(touch_web) == 1:
			is_mobile = true
	var a := OS.get_cmdline_args()
	var ua := OS.get_cmdline_user_args()
	dev_mode = a.has("--shots") or ua.has("--shots")
	verify_mode = a.has("--verify") or ua.has("--verify")
	autoplay = a.has("--autoplay") or ua.has("--autoplay")
	# --mobile 强制移动端模式，便于在桌面调试触摸按钮
	if a.has("--mobile") or ua.has("--mobile"):
		is_mobile = true

	for p in ["res://assets/art/p.png", "res://assets/art/wall.png"]:
		tex[p] = load(p)
	for nm in ["gf", "gj", "gbo", "x2", "x3"]:
		var gp := "res://assets/art/%s.png" % nm
		if ResourceLoader.exists(gp):
			tex[nm] = load(gp)
			crowd_g.append(nm)
	for i in range(1, 10):
		for pre in ["n", "g"]:
			var nm := "%s%02d" % [pre, i]
			var pth := "res://assets/art/%s.png" % nm
			if ResourceLoader.exists(pth):
				tex[nm] = load(pth)
				if pre == "n":
					crowd_n.append(nm)
				else:
					crowd_g.append(nm)
	for i in range(1, 5):
		var xp := "res://assets/art/x%d.png" % i
		if ResourceLoader.exists(xp):
			tex["x%d" % i] = load(xp)
	for sp in SCARE_POOL:
		if ResourceLoader.exists(sp):
			tex[sp] = load(sp)
	for cp in CORNER_POOL:
		if ResourceLoader.exists(cp):
			tex[cp] = load(cp)
	humans = crowd_n.duplicate()
	ghosts = crowd_g.duplicate()
	_load_progress()
	for nm in ["friend", "friend_g", "b1", "b2", "b3"]:
		var fp := "res://assets/art/%s.png" % nm
		if ResourceLoader.exists(fp):
			tex[nm] = load(fp)
	for nm in ["gb_1", "gb_2", "gb_3"]:
		if ResourceLoader.exists("res://assets/art/%s.png" % nm):
			tex[nm] = load("res://assets/art/%s.png" % nm)
	for n in ["amb_day", "amb_dusk", "amb_night", "amb_void", "step1", "step2", "step3", "step4",
			"hum_light", "bell", "musicbox", "heartbeat", "door", "stinger", "whisper", "drip", "scrape"]:
		sb[n] = load("res://assets/audio/%s.wav" % n)

	# 内嵌 Noto SC 子集字体（可分发），Web 导出与无系统字体环境都能正确显示中文
	font_ui = _font("res://assets/fonts/ui.ttf", "C:/Windows/Fonts/ui.ttf")
	font_serif = _font("res://assets/fonts/serif.ttf", "C:/Windows/Fonts/serif.ttf")
	if font_ui == null:
		font_ui = _font("res://assets/fonts/msyh.ttc", "C:/Windows/Fonts/msyh.ttc")
	if font_serif == null:
		font_serif = font_ui

	_build()
	_build_ui()
	_build_audio()
	_enter_title()
	if verify_mode:
		_verify_run()
	elif dev_mode:
		_dev_run()


func _font(res: String, abs_path: String) -> FontFile:
	# 优先用 load()：Godot 已把 ttf 导入为 .fontdata 资源，导出包里源文件不存在，
	# load() 会按 .import 的 remap 取到导入资源；load_dynamic_font 直接读源文件路径会失败。
	if ResourceLoader.exists(res):
		var loaded := load(res)
		if loaded is FontFile:
			return loaded
	var f := FontFile.new()
	if f.load_dynamic_font(abs_path) == OK:
		return f
	return null


func _build() -> void:
	stage = load("res://scripts/stage.gd").new()
	add_child(stage)
	stage.tick(0, 0.0)

	player = _mk_sprite("res://assets/art/p.png", CHAR_H)
	add_child(player)
	player.position = Vector2(PLAYER_X, PLAYER_BOTTOM)


func _mk_sprite(path: String, h: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex.get(path, load(path))
	s.centered = false
	var tw := float(s.texture.get_width())
	var th := float(s.texture.get_height())
	var sc := h / th
	s.scale = Vector2(sc, sc)
	s.offset = Vector2(-tw * 0.5, -th)
	return s


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	var gr := ColorRect.new()
	gr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grade.gdshader")
	gr.material = mat
	ui.add_child(gr)

	lid_top = ColorRect.new()
	lid_top.color = Color(0, 0, 0, 1)
	lid_top.position = Vector2(0, -380)
	lid_top.size = Vector2(VW, 380)
	lid_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lid_top)

	lid_bottom = ColorRect.new()
	lid_bottom.color = Color(0, 0, 0, 1)
	lid_bottom.position = Vector2(0, VH)
	lid_bottom.size = Vector2(VW, 380)
	lid_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lid_bottom)

	scare = TextureRect.new()
	scare.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scare.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scare.stretch_mode = TextureRect.STRETCH_SCALE
	scare.modulate = Color(1, 1, 1, 0)
	scare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(scare)

	art = TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.visible = false
	ui.add_child(art)

	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash)

	fade = ColorRect.new()
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)

	card_root = Control.new()
	card_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_root.visible = false
	ui.add_child(card_root)

	card_bleed = _mk_label("", 64, font_serif, Color(0.60, 0.05, 0.06))
	card_bleed.position = Vector2(0, 250)
	card_bleed.size = Vector2(VW, 80)
	card_bleed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_bleed.modulate = Color(1, 1, 1, 0)
	card_root.add_child(card_bleed)

	card_big = _mk_label("", 64, font_serif, Color(0.86, 0.89, 0.89))
	card_big.position = Vector2(0, 250)
	card_big.size = Vector2(VW, 80)
	card_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_root.add_child(card_big)

	var line := ColorRect.new()
	line.color = Color(0.5, 0.54, 0.54, 0.45)
	line.position = Vector2(VW * 0.5 - 90, 344)
	line.size = Vector2(180, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_root.add_child(line)

	card_small = _mk_label("", 22, font_ui, Color(0.55, 0.59, 0.60))
	card_small.position = Vector2(0, 364)
	card_small.size = Vector2(VW, 34)
	card_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_root.add_child(card_small)

	sub = _mk_label("", 26, font_ui, Color(0.85, 0.87, 0.86))
	sub.position = Vector2(0, 596)
	sub.size = Vector2(VW, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0)
	ui.add_child(sub)

	hint = _mk_label("", 19, font_ui, Color(0.62, 0.66, 0.65))
	hint.position = Vector2(0, 652)
	hint.size = Vector2(VW, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0)
	ui.add_child(hint)

	end_text = _mk_label("", 30, font_serif, Color(0.88, 0.89, 0.86))
	end_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_text.modulate = Color(1, 1, 1, 0)
	ui.add_child(end_text)

	title_root = Control.new()
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title_root)

	var sh := ColorRect.new()
	sh.color = Color(0, 0, 0, 0.55)
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(sh)

	title_big = _mk_label("放 学 后", 88, font_serif, Color(0.90, 0.90, 0.87))
	title_big.position = Vector2(0, 180)
	title_big.size = Vector2(VW, 120)
	title_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(title_big)

	title_small = _mk_label("逢　魔　之　时", 30, font_serif, Color(0.58, 0.62, 0.60))
	title_small.position = Vector2(0, 312)
	title_small.size = Vector2(VW, 40)
	title_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(title_small)

	title_hint = _mk_label("", 45, font_serif, Color(0.30, 0.16, 0.16))
	title_hint.position = Vector2(0, 424)
	title_hint.size = Vector2(VW, 30)
	title_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_root.add_child(title_hint)

	var items := ["开 始 游 戏", "结 局 收 录", "退 出"]
	for i in range(3):
		var b := Button.new()
		b.text = items[i]
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.position = Vector2(0, 448 + i * 46)
		b.size = Vector2(VW, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		if font_ui != null:
			b.add_theme_font_override("font", font_ui)
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color(0.56, 0.60, 0.59))
		b.add_theme_color_override("font_hover_color", Color(0.96, 0.93, 0.87))
		b.add_theme_color_override("font_focus_color", Color(0.96, 0.93, 0.87))
		b.add_theme_color_override("font_pressed_color", Color(0.96, 0.93, 0.87))
		for sty in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(sty, StyleBoxEmpty.new())
		b.pressed.connect(_on_menu_item.bind(i))
		b.focus_entered.connect(_on_menu_focus.bind(i))
		title_root.add_child(b)
		menu_buttons.append(b)

	var back := Button.new()
	back.text = "返 回"
	back.flat = true
	back.position = Vector2(0, 632)
	back.size = Vector2(VW, 36)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_ui != null:
		back.add_theme_font_override("font", font_ui)
	back.add_theme_font_size_override("font_size", 22)
	back.add_theme_color_override("font_color", Color(0.50, 0.54, 0.53))
	back.add_theme_color_override("font_hover_color", Color(0.92, 0.90, 0.85))
	for sty in ["normal", "hover", "pressed", "focus", "disabled"]:
		back.add_theme_stylebox_override(sty, StyleBoxEmpty.new())
	back.pressed.connect(_enter_title)
	back.visible = false
	title_root.add_child(back)
	gallery_back = back

	gallery_labels.clear()
	for i in range(ENDINGS.size()):
		var gl := _mk_label("", 21, font_serif, Color(0.70, 0.73, 0.72))
		gl.position = Vector2(300, 230 + i * 80)
		gl.size = Vector2(VW - 600, 76)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		gl.visible = false
		title_root.add_child(gl)
		gallery_labels.append(gl)

	_build_touch_controls()


func _build_touch_controls() -> void:
	if not is_mobile:
		return
	touch_root = Control.new()
	touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_root.visible = false
	ui.add_child(touch_root)

	# 左下角大箭头：按住向左走（游戏唯一必需操作）
	touch_left_btn = Button.new()
	touch_left_btn.text = "←"
	touch_left_btn.position = Vector2(64, VH - 176)
	touch_left_btn.size = Vector2(132, 132)
	touch_left_btn.flat = false
	touch_left_btn.focus_mode = Control.FOCUS_NONE
	if font_ui != null:
		touch_left_btn.add_theme_font_override("font", font_ui)
	touch_left_btn.add_theme_font_size_override("font_size", 72)
	touch_left_btn.add_theme_color_override("font_color", Color(0.92, 0.93, 0.90, 0.92))
	touch_left_btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.10, 0.42)
	sb.border_color = Color(0.72, 0.75, 0.74, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(66)
	var sb_press := StyleBoxFlat.new()
	sb_press.bg_color = Color(0.30, 0.34, 0.36, 0.72)
	sb_press.border_color = Color(0.92, 0.93, 0.90, 0.85)
	sb_press.set_border_width_all(2)
	sb_press.set_corner_radius_all(66)
	touch_left_btn.add_theme_stylebox_override("normal", sb)
	touch_left_btn.add_theme_stylebox_override("hover", sb)
	touch_left_btn.add_theme_stylebox_override("pressed", sb_press)
	touch_left_btn.add_theme_stylebox_override("focus", sb)
	touch_left_btn.add_theme_stylebox_override("disabled", sb)
	touch_left_btn.button_down.connect(_on_touch_left_down)
	touch_left_btn.button_up.connect(_on_touch_left_up)
	touch_root.add_child(touch_left_btn)


func _on_touch_left_down() -> void:
	touch_left = true


func _on_touch_left_up() -> void:
	touch_left = false


func _mk_label(txt: String, size: int, f: Font, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_audio() -> void:
	amb = AudioStreamPlayer.new()
	amb.volume_db = -10.0
	add_child(amb)
	amb.finished.connect(func() -> void: amb.play())
	for i in range(10):
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		sfx.append(p)


func play_amb(n: String, v := -10.0) -> void:
	if not sb.has(n):
		return
	amb.stream = sb[n]
	amb.volume_db = v
	amb.play()


func play_sfx(n: String, v := 0.0, pitch := 1.0) -> void:
	if not sb.has(n):
		return
	var p: AudioStreamPlayer = sfx[sfx_i]
	sfx_i = (sfx_i + 1) % sfx.size()
	p.stream = sb[n]
	p.volume_db = v
	p.pitch_scale = pitch
	p.play()


func _load_progress() -> void:
	unlocked.clear()
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for e in ENDINGS:
		if bool(cf.get_value("endings", String(e["id"]), false)):
			unlocked[String(e["id"])] = true


func _save_progress() -> void:
	var cf := ConfigFile.new()
	for e in ENDINGS:
		cf.set_value("endings", String(e["id"]), unlocked.has(String(e["id"])))
	cf.save(SAVE_PATH)


# ================================================== 流程

func _enter_title() -> void:
	st = St.TITLE
	menu_index = 0
	title_big.visible = true
	title_small.visible = true
	for tw_obj in [sub_tw, hint_tw, card_tw]:
		if tw_obj and tw_obj.is_valid():
			tw_obj.kill()
	sub.text = ""
	sub.modulate = Color(1, 1, 1, 0)
	hint.text = ""
	hint.modulate = Color(1, 1, 1, 0)
	card_root.visible = false
	lid_top.position = Vector2(0, -380)
	lid_bottom.position = Vector2(0, VH)
	end_text.text = ""
	end_text.modulate = Color(1, 1, 1, 0)
	scare.modulate = Color(1, 1, 1, 0)
	flash.color = Color(1, 1, 1, 0)
	fade.color = Color(0, 0, 0, 0)
	title_hint.position = Vector2(0, 424)
	for gl in gallery_labels:
		gl.visible = false
	if gallery_back:
		gallery_back.visible = false
	for b in menu_buttons:
		b.visible = true
	_refresh_menu()
	if menu_buttons.size() > 0:
		menu_buttons[0].grab_focus()
	art.visible = false
	title_root.visible = true
	fade.color = Color(0, 0, 0, 0)
	player.visible = false
	stage.darkness = 0.66
	stage.tick(0, 0.0)
	play_amb("amb_void", -18.0)
	title_hint.text = "已 收 录  %d / %d" % [unlocked.size(), ENDINGS.size()]
	title_hint.add_theme_font_size_override("font_size", 18)
	title_hint.add_theme_color_override("font_color", Color(0.45, 0.49, 0.48))
	title_hint.size = Vector2(VW, 30)


func _on_menu_item(i: int) -> void:
	match i:
		0:
			_begin_run()
		1:
			_enter_gallery()
		2:
			get_tree().quit()


func _refresh_menu() -> void:
	for i in range(menu_buttons.size()):
		var b: Button = menu_buttons[i]
		b.add_theme_color_override("font_color",
			Color(0.92, 0.89, 0.84) if i == menu_index else Color(0.50, 0.54, 0.53))


func _enter_gallery() -> void:
	st = St.GALLERY
	title_big.visible = false
	title_small.visible = false
	for b in menu_buttons:
		b.visible = false
	if gallery_back:
		gallery_back.visible = true
		gallery_back.grab_focus()
	for i in range(gallery_labels.size()):
		var gl: Label = gallery_labels[i]
		gl.visible = true
		var e: Dictionary = ENDINGS[i]
		if unlocked.has(String(e["id"])):
			gl.text = "◆  %s\n      %s" % [e["name"], e["hint"]]
			gl.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
		else:
			gl.text = "◇  ？ ？ ？\n      未 解 锁"
			gl.add_theme_color_override("font_color", Color(0.36, 0.39, 0.38))
	title_hint.text = "结 局 收 录　　已 解 锁 %d / %d" % [unlocked.size(), ENDINGS.size()]
	title_hint.add_theme_font_size_override("font_size", 30)
	title_hint.add_theme_color_override("font_color", Color(0.80, 0.79, 0.74))
	title_hint.position = Vector2(0, 158)
	title_hint.size = Vector2(VW, 44)


func _on_menu_focus(i: int) -> void:
	menu_index = i
	_refresh_menu()


func _update_title() -> void:
	pass


func _input(event: InputEvent) -> void:
	# 触摸松开兜底：手指滑出箭头按钮后松开也要停止行走
	if (event is InputEventScreenTouch and not event.pressed) \
		or (event is InputEventMouseButton and not event.pressed):
		touch_left = false
	if event is InputEventMouseButton and event.pressed:
		if st == St.GALLERY:
			_enter_title()
		elif st == St.END and end_text.modulate.a > 0.9:
			_enter_title()


func _update_gallery() -> void:
	if _just(KEY_ENTER) or _just(KEY_ESCAPE) or _just(KEY_SPACE):
		_enter_title()


func _begin_run() -> void:
	run_idle = 0.0
	run_mirror = 0.0
	person_ghost.clear()
	for i in range(humans.size()):
		person_ghost.append(false)
	scare_pool.clear()
	for sp in SCARE_POOL:
		scare_pool.append(sp)
	scare_pool.shuffle()
	corner_t = randf_range(28.0, 40.0)
	title_root.visible = false
	_start_day(0)


func _clear_peds() -> void:
	for p in peds:
		if is_instance_valid(p["spr"]):
			p["spr"].queue_free()
	peds.clear()


func _start_day(d: int) -> void:
	day = d
	st = St.CARD
	_clear_peds()
	stage.set_day(d)
	stage.darkness = DARK[d]
	stage.red_light = d >= 4
	stage.wet = d >= 4
	stage.flicker = 0.0
	scroll = 0.0
	ev_list = _events(d)
	ev_i = 0
	total_idle = 0.0
	mirror_timer = 0.0
	in_mirror = false
	busy = false
	step_t = 0.0
	ped_next = 0
	ped_t = 0.35
	forced_stop = 0.0
	still_time = 0.0
	lid_top.position = Vector2(0, -380)
	lid_bottom.position = Vector2(0, VH)
	var conv: float = [0.0, 0.25, 0.45, 0.72, 1.0][clampi(d, 0, 4)]
	for i in range(person_ghost.size()):
		if not bool(person_ghost[i]) and randf() < conv:
			person_ghost[i] = true
	if d >= 4:
		for i in range(person_ghost.size()):
			person_ghost[i] = true
	_build_queue()
	player.visible = true
	player.texture = tex["res://assets/art/p.png"]
	art.visible = false
	art.modulate = Color(1, 1, 1, 1)
	title_root.visible = false
	card_big.text = DAYS[d]["big"]
	card_bleed.text = DAYS[d]["big"]
	card_small.text = "%s　　%s" % [DAYS[d]["small"], DAYS[d]["time"]]
	# 越是往后，字迹越像在渗血、越失真
	var bl := float(d) / 4.0
	card_bleed.position = Vector2(2.0 + bl * 6.0, 250.0 + 1.0 + bl * 4.0)
	card_bleed.modulate = Color(1, 1, 1, 0.10 + bl * 0.72)
	card_big.add_theme_color_override("font_color",
		Color(0.86 - bl * 0.26, 0.89 - bl * 0.62, 0.89 - bl * 0.64))
	card_big.add_theme_color_override("font_shadow_color", Color(0.40 * bl, 0.02, 0.02, 0.9))
	card_small.add_theme_color_override("font_color",
		Color(0.55 - bl * 0.22, 0.59 - bl * 0.44, 0.60 - bl * 0.44))
	card_root.visible = true
	card_root.modulate = Color(1, 1, 1, 0)
	end_text.modulate = Color(1, 1, 1, 0)
	scare.modulate = Color(1, 1, 1, 0)
	fade.color = Color(0, 0, 0, 1)
	play_amb(DAYS[d]["amb"], -12.0)

	if card_tw and card_tw.is_valid():
		card_tw.kill()
	var tw := create_tween()
	card_tw = tw
	tw.tween_property(card_root, "modulate:a", 1.0, 0.8)
	tw.tween_interval(2.0)
	tw.tween_property(card_root, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(fade, "color:a", 0.0, 1.2)
	tw.tween_callback(_begin_play)


func _begin_play() -> void:
	st = St.PLAY
	card_root.visible = false
	if day == 0:
		_show_hint("按住  箭头　松开就停下。停下会被看见。" if is_mobile
			else "按住  ←　松开就停下。停下会被看见。", 5.0)


func _next_day() -> void:
	st = St.CARD
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 1.2)
	tw.tween_callback(func() -> void:
		if day >= 4:
			_finish()
		else:
			_start_day(day + 1))


func _resolve_ending() -> String:
	if run_mirror >= MIRROR_LIMIT:
		return "taken"
	if still_time >= BLINK_LIMIT:
		return "blink"
	return "normal"


func _finish() -> void:
	var e := _resolve_ending()
	if autoplay:
		print("[ending] idle=", snappedf(run_idle, 0.1), " mirror=", snappedf(run_mirror, 0.1), " -> ", e)
	_ending(e)


func _ending(kind: String) -> void:
	st = St.END
	ending = kind
	if not unlocked.has(kind):
		unlocked[kind] = true
		if not dev_mode and not verify_mode and not autoplay:
			_save_progress()
	_clear_peds()
	art.texture = tex["res://assets/art/wall.png"]
	art.modulate = Color(0.26, 0.29, 0.33, 1.0)
	if kind == "taken":
		play_sfx("stinger", -8.0)
	else:
		play_amb("amb_void", -18.0)
	art.visible = true
	player.visible = false
	card_root.visible = false
	sub.modulate = Color(1, 1, 1, 0)
	hint.modulate = Color(1, 1, 1, 0)
	fade.color = Color(0, 0, 0, 1)
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(fade, "color:a", 0.0, 1.2)
	tw.tween_interval(0.4)
	tw.tween_callback(func() -> void:
		var nm := ""
		for e in ENDINGS:
			if String(e["id"]) == kind:
				nm = String(e["name"])
		var back_tip := "轻触屏幕返回标题" if is_mobile else "按 Enter 返回标题"
		end_text.text = "%s\n\n%s\n\n\n—  %s  —" % [nm, _ending_body(kind), back_tip])
	tw.tween_property(end_text, "modulate:a", 1.0, 1.6)


# ================================================== 帧

func _process(dt: float) -> void:
	for c in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER,
			KEY_SPACE, KEY_ESCAPE, KEY_W, KEY_S, KEY_A, KEY_D]:
		k_now[c] = Input.is_key_pressed(c)

	if autoplay:
		dt *= 6.0
	anim_t += dt
	walking = (autoplay or _left()) and st == St.PLAY and forced_stop <= 0.0

	# 触摸箭头只在游戏进行中显示
	if is_mobile and touch_root != null:
		touch_root.visible = (st == St.PLAY)
		if st != St.PLAY:
			touch_left = false

	match st:
		St.TITLE:
			if autoplay:
				_begin_run()
			else:
				_update_title()
		St.GALLERY:
			_update_gallery()
		St.PLAY:
			_play(dt)
		St.END:
			if autoplay:
				get_tree().quit()
			elif _just(KEY_ENTER) or _just(KEY_SPACE) or _just(KEY_ESCAPE):
				_enter_title()

	_update_anchored()
	_update_chars(dt)
	stage.tick(scroll, dt)
	k_prev = k_now.duplicate()


func _update_anchored() -> void:
	var keep: Array = []
	for a in anchored:
		var sp = a["spr"]
		if not is_instance_valid(sp):
			continue
		sp.position.x = float(a["wx"]) + scroll
		keep.append(a)
	anchored = keep


func _just(code: int) -> bool:
	return bool(k_now.get(code, false)) and not bool(k_prev.get(code, false))


func _left() -> bool:
	return (Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
		or Input.is_action_pressed("ui_left") or touch_left)


func _retry() -> void:
	end_text.modulate = Color(1, 1, 1, 0)
	scare.modulate = Color(1, 1, 1, 0)
	art.visible = false
	_start_day(0)


func _play(dt: float) -> void:
	if forced_stop > 0.0:
		forced_stop -= dt
	if walking:
		still_time = 0.0
		scroll += WALK_SPEED * dt
		step_t += dt
		if step_t > 0.52:
			step_t = 0.0
			play_sfx("step%d" % (randi() % 4 + 1), -17.0, randf_range(0.92, 1.05))
	elif forced_stop <= 0.0:
		still_time += dt
		total_idle += dt
		run_idle += dt
		if still_time >= BLINK_LIMIT and not busy:
			_blink()
			return
		if day == 4 and in_mirror:
			mirror_timer += dt
			run_mirror += dt
			if mirror_timer > 2.6 and not busy:
				busy = true
				_do_scare()
				var tw := create_tween()
				tw.tween_interval(1.0)
				tw.tween_callback(func() -> void: _ending("taken"))

	corner_t -= dt
	if corner_t <= 0.0 and day >= 1:
		corner_t = randf_range(28.0, 46.0)
		_corner_ghost()

	_peds(dt)
	_check_events()
	if scroll >= DAY_LEN[day]:
		_next_day()


func _peds(dt: float) -> void:
	# 每天固定 10 个不同行人，一个只出现一次
	if walking:
		ped_t -= dt                      # 只有往前走才推进行人队列
	elif ped_next < 9:
		ped_t = maxf(ped_t, 0.35)        # 静止时抬成正值，绝不触发刷新
	if ped_t <= 0.0 and ped_next < 9:
		var crowded := false
		for p in peds:
			if float(p["x"]) < 380.0:
				crowded = true
				break
		if crowded:
			ped_t = 0.7                      # 挤了就等一会儿，别叠在一起
		else:
			_spawn_ped(ped_next)
			ped_next += 1
		ped_t = DAY_LEN[day] / WALK_SPEED / 9.0 * randf_range(0.88, 1.14)
		if day >= 4:
			ped_t *= 0.50

	var wv := WALK_SPEED if walking else 0.0     # 主角停，世界停
	var alive: Array = []
	for p in peds:
		var s: Sprite2D = p["spr"]
		if not is_instance_valid(s):
			continue
		p["x"] = float(p["x"]) + (wv + float(p["spd"])) * dt
		var ph := float(p["ph"]) + anim_t * 5.2
		s.position = Vector2(float(p["x"]), PLAYER_BOTTOM + SPRITE_SINK + sin(ph) * 4.0)
		var lv: float = 1.0 - float(stage.darkness) * 0.72
		s.modulate = Color(lv, lv, lv * 1.03, 1.0)
		s.rotation = sin(ph * 0.5) * 0.010
		if float(p["x"]) > 1620.0:
			s.queue_free()
		else:
			alive.append(p)
	peds = alive


func _build_queue() -> void:
	day_queue.clear()
	for i in range(humans.size()):
		if i < person_ghost.size() and bool(person_ghost[i]):
			day_queue.append(str(ghosts[i % ghosts.size()]))
		else:
			day_queue.append(str(humans[i]))


func _spawn_ped(idx: int) -> void:
	if idx < 0 or idx >= day_queue.size():
		return
	_make_ped(str(day_queue[idx]))


func _make_ped(path: String) -> void:
	if not tex.has(path):
		return
	var spr := _mk_sprite_from(tex[path], CHAR_H)
	spr.flip_h = true
	add_child(spr)
	spr.position = Vector2(-340.0, PLAYER_BOTTOM + SPRITE_SINK)
	peds.append({"spr": spr, "x": -340.0, "spd": randf_range(66.0, 92.0),
		"ph": randf() * 6.28})


func _mk_sprite_from(t: Texture2D, h: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	var tw := float(t.get_width())
	var th := float(t.get_height())
	var sc := h / th
	s.scale = Vector2(sc, sc)
	s.offset = Vector2(-tw * 0.5, -th)
	return s


func _update_chars(_dt: float) -> void:
	if st == St.PLAY or st == St.CARD:
		var amp := 5.0 if walking else 2.0
		var hz := 6.4 if walking else 2.2
		player.position = Vector2(PLAYER_X + sin(anim_t * hz * 0.5) * 2.0,
			PLAYER_BOTTOM + SPRITE_SINK + sin(anim_t * hz) * amp)
		var plv: float = 1.0 - float(stage.darkness) * 0.66
		player.modulate = Color(plv, plv, plv * 1.02, 1.0)
		player.rotation = sin(anim_t * hz * 0.5) * 0.011


# ================================================== 事件

func _check_events() -> void:
	while ev_i < ev_list.size():
		var e: Dictionary = ev_list[ev_i]
		if scroll < float(e["at"]) * DAY_LEN[day]:
			break
		ev_i += 1
		_fire(e)


func _e(at: float, t: String, x := {}) -> Dictionary:
	var d := {"at": at, "t": t}
	d.merge(x)
	return d


func _events(d: int) -> Array:
	var o: Array = []
	match d:
		0:
			o.append(_e(0.04, "text", {"s": "放学铃响过很久了。走廊里还有人没走。", "dur": 3.4}))
			o.append(_e(0.15, "text", {"s": "我休学了一个学期。今天回来，只是拿点东西。", "dur": 4.0}))
			o.append(_e(0.30, "beat", {"who": "friend", "hold": 8.0,
				"lines": ["【雪子】季靛？", "【雪子】真的是你。", "她说，她在校门口等我。"]}))
			o.append(_e(0.56, "beat", {"who": "bullies", "hold": 8.5,
				"lines": ["【赵磊】哟。", "【孙鹏】还真敢回来啊。", "我低着头，等他们走过去。"]}))
			o.append(_e(0.82, "text", {"s": "走廊里只剩下我一个人的脚步声。", "dur": 3.8}))
			o.append(_e(0.93, "sfx", {"s": "bell", "v": -15}))
		1:
			o.append(_e(0.05, "text", {"s": "今天走廊上的人，比昨天多。", "dur": 3.2}))
			o.append(_e(0.26, "text", {"s": "他们走路的样子，一模一样。", "dur": 3.4}))
			o.append(_e(0.44, "win"))
			o.append(_e(0.54, "text", {"s": "窗外有什么东西过去了。", "dur": 3.2}))
			o.append(_e(0.70, "scare"))
			o.append(_e(0.84, "text", {"s": "……是我看错了吧。", "dur": 3.0}))
		2:
			o.append(_e(0.05, "text", {"s": "灯管在响。", "dur": 2.8}))
			o.append(_e(0.18, "text", {"s": "有人的地方，就该有影子。", "dur": 3.6}))
			o.append(_e(0.36, "win"))
			o.append(_e(0.46, "text", {"s": "刚走过去的那个，脚下什么都没有。", "dur": 4.0}))
			o.append(_e(0.62, "scare"))
			o.append(_e(0.74, "text", {"s": "不要停下来。", "dur": 3.0}))
			o.append(_e(0.86, "text", {"s": "不要回头。", "dur": 3.0}))
		3:
			o.append(_e(0.04, "text", {"s": "黄昏了。", "dur": 2.8}))
			o.append(_e(0.15, "text", {"s": "走廊尽头全是人，都朝我这边走。", "dur": 4.0}))
			o.append(_e(0.34, "beat", {"who": "ghost_bullies", "hold": 7.5,
				"lines": ["赵磊他们三个，今天没来上学。", "走过来的，不是他们。"]}))
			o.append(_e(0.58, "win"))
			o.append(_e(0.70, "scare"))
			o.append(_e(0.84, "text", {"s": "他们贴着墙走，像在找什么。", "dur": 3.8}))
		_:
			o.append(_e(0.03, "text", {"s": "灯灭了。地上有水。", "dur": 3.0}))
			o.append(_e(0.14, "text", {"s": "前面就是鞋柜。", "dur": 3.0}))
			o.append(_e(0.30, "win"))
			o.append(_e(0.40, "scare"))
			o.append(_e(0.52, "text", {"s": "走廊上全是人。全是。", "dur": 3.4}))
			o.append(_e(0.64, "beat", {"who": "friend_g", "hold": 10.0,
				"lines": ["雪子？", "她抬起头。", "头发底下，什么都没有。", "她说，她一直在等我。"]}))
			o.append(_e(0.88, "mirror"))
			o.append(_e(0.94, "text", {"s": "走过去。不要停。", "dur": 3.0}))
	return o


func _beat(who: String, hold: float, lines: Array) -> void:
	forced_stop = hold
	hint.modulate.a = 0.0
	var group: Array = []
	match who:
		"bullies":
			group = ["b1", "b2", "b3"]
		"ghost_bullies":
			group = ["gb_1", "gb_2", "gb_3"]
			for nm in group:
				if not tex.has(nm):
					group = []
					for k in range(min(3, crowd_g.size())):
						group.append(str(crowd_g[k]))
					break
		_:
			group = [who]
	for i in range(group.size()):
		var nm: String = group[i]
		if not tex.has(nm):
			continue
		var spr := _mk_sprite_from(tex[nm], CHAR_H)
		spr.flip_h = true
		add_child(spr)
		var still: bool = who == "friend_g"
		var x0: float = 300.0 if still else (-230.0 - i * 108.0)
		spr.position = Vector2(x0, PLAYER_BOTTOM + SPRITE_SINK - i * 3.0)
		peds.append({"spr": spr, "x": x0, "spd": 0.0 if still else 165.0, "ph": float(i)})
	var tw := create_tween()
	tw.tween_interval(0.8)
	for ln in lines:
		var text_line: String = String(ln)
		tw.tween_callback(func() -> void: _show_sub(text_line, 2.3))
		tw.tween_interval(2.6)


func _fire(e: Dictionary) -> void:
	match String(e["t"]):
		"text":
			_show_sub(String(e["s"]), float(e.get("dur", 3.4)))
		"sfx":
			play_sfx(String(e["s"]), float(e.get("v", -8)))
		"win":
			_window_ghost()
		"scare":
			_do_scare()
		"beat":
			_beat(String(e["who"]), float(e["hold"]), e["lines"])
		"mirror":
			in_mirror = true
			_show_hint("……停下来的时候，就会看见", 3.6)


func _blink() -> void:
	busy = true
	st = St.CARD
	play_sfx("heartbeat", -7.0)
	play_sfx("whisper", -18.0, 0.7)
	var tw := create_tween()
	tw.tween_property(lid_top, "position:y", 0.0, 1.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(lid_bottom, "position:y", VH * 0.5 - 30.0, 1.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.0)
	tw.tween_callback(func() -> void: _ending("blink"))


func _corner_ghost() -> void:
	var path: String = CORNER_POOL[randi() % CORNER_POOL.size()]
	if not tex.has(path):
		return
	var spr := _mk_sprite_from(tex[path], 420.0)
	var left := randf() < 0.5
	spr.flip_h = not left
	var want_x: float = 96.0 if left else VW - 96.0
	# 记成世界坐标：主角往前走，它会往画面右滑出去，而不是钉在屏幕上
	var wx: float = want_x - scroll
	spr.position = Vector2(want_x, PLAYER_BOTTOM + 26.0)
	spr.modulate = Color(0.72, 0.84, 1.06, 0.0)
	add_child(spr)
	anchored.append({"spr": spr, "wx": wx})
	var tw := create_tween()
	tw.tween_property(spr, "modulate:a", 0.82, 0.05)
	tw.tween_interval(0.85)
	tw.tween_property(spr, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func() -> void: spr.queue_free())
	play_sfx("stinger", -15.0, 1.35)


func _window_ghost() -> void:
	var wins: Array = stage.visible_windows()
	if wins.is_empty():
		return
	var idx: int = randi() % wins.size()
	stage.flash_window(int(wins[idx]["slot"]))
	play_sfx("whisper", -15.0, 1.2)


func _do_scare() -> void:
	# 一局之内绝不重复：池子空了就不再触发，不补充、不重置
	if scare_pool.is_empty():
		return
	var spath := ""
	var guard := 0
	while not scare_pool.is_empty() and guard < 12:
		var cand := str(scare_pool.pop_back())
		guard += 1
		if tex.has(cand):
			spath = cand
			break
	if spath == "":
		return
	scare.texture = tex[spath]
	scare.modulate = Color(1.22, 1.20, 1.24, 1)   # 瞬间占满全屏，不做淡入
	scare.position = Vector2.ZERO
	play_sfx("stinger", -8.0)
	stage.shake = 7.0
	_flash(Color(0.42, 0.02, 0.02), 0.20, 0.20)
	sub.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.52)                     # 固定时长，不拖
	tw.tween_callback(func() -> void:
		scare.modulate = Color(1, 1, 1, 0)
		stage.shake = 0.0)


func _ending_body(kind: String) -> String:
	match kind:
		"blink":
			return "我只是想站一会儿。\n\n眼睛闭上的时候，走廊还在往前走。\n\n再睁开的时候，我不确定自己站在哪一边。"
		"taken":
			return "我回头了。\n\n走廊尽头那个人，终于等到了我。\n\n从明天起，换成我站在那儿。"
		_:
			return "我走出去了，没有回头。\n\n第二天，走廊是空的。\n\n只有鞋柜上，还放着她的发夹。"


func _flash(c: Color, a: float, d: float) -> void:
	flash.color = Color(c.r, c.g, c.b, a)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, d)


func _show_sub(t: String, dur: float) -> void:
	if sub_tw and sub_tw.is_valid():
		sub_tw.kill()
	sub.text = t
	sub.modulate = Color(1, 1, 1, 0)
	sub_tw = create_tween()
	sub_tw.tween_property(sub, "modulate:a", 0.95, 0.9)
	sub_tw.tween_interval(dur)
	sub_tw.tween_property(sub, "modulate:a", 0.0, 1.2)


func _show_hint(t: String, dur: float) -> void:
	if hint_tw and hint_tw.is_valid():
		hint_tw.kill()
	hint.text = t
	hint.modulate = Color(1, 1, 1, 0)
	hint_tw = create_tween()
	hint_tw.tween_property(hint, "modulate:a", 0.8, 0.8)
	hint_tw.tween_interval(dur)
	hint_tw.tween_property(hint, "modulate:a", 0.0, 1.2)


# ================================================== 自检

func _verify_crowd() -> int:
	var fails := 0
	# A) 每天队列不重复、数量等于人数
	for d in range(5):
		day = d
		person_ghost.clear()
		for i in range(humans.size()):
			person_ghost.append(false)
		var conv: float = [0.0, 0.25, 0.45, 0.72, 1.0][d]
		for i in range(person_ghost.size()):
			if randf() < conv:
				person_ghost[i] = true
		if d >= 4:
			for i in range(person_ghost.size()):
				person_ghost[i] = true
		_build_queue()
		var uniq := {}
		for nm in day_queue:
			uniq[nm] = true
		var ok: bool = uniq.size() == day_queue.size() and day_queue.size() == humans.size()
		# 判断鬼：只要不在人池里就算鬼（极端鬼 x2/x3 不以 g 开头）
		var any_human := false
		var any_ghost := false
		for nm in day_queue:
			if String(nm) in humans:
				any_human = true
			else:
				any_ghost = true
		var rule := true
		if d >= 4 and any_human:
			rule = false          # 第五天必须全是鬼
		if d == 0 and any_ghost:
			rule = false          # 第一天必须全是人
		if not ok or not rule:
			fails += 1
		print("[crowd] day%d size=%d uniq=%d human=%s ghost=%s %s" %
			[d + 1, day_queue.size(), uniq.size(), any_human, any_ghost,
			"OK" if (ok and rule) else "FAIL"])

	# B) 成鬼后不回退
	person_ghost.clear()
	for i in range(humans.size()):
		person_ghost.append(false)
	person_ghost[2] = true
	var reverted := false
	for d in range(1, 5):
		var cv: float = [0.0, 0.25, 0.45, 0.72, 1.0][d]
		for i in range(person_ghost.size()):
			if not bool(person_ghost[i]) and randf() < cv:
				person_ghost[i] = true
		if d >= 4:
			for i in range(person_ghost.size()):
				person_ghost[i] = true
		if not bool(person_ghost[2]):
			reverted = true
	if reverted:
		fails += 1
	print("[crowd] monotonic %s" % ("FAIL" if reverted else "OK"))

	# C) 静止不消耗名额，走动才推进
	day = 0
	person_ghost.clear()
	for i in range(humans.size()):
		person_ghost.append(false)
	_build_queue()
	_clear_peds()
	ped_next = 0
	ped_t = 0.0
	walking = false
	for k in range(40):
		_peds(1.0)
	var idle_n := ped_next
	walking = true
	for k in range(40):
		_peds(1.0)
	var walk_n := ped_next
	var ok_c: bool = idle_n == 0 and walk_n > 0
	if not ok_c:
		fails += 1
	print("[crowd] idle_spawn=%d walk_spawn=%d %s" % [idle_n, walk_n, "OK" if ok_c else "FAIL"])
	_clear_peds()
	return fails


func _verify_run() -> void:
	var fails := 0
	# 字体自检：内嵌字体必须加载成功且包含游戏用字，否则 Web 端中文会变码位方框
	var font_ok: bool = font_ui != null and font_ui.has_char("放".unicode_at(0)) \
		and font_serif != null and font_serif.has_char("后".unicode_at(0))
	print("[verify] font loaded=%s cjk=%s %s" %
		[font_ui != null, font_ok, "OK" if font_ok else "FAIL"])
	if not font_ok:
		fails += 1
	if is_mobile:
		var touch_ok: bool = touch_root != null and touch_left_btn != null
		print("[verify] mobile touch control built=%s %s" %
			[touch_ok, "OK" if touch_ok else "FAIL"])
		if not touch_ok:
			fails += 1
	var cases := [
		{"mirror": 0.0, "still": 0.0, "want": "normal"},
		{"mirror": 2.6, "still": 0.0, "want": "taken"},
		{"mirror": 0.0, "still": 15.0, "want": "blink"},
		{"mirror": 9.0, "still": 20.0, "want": "taken"},
		{"mirror": 0.0, "still": 14.9, "want": "normal"},
	]
	for c in cases:
		run_mirror = float(c["mirror"])
		still_time = float(c["still"])
		var got := _resolve_ending()
		var ok: bool = got == String(c["want"])
		if not ok:
			fails += 1
		print("[verify] mirror=%s still=%s -> %s (want %s) %s" %
			[c["mirror"], c["still"], got, c["want"], "OK" if ok else "FAIL"])
	print("[verify] endings=%d fails=%d" % [ENDINGS.size(), fails])
	fails += _verify_crowd()

	# 实跑验证：第五日停在镜面区是否真的走「留下」
	_begin_run()
	autoplay = false
	await _wait(4.6)
	day = 4
	in_mirror = true
	mirror_timer = 0.0
	run_mirror = 0.0
	forced_stop = 0.0
	await _wait(4.0)
	print("[verify] live taken -> ending=", ending, " run_mirror=", snappedf(run_mirror, 0.1))
	await get_tree().process_frame
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_dev/s_%s.png" % n)
	print("shot ", n)


func _dev_run() -> void:
	await _wait(1.2)
	_shot("01_menu")
	_enter_gallery()
	await _wait(0.6)
	_shot("02_gallery")
	_enter_title()
	await _wait(0.4)
	_begin_run()
	await _wait(4.8)
	_shot("03_day1")
	_start_day(3)
	await _wait(4.8)
	scroll = 2200.0
	await _wait(2.6)
	_shot("04_day4")
	_start_day(4)
	await _wait(4.8)
	scroll = 2400.0
	await _wait(2.6)
	_shot("05_day5")
	_corner_ghost()
	await _wait(0.2)
	_shot("06_corner")
	_window_ghost()
	await _wait(0.3)
	_shot("07_window")
	_do_scare()
	await _wait(0.12)
	_shot("08_scare")
	await _wait(0.9)
	end_text.text = ""
	_ending("taken")
	await _wait(5.0)
	_shot("09_end")
	_enter_title()
	await _wait(0.6)
	_shot("10_back_title")

	# 第二循环：验证重开一局后状态是否干净
	_begin_run()
	await _wait(4.8)
	scroll = 3000.0
	await _wait(1.6)
	_shot("11_cycle2")
	_ending("normal")
	await _wait(4.6)
	_shot("12_end2")
	_enter_title()
	await _wait(0.8)
	_shot("13_title3")
	print("[cycle] nodes=", get_child_count(), " peds=", peds.size(), " anchored=", anchored.size())
	_begin_run()
	autoplay = false                 # 停止自动前进，模拟玩家站着不动
	await _wait(15.6)
	print("[blink] still=", snappedf(still_time, 0.1), " st=", st)
	_shot("14_blink_mid")
	await _wait(2.2)
	_shot("15_blink_dark")
	await _wait(7.0)
	_shot("16_blink_end")
	print("[blink] ending=", ending)
	await _wait(0.3)
	get_tree().quit()
