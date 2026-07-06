# save_manager.gd
# ---------------------------------------------------------------------------
# Stub save system. Add as an autoload (singleton) named "SaveManager".
# No persistence exists yet -- this only exists so UI (e.g. the main menu's
# Continue button) has something stable to query/call against.
#
# TODO: implement real save/load (likely an in-progress-run snapshot, since
# this is a roguelite run structure rather than a traditional save file).
# ---------------------------------------------------------------------------
extends Node

func has_save() -> bool:
	return false

func load_game() -> void:
	push_warning("[SaveManager] load_game() called but no save system exists yet.")

func save_game() -> void:
	push_warning("[SaveManager] save_game() called but no save system exists yet.")
