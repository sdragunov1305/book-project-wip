extends RefCounted
class_name QuizBank


const BANK_PATH := "res://data/quiz_bank.json"


static func pick_five_shuffled() -> Array:
	var all := _load_all()
	if all.is_empty():
		return []
	all.shuffle()
	var take := mini(5, all.size())
	var out: Array = []
	for i in range(take):
		var q = all[i]
		if q is Dictionary:
			out.append(_shuffle_answers(q))
	return out


static func _load_all() -> Array:
	if not FileAccess.file_exists(BANK_PATH):
		return []
	var f := FileAccess.open(BANK_PATH, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Array:
		return d.duplicate()
	return []


static func _shuffle_answers(q: Dictionary) -> Dictionary:
	var answers: Array = q.get("a", [])
	if answers.size() != 4:
		return q.duplicate()
	var ci: int = clampi(int(q.get("c", 0)), 0, 3)
	var opts: Array = []
	for i in range(4):
		opts.append({"t": str(answers[i]), "ok": i == ci})
	opts.shuffle()
	## Plain Array so UI code can use `ans is Array` (PackedStringArray is not Array).
	var new_a: Array = []
	var new_c := 0
	for j in range(4):
		var o: Dictionary = opts[j]
		new_a.append(str(o.get("t", "")))
		if bool(o.get("ok", false)):
			new_c = j
	return {"q": str(q.get("q", "")), "a": new_a, "c": new_c}
