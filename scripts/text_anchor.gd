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
