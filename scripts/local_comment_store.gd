extends RefCounted
## Persists comments to user:// when cloud (Supabase) is disabled.

const _PATH := "user://local_comments.json"


static func _load_root() -> Dictionary:
	if not FileAccess.file_exists(_PATH):
		return {"version": 1, "comments": []}
	var f := FileAccess.open(_PATH, FileAccess.READ)
	if f == null:
		return {"version": 1, "comments": []}
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		var d: Dictionary = parsed
		if d.get("comments") is Array:
			return d
	return {"version": 1, "comments": []}


static func _save_root(root: Dictionary) -> void:
	var f := FileAccess.open(_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(root))
	f.close()


static func list_chapter(book_id: String, chapter_id: String, text_version: int) -> Array:
	var root := _load_root()
	var out: Array = []
	for it in root.get("comments", []):
		if it is Dictionary:
			var row: Dictionary = it
			if str(row.get("book_id", "")) != book_id:
				continue
			if str(row.get("chapter_id", "")) != chapter_id:
				continue
			if int(row.get("text_version", 0)) != text_version:
				continue
			out.append(row)
	return out


static func append_chapter(
	book_id: String,
	chapter_id: String,
	text_version: int,
	start_char: int,
	end_char: int,
	body: String,
	parent_id: String
) -> void:
	var root := _load_root()
	var comments: Array = root.get("comments", [])
	var id := "%d_%d_%d" % [Time.get_ticks_usec(), randi() % 1_000_000, comments.size()]
	var row := {
		"id": id,
		"book_id": book_id,
		"chapter_id": chapter_id,
		"text_version": text_version,
		"start_char": start_char,
		"end_char": end_char,
		"body": body,
		"parent_id": parent_id,
		"created_at": Time.get_datetime_string_from_system(),
	}
	comments.append(row)
	root["comments"] = comments
	_save_root(root)
