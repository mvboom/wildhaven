class_name SaveStore
extends RefCounted
## THE DISK LAYER of Tier 1 row 1. Static-only; never instantiated.
##
## THIS FILE DOES NOT KNOW WHAT A WORLD IS. It moves dictionaries to and from files, and that
## separation is what lets `WorldSnapshot` be exercised with no disk and this be exercised with
## no world. The schema lives in `world_snapshot.gd`; nothing here may read a key by name
## except `name`, which is the one field the Load list has to show without understanding the
## rest of the file.
##
## SAVES ARE HUMAN-READABLE ON PURPOSE — gdd.md -> Saves: "fully human-readable because the
## game must not hide or encrypt its content." Hence `JSON.stringify(..., "\t")` and never a
## binary or compressed form.
##
## NAMING VIA `unique_path_for()` IS NEVER DESTRUCTIVE — auto-suffixes, so retyping a name
## can never overwrite another world.
##
## RENAME AND DELETE EXIST (REVERSED, this session — see
## docs/superpowers/plans/2026-08-09-main-menu-simplification.md's header; was "no delete
## function... a stronger guarantee than a UI that chooses not to draw a button," 2026-08-01).
## The caller is responsible for confirming a delete with the player first — this file has
## no undo once `delete()` runs.

## `static var`, not `const`: production code never reassigns this — the default below is the
## only directory a real play session ever writes to. It is a `static var` solely so a test can
## redirect every `SaveStore` call to an isolated scratch directory (e.g. `user://test_saves`)
## for its own lifetime and restore the default afterward, and therefore can never delete or
## overwrite a real player's save. See `test_save_store.gd`'s `_initialize()`.
static var SAVE_DIR: String = "user://saves"

## Filename fallback when a name has no filesystem-safe characters at all (a kid typing only
## emoji). Never surfaced to the player — the world's display name is stored inside the file.
const FALLBACK_SLUG: String = "world"


## Lowercase, spaces and punctuation to single hyphens, trimmed. Path separators, `:` and `*`
## cannot survive, which is what makes a player-typed name safe to use as a filename.
static func slugify(name: String) -> String:
	var out: String = ""
	for c: String in name.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		else:
			out += "-"
	while out.contains("--"):
		out = out.replace("--", "-")
	out = out.strip_edges().lstrip("-").rstrip("-")
	return FALLBACK_SLUG if out.is_empty() else out


## The path a new world with this name should take. Never returns a path that already exists,
## so a colliding name becomes `wildhaven-2`, `wildhaven-3`, ... and no world is ever
## overwritten by a player retyping a name.
static func unique_path_for(name: String) -> String:
	var slug: String = slugify(name)
	var candidate: String = "%s/%s.json" % [SAVE_DIR, slug]
	var n: int = 2
	while FileAccess.file_exists(candidate):
		candidate = "%s/%s-%d.json" % [SAVE_DIR, slug, n]
		n += 1
	return candidate


## ATOMIC BY CONSTRUCTION: write to `.tmp`, then rename over the destination. A crash between
## the two leaves the previous save whole, so the only copy of a world is never observed
## truncated. A plain `open(path, WRITE)` truncates first and would lose the world outright.
static func write(path: String, data: Dictionary) -> Error:
	var err: Error = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("SaveStore: cannot create %s (error %d)" % [SAVE_DIR, err])
		return err

	var tmp: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		var open_err: Error = FileAccess.get_open_error()
		push_error("SaveStore: cannot open %s (error %d)" % [tmp, open_err])
		return open_err
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		push_error("SaveStore: cannot open %s for rename" % SAVE_DIR)
		return ERR_FILE_CANT_OPEN
	# `rename` replaces the destination on every platform Godot targets.
	err = dir.rename(tmp.get_file(), path.get_file())
	if err != OK:
		push_error("SaveStore: cannot rename %s -> %s (error %d)" % [tmp, path, err])
		return err
	return OK


## Rewrites the save's `name` field in place; the path/filename is unchanged. Read-modify-
## write through the existing atomic `write()`, not a raw string edit, so this can never
## produce a malformed file. Returns `ERR_FILE_CANT_OPEN` if `path` has nothing to read
## (matching `read()`'s own "empty on any failure" contract, translated into an Error).
static func rename(path: String, new_name: String) -> Error:
	var data: Dictionary = read(path)
	if data.is_empty():
		push_error("SaveStore: cannot rename %s (error %d)" % [path, ERR_FILE_CANT_OPEN])
		return ERR_FILE_CANT_OPEN
	data["name"] = new_name
	return write(path, data)


## Deletes the save file outright. No undo, no trash — the caller (the Saved Worlds screen)
## confirms with the player before ever calling this. Returns `ERR_FILE_CANT_OPEN` if the
## path has no file to delete (matching `rename()`'s convention for "nothing to act on").
static func delete(path: String) -> Error:
	if not FileAccess.file_exists(path):
		push_error("SaveStore: cannot delete %s (error %d)" % [path, ERR_FILE_CANT_OPEN])
		return ERR_FILE_CANT_OPEN
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		push_error("SaveStore: cannot open %s to delete %s (error %d)" % [SAVE_DIR, path, ERR_FILE_CANT_OPEN])
		return ERR_FILE_CANT_OPEN
	var err: Error = dir.remove(path.get_file())
	if err != OK:
		push_error("SaveStore: cannot delete %s (error %d)" % [path, err])
	return err


## `{}` on ANY failure — missing, unreadable, malformed, or valid JSON that is not an object.
## Never throws, never deletes. The caller decides what an empty read means.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveStore: %s is not a JSON object; treating as unreadable." % path)
		return {}
	return parsed as Dictionary


## Every world on disk, newest first. A file that cannot be OPENED is STILL LISTED, with
## `readable = false` and its filename standing in for the name — the Load screen greys it
## rather than hiding it, because a world silently vanishing is worse than one that will not
## open, and the file is human-readable precisely so a parent can go and look.
##
## `readable` MEANS "THIS BUILD CAN ACTUALLY OPEN IT", NOT "THIS PARSED AS JSON". Those are
## different predicates, and greying on the weaker one greys the wrong files: a save written by
## a later build, or one with no `save_version` at all, parses perfectly and is then refused by
## `WorldRoot._ready()` — so it used to draw as an ordinary clickable row that dumped the child
## into an empty default world when tapped. `can_apply()` is the same call that refusal makes,
## so the list and the load can no longer disagree.
##
## THE LAYERING IS INTACT: this file still reads no key by name but `name`. It delegates the one
## question it cannot answer to the schema layer instead of learning the schema — and the
## dependency is one-way, since `world_snapshot.gd` never touches the disk or this class.
## The alternative (return the raw `save_version` and let `load_game_screen.gd` compare it)
## was rejected: it would put `<= SAVE_VERSION` in a UI script, giving the version rule two
## homes that can drift, for no reduction in coupling.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return out  # no saves yet is not an error

	for filename: String in dir.get_files():
		if not filename.ends_with(".json"):
			continue  # skips any stranded .tmp
		var path: String = "%s/%s" % [SAVE_DIR, filename]
		var data: Dictionary = read(path)
		var readable: bool = not data.is_empty() and WorldSnapshot.can_apply(data)
		out.append({
			"name": data.get("name", filename.get_basename()) as String,
			"path": path,
			"modified": FileAccess.get_modified_time(path),
			"readable": readable,
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["modified"]) > int(b["modified"])
	)
	return out
