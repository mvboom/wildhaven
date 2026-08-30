extends QATestCase
## SAVE STORE — Tier 1 row 1's disk layer, in isolation. Nothing here knows what a world is.
##
## The four properties that matter, and why each is a property and not a nicety:
##   1. NAMING IS NEVER DESTRUCTIVE (human ruling, 2026-08-01). A colliding name auto-suffixes.
##      A six-year-old retyping "Wildhaven" must never overwrite last week's world.
##   2. A CRASH MID-WRITE CANNOT LOSE THE WORLD. Writes go to `.tmp` and rename, so the only
##      copy is never observed truncated.
##   3. A CORRUPT FILE IS LISTED, NOT HIDDEN AND NOT DELETED. The saves-are-human-readable
##      policy assumes a parent can go and look at the file.
##   4. SLUGS ARE FILESYSTEM-SAFE for names a kid actually types (spaces, punctuation, emoji).
##
## HARNESS LIMIT: true crash-atomicity (property 2) is NOT directly observable under this
## headless runner — there is no way to interrupt the process mid-write and inspect the
## half-written state. What `_check_write_is_atomic` actually asserts is that no `.tmp` file
## survives a successful write or rewrite, and that a rewrite's new content is what `read()`
## returns afterward. The atomicity guarantee itself rests on `DirAccess.rename()` being an
## atomic replace at the OS/filesystem level, which this suite takes on faith rather than
## observes.
##
## NEVER TOUCHES A REAL PLAYER SAVE. `SaveStore.SAVE_DIR` is a `static var` for exactly this
## reason: this suite redirects it to an isolated `user://test_saves` directory for its own
## lifetime and restores the real `user://saves` before `finish()`, even on the way out. A
## sweep of "everything in SAVE_DIR" is then safe, because SAVE_DIR never points at a real
## player's directory while this suite is running. (An earlier version of this suite instead
## swept a hardcoded list of filename prefixes inside the real save directory — that could
## delete a real world named "Wildhaven", the game's own default name. Do not reintroduce
## that pattern.)
##
## Run:
##   bash scripts/run-tests.sh save_store

## The real directory a play session uses. Restored onto `SaveStore.SAVE_DIR` before `finish()`.
const _REAL_SAVE_DIR: String = "user://saves"

## An isolated scratch directory that no real save ever lives in. Every path this suite reads
## or writes is built from `SaveStore.SAVE_DIR`, so once this is assigned, nothing here can
## reach `_REAL_SAVE_DIR` even by accident.
const _TEST_SAVE_DIR: String = "user://test_saves"


func _initialize() -> void:
	begin("save store")
	SaveStore.SAVE_DIR = _TEST_SAVE_DIR
	_clean()

	_check_slugify()
	_check_unique_path_auto_suffixes()
	_check_write_read_round_trip()
	_check_write_is_atomic()
	_check_corrupt_file_is_listed_but_unreadable()
	_check_non_numeric_save_version_is_listed_but_unreadable()
	_check_list_is_newest_first()
	_check_rename_updates_the_name_field()
	_check_delete_removes_the_file()

	_clean()
	SaveStore.SAVE_DIR = _REAL_SAVE_DIR
	finish()


## Removes every file in the test's own isolated directory. Safe to be this blunt precisely
## because `SaveStore.SAVE_DIR` is redirected to `_TEST_SAVE_DIR` for the whole run — this
## never runs while `SaveStore.SAVE_DIR` points at a real player's directory. Also fixes the
## crashed-prior-run fragility a `_made`-only clean would have: a stale file left by a killed
## previous run of this suite is still inside `_TEST_SAVE_DIR` and still gets swept here.
func _clean() -> void:
	var dir: DirAccess = DirAccess.open(SaveStore.SAVE_DIR)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/%s" % [SaveStore.SAVE_DIR, filename])
		)


func _check_slugify() -> void:
	check_eq(SaveStore.slugify("Wildhaven"), "wildhaven", "plain name lowercases")
	check_eq(SaveStore.slugify("Bunny Town"), "bunny-town", "spaces become hyphens")
	check_eq(SaveStore.slugify("  Bunny  Town  "), "bunny-town", "runs of space collapse")
	check_eq(SaveStore.slugify("Fox/Den:2*"), "fox-den-2", "path characters cannot survive")
	check_eq(SaveStore.slugify(""), "world", "an empty name still yields a filename")
	check_eq(SaveStore.slugify("🐰"), "world", "a name with no safe characters yields a filename")


func _check_unique_path_auto_suffixes() -> void:
	var first: String = SaveStore.unique_path_for("Wildhaven")
	check_eq(
		first, "%s/wildhaven.json" % SaveStore.SAVE_DIR, "first use of a name takes the plain slug"
	)
	check_eq(
		SaveStore.write(first, {"save_version": 1, "name": "Wildhaven", "wood": 11}), OK,
		"first write succeeds"
	)

	var second: String = SaveStore.unique_path_for("Wildhaven")
	check_eq(
		second, "%s/wildhaven-2.json" % SaveStore.SAVE_DIR, "a colliding name auto-suffixes"
	)
	# Distinguishable content from the first write — otherwise "not overwritten" cannot be told
	# apart from "overwritten with identical bytes."
	check_eq(
		SaveStore.write(second, {"save_version": 1, "name": "Wildhaven", "wood": 22}), OK,
		"second write succeeds"
	)

	check_eq(
		SaveStore.unique_path_for("Wildhaven"), "%s/wildhaven-3.json" % SaveStore.SAVE_DIR,
		"the suffix keeps climbing rather than reusing a taken slot"
	)
	# THE POINT OF THE WHOLE RULING: the first file is still exactly as it was written.
	check_eq(SaveStore.read(first).get("name", ""), "Wildhaven", "the original world was not overwritten")
	check_eq(
		int(SaveStore.read(first).get("wood", -1)), 11,
		"...and its content, distinguishable from the second write, proves it"
	)


func _check_write_read_round_trip() -> void:
	var path: String = SaveStore.unique_path_for("Round Trip")
	var data := {"save_version": 1, "name": "Round Trip", "wood": 50, "terrain": ["grass", "water"]}
	check_eq(SaveStore.write(path, data), OK, "write reports OK")
	var back: Dictionary = SaveStore.read(path)
	check_eq(back.get("name", ""), "Round Trip", "name survives")
	check_eq(int(back.get("wood", -1)), 50, "int survives")
	check_eq((back.get("terrain", []) as Array).size(), 2, "array survives")
	check(
		FileAccess.get_file_as_string(path).contains("\n"),
		"the file is pretty-printed, because gdd.md requires saves be human-readable"
	)


func _check_write_is_atomic() -> void:
	var path: String = SaveStore.unique_path_for("Atomic")
	check_eq(SaveStore.write(path, {"save_version": 1, "name": "Atomic"}), OK, "write succeeds")
	check(not FileAccess.file_exists(path + ".tmp"), "no .tmp survives a successful write")

	# Rewriting must never leave the destination absent, even for an instant we can observe.
	check_eq(SaveStore.write(path, {"save_version": 1, "name": "Atomic II"}), OK, "rewrite succeeds")
	check(FileAccess.file_exists(path), "the destination exists after a rewrite")
	check_eq(SaveStore.read(path).get("name", ""), "Atomic II", "the rewrite took effect")
	check(not FileAccess.file_exists(path + ".tmp"), "no .tmp survives a rewrite either")


func _check_corrupt_file_is_listed_but_unreadable() -> void:
	var path: String = "%s/corrupt.json" % SaveStore.SAVE_DIR
	DirAccess.make_dir_recursive_absolute(SaveStore.SAVE_DIR)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()

	check_eq(SaveStore.read(path), {}, "a corrupt file reads as empty rather than crashing")

	var listed: bool = false
	var marked_unreadable: bool = false
	for entry: Dictionary in SaveStore.list():
		if entry["path"] == path:
			listed = true
			marked_unreadable = not bool(entry["readable"])
	check(listed, "a corrupt world still appears in the list")
	check(marked_unreadable, "and is marked unreadable, so the screen can grey it out")
	check(FileAccess.file_exists(path), "reading a corrupt file never deletes it")


## REGRESSION (commit 1d2e13f's numeric-type guard fix missed `save_version` in
## `WorldSnapshot.can_apply()`). Saves are hand-editable by design, so a `save_version` that is
## not a number — an object, here — is anticipated input, not an impossibility. Before the fix,
## `list()` calling `can_apply()` on this file threw "Invalid call. Nonexistent 'int'
## constructor." merely by the file sitting in the saves directory, on every visit to the Load
## screen with no player action at all. `list()` must instead return normally and mark the file
## unreadable, exactly like a corrupt-JSON file.
func _check_non_numeric_save_version_is_listed_but_unreadable() -> void:
	var path: String = "%s/bad_version.json" % SaveStore.SAVE_DIR
	check_eq(
		SaveStore.write(path, {"save_version": {"oops": 1}, "name": "Bad Version"}), OK,
		"a file with a non-numeric (object) save_version writes fine — the bug is in reading it"
	)

	var listed: bool = false
	var marked_unreadable: bool = false
	for entry: Dictionary in SaveStore.list():
		if entry["path"] == path:
			listed = true
			marked_unreadable = not bool(entry["readable"])
	check(listed, "a non-numeric save_version file still appears in the list")
	check(
		marked_unreadable,
		"...and is marked unreadable rather than crashing `list()` with a script error"
	)


func _check_list_is_newest_first() -> void:
	var older: String = SaveStore.unique_path_for("Older")
	SaveStore.write(older, {"save_version": 1, "name": "Older"})
	OS.delay_msec(1100)  # filesystem mtime granularity is one second
	var newer: String = SaveStore.unique_path_for("Newer")
	SaveStore.write(newer, {"save_version": 1, "name": "Newer"})

	var names: Array[String] = []
	for entry: Dictionary in SaveStore.list():
		names.append(entry["name"] as String)
	var i_newer: int = names.find("Newer")
	var i_older: int = names.find("Older")
	check(i_newer != -1 and i_older != -1, "both worlds are listed")
	check(i_newer < i_older, "the most recently played world is offered first")


func _check_rename_updates_the_name_field() -> void:
	var path: String = SaveStore.unique_path_for("Rename Me")
	SaveStore.write(path, {"save_version": 1, "name": "Rename Me", "wood": 7})

	check_eq(SaveStore.rename(path, "Renamed World"), OK, "rename() reports OK")
	check_eq(SaveStore.read(path).get("name", ""), "Renamed World",
		"the name field changed")
	check_eq(int(SaveStore.read(path).get("wood", -1)), 7,
		"...and nothing else in the file did")
	check(FileAccess.file_exists(path), "the file itself did not move — rename() edits the "
		+ "name field in place, it does not relocate the file")

	check_eq(SaveStore.rename("%s/does-not-exist.json" % SaveStore.SAVE_DIR, "Ghost"), ERR_FILE_CANT_OPEN,
		"renaming a path with no file reports an error rather than fabricating one")


func _check_delete_removes_the_file() -> void:
	var path: String = SaveStore.unique_path_for("Delete Me")
	SaveStore.write(path, {"save_version": 1, "name": "Delete Me"})
	check(FileAccess.file_exists(path), "the file exists before deletion")

	check_eq(SaveStore.delete(path), OK, "delete() reports OK")
	check(not FileAccess.file_exists(path), "the file is gone")

	var listed: bool = false
	for entry: Dictionary in SaveStore.list():
		if entry["path"] == path:
			listed = true
	check(not listed, "...and no longer appears in list()")

	check_eq(SaveStore.delete("%s/does-not-exist.json" % SaveStore.SAVE_DIR), ERR_FILE_CANT_OPEN,
		"deleting a path with no file reports an error rather than succeeding silently")
