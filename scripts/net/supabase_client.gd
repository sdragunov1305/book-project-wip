extends Node


const CONFIG_PATH := "res://config/net.json"
const SESSION_PATH := "user://supabase_session.json"

var enabled: bool = false
var supabase_url: String = ""
var anon_key: String = ""
var access_token: String = ""

var _http: HTTPRequest
var _pending: Dictionary = {} ## int -> Callable

signal session_changed


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_load_config()
	_load_session()


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		enabled = false
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		enabled = false
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		supabase_url = str(d.get("supabase_url", "")).trim_suffix("/")
		anon_key = str(d.get("anon_key", ""))
		enabled = not supabase_url.is_empty() and not anon_key.is_empty()
	else:
		enabled = false


func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		access_token = str(d.get("access_token", ""))


func save_session() -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"access_token": access_token}))
	f.close()
	session_changed.emit()


func clear_session() -> void:
	access_token = ""
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	session_changed.emit()


func is_logged_in() -> bool:
	return not access_token.is_empty()


func _auth_header() -> String:
	if access_token.is_empty():
		return "Bearer %s" % anon_key
	return "Bearer %s" % access_token


func sign_in_email(email: String, password: String) -> Dictionary:
	var url := "%s/auth/v1/token?grant_type=password" % supabase_url
	var body := JSON.stringify({"email": email, "password": password})
	var headers := PackedStringArray(
		["Content-Type: application/json", "apikey: %s" % anon_key, "Authorization: Bearer %s" % anon_key]
	)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return {"ok": false, "error": "request_failed"}
	var out := await _wait_request(err)
	return out


func sign_up_email(email: String, password: String) -> Dictionary:
	var url := "%s/auth/v1/signup" % supabase_url
	var body := JSON.stringify({"email": email, "password": password})
	var headers := PackedStringArray(
		["Content-Type: application/json", "apikey: %s" % anon_key, "Authorization: Bearer %s" % anon_key]
	)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return {"ok": false, "error": "request_failed"}
	return await _wait_request(err)


func fetch_comments(book_id: String, chapter_id: String, text_version: int) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "offline", "data": []}
	var filter := "book_id=eq.%s&chapter_id=eq.%s&text_version=eq.%s&order=created_at.asc" % [
		book_id,
		chapter_id,
		str(text_version),
	]
	var url := "%s/rest/v1/comments?%s&select=*" % [supabase_url, filter]
	var headers := PackedStringArray(
		["apikey: %s" % anon_key, "Authorization: %s" % _auth_header()]
	)
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		return {"ok": false, "error": "request_failed", "data": []}
	return await _wait_request(err)


func post_comment(
	book_id: String,
	chapter_id: String,
	text_version: int,
	start_char: int,
	end_char: int,
	body: String,
	parent_id: Variant
) -> Dictionary:
	if not enabled or not is_logged_in():
		return {"ok": false, "error": "not_configured_or_guest"}
	var url := "%s/rest/v1/comments" % supabase_url
	var row := {
		"book_id": book_id,
		"chapter_id": chapter_id,
		"text_version": text_version,
		"start_char": start_char,
		"end_char": end_char,
		"body": body,
	}
	if parent_id != null and str(parent_id) != "":
		row["parent_id"] = str(parent_id)
	var headers := PackedStringArray(
		[
			"Content-Type: application/json",
			"apikey: %s" % anon_key,
			"Authorization: %s" % _auth_header(),
			"Prefer: return=representation",
		]
	)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(row))
	if err != OK:
		return {"ok": false, "error": "request_failed"}
	return await _wait_request(err)


func upsert_reading_progress(rows: Array) -> Dictionary:
	if not enabled or not is_logged_in():
		return {"ok": false, "error": "skip"}
	var url := "%s/rest/v1/reading_progress?on_conflict=user_id,book_id,chapter_id" % supabase_url
	var headers := PackedStringArray(
		[
			"Content-Type: application/json",
			"apikey: %s" % anon_key,
			"Authorization: %s" % _auth_header(),
			"Prefer: resolution=merge-duplicates",
		]
	)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(rows))
	if err != OK:
		return {"ok": false, "error": "request_failed"}
	return await _wait_request(err)


func _wait_request(rid: int) -> Dictionary:
	_pending[rid] = true
	var args = await _http.request_completed ## result, code, headers, body
	var result: int = args[0]
	var code: int = args[1]
	var body: PackedByteArray = args[3]
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "network", "code": code, "raw": text}
	var json = JSON.parse_string(text)
	if code >= 200 and code < 300:
		return {"ok": true, "data": json, "raw": text, "code": code}
	return {"ok": false, "error": "http", "code": code, "data": json, "raw": text}


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	pass


func apply_auth_response(resp: Dictionary) -> void:
	if not resp.get("ok", false):
		return
	var data = resp.get("data", null)
	if data is Dictionary:
		var tok := str(data.get("access_token", ""))
		if not tok.is_empty():
			access_token = tok
			save_session()
