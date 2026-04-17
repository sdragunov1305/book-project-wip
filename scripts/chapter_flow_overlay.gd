extends CanvasLayer


signal skip_pressed
signal quiz_continue_pressed

const QUIZ_NEED := 3
const QUIZ_TOTAL := 5
const _OPTION_MIN_H := 56.0
const _NEXT_DELAY := 0.75

var _questions: Array = []

var _congrats: VBoxContainer
var _quiz: VBoxContainer
var _congrats_actions: HBoxContainer
var _quiz_feedback: Label
var _quiz_prog: Label
var _quiz_qtext: Label
var _quiz_opts: VBoxContainer
var _quiz_option_btns: Array[Button] = []
var _quiz_nav: HBoxContainer
var _main: Control

var _quiz_idx: int = 0
var _quiz_score: int = 0
var _quiz_locked: bool = false


func _ready() -> void:
	layer = 80
	visible = false
	_quiz_option_btns.clear()
	_main = Control.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_main)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_main.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 420)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)
	_congrats = VBoxContainer.new()
	_congrats.add_theme_constant_override("separation", 10)
	var ct := Label.new()
	ct.name = "CTitle"
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_congrats.add_child(ct)
	var cs := Label.new()
	cs.name = "CSub"
	cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_congrats.add_child(cs)
	_congrats_actions = HBoxContainer.new()
	_congrats_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var bq := Button.new()
	bq.text = "Quiz"
	bq.custom_minimum_size = Vector2(140, 44)
	bq.pressed.connect(_show_quiz)
	_congrats_actions.add_child(bq)
	var bs := Button.new()
	bs.text = "Skip"
	bs.custom_minimum_size = Vector2(140, 44)
	bs.pressed.connect(_emit_skip)
	_congrats_actions.add_child(bs)
	_congrats.add_child(_congrats_actions)
	outer.add_child(_congrats)
	_quiz = _build_quiz_duolingo_style()
	_quiz.visible = false
	outer.add_child(_quiz)


func _build_quiz_duolingo_style() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_quiz_prog = Label.new()
	_quiz_prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quiz_prog.add_theme_font_size_override("font_size", 15)
	box.add_child(_quiz_prog)
	_quiz_qtext = Label.new()
	_quiz_qtext.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quiz_qtext.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quiz_qtext.add_theme_font_size_override("font_size", 20)
	box.add_child(_quiz_qtext)
	_quiz_opts = VBoxContainer.new()
	_quiz_opts.add_theme_constant_override("separation", 10)
	_quiz_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_quiz_opts)
	for ai in range(4):
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, _OPTION_MIN_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.09))
		b.add_theme_color_override("font_pressed_color", Color(0.08, 0.08, 0.09))
		b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.09))
		b.add_theme_color_override("font_focus_color", Color(0.08, 0.08, 0.09))
		b.pressed.connect(_on_option_pressed.bind(ai))
		_quiz_opts.add_child(b)
		_quiz_option_btns.append(b)
	_quiz_feedback = Label.new()
	_quiz_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quiz_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quiz_feedback.add_theme_font_size_override("font_size", 18)
	box.add_child(_quiz_feedback)
	_quiz_nav = HBoxContainer.new()
	_quiz_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	_quiz_nav.add_theme_constant_override("separation", 12)
	var br := Button.new()
	br.text = "New set"
	br.custom_minimum_size = Vector2(120, 40)
	br.pressed.connect(_on_new_questions)
	_quiz_nav.add_child(br)
	var bb := Button.new()
	bb.text = "Back"
	bb.custom_minimum_size = Vector2(120, 40)
	bb.pressed.connect(_on_back_quiz)
	_quiz_nav.add_child(bb)
	box.add_child(_quiz_nav)
	return box


func show_after_chapter(chapter_title: String) -> void:
	visible = true
	_congrats.visible = true
	_quiz.visible = false
	(_congrats.get_node("CTitle") as Label).text = "Congratulations!"
	(_congrats.get_node("CSub") as Label).text = (
		"%s\n\nTake the quiz (5 taps, need 3+ correct) or skip." % chapter_title
	)
	_set_congrats_two_buttons()
	_quiz_feedback.text = ""


func _set_congrats_two_buttons() -> void:
	for c in _congrats_actions.get_children():
		c.queue_free()
	var bq := Button.new()
	bq.text = "Quiz"
	bq.custom_minimum_size = Vector2(140, 44)
	bq.pressed.connect(_show_quiz)
	_congrats_actions.add_child(bq)
	var bs := Button.new()
	bs.text = "Skip"
	bs.custom_minimum_size = Vector2(140, 44)
	bs.pressed.connect(_emit_skip)
	_congrats_actions.add_child(bs)


func _set_congrats_one_button_continue() -> void:
	for c in _congrats_actions.get_children():
		c.queue_free()
	var bc := Button.new()
	bc.text = "Continue"
	bc.custom_minimum_size = Vector2(180, 44)
	bc.pressed.connect(_emit_quiz_continue)
	_congrats_actions.add_child(bc)


func _emit_skip() -> void:
	skip_pressed.emit()


func _emit_quiz_continue() -> void:
	quiz_continue_pressed.emit()


func _show_quiz() -> void:
	_questions = QuizBank.pick_five_shuffled()
	if _questions.size() < QUIZ_TOTAL:
		_quiz_feedback.text = "Question bank too small."
		return
	_quiz_idx = 0
	_quiz_score = 0
	_quiz_locked = false
	_quiz_nav.visible = true
	_congrats.visible = false
	_quiz.visible = true
	_show_current_question()


func _show_current_question() -> void:
	_quiz_locked = false
	_quiz_feedback.remove_theme_color_override("font_color")
	_quiz_prog.text = "Question %d / %d" % [_quiz_idx + 1, QUIZ_TOTAL]
	var qd: Dictionary = _questions[_quiz_idx]
	_quiz_qtext.text = str(qd.get("q", ""))
	var ans: Variant = qd.get("a", [])
	for i in range(4):
		var b := _quiz_option_btns[i]
		b.visible = true
		b.disabled = false
		b.modulate = Color.WHITE
		var line := ""
		if ans is Array and i < (ans as Array).size():
			line = str((ans as Array)[i])
		elif ans is PackedStringArray and i < (ans as PackedStringArray).size():
			line = str((ans as PackedStringArray)[i])
		b.text = line if not line.is_empty() else ("Option %d" % (i + 1))
	_quiz_feedback.text = ""


func _on_option_pressed(ai: int) -> void:
	if _quiz_locked:
		return
	_quiz_locked = true
	var qd: Dictionary = _questions[_quiz_idx]
	var want: int = clampi(int(qd.get("c", 0)), 0, 3)
	var correct := ai == want
	if correct:
		_quiz_score += 1
		_quiz_feedback.text = "Correct!"
		_quiz_feedback.add_theme_color_override("font_color", Color(0.15, 0.55, 0.22))
	else:
		_quiz_feedback.text = "Wrong"
		_quiz_feedback.add_theme_color_override("font_color", Color(0.75, 0.18, 0.15))
	for i in range(4):
		var b := _quiz_option_btns[i]
		b.disabled = true
		if i == want:
			b.modulate = Color(0.75, 1.0, 0.78)
		elif i == ai:
			b.modulate = Color(1.0, 0.78, 0.78)
		else:
			b.modulate = Color(0.88, 0.88, 0.88)
	await get_tree().create_timer(_NEXT_DELAY).timeout
	_advance_quiz()


func _advance_quiz() -> void:
	_quiz_idx += 1
	if _quiz_idx >= QUIZ_TOTAL:
		_finish_quiz_run()
		return
	_show_current_question()


func _finish_quiz_run() -> void:
	_quiz_nav.visible = true
	if _quiz_score >= QUIZ_NEED:
		_quiz.visible = false
		_congrats.visible = true
		(_congrats.get_node("CTitle") as Label).text = "Great!"
		(_congrats.get_node("CSub") as Label).text = "%d / %d correct. Next chapter will unlock." % [_quiz_score, QUIZ_TOTAL]
		_set_congrats_one_button_continue()
		_quiz_feedback.text = ""
	else:
		_quiz_qtext.text = "Quiz result"
		_quiz_prog.text = ""
		for b in _quiz_option_btns:
			b.visible = false
		_quiz_feedback.text = "Score: %d / %d (need %d+). Tap New set or Back." % [_quiz_score, QUIZ_TOTAL, QUIZ_NEED]
		_quiz_feedback.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))


func _on_new_questions() -> void:
	for b in _quiz_option_btns:
		b.visible = true
	_show_quiz()


func _on_back_quiz() -> void:
	_quiz.visible = false
	_congrats.visible = true
	_quiz_feedback.text = ""
	for b in _quiz_option_btns:
		b.visible = true
		_restore_option_style(b)


func _restore_option_style(b: Button) -> void:
	b.modulate = Color.WHITE
	b.disabled = false


func close_overlay() -> void:
	visible = false
