class_name Tooltip
extends Control

const PAD: int = 12

var _panel:        PanelContainer = null
var _vbox:         VBoxContainer  = null
var _mouse_on_src: bool           = false
var _mouse_on_tip: bool           = false
var _hide_timer:   SceneTreeTimer = null
var _show_timer:   SceneTreeTimer = null
var _was_shown:    bool           = false
var _show_generation: int         = 0
var _on_hidden_callback: Callable = Callable()

const SHOW_DELAY: float = 0.20
const HIDE_DELAY: float = 0.10

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4096
	hide()

	_panel = PanelContainer.new()
	_panel.mouse_filter          = Control.MOUSE_FILTER_PASS
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	_panel.mouse_entered.connect(func() -> void:
		_mouse_on_tip = true
		_cancel_hide())
	_panel.mouse_exited.connect(func() -> void:
		_mouse_on_tip = false
		_evaluate_hide())
	_panel.add_theme_stylebox_override("panel", _make_style())
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(_vbox)

func _build_content(_data: Object) -> void:
	pass

func _make_style() -> StyleBoxFlat:
	return StyleBoxFlat.new()

# ── public API ────────────────────────────────────────────────────────────────

func request_show(data: Object, at_global: Vector2) -> void:
	_mouse_on_src = true
	_cancel_hide()
	_show_generation += 1
	var my_gen: int = _show_generation
	_show_timer = get_tree().create_timer(SHOW_DELAY)
	_show_timer.timeout.connect(func() -> void:
		_show_timer = null
		if not _mouse_on_src or my_gen != _show_generation:
			return
		_was_shown = true
		_open(data, at_global)
	)

func update_position(at_global: Vector2) -> void:
	if visible:
		_reposition(at_global)

func request_hide() -> void:
	_mouse_on_src = false
	_cancel_show()
	if not _was_shown:
		hide()
		return
	_evaluate_hide()

func hide_now() -> void:
	_mouse_on_src = false
	_mouse_on_tip = false
	_was_shown    = false
	_cancel_show()
	_cancel_hide()
	hide()

# ── internal ──────────────────────────────────────────────────────────────────

func _open(data: Object, at_global: Vector2) -> void:
	for child in _vbox.get_children():
		_vbox.remove_child(child)
		child.free()
	_build_content(data)
	_ignore_mouse(_vbox)
	_panel.size = Vector2.ZERO
	await get_tree().process_frame
	_reposition(at_global)
	show()

func _cancel_show() -> void:
	_show_generation += 1   # invalidates any pending timer callback
	_show_timer = null

func _cancel_hide() -> void:
	_hide_timer = null

func _evaluate_hide() -> void:
	if _mouse_on_src or _mouse_on_tip:
		return
	if _hide_timer != null:
		return
	_hide_timer = get_tree().create_timer(HIDE_DELAY)
	_hide_timer.timeout.connect(func() -> void:
		_hide_timer = null
		if not _mouse_on_src and not _mouse_on_tip:
			_was_shown = false
			hide()
			if _on_hidden_callback.is_valid():
				_on_hidden_callback.call()
	)

func _ignore_mouse(node: Control) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ignore_mouse(child)

func _reposition(at_global: Vector2) -> void:
	var vp:    Vector2 = get_viewport_rect().size
	var psize: Vector2 = _panel.size
	const OFFSET: Vector2 = Vector2(14, 0)
	var pos: Vector2 = at_global + OFFSET
	if pos.x + psize.x > vp.x - 8:
		pos.x = at_global.x - psize.x - OFFSET.x
	pos.y = clampf(pos.y, 8, vp.y - psize.y - 8)
	_panel.position = pos

func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_sep(color: Color) -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", color)
	return sep
