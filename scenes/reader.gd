extends Control


const _FlowScript = preload("res://scripts/chapter_flow_overlay.gd")
const _LocalCommentStore = preload("res://scripts/local_comment_store.gd")

@onready var _title: Label = $Margin/VBox/TitleLabel
@onready var _book_bar: ProgressBar = $Margin/VBox/BookProgress
@onready var _split: HSplitContainer = $Margin/VBox/HSplit
@onready var _text: TextEdit = $Margin/VBox/HSplit/TextFrame/TextEdit
@onready var _chapter_title: Label = $Margin/VBox/HSplit/Right/ChapterTitle
@onready var _chapter_blurb: Label = $Margin/VBox/HSplit/Right/ChapterBlurb
@onready var _chapter_bar: ProgressBar = $Margin/VBox/HSplit/Right/ChapterProgress
@onready var _btn_complete: Button = $Margin/VBox/HSplit/Right/BtnComplete
@onready var _comments_box: VBoxContainer = $Margin/VBox/HSplit/Right/Scroll/CommentsVBox
@onready var _comment_body: TextEdit = $Margin/VBox/HSplit/Right/CommentBody
@onready var _reply_banner: HBoxContainer = $Margin/VBox/HSplit/Right/ReplyBanner
@onready var _reply_to_label: Label = $Margin/VBox/HSplit/Right/ReplyBanner/ReplyToLabel
@onready var _btn_cancel_reply: Button = $Margin/VBox/HSplit/Right/ReplyBanner/BtnCancelReply
@onready var _btn_post: Button = $Margin/VBox/HSplit/Right/BtnPost
@onready var _btn_refresh: Button = $Margin/VBox/HSplit/Right/BtnRefresh
@onready var _btn_cloud: Button = $Margin/VBox/HSplit/Right/BtnCloudSave
@onready var _status: Label = $Margin/VBox/HSplit/Right/Status
@onready var _picker: OptionButton = $Margin/VBox/BottomRow/ChapterPicker
@onready var _btn_debug_reset: Button = $Margin/VBox/DebugRow/BtnDebugResetReading
@onready var _ach: Label = $Margin/VBox/AchievementsLabel

var _chapter_id: String = ""
var _reply_parent_id: Variant = null
var _pending_flow_chapter_id: String = ""
## chapter_id -> true: auto quiz overlay already shown for this chapter (until completed / debug reset).
var _auto_chapter_flow_shown: Dictionary = {}
## For chapters that fit on one screen (no v-scroll), require at least one interaction before "read to end".
var _chapter_reader_touched: bool = false
var _picker_safe_idx: int = 0
var _flow: CanvasLayer
var _dlg_next: AcceptDialog
## Shared UI font: Godot default on TextEdit supports Cyrillic; Labels/Buttons/OptionButton need an explicit Windows-safe stack.
var _ui_sans_font: SystemFont


func _ensure_ui_sans_font() -> void:
	if _ui_sans_font != null:
		return
	_ui_sans_font = SystemFont.new()
	_ui_sans_font.font_names = PackedStringArray([
		"Segoe UI",
		"Segoe UI Variable",
		"Segoe UI Variable Display",
		"Tahoma",
		"Arial",
		"Calibri",
		"Verdana",
		"DejaVu Sans",
		"Liberation Sans",
	])
	_ui_sans_font.generate_mipmaps = false


func _ready() -> void:
	_book_bar.max_value = 1.0
	_chapter_bar.max_value = 1.0
	GameState.progress_changed.connect(_refresh_bars)
	GameState.achievements_changed.connect(_refresh_achievements)
	_text.get_v_scroll_bar().value_changed.connect(_on_scroll)
	_text.gui_input.connect(_on_reader_text_gui_input)
	_text.caret_changed.connect(_on_reader_caret_moved)
	_flow = _FlowScript.new()
	add_child(_flow)
	_flow.skip_pressed.connect(_on_flow_skip)
	_flow.quiz_continue_pressed.connect(_on_flow_quiz_continue)
	_dlg_next = AcceptDialog.new()
	_dlg_next.title = "Progress"
	add_child(_dlg_next)
	_configure_reader_text_for_comments()
	_apply_book_reader_theme()
	_setup_comment_composer()
	_title.text = GameState.get_book_title()
	_fill_picker()
	_style_chapter_picker()
	if _picker.item_count > 0:
		_picker.select(0)
		_picker_safe_idx = 0
		_on_picker(0)
	else:
		_text.text = GameState.get_book_load_error_report()
	_refresh_achievements()
	_refresh_bars()
	_btn_complete.pressed.connect(_on_complete_pressed)
	_btn_post.pressed.connect(_on_post_pressed)
	_btn_refresh.pressed.connect(_reload_comments)
	_btn_cloud.pressed.connect(_on_cloud_save)
	_picker.item_selected.connect(_on_picker)
	_btn_debug_reset.pressed.connect(_on_debug_reset_reading)
	_btn_cancel_reply.pressed.connect(_on_cancel_reply_pressed)


func _style_chapter_picker() -> void:
	var fg := Color(0.94, 0.92, 0.9, 1)
	_picker.add_theme_color_override("font_color", fg)
	_picker.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	_picker.add_theme_color_override("font_pressed_color", fg)
	_picker.add_theme_color_override("font_focus_color", fg)


func _apply_book_reader_theme() -> void:
	_ensure_ui_sans_font()
	var serif := SystemFont.new()
	# Avoid trailing generic "Serif" — on Windows it can resolve to a Latin-only face and show "????" for Cyrillic.
	serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "Times", "Noto Serif", "DejaVu Serif"])
	serif.generate_mipmaps = false
	serif.fallbacks = [_ui_sans_font]
	# SystemFont on large TextEdit can fail to render on some Windows setups — use default project font for body.
	_text.remove_theme_font_override("font")
	_text.add_theme_font_size_override("font_size", 19)
	_text.add_theme_constant_override("line_spacing", 10)
	var paper := Color(0.99, 0.98, 0.95, 1)
	var ink := Color(0.13, 0.12, 0.11, 1)
	_text.add_theme_color_override("font_color", ink)
	_text.add_theme_color_override("background_color", paper)
	_text.add_theme_color_override("font_readonly_color", ink)
	# Godot 4.6 default theme: read_only stylebox can hide text; force light panels.
	var ro := StyleBoxFlat.new()
	ro.bg_color = paper
	ro.border_color = Color(0.88, 0.84, 0.78, 1)
	ro.set_border_width_all(1)
	ro.set_corner_radius_all(4)
	ro.content_margin_left = 8
	ro.content_margin_top = 8
	ro.content_margin_right = 8
	ro.content_margin_bottom = 8
	_text.add_theme_stylebox_override("read_only", ro)
	var nm := ro.duplicate() as StyleBoxFlat
	_text.add_theme_stylebox_override("normal", nm)
	var fe := StyleBoxEmpty.new()
	_text.add_theme_stylebox_override("focus", fe)
	_text.add_theme_color_override("selection_color", Color(0.35, 0.55, 0.95, 0.35))
	_title.add_theme_font_override("font", serif)
	_title.add_theme_font_size_override("font_size", 22)
	_chapter_title.add_theme_font_override("font", serif)
	_chapter_title.add_theme_font_size_override("font_size", 20)
	_chapter_blurb.add_theme_font_override("font", serif)
	_apply_cyrillic_safe_fonts_to_chrome()


func _apply_cyrillic_safe_fonts_to_chrome() -> void:
	_ensure_ui_sans_font()
	var f: Font = _ui_sans_font
	for n: Control in [
		_btn_complete,
		_btn_post,
		_btn_refresh,
		_btn_cloud,
		_btn_debug_reset,
		_btn_cancel_reply,
		_status,
		_ach,
		_reply_to_label,
		_comment_body,
		_picker,
		$Margin/VBox/HSplit/Right/CommentsHeader as Control,
		$Margin/VBox/BottomRow/LabelCh as Control,
	]:
		n.add_theme_font_override("font", f)
	var pop: PopupMenu = _picker.get_popup()
	pop.add_theme_font_override("font", f)


func _configure_reader_text_for_comments() -> void:
	_text.selecting_enabled = true
	_text.context_menu_enabled = true
	_text.shortcut_keys_enabled = true
	_text.focus_mode = Control.FOCUS_ALL


func _setup_comment_composer() -> void:
	_comment_body.placeholder_text = "Заметка к выделенной цитате…"
	_comment_body.context_menu_enabled = true
	_comment_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	if _comment_body.get_line_height() > 0.0:
		_comment_body.custom_minimum_size = Vector2(0, maxf(88.0, _comment_body.get_line_height() * 3.0 + 24.0))


func _comment_card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.995, 0.988, 0.978, 1)
	s.border_color = Color(0.86, 0.8, 0.72, 1)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_top = 10
	s.content_margin_right = 12
	s.content_margin_bottom = 10
	return s


func _quote_from_range(start: int, end: int) -> String:
	var full := GameState.get_chapter_plain_text(_chapter_id)
	var a := clampi(start, 0, full.length())
	var b := clampi(end, 0, full.length())
	if b <= a:
		return ""
	var q := full.substr(a, mini(b - a, 160)).strip_edges()
	q = q.replace("\n", " ").replace("\r", "")
	if q.length() >= 160:
		q = q + "…"
	return q


func _reader_comment_hint_idle() -> String:
	if Net.enabled:
		return "Выделите цитату в тексте слева, напишите заметку и нажмите Add comment (облако — только если сессия уже есть)."
	return "Выделите цитату слева, напишите заметку и нажмите Add comment — сохранение только на этом устройстве."


func _on_reader_caret_moved() -> void:
	if _chapter_id.is_empty():
		return
	if _text.has_selection():
		var sel := TextAnchor.selection_to_range(_text)
		if sel.x >= 0 and sel.y > sel.x:
			var n: int = sel.y - sel.x
			var snippet := _text.get_selected_text().replace("\n", " ").strip_edges()
			if snippet.length() > 40:
				snippet = snippet.substr(0, 40) + "…"
			_status.text = "Фрагмент (%d симв.): «%s» — заметка ниже, затем Add comment." % [n, snippet]
			return
	_status.text = _reader_comment_hint_idle()


func _fill_picker() -> void:
	_picker.clear()
	var i := 0
	for ch in GameState.get_chapters():
		if ch is Dictionary:
			_picker.add_item(str(ch.get("title", "Chapter")))
			_picker.set_item_metadata(i, str(ch.get("chapter_id", "")))
			_picker.set_item_disabled(i, not GameState.can_select_chapter_index(i))
			i += 1


func _refresh_picker_lock() -> void:
	for i in range(_picker.item_count):
		_picker.set_item_disabled(i, not GameState.can_select_chapter_index(i))


func _on_picker(idx: int) -> void:
	if not GameState.can_select_chapter_index(idx):
		_picker.select(_picker_safe_idx)
		return
	_picker_safe_idx = idx
	_chapter_id = str(_picker.get_item_metadata(idx))
	_chapter_reader_touched = false
	var meta := GameState.get_chapter_meta(_chapter_id)
	_chapter_title.text = str(meta.get("title", ""))
	var bl := str(meta.get("blurb", ""))
	_chapter_blurb.text = bl
	_chapter_blurb.visible = not bl.is_empty()
	var body := GameState.get_chapter_plain_text(_chapter_id)
	if body.is_empty():
		body = (
			"[Текст главы пустой]\n\n"
			+ "chapter_id: %s\n" % _chapter_id
			+ "Проверь: books/main.epub, config/book_source.json, вкладка Output в Godot (ошибки EPUB).\n"
			+ "Если EPUB на месте — перезапусти сцену (останови игру и F5)."
		)
	_text.text = body
	_text.set_deferred("scroll_vertical", 0)
	_clear_reply_target()
	_text.deselect()
	_status.text = _reader_comment_hint_idle()
	call_deferred("_bootstrap_comments")
	call_deferred("_sync_scroll_progress")
	_update_complete_button()


func _bootstrap_comments() -> void:
	await _reload_comments()


func _sync_scroll_progress() -> void:
	_on_scroll(0.0)


func _on_scroll(_v: float) -> void:
	if _chapter_id.is_empty():
		return
	var r_raw: float = _scroll_ratio()
	var at_end := _reader_at_chapter_end_for_flow()
	var r_store: float = 1.0 if at_end else minf(r_raw, 0.999)
	GameState.set_chapter_read_ratio(_chapter_id, r_store, at_end)
	_maybe_auto_show_chapter_flow_at_end(at_end)
	_refresh_bars()


func _on_reader_text_gui_input(event: InputEvent) -> void:
	if _chapter_id.is_empty():
		return
	var mark := false
	if event is InputEventMouseButton:
		mark = true
	elif event is InputEventKey and event.pressed and not event.echo:
		mark = true
	elif event is InputEventScreenTouch and event.pressed:
		mark = true
	if not mark:
		return
	if not _chapter_reader_touched:
		_chapter_reader_touched = true
		call_deferred("_on_scroll", 0.0)


func _scroll_ratio() -> float:
	var sb := _text.get_v_scroll_bar()
	var mx := sb.max_value
	if mx <= 0.0:
		return 1.0
	return clampf(sb.value / mx, 0.0, 1.0)


## True only when the vertical scrollbar is at the real bottom (not "high %" earlier in the chapter).
func _scroll_geometry_at_bottom() -> bool:
	var sb := _text.get_v_scroll_bar()
	var mx := sb.max_value
	if mx <= 0.0:
		return false
	var pg: float = float(sb.page)
	var eps: float = maxf(2.0, pg * 0.03)
	return sb.value >= mx - eps


func _reader_at_chapter_end_for_flow() -> bool:
	var mx := _text.get_v_scroll_bar().max_value
	if mx <= 0.0:
		return _chapter_reader_touched
	return _scroll_geometry_at_bottom()


func _maybe_auto_show_chapter_flow_at_end(at_end: bool) -> void:
	if _flow == null or not is_instance_valid(_flow):
		return
	if _flow.visible:
		return
	if not at_end:
		return
	if not GameState.is_eligible_for_completion_flow(_chapter_id):
		return
	if bool(_auto_chapter_flow_shown.get(_chapter_id, false)):
		return
	_auto_chapter_flow_shown[_chapter_id] = true
	_pending_flow_chapter_id = _chapter_id
	var meta := GameState.get_chapter_meta(_chapter_id)
	_flow.show_after_chapter(str(meta.get("title", "")))


func _refresh_bars() -> void:
	_book_bar.value = GameState.get_weighted_book_ratio()
	if not _chapter_id.is_empty():
		var r: float = float(GameState.chapter_read_ratio.get(_chapter_id, 0.0))
		if bool(GameState.chapters_completed.get(_chapter_id, false)):
			r = 1.0
		_chapter_bar.value = r
	_update_complete_button()


func _update_complete_button() -> void:
	if _chapter_id.is_empty():
		_btn_complete.disabled = true
		return
	_btn_complete.disabled = not GameState.is_eligible_for_completion_flow(_chapter_id)


func _on_debug_reset_reading() -> void:
	_auto_chapter_flow_shown.clear()
	GameState.debug_reset_reading_progress()
	_fill_picker()
	_refresh_picker_lock()
	if _picker.item_count > 0:
		_picker.select(0)
		_picker_safe_idx = 0
		_on_picker(0)
	_refresh_bars()
	_status.text = "Debug: reading progress reset."


func _refresh_achievements() -> void:
	var parts: PackedStringArray = GameState.achievements
	_ach.text = "Achievements: %s" % ", ".join(parts)


func _on_complete_pressed() -> void:
	if _chapter_id.is_empty():
		return
	if not GameState.is_eligible_for_completion_flow(_chapter_id):
		if bool(GameState.chapters_completed.get(_chapter_id, false)):
			_status.text = "This chapter is already completed."
		elif GameState.get_chapter_index(_chapter_id) != GameState.linear_unlock_index:
			_status.text = "Complete the current chapter in order first."
		else:
			_status.text = "Scroll to the very bottom of the chapter (100% on the bar) first."
		return
	_auto_chapter_flow_shown[_chapter_id] = true
	_pending_flow_chapter_id = _chapter_id
	var meta := GameState.get_chapter_meta(_chapter_id)
	_flow.show_after_chapter(str(meta.get("title", "")))


func _on_flow_skip() -> void:
	if _pending_flow_chapter_id.is_empty():
		return
	if GameState.finalize_chapter_completion(_pending_flow_chapter_id):
		_status.text = "Chapter closed. +HP."
	_flow.close_overlay()
	_after_chapter_flow_done()


func _on_flow_quiz_continue() -> void:
	if _pending_flow_chapter_id.is_empty():
		return
	if GameState.finalize_chapter_completion(_pending_flow_chapter_id):
		_status.text = "Chapter closed. +HP."
	_flow.close_overlay()
	_after_chapter_flow_done()


func _after_chapter_flow_done() -> void:
	var done_id := _pending_flow_chapter_id
	_pending_flow_chapter_id = ""
	_refresh_bars()
	_refresh_picker_lock()
	var next_title := GameState.get_next_chapter_title_after(done_id)
	if next_title.is_empty():
		_dlg_next.dialog_text = "Congratulations! You have finished all chapters in this book."
	else:
		_dlg_next.dialog_text = "Congratulations! Unlocked next chapter:\n" + next_title
	_dlg_next.popup_centered()
	var next_idx := GameState.get_chapter_index(done_id) + 1
	if next_idx < _picker.item_count and GameState.can_select_chapter_index(next_idx):
		_picker.select(next_idx)
		_picker_safe_idx = next_idx
		_on_picker(next_idx)


func _clear_comments() -> void:
	for c in _comments_box.get_children():
		c.queue_free()


func _clear_reply_target() -> void:
	_reply_parent_id = null
	_reply_banner.visible = false


func _on_cancel_reply_pressed() -> void:
	_clear_reply_target()


func _sorted_comment_dicts(raw: Array) -> Array:
	var dicts: Array = []
	for it in raw:
		if it is Dictionary:
			dicts.append(it)
	dicts.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var da: Dictionary = a
			var db: Dictionary = b
			var sa := int(da.get("start_char", 0))
			var sb := int(db.get("start_char", 0))
			if sa != sb:
				return sa < sb
			return str(da.get("created_at", "")) < str(db.get("created_at", ""))
	)
	return dicts


func _jump_to_comment_anchor(start_char: int, end_char: int) -> void:
	if _chapter_id.is_empty():
		return
	var sc := clampi(start_char, 0, _text.text.length())
	var ec := clampi(end_char, 0, _text.text.length())
	if ec <= sc:
		return
	TextAnchor.select_index_range(_text, sc, ec)
	_text.grab_focus()
	TextAnchor.scroll_range_visible(_text, sc, ec)
	_on_reader_caret_moved()


func _begin_reply_to_card(comment_id: Variant, body_preview: String) -> void:
	if comment_id == null or str(comment_id).is_empty():
		return
	_reply_parent_id = comment_id
	var pv := body_preview.strip_edges()
	if pv.length() > 72:
		pv = pv.substr(0, 72) + "…"
	_reply_to_label.text = "Reply to: \"%s\"" % pv
	_reply_banner.visible = true


func _reload_comments() -> void:
	_clear_comments()
	if _chapter_id.is_empty():
		return
	var meta := GameState.get_chapter_meta(_chapter_id)
	var ver := int(meta.get("text_version", 1))
	var bid := GameState.get_book_id()
	if Net.enabled:
		var resp := await Net.fetch_comments(bid, _chapter_id, ver)
		if not resp.get("ok", false):
			_add_comments_error(str(resp.get("error", "?")))
			return
		var data = resp.get("data", [])
		if data is Array:
			if (data as Array).is_empty():
				_add_comments_empty("Пока нет облачных комментариев к этой главе.")
			else:
				for item in _sorted_comment_dicts(data as Array):
					_add_comment_card(item as Dictionary)
		else:
			_add_comments_empty("Пока нет облачных комментариев к этой главе.")
		return
	var local: Array = _LocalCommentStore.list_chapter(bid, _chapter_id, ver)
	if local.is_empty():
		_add_comments_empty(
			"Пока нет комментариев.\nВыделите фрагмент в книге слева, напишите заметку ниже и нажмите Add comment — данные останутся на этом устройстве (как черновик до Supabase)."
		)
	else:
		for item in _sorted_comment_dicts(local):
			_add_comment_card(item as Dictionary)


func _add_comments_empty(msg: String) -> void:
	var lab := Label.new()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_color_override("font_color", Color(0.52, 0.48, 0.44, 1))
	lab.add_theme_font_size_override("font_size", 13)
	_ensure_ui_sans_font()
	lab.add_theme_font_override("font", _ui_sans_font)
	lab.text = msg
	_comments_box.add_child(lab)


func _add_comments_error(msg: String) -> void:
	var panel := PanelContainer.new()
	var sb := _comment_card_style()
	sb.bg_color = Color(1.0, 0.94, 0.93, 1)
	sb.border_color = Color(0.78, 0.42, 0.4, 1)
	panel.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ensure_ui_sans_font()
	lab.add_theme_font_override("font", _ui_sans_font)
	lab.text = "Could not load comments: %s" % msg
	panel.add_child(lab)
	_comments_box.add_child(panel)


func _add_comment_card(c: Dictionary) -> void:
	var is_reply := not str(c.get("parent_id", "")).strip_edges().is_empty()
	var outer := PanelContainer.new()
	var style := _comment_card_style()
	outer.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	if is_reply:
		margin.add_theme_constant_override("margin_left", 16)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)
	outer.add_child(margin)
	var sc := int(c.get("start_char", -1))
	var ec := int(c.get("end_char", -1))
	if sc >= 0 and ec > sc:
		var quote := Label.new()
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quote.add_theme_font_size_override("font_size", 12)
		quote.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38, 1))
		_ensure_ui_sans_font()
		quote.add_theme_font_override("font", _ui_sans_font)
		quote.text = "“%s”" % _quote_from_range(sc, ec)
		inner.add_child(quote)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	_ensure_ui_sans_font()
	body.add_theme_font_override("font", _ui_sans_font)
	body.text = str(c.get("body", ""))
	inner.add_child(body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	var meta_l := Label.new()
	meta_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_l.add_theme_font_size_override("font_size", 11)
	meta_l.add_theme_color_override("font_color", Color(0.55, 0.5, 0.46, 1))
	_ensure_ui_sans_font()
	meta_l.add_theme_font_override("font", _ui_sans_font)
	var created := str(c.get("created_at", ""))
	if created.length() > 19:
		created = created.substr(0, 19).replace("T", " ")
	meta_l.text = created if not created.is_empty() else " "
	foot.add_child(meta_l)
	var sc_i := int(c.get("start_char", -1))
	var ec_i := int(c.get("end_char", -1))
	if sc_i >= 0 and ec_i > sc_i:
		var btn_jump := Button.new()
		btn_jump.text = "В тексте"
		btn_jump.flat = true
		btn_jump.add_theme_font_size_override("font_size", 13)
		btn_jump.add_theme_font_override("font", _ui_sans_font)
		var sj := sc_i
		var ej := ec_i
		btn_jump.pressed.connect(func(): _jump_to_comment_anchor(sj, ej))
		foot.add_child(btn_jump)
	var btn := Button.new()
	btn.text = "Ответить"
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_font_override("font", _ui_sans_font)
	var id_for_reply: Variant = c.get("id", null)
	var body_for_reply := str(c.get("body", ""))
	btn.pressed.connect(func(): _begin_reply_to_card(id_for_reply, body_for_reply))
	foot.add_child(btn)
	inner.add_child(foot)
	_comments_box.add_child(outer)


func _on_post_pressed() -> void:
	if _chapter_id.is_empty():
		return
	var meta := GameState.get_chapter_meta(_chapter_id)
	var ver := int(meta.get("text_version", 1))
	var bid := GameState.get_book_id()
	var sel := TextAnchor.selection_to_range(_text)
	if sel.x < 0 or sel.y <= sel.x:
		_status.text = _reader_comment_hint_idle()
		return
	var body := _comment_body.text.strip_edges()
	if body.is_empty():
		_status.text = "Write the comment text in the box below."
		return
	if body.length() > 2000:
		body = body.substr(0, 2000)
	if Net.enabled:
		if not Net.is_logged_in():
			_status.text = "Облако: сессия не открыта (вход из игры отключён). Используйте локальные заметки или настройте Net отдельно."
			return
		var resp := await Net.post_comment(
			bid,
			_chapter_id,
			ver,
			sel.x,
			sel.y,
			body,
			_reply_parent_id
		)
		if resp.get("ok", false):
			GameState.record_comment_posted()
			_comment_body.text = ""
			_clear_reply_target()
			_text.deselect()
			_status.text = "Комментарий отправлен в облако."
			await _reload_comments()
		else:
			_status.text = "Error: %s" % str(resp.get("error", resp.get("raw", "?")))
		return
	var parent_str := ""
	if _reply_parent_id != null:
		parent_str = str(_reply_parent_id)
	_LocalCommentStore.append_chapter(bid, _chapter_id, ver, sel.x, sel.y, body, parent_str)
	GameState.record_comment_posted()
	_comment_body.text = ""
	_clear_reply_target()
	_text.deselect()
	_status.text = "Комментарий сохранён на этом устройстве."
	await _reload_comments()


func _on_cloud_save() -> void:
	if not Net.is_logged_in():
		_status.text = "Облако: нет активной сессии (вход из игры отключён)."
		return
	var rows := GameState.build_reading_progress_rows()
	var resp := await Net.upsert_reading_progress(rows)
	if resp.get("ok", false):
		_status.text = "Progress synced to server."
	else:
		_status.text = "Cloud: %s" % str(resp.get("error", "?"))
