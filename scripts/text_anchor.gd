extends RefCounted
class_name TextAnchor


static func line_column_to_index(text_edit: TextEdit, line: int, column: int) -> int:
	var acc := 0
	for i in range(line):
		acc += text_edit.get_line(i).length() + 1
	acc += column
	return acc


static func selection_to_range(text_edit: TextEdit) -> Vector2i:
	if not text_edit.has_selection():
		return Vector2i(-1, -1)
	var from_line := text_edit.get_selection_from_line()
	var from_col := text_edit.get_selection_from_column()
	var to_line := text_edit.get_selection_to_line()
	var to_col := text_edit.get_selection_to_column()
	var i_from := line_column_to_index(text_edit, from_line, from_col)
	var i_to := line_column_to_index(text_edit, to_line, to_col)
	var start := mini(i_from, i_to)
	var end := maxi(i_from, i_to)
	return Vector2i(start, end)


static func index_to_line_column(text_edit: TextEdit, index: int) -> Vector2i:
	var lc := text_edit.get_line_count()
	if lc == 0:
		return Vector2i(0, 0)
	var max_i := text_edit.text.length()
	var idx := clampi(index, 0, maxi(max_i, 0))
	var acc := 0
	for line in range(lc):
		var ln := text_edit.get_line(line).length()
		var after_line := acc + ln
		if idx < after_line:
			return Vector2i(line, idx - acc)
		if idx == after_line:
			if line < lc - 1:
				return Vector2i(line + 1, 0)
			return Vector2i(line, ln)
		if line < lc - 1:
			acc = after_line + 1
		else:
			return Vector2i(line, ln)
	return Vector2i(lc - 1, text_edit.get_line(lc - 1).length())


static func select_index_range(text_edit: TextEdit, start: int, end_excl: int) -> void:
	var maxp := text_edit.text.length()
	var a := clampi(start, 0, maxp)
	var b := clampi(end_excl, 0, maxp)
	if b <= a:
		text_edit.deselect()
		return
	var from_lc := index_to_line_column(text_edit, a)
	var to_caret := index_to_line_column(text_edit, b)
	text_edit.select(from_lc.x, from_lc.y, to_caret.x, to_caret.y)


static func scroll_range_visible(text_edit: TextEdit, start: int, _end_excl: int) -> void:
	var from_lc := index_to_line_column(text_edit, clampi(start, 0, maxi(text_edit.text.length(), 0)))
	if text_edit.has_method("adjust_viewport_to_caret"):
		text_edit.adjust_viewport_to_caret(0)
		return
	var lh := int(ceil(maxf(text_edit.get_line_height(), 1.0)))
	text_edit.scroll_vertical = clampi(from_lc.x * lh, 0, 10_000_000)
