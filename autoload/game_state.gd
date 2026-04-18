extends Node


const SAVE_PATH := "user://save.json"
const BOOK_SOURCE_PATH := "res://config/book_source.json"
const ARC_PARTS_PATH := "res://config/book_arc_parts.json"
## Optional: set a machine-local default EPUB path here (UTF-8), or leave empty and use book_source.json only.
const _EPUB_DOWNLOADS_FALLBACK := ""
const SAMPLE_MANIFEST_PATH := "res://data/book_manifest.json"

var manifest: Dictionary = {}
var chapter_lengths: Dictionary = {} ## chapter_id -> int

var chapter_read_ratio: Dictionary = {} ## chapter_id -> float 0..1
## Runtime only (cleared on load): scrollbar is physically at chapter end (reader updates each scroll).
var chapter_at_scroll_end: Dictionary = {} ## chapter_id -> bool
var chapters_completed: Dictionary = {} ## chapter_id -> bool
var total_hp: int = 0
var comments_posted_count: int = 0
var achievements: PackedStringArray = PackedStringArray()
## Highest chapter index (0-based) selectable in the list; complete flow unlocks next.
var linear_unlock_index: int = 0

signal progress_changed
signal achievements_changed


func _ready() -> void:
	_load_manifest_with_epub_priority()
	_ensure_readable_book_or_sample()
	_compute_chapter_lengths()
	load_game()
	_check_achievements()


func _manifest_has_chapter_list() -> bool:
	var chs: Variant = manifest.get("chapters", [])
	return chs is Array and not (chs as Array).is_empty()


func _count_readable_chars_in_current_manifest() -> int:
	if manifest.is_empty():
		return 0
	var chs: Variant = manifest.get("chapters", [])
	if not chs is Array:
		return 0
	var sum := 0
	for ch in chs as Array:
		if ch is Dictionary:
			sum += str(ch.get("text", "")).length()
			var p := str(ch.get("path", ""))
			if not p.is_empty() and FileAccess.file_exists(p):
				var f := FileAccess.open(p, FileAccess.READ)
				if f:
					sum += f.get_as_text().length()
					f.close()
	return sum


func _ensure_readable_book_or_sample() -> void:
	if not _manifest_has_chapter_list():
		push_warning("Manifest has no chapters; loading sample book.")
		_load_sample_manifest_fallback()
		return
	if _count_readable_chars_in_current_manifest() < 80:
		push_warning("Manifest text is almost empty (broken EPUB/encoding); loading sample book.")
		_load_sample_manifest_fallback()


func _load_sample_manifest_fallback() -> void:
	if not FileAccess.file_exists(SAMPLE_MANIFEST_PATH):
		_load_placeholder_manifest()
		return
	var f := FileAccess.open(SAMPLE_MANIFEST_PATH, FileAccess.READ)
	if f == null:
		_load_placeholder_manifest()
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		_load_placeholder_manifest()
		return
	var d: Dictionary = parsed
	if not d.has("chapters"):
		_load_placeholder_manifest()
		return
	manifest = d
	push_warning("Using sample book from data/book_manifest.json (EPUB missing, unreadable, or produced empty text).")


func _load_manifest_with_epub_priority() -> void:
	for epub_path in _epub_paths_to_try():
		if epub_path.is_empty():
			continue
		if not FileAccess.file_exists(epub_path):
			continue
		var loaded := EpubLoader.load_epub(epub_path)
		if bool(loaded.get("ok", false)):
			var m = loaded.get("manifest", null)
			if m is Dictionary:
				var ch0: Variant = m.get("chapters", [])
				if ch0 is Array and not (ch0 as Array).is_empty():
					manifest = m
					_maybe_merge_story_arcs()
					return
				push_warning("EPUB ok but manifest has no chapters: %s" % epub_path)
			else:
				push_warning("EPUB ok but manifest is not a Dictionary: %s" % epub_path)
		else:
			push_warning("EPUB failed for '%s': %s" % [epub_path, str(loaded.get("error", "?"))])
	# No EPUB: try bundled sample chapters so the picker is not empty (main.epub is usually gitignored).
	_load_sample_manifest_fallback()
	if not _manifest_has_chapter_list():
		_load_placeholder_manifest()


func _epub_paths_to_try() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var p1 := _read_epub_path_from_config()
	if not p1.is_empty() and not seen.has(p1):
		out.append(p1)
		seen[p1] = true
	var p2 := "res://books/main.epub"
	if not seen.has(p2):
		out.append(p2)
		seen[p2] = true
	var p3 := _EPUB_DOWNLOADS_FALLBACK.replace("\\", "/")
	if not seen.has(p3):
		out.append(p3)
		seen[p3] = true
	return out


func _read_epub_path_from_config() -> String:
	if not FileAccess.file_exists(BOOK_SOURCE_PATH):
		return ""
	var f := FileAccess.open(BOOK_SOURCE_PATH, FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		return str(d.get("epub_path", "")).strip_edges()
	return ""


func _maybe_merge_story_arcs() -> void:
	var cfg := BookArcMerger.load_parts_config(ARC_PARTS_PATH)
	if not bool(cfg.get("enabled", false)):
		return
	var parts: Array = cfg.get("parts", []) as Array
	if parts.size() != 3:
		return
	var raw: Array = manifest.get("chapters", []) as Array
	if raw.size() < 3:
		return
	var ver := int(cfg.get("text_version", 2))
	var merged: Array = BookArcMerger.merge_into_three_parts(raw, parts, ver)
	if merged.size() != 3:
		return
	var merged_chars := 0
	for m in merged:
		if m is Dictionary:
			merged_chars += str(m.get("text", "")).length()
	if merged_chars < 16:
		push_warning("book_arc_parts: merged chapters look empty; keeping original spine chapters.")
		return
	manifest["chapters"] = merged


func _load_placeholder_manifest() -> void:
	var msg := (
		"Could not load any EPUB.\n\n"
		+ "1) Copy your book to the project folder books/ and rename it to: main.epub\n"
		+ "   (path res://books/main.epub)\n\n"
		+ "2) Or set \"epub_path\" in res://config/book_source.json to the full path of your .epub\n"
		+ "   Save that file as UTF-8 if the path contains non-English letters.\n\n"
		+ "3) Or set _EPUB_DOWNLOADS_FALLBACK in game_state.gd for a personal default path (keep empty in git).\n"
	)
	manifest = {
		"book_id": "no_epub",
		"title": "Book not loaded",
		"chapters":
		[
			{
				"chapter_id": "howto",
				"title": "How to load your book",
				"path": "",
				"text": msg,
				"text_version": 1,
				"hp_reward": 0,
			}
		],
	}
	push_error("No EPUB loaded. See on-screen instructions.")


func _compute_chapter_lengths() -> void:
	chapter_lengths.clear()
	if manifest.is_empty():
		return
	for ch in manifest.get("chapters", []):
		if ch is Dictionary:
			var cid: String = ch.get("chapter_id", "")
			if cid.is_empty():
				continue
			if ch.has("text"):
				chapter_lengths[cid] = str(ch["text"]).length()
				continue
			var path: String = ch.get("path", "")
			if path.is_empty():
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


func get_book_load_error_report() -> String:
	var lines: Array = []
	lines.append("Книга не загрузилась: в списке 0 глав.")
	lines.append("book_id: %s" % get_book_id())
	lines.append("title: %s" % get_book_title())
	var epub_res := "res://books/main.epub"
	lines.append("exists %s: %s" % [epub_res, str(FileAccess.file_exists(epub_res))])
	if FileAccess.file_exists(BOOK_SOURCE_PATH):
		var cf := FileAccess.open(BOOK_SOURCE_PATH, FileAccess.READ)
		if cf:
			lines.append("book_source.json: %s" % cf.get_as_text().strip_edges())
			cf.close()
	var chs := get_chapters()
	lines.append("manifest chapters: %d" % chs.size())
	var probe := EpubLoader.load_epub(epub_res)
	lines.append(
		"probe EPUB ok=%s err=%s" % [str(probe.get("ok", false)), str(probe.get("error", ""))]
	)
	if bool(probe.get("ok", false)):
		var pm = probe.get("manifest", null)
		if pm is Dictionary:
			var pc: Array = pm.get("chapters", []) as Array
			lines.append("probe chapter count: %d" % pc.size())
	lines.append("")
	lines.append("Если probe ок, а manifest пуст — удали user://save.json (сбой прогресса) и перезапусти.")
	return "\n".join(lines)


func get_chapters() -> Array:
	var v: Variant = manifest.get("chapters", [])
	if v is Array:
		return v
	return []


func get_chapter_meta(chapter_id: String) -> Dictionary:
	for ch in get_chapters():
		if ch is Dictionary and str(ch.get("chapter_id", "")) == chapter_id:
			return ch
	return {}


func get_chapter_plain_text(chapter_id: String) -> String:
	var meta := get_chapter_meta(chapter_id)
	if meta.has("text"):
		return str(meta["text"])
	var p := str(meta.get("path", ""))
	if p.is_empty():
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func get_first_chapter_id() -> String:
	var chs := get_chapters()
	if chs.is_empty():
		return ""
	var c0 = chs[0]
	if c0 is Dictionary:
		return str(c0.get("chapter_id", ""))
	return ""


func get_chapter_index(chapter_id: String) -> int:
	var chs := get_chapters()
	for i in range(chs.size()):
		var ch = chs[i]
		if ch is Dictionary and str(ch.get("chapter_id", "")) == chapter_id:
			return i
	return -1


func can_select_chapter_index(idx: int) -> bool:
	return idx >= 0 and idx <= linear_unlock_index


func get_next_chapter_title_after(chapter_id: String) -> String:
	var chs := get_chapters()
	var i := get_chapter_index(chapter_id)
	if i < 0 or i >= chs.size() - 1:
		return ""
	var nx = chs[i + 1]
	if nx is Dictionary:
		return str(nx.get("title", ""))
	return ""


func is_eligible_for_completion_flow(chapter_id: String) -> bool:
	if bool(chapters_completed.get(chapter_id, false)):
		return false
	if not bool(chapter_at_scroll_end.get(chapter_id, false)):
		return false
	var idx := get_chapter_index(chapter_id)
	if idx < 0:
		return false
	return idx == linear_unlock_index


func finalize_chapter_completion(chapter_id: String) -> bool:
	if bool(chapters_completed.get(chapter_id, false)):
		return false
	var idx := get_chapter_index(chapter_id)
	if idx < 0 or idx != linear_unlock_index:
		return false
	var meta := get_chapter_meta(chapter_id)
	var reward: int = int(meta.get("hp_reward", 0))
	chapters_completed[chapter_id] = true
	total_hp += reward
	var last_i := get_chapters().size() - 1
	linear_unlock_index = mini(idx + 1, maxi(last_i, 0))
	progress_changed.emit()
	save_game()
	_check_achievements()
	return true


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


func set_chapter_read_ratio(chapter_id: String, ratio: float, at_scroll_end: bool = false) -> void:
	chapter_read_ratio[chapter_id] = clampf(ratio, 0.0, 1.0)
	chapter_at_scroll_end[chapter_id] = at_scroll_end
	progress_changed.emit()
	save_game()
	_check_achievements()


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
	var first_id := get_first_chapter_id()
	if not first_id.is_empty() and bool(chapters_completed.get(first_id, false)):
		unlock_achievement("first_chapter")
	if total_hp >= 20:
		unlock_achievement("hp_20")
	if comments_posted_count >= 1:
		unlock_achievement("first_comment")


func debug_reset_reading_progress() -> void:
	chapter_read_ratio.clear()
	chapter_at_scroll_end.clear()
	chapters_completed.clear()
	linear_unlock_index = 0
	save_game()
	progress_changed.emit()
	_check_achievements()


func save_game() -> void:
	var data := {
		"book_id": get_book_id(),
		"chapter_read_ratio": chapter_read_ratio,
		"chapters_completed": chapters_completed,
		"total_hp": total_hp,
		"comments_posted_count": comments_posted_count,
		"achievements": achievements,
		"linear_unlock_index": linear_unlock_index,
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
		var saved_bid := str(d.get("book_id", "")).strip_edges()
		var cur_bid := get_book_id()
		var reset_reading := not saved_bid.is_empty() and not cur_bid.is_empty() and saved_bid != cur_bid
		if reset_reading:
			push_warning("Save was for book '%s'; current book is '%s'. Reading progress reset." % [saved_bid, cur_bid])
		if reset_reading:
			chapter_read_ratio.clear()
			chapters_completed.clear()
			linear_unlock_index = 0
		else:
			chapter_read_ratio = _dict_to_float_dict(d.get("chapter_read_ratio", {}))
			chapters_completed = _dict_to_bool_dict(d.get("chapters_completed", {}))
			if d.has("linear_unlock_index"):
				linear_unlock_index = int(d.get("linear_unlock_index", 0))
			else:
				_migrate_linear_unlock_from_completed()
		total_hp = int(d.get("total_hp", 0))
		comments_posted_count = int(d.get("comments_posted_count", 0))
		var ach = d.get("achievements", [])
		if ach is Array:
			achievements.clear()
			for a in ach:
				achievements.append(str(a))
		linear_unlock_index = clampi(linear_unlock_index, 0, maxi(get_chapters().size() - 1, 0))
	chapter_at_scroll_end.clear()


func _migrate_linear_unlock_from_completed() -> void:
	var chs := get_chapters()
	var u := 0
	for i in range(chs.size()):
		var ch = chs[i]
		if ch is Dictionary:
			var cid := str(ch.get("chapter_id", ""))
			if bool(chapters_completed.get(cid, false)):
				u = i + 1
			else:
				break
	linear_unlock_index = mini(u, maxi(chs.size() - 1, 0))


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
