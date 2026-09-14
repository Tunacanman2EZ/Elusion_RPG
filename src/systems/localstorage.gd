# local file-based storage backend for save data.
# implements atomic writes with automatic backup and crash recovery.
#
# this class knows about files and JSON — but knows NOTHING about characters,
# stats, or game logic. it just stores and retrieves dictionaries.
#
# atomic write flow:
# 1. write the new payload to a .tmp file (existing save untouched)
# 2. copy the current save to .bak (backup before overwrite)
# 3. delete the existing save
# 4. rename .tmp to the real save name (atomic OS operation)
# at no point can a crash leave a half-written save file. either:
# - .tmp exists with the new payload, .save unchanged → recoverable
# - .save exists with the new payload, .tmp gone → completed
# the .bak gives a second-chance fallback if both fail somehow.
#
# to swap for a different storage backend (e.g. server-based for MMO),
# write a new class with the same save() and load() methods.
class_name LocalStorage
extends SaveStorage


# =============================================================================
# STATE
# =============================================================================

# absolute paths to the three save files (real, temp, backup).
# derived from the base_path passed to _init().
var save_path:   String
var tmp_path:    String
var backup_path: String


# =============================================================================
# CONSTRUCTOR
# =============================================================================

func _init(base_path: String = "user://character.save") -> void:
	# allow callers to override the save location (test isolation, alt save
	# slots, etc.). tmp and backup paths are derived from the base.
	save_path   = base_path
	tmp_path    = base_path + ".tmp"
	backup_path = base_path + ".bak"


# =============================================================================
# SAVE
# =============================================================================

func save(payload: Dictionary) -> bool:
	# atomic save: write to .tmp first, back up the current save, then
	# rename .tmp to the real save name. if any step fails, the existing
	# save file is untouched. prevents corruption on crash.
	if not _write_temp_file(payload):
		return false

	_backup_existing_save()

	return _promote_temp_to_save()


func _write_temp_file(payload: Dictionary) -> bool:
	# step 1: write the new payload to .tmp.
	# the real save file is not touched at this point — if this fails,
	# the previous save remains intact.
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("save failed: could not open temp file. error: %s" % FileAccess.get_open_error())
		return false

	file.store_line(JSON.stringify(payload))
	file.close()
	return true


func _backup_existing_save() -> void:
	# step 2: copy the current save to .bak before we overwrite it.
	# non-fatal if this fails — log a warning but let the save proceed,
	# since the new payload is still safely on disk as .tmp.
	if not FileAccess.file_exists(save_path):
		return

	# remove old backup before copying
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)

	var copy_err: int = DirAccess.copy_absolute(save_path, backup_path)
	if copy_err != OK:
		push_warning("backup creation failed: %s (save will still proceed)" % error_string(copy_err))


func _promote_temp_to_save() -> bool:
	# step 3: rename .tmp to the real save file. this is the "atomic" step —
	# the OS does the rename as a single operation, so the file is either
	# fully the old version or fully the new one, never half-written.
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("save failed: could not access user:// directory")
		return false

	# DirAccess.rename uses filenames relative to its open path, not full paths
	var save_filename: String = save_path.get_file()
	var tmp_filename:  String = tmp_path.get_file()

	# delete the existing save first — some platforms refuse to rename
	# over an existing file (Windows is notorious for this).
	if FileAccess.file_exists(save_path):
		dir.remove(save_filename)

	var err: int = dir.rename(tmp_filename, save_filename)
	if err != OK:
		push_error("save failed: could not finalize save. error: %s" % error_string(err))
		return false

	return true


# =============================================================================
# LOAD
# =============================================================================

func load() -> Dictionary:
	# loads save data with automatic fallback to the backup file.
	# returns the parsed dictionary on success, or {} if both files are
	# missing or corrupt.
	#
	# fallback order:
	# 1. try the main save file
	# 2. if main fails AND backup exists, try the backup
	# 3. if both fail, log critical error and return {}

	var data: Dictionary = _load_file(save_path)

	# fall back to backup if main save was unreadable
	if data.is_empty() and FileAccess.file_exists(backup_path):
		push_warning("main save unavailable, attempting to load backup")
		data = _load_file(backup_path)
		if not data.is_empty():
			# NOT debug-gated, and promoted from print to push_warning.
			# Falling back to the backup means the main save was unreadable
			# and the player has silently lost whatever happened between the
			# two writes. It is the quietest serious thing this file can do,
			# and it needs to be visible in the build it happens in.
			push_warning("LocalStorage: main save was unreadable — recovered from backup (progress since the last backup is lost)")

	# critical: save file exists but couldn't be parsed AND no backup
	if data.is_empty() and FileAccess.file_exists(save_path):
		push_error("CRITICAL: save file exists but could not be loaded, and backup is missing or corrupt")

	return data


func _load_file(path: String) -> Dictionary:
	# attempts to load and parse a single save file at the given path.
	# returns {} on any failure (missing, unreadable, empty, malformed JSON,
	# wrong root type). errors are logged with the path for diagnosability.
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("could not open save file at %s. error: %s" % [path, FileAccess.get_open_error()])
		return {}

	var line: String = file.get_line()
	file.close()

	if line.is_empty():
		push_error("save file at %s is empty" % path)
		return {}

	var data = JSON.parse_string(line)
	if data == null:
		push_error("save file at %s contains invalid JSON" % path)
		return {}

	if typeof(data) != TYPE_DICTIONARY:
		push_error("save file at %s does not contain a dictionary" % path)
		return {}

	return data
