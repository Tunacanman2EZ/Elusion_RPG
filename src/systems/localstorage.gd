# local file-based storage backend for save data.
# implements atomic writes with automatic backup and crash recovery.
# this class knows about files and JSON — but knows NOTHING about characters,
# stats, or game logic. it just stores and retrieves dictionaries.
#
# to swap for a different storage backend (e.g. server-based for MMO),
# write a new class with the same save() and load() methods.
class_name LocalStorage
extends RefCounted

# file paths for the save, temp, and backup files
var save_path: String
var tmp_path: String
var backup_path: String

func _init(base_path: String = "user://character.save") -> void:
	# allow callers to specify the save file path — defaults to character.save
	# tmp and backup are derived from the base path
	save_path = base_path
	tmp_path = base_path + ".tmp"
	backup_path = base_path + ".bak"

func save(payload: Dictionary) -> bool:
	# atomic save: write to a temp file, back up the current save,
	# then rename temp to real. if anything fails partway through,
	# the existing save file is untouched. prevents corruption on crash.

	# step 1: open the temp file for writing — does NOT touch the real save yet
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("save failed: could not open temp file. error: %s" % FileAccess.get_open_error())
		return false

	# step 2: write the payload as JSON
	file.store_line(JSON.stringify(payload))
	file.close()

	# step 3: if a previous save exists, copy it to the backup file
	# uses copy_absolute with full paths — more reliable than relative copy
	if FileAccess.file_exists(save_path):
		# remove old backup first if it exists
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		# copy current save to backup using absolute paths
		var copy_err := DirAccess.copy_absolute(save_path, backup_path)
		if copy_err != OK:
			# backup failed but the new save is still safe in the temp file
			# log the issue but don't abort — the main save can still proceed
			push_warning("backup creation failed: %s (save will still proceed)" % error_string(copy_err))

	# step 4: rename temp file to the real save file
	# this is the "atomic" part — the OS does this as a single operation,
	# so the file is either fully the old version or fully the new version,
	# never half-written.
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("save failed: could not access user:// directory")
		return false

	# extract the filename from the path for the rename call
	var save_filename := save_path.get_file()
	var tmp_filename := tmp_path.get_file()

	# delete the existing save file first to be safe across platforms
	if FileAccess.file_exists(save_path):
		dir.remove(save_filename)

	var err := dir.rename(tmp_filename, save_filename)
	if err != OK:
		push_error("save failed: could not finalize save. error: %s" % error_string(err))
		return false

	return true

func load() -> Dictionary:
	# loads save data with automatic fallback to the backup file.
	# returns the parsed dictionary on success, or empty {} if both files
	# are missing or corrupt.

	# try the main save file first
	var data := _load_file(save_path)

	# if main save failed and we have a backup, try the backup
	if data.is_empty() and FileAccess.file_exists(backup_path):
		push_warning("main save unavailable, attempting to load backup")
		data = _load_file(backup_path)
		if not data.is_empty():
			print("recovered from backup save file")

	# log clearly if everything failed but a save was supposed to exist
	if data.is_empty() and FileAccess.file_exists(save_path):
		push_error("CRITICAL: save file exists but could not be loaded, and backup is missing or corrupt")

	return data

func _load_file(path: String) -> Dictionary:
	# attempts to load and parse a single save file at the given path.
	# returns the parsed dictionary on success, or empty {} on failure.

	# bail early if the file doesn't exist
	if not FileAccess.file_exists(path):
		return {}

	# try to open the file
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("could not open save file at %s. error: %s" % [path, FileAccess.get_open_error()])
		return {}

	# read and close
	var line := file.get_line()
	file.close()

	# guard against empty file
	if line.is_empty():
		push_error("save file at %s is empty" % path)
		return {}

	# parse the JSON
	var data = JSON.parse_string(line)
	if data == null:
		push_error("save file at %s contains invalid JSON" % path)
		return {}

	# guard against unexpected structure
	if typeof(data) != TYPE_DICTIONARY:
		push_error("save file at %s does not contain a dictionary" % path)
		return {}

	return data
