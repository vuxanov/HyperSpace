extends RefCounted
class_name DriverExpr

## Tiny safe math: numbers, identifiers, + - * / ( ). No GDScript eval.
## Unknown identifiers → 0. Divide by zero → 0.

enum _Tok { NUM, IDENT, OP, LP, RP, END }


static func is_plain_number(text: String) -> bool:
	var t := text.strip_edges()
	if t.is_empty():
		return false
	return t.is_valid_float()


static func looks_like_expr(text: String) -> bool:
	var t := text.strip_edges()
	if t.is_empty() or is_plain_number(t):
		return false
	return true


static func eval(expr: String, vars: Dictionary) -> float:
	var scr: GDScript = preload("res://core/driver_expr.gd")
	var p: Object = scr.new()
	return float(p.call("evaluate", expr, vars))


func evaluate(expr: String, vars: Dictionary) -> float:
	var tokens: Array = _tokenize(expr)
	if tokens.is_empty():
		return 0.0
	var pos := {"i": 0}
	var v := _parse_expr(tokens, pos, vars)
	if int(pos["i"]) < tokens.size() and int((tokens[int(pos["i"])] as Dictionary).get("t", _Tok.END)) != _Tok.END:
		return 0.0
	return v


func _tokenize(src: String) -> Array:
	var out: Array = []
	var i := 0
	var n := src.length()
	while i < n:
		var ch := src.unicode_at(i)
		if ch <= 32:
			i += 1
			continue
		if ch == 40:
			out.append({"t": _Tok.LP})
			i += 1
			continue
		if ch == 41:
			out.append({"t": _Tok.RP})
			i += 1
			continue
		if ch == 43 or ch == 45 or ch == 42 or ch == 47:
			out.append({"t": _Tok.OP, "op": String.chr(ch)})
			i += 1
			continue
		if (ch >= 48 and ch <= 57) or ch == 46:
			var start := i
			var dots := 0
			while i < n:
				var c2 := src.unicode_at(i)
				if c2 == 46:
					dots += 1
					if dots > 1:
						break
					i += 1
					continue
				if c2 >= 48 and c2 <= 57:
					i += 1
					continue
				break
			# Scientific notation: 1e4, 1E-3, 2.5e+2
			if i < n:
				var ee := src.unicode_at(i)
				if ee == 101 or ee == 69:
					var j := i + 1
					if j < n:
						var sgn := src.unicode_at(j)
						if sgn == 43 or sgn == 45:
							j += 1
					var exp_digits := 0
					while j < n:
						var ed := src.unicode_at(j)
						if ed >= 48 and ed <= 57:
							j += 1
							exp_digits += 1
							continue
						break
					if exp_digits > 0:
						i = j
			var num_s := src.substr(start, i - start)
			if not num_s.is_valid_float():
				return []
			out.append({"t": _Tok.NUM, "v": num_s.to_float()})
			continue
		if _is_ident_start(ch):
			var s0 := i
			i += 1
			while i < n and _is_ident_part(src.unicode_at(i)):
				i += 1
			out.append({"t": _Tok.IDENT, "s": src.substr(s0, i - s0).to_lower()})
			continue
		return []
	out.append({"t": _Tok.END})
	return out


func _is_ident_start(ch: int) -> bool:
	return (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 95


func _is_ident_part(ch: int) -> bool:
	return _is_ident_start(ch) or (ch >= 48 and ch <= 57)


func _peek(tokens: Array, pos: Dictionary) -> Dictionary:
	var i := int(pos["i"])
	if i < 0 or i >= tokens.size():
		return {"t": _Tok.END}
	return tokens[i] as Dictionary


func _eat(tokens: Array, pos: Dictionary) -> Dictionary:
	var tok := _peek(tokens, pos)
	pos["i"] = int(pos["i"]) + 1
	return tok


func _parse_expr(tokens: Array, pos: Dictionary, vars: Dictionary) -> float:
	var v := _parse_term(tokens, pos, vars)
	while true:
		var tok := _peek(tokens, pos)
		if int(tok.get("t", _Tok.END)) != _Tok.OP:
			break
		var op := str(tok.get("op", ""))
		if op != "+" and op != "-":
			break
		_eat(tokens, pos)
		var r := _parse_term(tokens, pos, vars)
		if op == "+":
			v += r
		else:
			v -= r
	return v


func _parse_term(tokens: Array, pos: Dictionary, vars: Dictionary) -> float:
	var v := _parse_unary(tokens, pos, vars)
	while true:
		var tok := _peek(tokens, pos)
		if int(tok.get("t", _Tok.END)) != _Tok.OP:
			break
		var op := str(tok.get("op", ""))
		if op != "*" and op != "/":
			break
		_eat(tokens, pos)
		var r := _parse_unary(tokens, pos, vars)
		if op == "*":
			v *= r
		else:
			if is_zero_approx(r):
				v = 0.0
			else:
				v = v / r
	return v


func _parse_unary(tokens: Array, pos: Dictionary, vars: Dictionary) -> float:
	var tok := _peek(tokens, pos)
	if int(tok.get("t", _Tok.END)) == _Tok.OP and str(tok.get("op", "")) == "-":
		_eat(tokens, pos)
		return -_parse_unary(tokens, pos, vars)
	if int(tok.get("t", _Tok.END)) == _Tok.OP and str(tok.get("op", "")) == "+":
		_eat(tokens, pos)
		return _parse_unary(tokens, pos, vars)
	return _parse_primary(tokens, pos, vars)


func _parse_primary(tokens: Array, pos: Dictionary, vars: Dictionary) -> float:
	var tok := _eat(tokens, pos)
	var kind := int(tok.get("t", _Tok.END))
	if kind == _Tok.NUM:
		return float(tok.get("v", 0.0))
	if kind == _Tok.IDENT:
		var name := str(tok.get("s", ""))
		if vars.has(name):
			return float(vars[name])
		return 0.0
	if kind == _Tok.LP:
		var v := _parse_expr(tokens, pos, vars)
		var close := _eat(tokens, pos)
		if int(close.get("t", _Tok.END)) != _Tok.RP:
			return 0.0
		return v
	return 0.0
