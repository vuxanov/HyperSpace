class_name GifDecoder
extends RefCounted

## Pure GDScript GIF89a / GIF87a frame decoder (no ffmpeg).
## Returns RGBA8 Image frames + delay seconds for AnimatedTexture / manual cycling.


const MAX_FRAMES := 90


static func decode_path(path: String) -> Dictionary:
	## { "ok": bool, "frames": Array[Image], "durations": Array[float], "width": int, "height": int }
	var abs_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	abs_path = abs_path.replace("\\", "/")
	if not FileAccess.file_exists(abs_path):
		return {"ok": false, "frames": [], "durations": [], "width": 0, "height": 0}
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "frames": [], "durations": [], "width": 0, "height": 0}
	var data := f.get_buffer(f.get_length())
	f.close()
	return decode_bytes(data)


static func decode_bytes(data: PackedByteArray) -> Dictionary:
	var empty := {"ok": false, "frames": [], "durations": [], "width": 0, "height": 0}
	if data.size() < 13:
		return empty
	var sig := data.slice(0, 6).get_string_from_ascii()
	if sig != "GIF87a" and sig != "GIF89a":
		return empty
	var width := data[6] | (data[7] << 8)
	var height := data[8] | (data[9] << 8)
	var packed := data[10]
	var gct_flag := (packed & 0x80) != 0
	var gct_size := 1 << ((packed & 0x07) + 1)
	var pos := 13
	var gct: PackedByteArray = PackedByteArray()
	if gct_flag:
		var gct_bytes := gct_size * 3
		if pos + gct_bytes > data.size():
			return empty
		gct = data.slice(pos, pos + gct_bytes)
		pos += gct_bytes

	var frames: Array[Image] = []
	var durations: Array[float] = []
	var canvas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var prev_canvas: Image = null
	var delay_cs := 8
	var dispose := 0
	var prev_dispose := 0
	var transparent_index := -1
	var prev_left := 0
	var prev_top := 0
	var prev_fw := 0
	var prev_fh := 0

	while pos < data.size() and frames.size() < MAX_FRAMES:
		var block := data[pos]
		pos += 1
		if block == 0x3B: # trailer
			break
		if block == 0x21: # extension
			if pos >= data.size():
				break
			var label := data[pos]
			pos += 1
			if label == 0xF9: # Graphic Control Extension
				if pos >= data.size():
					break
				var blksz := data[pos]
				pos += 1
				if blksz >= 4 and pos + 4 <= data.size():
					var gpacked := data[pos]
					dispose = (gpacked >> 2) & 0x07
					var t_flag := (gpacked & 0x01) != 0
					delay_cs = data[pos + 1] | (data[pos + 2] << 8)
					if delay_cs <= 0:
						delay_cs = 8
					transparent_index = data[pos + 3] if t_flag else -1
					pos += blksz
				else:
					pos += blksz
				if pos < data.size() and data[pos] == 0:
					pos += 1
			else:
				# Skip application / comment / plain text blocks.
				while pos < data.size():
					var sz := data[pos]
					pos += 1
					if sz == 0:
						break
					pos += sz
			continue
		if block != 0x2C: # image descriptor
			continue
		if pos + 9 > data.size():
			break
		var left := data[pos] | (data[pos + 1] << 8)
		var top := data[pos + 2] | (data[pos + 3] << 8)
		var fw := data[pos + 4] | (data[pos + 5] << 8)
		var fh := data[pos + 6] | (data[pos + 7] << 8)
		var ipacked := data[pos + 8]
		pos += 9
		var lct_flag := (ipacked & 0x80) != 0
		var interlace := (ipacked & 0x40) != 0
		var lct_size := 1 << ((ipacked & 0x07) + 1)
		var local_ct := gct
		if lct_flag:
			var lct_bytes := lct_size * 3
			if pos + lct_bytes > data.size():
				break
			local_ct = data.slice(pos, pos + lct_bytes)
			pos += lct_bytes
		if pos >= data.size():
			break
		var min_code_size := data[pos]
		pos += 1
		var compressed := PackedByteArray()
		while pos < data.size():
			var sz2 := data[pos]
			pos += 1
			if sz2 == 0:
				break
			if pos + sz2 > data.size():
				compressed.append_array(data.slice(pos, data.size()))
				pos = data.size()
				break
			compressed.append_array(data.slice(pos, pos + sz2))
			pos += sz2

		# Apply previous frame's disposal before composing this frame.
		if prev_dispose == 2:
			_clear_rect(canvas, prev_left, prev_top, prev_fw, prev_fh)
		elif prev_dispose == 3 and prev_canvas != null:
			canvas.copy_from(prev_canvas)

		# Snapshot before draw when this frame requests restore-previous.
		if dispose == 3:
			prev_canvas = canvas.duplicate()

		var indices := _lzw_decode(compressed, min_code_size, fw * fh)
		if indices.is_empty() and fw * fh > 0:
			transparent_index = -1
			delay_cs = 8
			dispose = 0
			continue

		_blit_indices(canvas, indices, left, top, fw, fh, local_ct, transparent_index, interlace)
		frames.append(canvas.duplicate())
		durations.append(maxf(float(delay_cs) / 100.0, 0.02))

		prev_dispose = dispose
		prev_left = left
		prev_top = top
		prev_fw = fw
		prev_fh = fh
		transparent_index = -1
		delay_cs = 8
		dispose = 0

	if frames.is_empty():
		return empty
	return {
		"ok": true,
		"frames": frames,
		"durations": durations,
		"width": width,
		"height": height,
	}


static func _clear_rect(canvas: Image, left: int, top: int, fw: int, fh: int) -> void:
	var cw := canvas.get_width()
	var ch := canvas.get_height()
	if fw <= 0 or fh <= 0 or cw <= 0 or ch <= 0:
		return
	var data := canvas.get_data()
	var y0 := maxi(top, 0)
	var y1 := mini(top + fh, ch)
	var x0 := maxi(left, 0)
	var x1 := mini(left + fw, cw)
	for py in range(y0, y1):
		var row := py * cw * 4
		for px in range(x0, x1):
			var off := row + px * 4
			data[off] = 0
			data[off + 1] = 0
			data[off + 2] = 0
			data[off + 3] = 0
	canvas.set_data(cw, ch, false, Image.FORMAT_RGBA8, data)


static func _blit_indices(
	canvas: Image,
	indices: PackedByteArray,
	left: int,
	top: int,
	fw: int,
	fh: int,
	ct: PackedByteArray,
	transparent_index: int,
	interlace: bool
) -> void:
	var cw := canvas.get_width()
	var ch := canvas.get_height()
	if fw <= 0 or fh <= 0 or cw <= 0 or ch <= 0:
		return
	var data := canvas.get_data()
	var pass_rows: PackedInt32Array = PackedInt32Array()
	if interlace:
		for y in range(0, fh, 8):
			pass_rows.append(y)
		for y in range(4, fh, 8):
			pass_rows.append(y)
		for y in range(2, fh, 4):
			pass_rows.append(y)
		for y in range(1, fh, 2):
			pass_rows.append(y)
	else:
		pass_rows.resize(fh)
		for y in fh:
			pass_rows[y] = y
	var i := 0
	for row_i in pass_rows.size():
		var y := int(pass_rows[row_i])
		for x in fw:
			if i >= indices.size():
				canvas.set_data(cw, ch, false, Image.FORMAT_RGBA8, data)
				return
			var idx := indices[i]
			i += 1
			if idx == transparent_index:
				continue
			var px := left + x
			var py := top + y
			if px < 0 or py < 0 or px >= cw or py >= ch:
				continue
			var coff := idx * 3
			if coff + 2 >= ct.size():
				continue
			var off := (py * cw + px) * 4
			data[off] = ct[coff]
			data[off + 1] = ct[coff + 1]
			data[off + 2] = ct[coff + 2]
			data[off + 3] = 255
	canvas.set_data(cw, ch, false, Image.FORMAT_RGBA8, data)


static func _lzw_decode(data: PackedByteArray, min_code_size: int, expected: int) -> PackedByteArray:
	var clear_code := 1 << min_code_size
	var end_code := clear_code + 1
	var code_size := min_code_size + 1
	var next_code := end_code + 1
	var table: Array = []
	table.resize(4096)
	for i in clear_code:
		table[i] = PackedByteArray([i])

	var out := PackedByteArray()
	out.resize(maxi(expected, 0))
	var out_i := 0
	var bit_pos := 0
	var data_size := data.size()
	var prev: PackedByteArray = PackedByteArray()

	while bit_pos < data_size * 8 and out_i < expected:
		var code := _read_bits(data, bit_pos, code_size)
		bit_pos += code_size
		if code < 0:
			break
		if code == clear_code:
			code_size = min_code_size + 1
			next_code = end_code + 1
			for i2 in clear_code:
				table[i2] = PackedByteArray([i2])
			for i3 in range(clear_code, 4096):
				table[i3] = null
			prev = PackedByteArray()
			continue
		if code == end_code:
			break
		var entry: PackedByteArray
		if code < next_code and table[code] != null:
			entry = table[code]
		elif code == next_code and prev.size() > 0:
			entry = prev.duplicate()
			entry.append(prev[0])
		else:
			break
		for b in entry:
			if out_i < out.size():
				out[out_i] = b
			else:
				out.append(b)
			out_i += 1
			if out_i >= expected:
				break
		if prev.size() > 0 and next_code < 4096:
			var new_entry := prev.duplicate()
			new_entry.append(entry[0])
			table[next_code] = new_entry
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1
		prev = entry

	if out_i < out.size():
		out.resize(out_i)
	return out


static func _read_bits(data: PackedByteArray, bit_pos: int, nbits: int) -> int:
	var value := 0
	for i in nbits:
		var byte_i := (bit_pos + i) >> 3
		if byte_i >= data.size():
			return -1
		var bit := (data[byte_i] >> ((bit_pos + i) & 7)) & 1
		value |= bit << i
	return value
