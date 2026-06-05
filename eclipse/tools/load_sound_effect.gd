@tool
extends EditorScript
## Syncs SoundEffect .tres files from [member folder_path] directly into the
## audio_manager.tscn by writing the file as text — bypasses Godot's scene
## serializer so exports are never silently dropped.
##
## Run via File → Run in the script editor.

# ── config ────────────────────────────────────────────────────────────────────
var audio_manager_path: String = "res://scenes/audio_manager.tscn"
var folder_path: String        = "res://data/sounds/"

# ── entry point ───────────────────────────────────────────────────────────────
func _run() -> void:
	var global_scene: String = ProjectSettings.globalize_path(audio_manager_path)
	var global_folder: String = ProjectSettings.globalize_path(folder_path)

	if not FileAccess.file_exists(audio_manager_path):
		push_error("AudioManagerTool: scene not found at '%s'" % audio_manager_path)
		return
	if not DirAccess.dir_exists_absolute(global_folder):
		push_error("AudioManagerTool: folder not found at '%s'" % folder_path)
		return

	# ── read existing .tscn ───────────────────────────────────────────────────
	var file := FileAccess.open(audio_manager_path, FileAccess.READ)
	var original := file.get_as_text()
	file.close()

	# Parse out the header line and the [node ...] block separately.
	# We'll rebuild ext_resource blocks and the sound_effects property ourselves.
	var lines := original.split("\n")

	# Find the script ext_resource line and the node section.
	var header_line := ""         # [gd_scene ...] line
	var script_ext_line := ""     # the ext_resource for the script
	var node_lines: Array = []    # everything from [node ...] onward
	var in_node := false

	for line in lines:
		if line.begins_with("[gd_scene"):
			header_line = line
		elif line.begins_with("[ext_resource") and "Script" in line:
			script_ext_line = line
		elif line.begins_with("[node"):
			in_node = true
			node_lines.append(line)
		elif in_node:
			# Skip any existing sound_effects line — we'll rewrite it.
			if line.begins_with("sound_effects"):
				continue
			node_lines.append(line)

	# ── collect .tres files ───────────────────────────────────────────────────
	var files := DirAccess.get_files_at(folder_path)
	var sound_paths: Array[String] = []
	for f in files:
		if f.ends_with(".tres") or f.ends_with(".res"):
			var res_path := folder_path + f
			var res := ResourceLoader.load(res_path)
			if res is SoundEffect:
				sound_paths.append(res_path)

	if sound_paths.is_empty():
		push_error("AudioManagerTool: no SoundEffect resources found in '%s'" % folder_path)
		return

	# ── build new .tscn text ──────────────────────────────────────────────────
	var out := ""
	out += header_line + "\n\n"
	out += script_ext_line + "\n"

	# Write one ext_resource per sound effect.
	var refs: Array[String] = []
	for i in sound_paths.size():
		var id := "se_%d" % i
		out += '[ext_resource type="Resource" path="%s" id="%s"]\n' % [sound_paths[i], id]
		refs.append('ExtResource("%s")' % id)

	out += "\n"

	# Write the node block, inserting sound_effects after the script line.
	for i in node_lines.size():
		out += node_lines[i] + "\n"
		if node_lines[i].begins_with("[node"):
			# Insert script line if not already in node_lines.
			if not "script" in node_lines[i]:
				pass  # script is on its own line, handled below
		if "script = ExtResource" in node_lines[i]:
			out += "sound_effects = [%s]\n" % ", ".join(refs)

	# ── save ──────────────────────────────────────────────────────────────────
	var out_file := FileAccess.open(audio_manager_path, FileAccess.WRITE)
	if out_file == null:
		push_error("AudioManagerTool: could not open scene for writing.")
		return
	out_file.store_string(out)
	out_file.close()

	print("AudioManagerTool: wrote %d SoundEffect(s) into %s" % [sound_paths.size(), audio_manager_path])
	get_editor_interface().get_resource_filesystem().scan()
