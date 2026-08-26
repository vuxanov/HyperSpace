extends RefCounted
class_name AsciiCharset

## Builds a 1-row glyph atlas ImageTexture from a character ramp (dark → bright).
## Prefers bundled Noto fonts (real ASCII / Unicode glyphs); 5×7 bitmaps are fallback only.

const CELL := 32
const FONT_SIZE := 26
const FONT_PATHS := [
	"res://assets/fonts/NotoSansMono-Regular.ttf",
	"res://assets/fonts/NotoSansSymbols-Regular.ttf",
	"res://assets/fonts/NotoSansSymbols2-Regular.ttf",
	"res://assets/fonts/NotoSansRunic-Regular.ttf",
	"res://assets/fonts/NotoEmoji-Regular.ttf",
]

static var _font: Font
## True while a live SubViewport atlas bake is in the tree. Feedback must not
## CPU-capture the output RT in this window (nested force_draw used to steal it).
static var baking: bool = false
static var _bake_token: int = 0

## 5-bit-wide rows (values 0–31). Dark→bright ramps should order from sparse to dense.
const BITMAPS := {
	" ": [0, 0, 0, 0, 0, 0, 0],
	".": [0, 0, 0, 0, 0, 0, 4],
	"·": [0, 0, 0, 4, 0, 0, 0],
	":": [0, 0, 4, 0, 4, 0, 0],
	"-": [0, 0, 0, 14, 0, 0, 0],
	"'": [4, 4, 0, 0, 0, 0, 0],
	"`": [8, 4, 0, 0, 0, 0, 0],
	",": [0, 0, 0, 0, 4, 4, 8],
	"^": [4, 10, 17, 0, 0, 0, 0],
	"\"": [10, 10, 0, 0, 0, 0, 0],
	";": [0, 4, 0, 0, 4, 4, 8],
	"=": [0, 0, 14, 0, 14, 0, 0],
	"+": [0, 4, 4, 31, 4, 4, 0],
	"*": [0, 10, 4, 31, 4, 10, 0],
	"!": [4, 4, 4, 4, 0, 4, 0],
	"?": [14, 17, 2, 4, 0, 4, 0],
	"/": [1, 2, 4, 8, 16, 0, 0],
	"\\": [16, 8, 4, 2, 1, 0, 0],
	"|": [4, 4, 4, 4, 4, 4, 4],
	"~": [0, 0, 8, 21, 2, 0, 0],
	"<": [2, 4, 8, 16, 8, 4, 2],
	">": [8, 4, 2, 1, 2, 4, 8],
	"(": [2, 4, 8, 8, 8, 4, 2],
	")": [8, 4, 2, 2, 2, 4, 8],
	"[": [14, 8, 8, 8, 8, 8, 14],
	"]": [14, 2, 2, 2, 2, 2, 14],
	"{": [6, 8, 8, 16, 8, 8, 6],
	"}": [12, 2, 2, 1, 2, 2, 12],
	"i": [4, 0, 12, 4, 4, 4, 14],
	"l": [12, 4, 4, 4, 4, 4, 14],
	"I": [14, 4, 4, 4, 4, 4, 14],
	"t": [0, 4, 4, 14, 4, 4, 3],
	"f": [6, 8, 8, 28, 8, 8, 8],
	"j": [2, 0, 2, 2, 2, 10, 4],
	"r": [0, 0, 14, 17, 16, 16, 16],
	"x": [0, 17, 10, 4, 10, 17, 0],
	"n": [0, 0, 22, 25, 17, 17, 17],
	"u": [0, 0, 17, 17, 17, 17, 14],
	"v": [0, 0, 17, 17, 17, 10, 4],
	"c": [0, 0, 14, 16, 16, 16, 14],
	"z": [0, 0, 31, 2, 4, 8, 31],
	"Y": [17, 17, 10, 4, 4, 4, 4],
	"U": [17, 17, 17, 17, 17, 17, 14],
	"J": [2, 2, 2, 2, 2, 18, 12],
	"C": [14, 17, 16, 16, 16, 17, 14],
	"L": [16, 16, 16, 16, 16, 16, 31],
	"Q": [14, 17, 17, 17, 21, 18, 13],
	"0": [14, 17, 19, 21, 25, 17, 14],
	"1": [4, 12, 4, 4, 4, 4, 14],
	"O": [14, 17, 17, 17, 17, 17, 14],
	"Z": [31, 1, 2, 4, 8, 16, 31],
	"m": [0, 0, 27, 21, 21, 21, 21],
	"w": [0, 0, 17, 17, 21, 21, 10],
	"q": [0, 0, 14, 17, 17, 15, 1],
	"p": [0, 0, 30, 17, 17, 30, 16],
	"d": [1, 1, 13, 19, 17, 17, 15],
	"b": [16, 16, 30, 17, 17, 17, 30],
	"k": [16, 16, 18, 20, 24, 20, 18],
	"h": [16, 16, 22, 25, 17, 17, 17],
	"a": [0, 0, 14, 1, 15, 17, 15],
	"o": [0, 0, 14, 17, 17, 17, 14],
	"#": [10, 31, 10, 31, 10, 31, 10],
	"%": [17, 18, 4, 8, 16, 9, 1],
	"&": [12, 18, 20, 8, 21, 18, 13],
	"8": [14, 17, 17, 14, 17, 17, 14],
	"B": [30, 17, 17, 30, 17, 17, 30],
	"@": [14, 17, 21, 21, 14, 0, 4],
	"M": [17, 27, 21, 21, 17, 17, 17],
	"W": [17, 17, 17, 21, 21, 27, 17],
	"$": [4, 15, 20, 14, 5, 30, 4],
	"H": [17, 17, 17, 31, 17, 17, 17],
	"X": [17, 17, 10, 4, 10, 17, 17],
	"•": [0, 0, 14, 14, 14, 0, 0],
	"○": [0, 14, 17, 17, 14, 0, 0],
	"●": [0, 14, 31, 31, 14, 0, 0],
	"░": [10, 5, 10, 5, 10, 5, 10],
	"▒": [15, 10, 15, 10, 15, 10, 15],
	"▓": [15, 15, 10, 15, 15, 10, 15],
	"█": [31, 31, 31, 31, 31, 31, 31],
	# Half-width katakana (vuxanov/ASCII Matrix preset) — simplified 5×7 glyphs.
	"ｦ": [0, 14, 2, 14, 16, 16, 14],
	"ｱ": [4, 4, 14, 17, 17, 17, 0],
	"ｳ": [14, 0, 14, 17, 17, 17, 0],
	"ｴ": [0, 31, 4, 4, 4, 4, 0],
	"ｵ": [4, 31, 4, 14, 21, 4, 4],
	"ｶ": [8, 8, 14, 9, 9, 17, 0],
	"ｷ": [4, 31, 4, 14, 4, 4, 0],
	"ｸ": [14, 1, 2, 4, 8, 0, 0],
	"ｹ": [8, 8, 14, 9, 10, 12, 8],
	"ｺ": [0, 14, 1, 1, 14, 0, 0],
	"ｻ": [10, 10, 31, 10, 10, 18, 0],
	"ｼ": [1, 2, 18, 18, 18, 12, 0],
	"ｽ": [14, 4, 4, 4, 4, 0, 0],
	"ｾ": [18, 18, 14, 2, 2, 4, 0],
	"ｿ": [2, 4, 8, 20, 8, 4, 0],
	"ﾀ": [8, 8, 14, 8, 8, 7, 0],
	"ﾁ": [4, 31, 4, 4, 4, 8, 0],
	"ﾂ": [10, 10, 0, 0, 0, 0, 0],
	"ﾃ": [31, 4, 4, 4, 4, 0, 0],
	"ﾄ": [8, 8, 8, 8, 10, 12, 0],
	# Pixel bar ramp (Live Visuals Engine).
	"▁": [0, 0, 0, 0, 0, 0, 31],
	"▂": [0, 0, 0, 0, 0, 31, 31],
	"▃": [0, 0, 0, 0, 31, 31, 31],
	"▄": [0, 0, 0, 31, 31, 31, 31],
	"▅": [0, 0, 31, 31, 31, 31, 31],
	"▆": [0, 31, 31, 31, 31, 31, 31],
	"▇": [31, 31, 31, 31, 31, 31, 31],
	# Glitch mosaic quadrants (approximated 5×7).
	"▚": [17, 10, 4, 4, 10, 17, 0],
	"▞": [1, 2, 4, 8, 20, 18, 17],
	"▙": [16, 16, 16, 16, 31, 31, 31],
	"▛": [31, 31, 31, 16, 16, 16, 16],
	"▜": [31, 31, 31, 1, 1, 1, 1],
	"▟": [1, 1, 1, 1, 31, 31, 31],
	# Braille density steps.
	"⠁": [4, 0, 0, 0, 0, 0, 0],
	"⠂": [0, 0, 4, 0, 0, 0, 0],
	"⠃": [4, 0, 4, 0, 0, 0, 0],
	"⠄": [0, 0, 0, 0, 4, 0, 0],
	"⠅": [4, 0, 0, 0, 4, 0, 0],
	"⠆": [0, 0, 4, 0, 4, 0, 0],
	"⠇": [4, 0, 4, 0, 4, 0, 0],
	"⠸": [4, 0, 4, 0, 4, 0, 4],
	"⠿": [10, 0, 10, 0, 10, 0, 10],
	# Crosses (sparse → dense).
	"×": [0, 17, 10, 4, 10, 17, 0],
	"✕": [17, 10, 4, 0, 4, 10, 17],
	"†": [4, 4, 31, 4, 4, 4, 4],
	"‡": [4, 31, 4, 31, 4, 4, 0],
	"✚": [4, 4, 14, 31, 14, 4, 4],
	"✙": [0, 4, 14, 31, 14, 4, 0],
	"┼": [4, 4, 31, 4, 31, 4, 4],
	"╋": [14, 14, 31, 14, 14, 14, 14],
	"✖": [17, 10, 4, 14, 4, 10, 17],
	# Elder Futhark (simplified 5×7).
	"ᛁ": [4, 4, 4, 4, 4, 4, 4],
	"ᚾ": [1, 2, 4, 8, 16, 16, 16],
	"ᚲ": [14, 16, 16, 16, 16, 16, 14],
	"ᚢ": [17, 17, 17, 17, 17, 10, 4],
	"ᚠ": [16, 16, 28, 18, 16, 16, 16],
	"ᚦ": [16, 16, 30, 17, 17, 16, 16],
	"ᚱ": [30, 17, 17, 30, 20, 18, 17],
	"ᚺ": [17, 17, 31, 17, 17, 17, 17],
	"ᛏ": [4, 14, 21, 4, 4, 4, 4],
	"ᛉ": [17, 17, 10, 4, 4, 4, 4],
	"ᛊ": [31, 1, 2, 4, 8, 16, 31],
	"ᛒ": [30, 17, 17, 30, 17, 17, 30],
	"ᛗ": [17, 27, 21, 17, 17, 17, 17],
	# Cyrillic (visual weight ramp).
	"і": [4, 0, 4, 4, 4, 4, 4],
	"о": [0, 0, 14, 17, 17, 17, 14],
	"с": [0, 0, 14, 16, 16, 16, 14],
	"е": [0, 0, 14, 17, 31, 16, 14],
	"а": [0, 0, 14, 1, 15, 17, 15],
	"н": [17, 17, 31, 17, 17, 17, 17],
	"к": [17, 18, 20, 24, 20, 18, 17],
	"д": [14, 2, 2, 2, 2, 2, 31],
	"ж": [17, 10, 4, 31, 4, 10, 17],
	"ш": [17, 17, 17, 17, 17, 17, 31],
	"щ": [17, 17, 17, 17, 17, 31, 2],
	"Ж": [17, 27, 14, 31, 14, 27, 17],
	"Ш": [17, 17, 17, 17, 31, 31, 31],
	"М": [17, 27, 21, 21, 17, 17, 17],
	# Emoji blocks / shapes (5×7 stand-ins that read at cell size).
	"▫": [0, 0, 0, 14, 14, 0, 0],
	"▪": [0, 0, 14, 14, 14, 0, 0],
	"□": [14, 17, 17, 17, 17, 17, 14],
	"■": [14, 31, 31, 31, 31, 31, 14],
	"⬜": [31, 17, 17, 17, 17, 17, 31],
	"⬛": [31, 31, 31, 31, 31, 31, 31],
	"🔲": [31, 17, 21, 21, 21, 17, 31],
	"🔳": [31, 31, 21, 21, 21, 31, 31],
	# Emoji faces / symbols.
	"☆": [4, 10, 17, 4, 14, 0, 0],
	"★": [4, 14, 31, 14, 10, 17, 0],
	"⭐": [4, 14, 31, 14, 31, 4, 0],
	"❤": [0, 10, 31, 31, 14, 4, 0],
	"💫": [4, 14, 4, 31, 4, 14, 4],
	"🔥": [4, 14, 14, 31, 14, 4, 14],
	"☀": [4, 14, 21, 14, 4, 0, 0],
	"✧": [4, 0, 14, 4, 0, 4, 0],
	"✦": [4, 14, 4, 31, 4, 14, 4],
	"✪": [4, 14, 21, 14, 31, 14, 4],
}


static func build_atlas(charset: String) -> ImageTexture:
	## Sync path: font atlas pages + 5×7 fallback. Never force_draw — that nested
	## redraw stole Feedback's history RT and stale-copied the output viewport.
	var chars := charset
	if chars.is_empty():
		chars = " .:-=+*#%@"
	var n := chars.length()
	var img := Image.create(n * CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var font := _ensure_font()
	for i in n:
		var ch := chars.substr(i, 1)
		var drawn := _blit_font_glyph(img, i * CELL, font, ch)
		if not drawn and BITMAPS.has(ch):
			_blit_glyph(img, i * CELL, ch)
	return ImageTexture.create_from_image(img)


static func start_viewport_atlas(charset: String) -> Dictionary:
	## One SubViewport strip, no force_draw. Caller waits natural frames, then finish.
	var font := _ensure_font()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or font == null:
		return {}
	if OS.has_feature("headless"):
		return {}
	var driver := RenderingServer.get_current_rendering_driver_name()
	if driver.is_empty() or driver.contains("dummy"):
		return {}
	var chars := charset if not charset.is_empty() else " .:-=+*#%@"
	var n := maxi(chars.length(), 1)
	var vp := SubViewport.new()
	vp.size = Vector2i(n * CELL, CELL)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var host := Control.new()
	host.size = Vector2(n * CELL, CELL)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(host)
	for i in chars.length():
		var ch := chars.substr(i, 1)
		var label := Label.new()
		label.position = Vector2(i * CELL, 0)
		label.size = Vector2(CELL, CELL)
		label.custom_minimum_size = Vector2(CELL, CELL)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not ch.is_empty() and ch.unicode_at(0) != 0x20:
			label.text = ch
		host.add_child(label)
	_bake_token += 1
	baking = true
	tree.root.add_child(vp)
	return {"vp": vp, "charset": chars, "token": _bake_token}


static func finish_viewport_atlas(bake: Dictionary) -> ImageTexture:
	var chars := str(bake.get("charset", ""))
	var tex: ImageTexture = null
	var token := int(bake.get("token", -1))
	if not bake.is_empty():
		var vp: SubViewport = bake.get("vp")
		if vp != null and not chars.is_empty() and is_instance_valid(vp):
			var snap: Image = vp.get_texture().get_image()
			if snap != null and not snap.is_empty():
				tex = _atlas_from_viewport_strip(chars, snap)
		_end_viewport_bake(bake)
	if token == _bake_token:
		baking = false
	if tex != null:
		return tex
	return build_atlas(chars)


static func abort_viewport_atlas(bake: Dictionary) -> void:
	_end_viewport_bake(bake)
	if int(bake.get("token", -1)) == _bake_token:
		baking = false


static func filter_charset(charset: String) -> String:
	var out := ""
	var seen := {}
	var font := _ensure_font()
	for i in charset.length():
		var c := charset.substr(i, 1)
		if seen.has(c):
			continue
		if not _can_render(c, font):
			continue
		seen[c] = true
		out += c
	return out if not out.is_empty() else " .:-=+*#%@"


static func _can_render(ch: String, font: Font) -> bool:
	if ch.is_empty():
		return false
	if BITMAPS.has(ch):
		return true
	var code := ch.unicode_at(0)
	if code == 0x20:
		return true
	if font != null and font.has_method("has_char") and font.has_char(code):
		return true
	return false


static func _ensure_font() -> Font:
	if _font != null:
		return _font
	var loaded: Array[Font] = []
	for p in FONT_PATHS:
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			continue
		var res: Variant = null
		if FileAccess.file_exists(p + ".import"):
			res = load(p)
		if not (res is Font):
			res = _load_ttf(p)
		if res is Font:
			loaded.append(res as Font)
	if loaded.is_empty():
		_font = ThemeDB.fallback_font
		return _font
	if loaded.size() == 1:
		_font = loaded[0]
		return _font
	var chain := FontVariation.new()
	chain.base_font = loaded[0]
	var fbs: Array[Font] = []
	for i in range(1, loaded.size()):
		fbs.append(loaded[i])
	chain.fallbacks = fbs
	_font = chain
	return _font


static func _load_ttf(res_path: String) -> Font:
	var ff := FontFile.new()
	ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	ff.multichannel_signed_distance_field = false
	var err := ff.load_dynamic_font(res_path)
	if err != OK:
		err = ff.load_dynamic_font(ProjectSettings.globalize_path(res_path))
	if err != OK:
		return null
	return ff


static func _end_viewport_bake(bake: Dictionary) -> void:
	if bake.is_empty():
		return
	var vp: SubViewport = bake.get("vp")
	if vp == null or not is_instance_valid(vp):
		return
	var parent := vp.get_parent()
	if parent:
		parent.remove_child(vp)
	vp.free()


static func _atlas_from_viewport_strip(chars: String, snap: Image) -> ImageTexture:
	if snap.get_format() != Image.FORMAT_RGBA8:
		snap.convert(Image.FORMAT_RGBA8)
	var n := chars.length()
	var img := Image.create(n * CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var font := _ensure_font()
	for i in n:
		var ch := chars.substr(i, 1)
		var drawn := false
		if ch.is_empty() or ch.unicode_at(0) == 0x20:
			drawn = true
		else:
			var src_x := i * CELL
			if src_x + CELL <= snap.get_width() and CELL <= snap.get_height():
				var cell := snap.get_region(Rect2i(src_x, 0, CELL, CELL))
				var ink := _normalize_glyph_image(cell)
				var coverage := 0
				for y in ink.get_height():
					for x in ink.get_width():
						if ink.get_pixel(x, y).a > 0.12:
							coverage += 1
				if coverage >= 8:
					img.blit_rect(ink, Rect2i(0, 0, ink.get_width(), ink.get_height()), Vector2i(src_x, 0))
					drawn = true
		if not drawn:
			drawn = _blit_font_glyph(img, i * CELL, font, ch)
		if not drawn and BITMAPS.has(ch):
			_blit_glyph(img, i * CELL, ch)
	return ImageTexture.create_from_image(img)


static func _font_rid_for_char(ts: TextServer, font: Font, code: int) -> RID:
	if font == null:
		return RID()
	if font is FontVariation:
		var fv := font as FontVariation
		var nested := _font_rid_for_char(ts, fv.base_font, code)
		if nested.is_valid():
			return nested
		for fb in fv.fallbacks:
			if fb is Font:
				nested = _font_rid_for_char(ts, fb, code)
				if nested.is_valid():
					return nested
		return RID()
	var rids: Array = font.get_rids()
	for rid in rids:
		if rid is RID and ts.font_has_char(rid, code):
			return rid
	for fb in font.fallbacks:
		if fb is Font:
			var nested := _font_rid_for_char(ts, fb, code)
			if nested.is_valid():
				return nested
	return RID()


static func _blit_font_glyph(img: Image, x0: int, font: Font, ch: String) -> bool:
	if font == null or ch.is_empty():
		return false
	var code := ch.unicode_at(0)
	if code == 0x20:
		return true
	var ts := TextServerManager.get_primary_interface()
	if ts == null:
		return false
	## Warm the glyph cache at this pixel size before sampling the atlas page.
	font.get_char_size(code, FONT_SIZE)
	var font_rid := _font_rid_for_char(ts, font, code)
	if not font_rid.is_valid():
		return false
	var glyph := ts.font_get_glyph_index(font_rid, FONT_SIZE, code, 0)
	if glyph == 0 and not ts.font_has_char(font_rid, code):
		return false
	var sz := Vector2i(FONT_SIZE, 0)
	var tex_rid: RID = ts.font_get_glyph_texture_rid(font_rid, sz, glyph)
	if not tex_rid.is_valid():
		return false
	var page: Image = RenderingServer.texture_2d_get(tex_rid)
	if page == null or page.is_empty():
		return false
	var uv: Rect2 = ts.font_get_glyph_uv_rect(font_rid, sz, glyph)
	var src_x := clampi(int(uv.position.x), 0, maxi(page.get_width() - 1, 0))
	var src_y := clampi(int(uv.position.y), 0, maxi(page.get_height() - 1, 0))
	var src_w := clampi(int(round(uv.size.x)), 1, page.get_width() - src_x)
	var src_h := clampi(int(round(uv.size.y)), 1, page.get_height() - src_y)
	if src_w <= 0 or src_h <= 0:
		return false
	var cropped := page.get_region(Rect2i(src_x, src_y, src_w, src_h))
	if cropped == null or cropped.is_empty():
		return false
	var ink := _normalize_glyph_image(cropped)
	var coverage := 0
	for y in ink.get_height():
		for x in ink.get_width():
			if ink.get_pixel(x, y).a > 0.12:
				coverage += 1
	if coverage < 4:
		return false
	if ink.get_width() > CELL - 2 or ink.get_height() > CELL - 2:
		var fit := minf(float(CELL - 2) / float(ink.get_width()), float(CELL - 2) / float(ink.get_height()))
		ink.resize(
			maxi(1, int(ink.get_width() * fit)),
			maxi(1, int(ink.get_height() * fit)),
			Image.INTERPOLATE_LANCZOS
		)
	var dst_x := x0 + int((CELL - ink.get_width()) / 2.0)
	var dst_y := int((CELL - ink.get_height()) / 2.0)
	img.blit_rect(ink, Rect2i(0, 0, ink.get_width(), ink.get_height()), Vector2i(dst_x, dst_y))
	return true


static func _normalize_glyph_image(src: Image) -> Image:
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var min_a := 1.0
	var max_a := 0.0
	var min_l := 1.0
	for y in h:
		for x in w:
			var p := src.get_pixel(x, y)
			min_a = minf(min_a, p.a)
			max_a = maxf(max_a, p.a)
			min_l = minf(min_l, (p.r + p.g + p.b) / 3.0)
	## Empty GPU readback is white RGB with A=0 — do not turn that into tofu boxes.
	if max_a < 0.08 and min_l > 0.85:
		return out
	## L8 / opaque atlas pages keep A=1; coverage lives in RGB. Alpha-only pages vary A.
	var use_alpha := (max_a - min_a) > 0.08
	for y in h:
		for x in w:
			var p := src.get_pixel(x, y)
			var cov := p.a if use_alpha else (p.r + p.g + p.b) / 3.0
			if cov > 0.08:
				out.set_pixel(x, y, Color(1, 1, 1, cov))
	return out


static func _blit_glyph(img: Image, x0: int, ch: String) -> void:
	var rows: Array = BITMAPS.get(ch, BITMAPS["."])
	var gw := 5
	var gh := 7
	var scale := maxi(2, int(CELL / 8))
	var pad_x := int((CELL - gw * scale) / 2.0)
	var pad_y := int((CELL - gh * scale) / 2.0)
	for y in gh:
		var bits: int = int(rows[y]) if y < rows.size() else 0
		for x in gw:
			if (bits & (1 << (gw - 1 - x))) != 0:
				for sy in scale:
					for sx in scale:
						var px := x0 + pad_x + x * scale + sx
						var py := pad_y + y * scale + sy
						if px >= x0 and px < x0 + CELL and py >= 0 and py < CELL:
							img.set_pixel(px, py, Color.WHITE)
