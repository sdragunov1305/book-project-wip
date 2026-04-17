extends RefCounted
class_name EpubLoader


const HP_REWARD_CAP := 40
const HP_REWARD_BASE := 10


static func load_epub(epub_path: String) -> Dictionary:
	var abs_path := epub_path.replace("\\", "/")
	if not FileAccess.file_exists(abs_path):
		return {"ok": false, "error": "file_not_found"}
	var z := ZIPReader.new()
	if z.open(abs_path) != OK:
		return {"ok": false, "error": "zip_open_failed"}
	var container_path := _find_container_path(z)
	if container_path.is_empty():
		z.close()
		return {"ok": false, "error": "no_container_xml"}
	var container_bytes := z.read_file(container_path, false)
	if container_bytes.is_empty():
		z.close()
		return {"ok": false, "error": "container_empty"}
	var opf_rel := _extract_rootfile_fullpath(container_bytes.get_string_from_utf8())
	if opf_rel.is_empty():
		z.close()
		return {"ok": false, "error": "no_opf_in_container"}
	opf_rel = opf_rel.replace("\\", "/").trim_prefix("/")
	var opf_bytes := z.read_file(opf_rel, false)
	if opf_bytes.is_empty():
		z.close()
		return {"ok": false, "error": "opf_missing"}
	var opf_text := opf_bytes.get_string_from_utf8()
	var opf_dir := opf_rel.get_base_dir()
	var manifest_ids := _parse_manifest(opf_text)
	var spine := _parse_spine(opf_text)
	var title := _parse_dc_title(opf_text)
	if title.is_empty():
		title = abs_path.get_file().get_basename()
	var chapters: Array = []
	var spine_index := 0
	for idref in spine:
		if not manifest_ids.has(idref):
			continue
		var href: String = str(manifest_ids[idref])
		href = _uri_decode_path(href)
		var full_path := opf_dir.path_join(href).replace("\\", "/")
		var lower := full_path.to_lower()
		if not (
			lower.ends_with(".xhtml")
			or lower.ends_with(".html")
			or lower.ends_with(".htm")
		):
			continue
		var body_bytes := z.read_file(full_path, false)
		if body_bytes.is_empty():
			continue
		var raw := body_bytes.get_string_from_utf8()
		var plain := html_to_book_plain(raw)
		if plain.strip_edges().is_empty():
			continue
		var ch_title := guess_chapter_title(raw, spine_index + 1)
		chapters.append(
			{
				"chapter_id": "spine_%d" % spine_index,
				"title": ch_title,
				"path": "",
				"text": plain,
				"text_version": 1,
				"hp_reward": mini(HP_REWARD_BASE + spine_index * 2, HP_REWARD_CAP),
			}
		)
		spine_index += 1
	z.close()
	if chapters.is_empty():
		return {"ok": false, "error": "no_readable_chapters"}
	var book_id := "%s_%s" % [slugify(title), str(abs_path.hash())]
	return {"ok": true, "manifest": {"book_id": book_id, "title": title, "chapters": chapters}}


static func _find_container_path(z: ZIPReader) -> String:
	for p in z.get_files():
		if str(p).to_lower().ends_with("meta-inf/container.xml"):
			return str(p)
	return ""


static func _extract_rootfile_fullpath(container_xml: String) -> String:
	var rx := RegEx.new()
	rx.compile("full-path\\s*=\\s*\"([^\"]+)\"", true)
	var m := rx.search(container_xml)
	if m:
		return m.get_string(1).strip_edges()
	rx.compile("full-path\\s*=\\s*'([^']+)'", true)
	m = rx.search(container_xml)
	if m:
		return m.get_string(1).strip_edges()
	return ""


static func _local_name(tag: String) -> String:
	var s := tag.strip_edges()
	if ":" in s:
		return s.split(":")[-1]
	return s


static func _parse_manifest(opf: String) -> Dictionary:
	var out := {}
	var p := XMLParser.new()
	if p.open_buffer(opf.to_utf8_buffer()) != OK:
		return out
	while p.read() == OK:
		if p.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if _local_name(p.get_node_name()) != "item":
			continue
		var idv := ""
		var hrefv := ""
		for i in range(p.get_attribute_count()):
			var an := _local_name(p.get_attribute_name(i))
			if an == "id":
				idv = p.get_attribute_value(i)
			elif an == "href":
				hrefv = p.get_attribute_value(i)
		if not idv.is_empty() and not hrefv.is_empty():
			out[idv] = hrefv
	return out


static func _parse_spine(opf: String) -> PackedStringArray:
	var order: PackedStringArray = PackedStringArray()
	var p := XMLParser.new()
	if p.open_buffer(opf.to_utf8_buffer()) != OK:
		return order
	while p.read() == OK:
		if p.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if _local_name(p.get_node_name()) != "itemref":
			continue
		var idref := ""
		for i in range(p.get_attribute_count()):
			if _local_name(p.get_attribute_name(i)) == "idref":
				idref = p.get_attribute_value(i)
				break
		if not idref.is_empty():
			order.append(idref)
	return order


static func _parse_dc_title(opf: String) -> String:
	var rx := RegEx.new()
	rx.compile("<[^:>]*:title[^>]*>([^<]+)</[^:>]*:title>", true)
	var m := rx.search(opf)
	if m:
		return m.get_string(1).strip_edges()
	rx.compile("<dc:title[^>]*>([^<]+)</dc:title>", true)
	m = rx.search(opf)
	if m:
		return m.get_string(1).strip_edges()
	return ""


static func html_to_book_plain(html: String) -> String:
	var rx_body := RegEx.new()
	rx_body.compile("<body[^>]*>([\\s\\S]*?)</body>", true)
	var inner := html
	var mb := rx_body.search(html)
	if mb:
		inner = mb.get_string(1)
	inner = _rex_replace(inner, "<script[^>]*>[\\s\\S]*?</script>", " ", true)
	inner = _rex_replace(inner, "<style[^>]*>[\\s\\S]*?</style>", " ", true)
	inner = _rex_replace(inner, "<svg[^>]*>[\\s\\S]*?</svg>", " ", true)
	## Soft line breaks
	inner = _rex_replace(inner, "<br[^>]*/?>", "\n", true)
	## Typical paragraph opens (before we strip remaining tags)
	inner = _rex_replace(inner, "<p[^>]*>", "\n", true)
	inner = _rex_replace(inner, "<div[^>]*>", "\n", true)
	inner = _rex_replace(inner, "<section[^>]*>", "\n", true)
	## Block boundaries → paragraph gaps
	var rx_blk := RegEx.new()
	rx_blk.compile("</(p|div|section|article|header|footer|blockquote|figure|h1|h2|h3|h4|h5|h6)[^>]*>", true)
	inner = rx_blk.sub(inner, "\n\n", true)
	## List lines
	inner = _rex_replace(inner, "<li[^>]*>", "\n    • ", true)
	inner = _rex_replace(inner, "</li>", "\n", true)
	## Drop remaining tags (keep text)
	inner = _rex_replace(inner, "<[^>]+>", " ", true)
	inner = inner.replace("\r\n", "\n").replace("\r", "\n")
	inner = unescape_basic(inner)
	inner = unescape_numeric_entities(inner)
	inner = normalize_inline_whitespace(inner)
	inner = collapse_blank_lines(inner)
	inner = indent_paragraph_blocks(inner)
	return inner.strip_edges()


## Collapse spaces/tabs inside each line; keep single newlines inside a block.
static func normalize_inline_whitespace(s: String) -> String:
	var lines := s.split("\n")
	var out: PackedStringArray = PackedStringArray()
	var rxsp := RegEx.new()
	rxsp.compile("[ \\t]+")
	for line in lines:
		var L := rxsp.sub(str(line), " ", true).strip_edges()
		out.append(L)
	return "\n".join(out)


## 3+ newlines → double (one blank line between paragraphs).
static func collapse_blank_lines(s: String) -> String:
	var rx := RegEx.new()
	rx.compile("\n{3,}")
	return rx.sub(s, "\n\n", true)


## First line of each paragraph (split by blank line) gets a book indent.
static func indent_paragraph_blocks(s: String) -> String:
	var blocks := s.split("\n\n", false)
	var out: PackedStringArray = PackedStringArray()
	for block in blocks:
		var b := str(block).strip_edges()
		if b.is_empty():
			continue
		var lines := b.split("\n")
		var cleaned: PackedStringArray = PackedStringArray()
		for line in lines:
			var L := str(line).strip_edges()
			if not L.is_empty():
				cleaned.append(L)
		if cleaned.is_empty():
			continue
		var first: String = str(cleaned[0])
		if cleaned.size() == 1:
			out.append("\t" + first)
		else:
			var tail: PackedStringArray = PackedStringArray()
			for k in range(1, cleaned.size()):
				tail.append(str(cleaned[k]))
			out.append("\t" + first + "\n" + "\n".join(tail))
	return "\n\n".join(out)


static func unescape_numeric_entities(s: String) -> String:
	var rx := RegEx.new()
	rx.compile("&#(x?[0-9A-Fa-f]+);")
	var out := s
	var safety := 0
	while safety < 5000:
		safety += 1
		var m := rx.search(out)
		if not m:
			break
		var cap := m.get_string(1)
		var code := 0
		if cap.begins_with("x") or cap.begins_with("X"):
			code = cap.substr(1).hex_to_int()
		else:
			code = int(cap)
		var ch := ""
		if code > 0 and code <= 0x10FFFF:
			ch = String.chr(code)
		out = out.substr(0, m.get_start()) + ch + out.substr(m.get_end())
	return out


static func guess_chapter_title(html: String, fallback_num: int) -> String:
	var rx := RegEx.new()
	for pat in ["<h1[^>]*>([\\s\\S]*?)</h1>", "<h2[^>]*>([\\s\\S]*?)</h2>", "<title[^>]*>([\\s\\S]*?)</title>"]:
		rx.compile(pat, true)
		var m := rx.search(html)
		if m:
			var t := _rex_replace(m.get_string(1), "<[^>]+>", " ", true)
			t = unescape_basic(collapse_whitespace(t)).strip_edges()
			if not t.is_empty() and t.length() < 200:
				return t
	return "Глава %d" % fallback_num


static func _is_slug_char(ch: String) -> bool:
	if ch.is_empty():
		return false
	var c: int = ch.unicode_at(0)
	if c >= 0x30 and c <= 0x39:
		return true
	if c >= 0x41 and c <= 0x5A or c >= 0x61 and c <= 0x7A:
		return true
	if c >= 0x0400 and c <= 0x04FF or c >= 0x0500 and c <= 0x052F:
		return true
	return false


static func slugify(s: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var buf := ""
	for i in s.length():
		var ch := s[i]
		if _is_slug_char(ch):
			buf += ch.to_lower()
		else:
			if not buf.is_empty():
				parts.append(buf)
				buf = ""
	if not buf.is_empty():
		parts.append(buf)
	if parts.is_empty():
		return "book"
	return "_".join(parts)


static func _rex_replace(s: String, pattern: String, repl: String, ci: bool) -> String:
	var rx := RegEx.new()
	rx.compile(pattern, ci)
	return rx.sub(s, repl, true)


static func unescape_basic(s: String) -> String:
	return (
		s.replace("&nbsp;", " ")
		.replace("&amp;", "&")
		.replace("&lt;", "<")
		.replace("&gt;", ">")
		.replace("&quot;", "\"")
		.replace("&#39;", "'")
		.replace("&laquo;", "\u00ab")
		.replace("&raquo;", "\u00bb")
		.replace("&mdash;", "\u2014")
		.replace("&ndash;", "\u2013")
		.replace("&hellip;", "\u2026")
		.replace("&apos;", "'")
	)


static func collapse_whitespace(s: String) -> String:
	var rx := RegEx.new()
	rx.compile("\\s+")
	return rx.sub(s, " ", true)


static func _uri_decode_path(s: String) -> String:
	return s.uri_decode()
