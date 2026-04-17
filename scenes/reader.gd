extends Control


@onready var _title: Label = $Margin/VBox/TitleLabel
@onready var _book_bar: ProgressBar = $Margin/VBox/BookProgress
@onready var _split: HSplitContainer = $Margin/VBox/HSplit
@onready var _text: TextEdit = $Margin/VBox/HSplit/TextEdit
@onready var _chapter_title: Label = $Margin/VBox/HSplit/Right/ChapterTitle
@onready var _chapter_bar: ProgressBar = $Margin/VBox/HSplit/Right/ChapterProgress
@onready var _btn_complete: Button = $Margin/VBox/HSplit/Right/BtnComplete
@onready var _comments_box: VBoxContainer = $Margin/VBox/HSplit/Right/Scroll/CommentsVBox
@onready var _comment_input: LineEdit = $Margin/VBox/HSplit/Right/CommentInput
@onready var _btn_post: Button = $Margin/VBox/HSplit/Right/BtnPost
@onready var _btn_refresh: Button = $Margin/VBox/HSplit/Right/BtnRefresh
@onready var _btn_cloud: Button = $Margin/VBox/HSplit/Right/BtnCloudSave
@onready var _email: LineEdit = $Margin/VBox/HSplit/Right/Email
@onready var _password: LineEdit = $Margin/VBox/HSplit/Right/Password
@onready var _btn_login: Button = $Margin/VBox/HSplit/Right/BtnLogin
@onready var _status: Label = $Margin/VBox/HSplit/Right/Status
@onready var _picker: OptionButton = $Margin/VBox/BottomRow/ChapterPicker
@onready var _ach: Label = $Margin/VBox/AchievementsLabel

var _chapter_id: String = ""
var _reply_parent_id: Variant = null


func _ready() -> void:
	_book_bar.max_value = 1.0
	_chapter_bar.max_value = 1.0
	_title.text = GameState.get_book_title()
	_fill_picker()
	GameState.progress_changed.connect(_refresh_bars)
	GameState.achievements_changed.connect(_refresh_achievements)
	_refresh_achievements()
	_refresh_bars()
	if _picker.item_count > 0:
		_picker.select(0)
		_on_picker(0)
	_text.get_v_scroll_bar().value_changed.connect(_on_scroll)
	_btn_complete.pressed.connect(_on_complete_pressed)
	_btn_post.pressed.connect(_on_post_pressed)
	_btn_refresh.pressed.connect(_reload_comments)
	_btn_cloud.pressed.connect(_on_cloud_save)
	_btn_login.pressed.connect(_on_login_pressed)
	_picker.item_selected.connect(_on_picker)


func _fill_picker() -> void:
	_picker.clear()
	var i := 0
	for ch in GameState.get_chapters():
		if ch is Dictionary:
			_picker.add_item(str(ch.get("title", "Chapter")))
			_picker.set_item_metadata(i, str(ch.get("chapter_id", "")))
			i += 1


func _on_picker(idx: int) -> void:
	_chapter_id = str(_picker.get_item_metadata(idx))
	var meta := GameState.get_chapter_meta(_chapter_id)
	_chapter_title.text = str(meta.get("title", ""))
	_text.text = GameState.get_chapter_plain_text(_chapter_id)
	_text.set_deferred("scroll_vertical", 0)
	_reply_parent_id = null
	_status.text = ""
	call_deferred("_bootstrap_comments")
	call_deferred("_sync_scroll_progress")


func _bootstrap_comments() -> void:
	await _reload_comments()


func _sync_scroll_progress() -> void:
	_on_scroll(0.0)


func _on_scroll(_v: float) -> void:
	if _chapter_id.is_empty():
		return
	GameState.set_chapter_read_ratio(_chapter_id, _scroll_ratio())
	_refresh_bars()


func _scroll_ratio() -> float:
	var sb := _text.get_v_scroll_bar()
	var mx := sb.max_value
	if mx <= 0.0:
		return 1.0
	return clampf(sb.value / mx, 0.0, 1.0)


func _refresh_bars() -> void:
	_book_bar.value = GameState.get_weighted_book_ratio()
	if not _chapter_id.is_empty():
		var r: float = float(GameState.chapter_read_ratio.get(_chapter_id, 0.0))
		if bool(GameState.chapters_completed.get(_chapter_id, false)):
			r = 1.0
		_chapter_bar.value = r


func _refresh_achievements() -> void:
	var parts: PackedStringArray = GameState.achievements
	_ach.text = "Achievements: %s" % ", ".join(parts)


func _on_complete_pressed() -> void:
	if _chapter_id.is_empty():
		return
	if GameState.try_complete_chapter(_chapter_id):
		_status.text = "Chapter completed. +HP."
	else:
		_status.text = "Scroll ~85% or chapter already done."
	_refresh_bars()


func _clear_comments() -> void:
	for c in _comments_box.get_children():
		c.queue_free()


func _reload_comments() -> void:
	_clear_comments()
	if _chapter_id.is_empty():
		return
	var meta := GameState.get_chapter_meta(_chapter_id)
	var ver := int(meta.get("text_version", 1))
	var resp := await Net.fetch_comments(GameState.get_book_id(), _chapter_id, ver)
	if not resp.get("ok", false):
		var row := Label.new()
		row.text = "Comments: %s" % str(resp.get("error", "?"))
		_comments_box.add_child(row)
		return
	var data = resp.get("data", [])
	if data == null:
		return
	if data is Array:
		for item in data:
			if item is Dictionary:
				_add_comment_row(item)


func _add_comment_row(c: Dictionary) -> void:
	var hb := HBoxContainer.new()
	var body := Label.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pid := str(c.get("parent_id", ""))
	var prefix := "> " if not pid.is_empty() else ""
	var snippet := str(c.get("body", ""))
	body.text = "%s%s" % [prefix, snippet]
	hb.add_child(body)
	var btn := Button.new()
	btn.text = "Reply"
	btn.pressed.connect(
		func():
			_reply_parent_id = c.get("id", null)
			_status.text = "Replying to comment."
	)
	hb.add_child(btn)
	_comments_box.add_child(hb)


func _on_post_pressed() -> void:
	if _chapter_id.is_empty():
		return
	var meta := GameState.get_chapter_meta(_chapter_id)
	var ver := int(meta.get("text_version", 1))
	var sel := TextAnchor.selection_to_range(_text)
	if sel.x < 0 or sel.y <= sel.x:
		_status.text = "Select text in the reader."
		return
	var body := _comment_input.text.strip_edges()
	if body.is_empty():
		_status.text = "Enter comment text."
		return
	if body.length() > 2000:
		body = body.substr(0, 2000)
	var resp := await Net.post_comment(
		GameState.get_book_id(),
		_chapter_id,
		ver,
		sel.x,
		sel.y,
		body,
		_reply_parent_id
	)
	if resp.get("ok", false):
		GameState.record_comment_posted()
		_comment_input.text = ""
		_reply_parent_id = null
		_status.text = "Comment posted."
		await _reload_comments()
	else:
		_status.text = "Error: %s" % str(resp.get("error", resp.get("raw", "?")))


func _on_login_pressed() -> void:
	var em := _email.text.strip_edges()
	var pw := _password.text
	if em.is_empty() or pw.is_empty():
		_status.text = "Email and password required."
		return
	var resp := await Net.sign_in_email(em, pw)
	Net.apply_auth_response(resp)
	if Net.is_logged_in():
		_status.text = "Signed in."
	else:
		_status.text = "Sign-in failed: %s" % str(resp.get("raw", resp))


func _on_cloud_save() -> void:
	if not Net.is_logged_in():
		_status.text = "Sign in (Supabase) first."
		return
	var rows := GameState.build_reading_progress_rows()
	var resp := await Net.upsert_reading_progress(rows)
	if resp.get("ok", false):
		_status.text = "Progress synced to server."
	else:
		_status.text = "Cloud: %s" % str(resp.get("error", "?"))
