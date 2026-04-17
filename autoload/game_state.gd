extends Node


const SAVE_PATH := "user://save.json"
const MANIFEST_PATH := "res://data/book_manifest.json"

var manifest: Dictionary = {}
var chapter_lengths: Dictionary = {} ## chapter_id -> int

var chapter_read_ratio: Dictionary = {} ## chapter_id -> float 0..1
var chapters_completed: Dictionary = {} ## chapter_id -> bool
var total_hp: int = 0
var comments_posted_count: int = 0
var achievements: PackedStringArray = PackedStringArray()

signal progress_changed
signal achievements_changed


func _ready() -> void:
	_load_manifest()
	_compute_chapter_lengths()
	load_game()
	_check_achievements()


func _load_manifest() -> void:
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		push_error("Missing book manifest at %s" % MANIFEST_PATH)
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if data is Dictionary:
		manifest = data
	else:
		push_error("Invalid manifest JSON")


func _compute_chapter_lengths() -> void:
	chapter_lengths.clear()
	if manifest.is_empty():
		return
	for ch in manifest.get("chapters", []):
		if ch is Dictionary:
			var path: String = ch.get("path", "")
			var cid: String = ch.get("chapter_id", "")
			if path.is_empty() or cid.is_empty():
				continue
			var cf := FileAccess.open(path, FileAccess.READ)
			if cf:
				chapter_lengths[cid] = cf.get_as_text().length()
				cf.close()
			else:
				chapter_lengths[cid] = 0


func get_book_id() -> String:
	return str(manifest.get("book_id", ""))


func get_book_title() -> String:
	return str(manifest.get("title", "Book"))


func get_chapters() -> Array:
	return manifest.get("chapters", []) as Array


func get_chapter_meta(chapter_id: String) -> Dictionary:
	for ch in get_chapters():
		if ch is Dictionary and str(ch.get("chapter_id", "")) == chapter_id:
			return ch
	return {}


func get_total_chars() -> int:
	var sum := 0
	for _k in chapter_lengths:
		sum += int(chapter_lengths[_k])
	return maxi(sum, 1)


func get_weighted_book_ratio() -> float:
	var total := get_total_chars()
	var acc := 0.0
	for cid in chapter_lengths:
		var w: int = int(chapter_lengths[cid])
		var r: float = float(chapter_read_ratio.get(cid, 0.0))
		if bool(chapters_completed.get(cid, false)):
			r = 1.0
		acc += r * float(w)
	return clampf(acc / float(total), 0.0, 1.0)


func set_chapter_read_ratio(chapter_id: String, ratio: float) -> void:
	chapter_read_ratio[chapter_id] = clampf(ratio, 0.0, 1.0)
	progress_changed.emit()
	save_game()
	_check_achievements()


func try_complete_chapter(chapter_id: String) -> bool:
	if bool(chapters_completed.get(chapter_id, false)):
		return false
	var ratio: float = float(chapter_read_ratio.get(chapter_id, 0.0))
	if ratio < 0.85:
		return false
	var meta := get_chapter_meta(chapter_id)
	var reward: int = int(meta.get("hp_reward", 0))
	chapters_completed[chapter_id] = true
	total_hp += reward
	progress_changed.emit()
	save_game()
	_check_achievements()
	return true


func record_comment_posted() -> void:
	comments_posted_count += 1
	save_game()
	_check_achievements()


func unlock_achievement(id: String) -> void:
	if achievements.has(id):
		return
	achievements.append(id)
	achievements_changed.emit()
	save_game()


func _check_achievements() -> void:
	if bool(chapters_completed.get("ch1", false)):
		unlock_achievement("first_chapter")
	if total_hp >= 20:
		unlock_achievement("hp_20")
	if comments_posted_count >= 1:
		unlock_achievement("first_comment")


func save_game() -> void:
	var data := {
		"chapter_read_ratio": chapter_read_ratio,
		"chapters_completed": chapters_completed,
		"total_hp": total_hp,
		"comments_posted_count": comments_posted_count,
		"achievements": achievements,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var d: Dictionary = parsed
		chapter_read_ratio = _dict_to_float_dict(d.get("chapter_read_ratio", {}))
		chapters_completed = _dict_to_bool_dict(d.get("chapters_completed", {}))
		total_hp = int(d.get("total_hp", 0))
		comments_posted_count = int(d.get("comments_posted_count", 0))
		var ach = d.get("achievements", [])
		if ach is Array:
			achievements.clear()
			for a in ach:
				achievements.append(str(a))


func _dict_to_float_dict(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			out[str(k)] = float(v[k])
	return out


func _dict_to_bool_dict(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			out[str(k)] = bool(v[k])
	return out


func build_reading_progress_rows() -> Array:
	var rows: Array = []
	var book_id := get_book_id()
	for cid in chapter_lengths:
		rows.append(
			{
				"book_id": book_id,
				"chapter_id": cid,
				"max_ratio": float(chapter_read_ratio.get(cid, 0.0)),
				"completed": bool(chapters_completed.get(cid, false)),
			}
		)
	return rows
