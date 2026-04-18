Put your EPUB in this folder as:

  main.epub

The game loads it from the repository by default (see config/book_source.json:
  "epub_path": "res://books/main.epub"

You can commit main.epub to Git if the file size is acceptable for your remote.

To use another file name, set "epub_path" in book_source.json to a res:// path
under books/ or to an absolute path. Save that JSON as UTF-8 if the path
contains non-ASCII letters.
