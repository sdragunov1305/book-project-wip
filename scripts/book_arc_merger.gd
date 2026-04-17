extends RefCounted
class_name BookArcMerger


## Ровно три части: границы по накопленной длине текста (~⅓ и ~⅔ книги).
static func merge_into_three_parts(raw_chapters: Array, parts: Array, text_version: int) -> Array:
	if parts.size() != 3 or raw_chapters.size() < 3:
		return raw_chapters
	var sizes: Array[int] = []
	for ch in raw_chapters:
		if ch is Dictionary:
			sizes.append(str(ch.get("text", "")).length())
		else:
			sizes.append(0)
	var n := sizes.size()
	var total := 0
	for s in sizes:
		total += s
	if total < 1:
		return raw_chapters
	var cum: Array[int] = []
	var run := 0
	for s in sizes:
		run += s
		cum.append(run)
	var e0 := _first_exclusive_end(cum, total, 1.0 / 3.0)
	var e1 := _first_exclusive_end(cum, total, 2.0 / 3.0)
	e0 = clampi(e0, 1, n - 1)
	e1 = clampi(e1, e0 + 1, n)
	if e1 >= n:
		e1 = n - 1
	if e0 >= e1:
		e0 = maxi(1, e1 - 1)
	var cuts: Array[int] = [0, e0, e1, n]
	var out: Array = []
	for p in range(3):
		var a: int = cuts[p]
		var b: int = cuts[p + 1]
		var piece: PackedStringArray = PackedStringArray()
		var hp_sum := 0
		for i in range(a, b):
			var ch = raw_chapters[i]
			if ch is Dictionary:
				piece.append(str(ch.get("text", "")))
				hp_sum += int(ch.get("hp_reward", 0))
		var meta = parts[p]
		if not meta is Dictionary:
			return raw_chapters
		var cid := str(meta.get("chapter_id", "arc_%d" % p))
		out.append(
			{
				"chapter_id": cid,
				"title": str(meta.get("title", "Part %d" % (p + 1))),
				"blurb": str(meta.get("blurb", "")),
				"path": "",
				"text": "\n\n".join(piece),
				"text_version": text_version,
				"hp_reward": maxi(hp_sum, 10 + p * 5),
			}
		)
	return out


static func _first_exclusive_end(cum: Array, total: int, frac: float) -> int:
	if cum.is_empty():
		return 0
	var target := maxi(1, int(ceil(float(total) * frac)))
	for i in range(cum.size()):
		if int(cum[i]) >= target:
			return i + 1
	return cum.size()


static func load_parts_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		return d
	return {}
