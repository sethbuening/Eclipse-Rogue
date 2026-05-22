# forge_ui.gd
extends CanvasLayer

# ── references ────────────────────────────────────────────────────────────────
var player: Node2D = null
var forge:  Forge  = null

# ── state ─────────────────────────────────────────────────────────────────────
var staged_orbs:   Array[Orb]    = []
var staged_metals: Dictionary    = {}   # MetalData → int

# ── nodes ─────────────────────────────────────────────────────────────────────
@onready var root_panel:       Control       = %RootPanel
@onready var input_screen:     Control       = %InputScreen
@onready var forging_screen:   Control       = %ForgingScreen
@onready var complete_screen:  Control       = %CompleteScreen

# input screen
@onready var orb_inventory_list:   VBoxContainer = %OrbInventoryList
@onready var metal_inventory_list: VBoxContainer = %MetalInventoryList
@onready var staged_orb_list:      VBoxContainer = %StagedOrbList
@onready var staged_metal_list:    VBoxContainer = %StagedMetalList
@onready var heat_label:           Label         = %HeatLabel
@onready var preview_label:        Label         = %PreviewLabel
@onready var activate_button:      Button        = %ActivateButton
@onready var cancel_button:        Button        = %CancelButton

# forging screen
@onready var progress_bar:         ProgressBar   = %ForgeProgressBar
@onready var forging_heat_label:   Label         = %ForgingHeatLabel
@onready var forging_wave_label:   Label         = %ForgingWaveLabel

# complete screen
@onready var result_name_label:    Label         = %ResultNameLabel
@onready var result_ability_list:  VBoxContainer = %ResultAbilityList
@onready var result_stat_list:     VBoxContainer = %ResultStatList
@onready var collect_button:       Button        = %CollectButton

# ── ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	activate_button.pressed.connect(_on_activate_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	collect_button.pressed.connect(_on_collect_pressed)

# ── open / close ──────────────────────────────────────────────────────────────
func open(p: Node2D, f: Forge) -> void:
	player = p
	forge  = f
	staged_orbs   = []
	staged_metals = {}
	forge.forge_complete.connect(_on_forge_complete, CONNECT_ONE_SHOT)
	var inventory: Node = player.get_node_or_null("Inventory")
	if inventory == null:
		push_error("ForgeUI: player has no Inventory node!")
		return
	_show_input_screen()
	show()
	get_tree().paused = true

func close() -> void:
	if forge != null and forge.state == Forge.State.OPEN:
		forge.state = Forge.State.IDLE
		forge.input_orbs.clear()
		forge.metal_counts.clear()
	player        = null
	forge         = null
	staged_orbs   = []
	staged_metals = {}
	hide()
	get_tree().paused = false

# ── screens ───────────────────────────────────────────────────────────────────
func _show_input_screen() -> void:
	input_screen.show()
	forging_screen.hide()
	complete_screen.hide()
	_rebuild_input_screen()

func _show_forging_screen() -> void:
	input_screen.hide()
	forging_screen.show()
	complete_screen.hide()
	forging_heat_label.text = "Heat: %d" % forge.compute_heat()
	forging_wave_label.text = "Enemies approaching..."
	progress_bar.value      = 0.0

func _show_complete_screen(result: ForgeResult) -> void:
	input_screen.hide()
	forging_screen.hide()
	complete_screen.show()
	_populate_result(result)

# ── process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not visible:
		return
	if forging_screen.visible and forge != null:
		var t: float     = forge.forge_timer / forge.forge_duration
		progress_bar.value = clampf(t * 100.0, 0.0, 100.0)

# ── input screen build ────────────────────────────────────────────────────────
func _rebuild_input_screen() -> void:
	_rebuild_orb_inventory()
	_rebuild_metal_inventory()
	_rebuild_staged_orbs()
	_rebuild_staged_metals()
	_rebuild_heat_and_preview()

func _rebuild_orb_inventory() -> void:
	for child in orb_inventory_list.get_children():
		child.free()
	if player == null:
		return
	var inventory: Node = player.get_node("Inventory")
	for orb: Orb in inventory.orbs:
		if staged_orbs.has(orb):
			continue
		var btn    := Button.new()
		btn.text    = "%s  [+]" % orb.display_name
		btn.pressed.connect(_stage_orb.bind(orb))
		orb_inventory_list.add_child(btn)

func _rebuild_metal_inventory() -> void:
	for child in metal_inventory_list.get_children():
		child.free()
	if player == null:
		return
	var inventory: Node       = player.get_node("Inventory")
	var metals:    Dictionary = inventory.get_metals()
	print("rebuilding metal inventory — metal count: ", metals.size())
	for metal: MetalData in metals.keys():
		var available: int = metals[metal] - staged_metals.get(metal, 0)
		if available <= 0:
			continue
		var hbox   := HBoxContainer.new()
		var label  := Label.new()
		label.text  = "%s  (x%d available)" % [metal.display_name, available]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var add_one  := Button.new()
		var add_five := Button.new()
		var add_all  := Button.new()
		add_one.text  = "+1"
		add_five.text = "+5"
		add_all.text  = "+All"
		add_one.pressed.connect(_stage_metal.bind(metal, 1))
		add_five.pressed.connect(_stage_metal.bind(metal, mini(5, available)))
		add_all.pressed.connect(_stage_metal.bind(metal, available))
		hbox.add_child(label)
		hbox.add_child(add_one)
		hbox.add_child(add_five)
		hbox.add_child(add_all)
		metal_inventory_list.add_child(hbox)
		print("added hbox for: ", metal.display_name, " | list child count: ", metal_inventory_list.get_child_count())

func _rebuild_staged_orbs() -> void:
	for child in staged_orb_list.get_children():
		child.free()
	for orb: Orb in staged_orbs:
		var hbox  := HBoxContainer.new()
		var label := Label.new()
		label.text = orb.display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var remove := Button.new()
		remove.text = "[-]"
		remove.pressed.connect(_unstage_orb.bind(orb))
		hbox.add_child(label)
		hbox.add_child(remove)
		staged_orb_list.add_child(hbox)

func _rebuild_staged_metals() -> void:
	for child in staged_metal_list.get_children():
		child.free()
	for metal: MetalData in staged_metals:
		var count: int = staged_metals[metal]
		if count <= 0:
			continue
		var hbox   := HBoxContainer.new()
		var label  := Label.new()
		label.text  = "%s  x%d" % [metal.display_name, count]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rem_one := Button.new()
		var rem_all := Button.new()
		rem_one.text = "-1"
		rem_all.text = "-All"
		rem_one.pressed.connect(_unstage_metal.bind(metal, 1))
		rem_all.pressed.connect(_unstage_metal.bind(metal, count))
		hbox.add_child(label)
		hbox.add_child(rem_one)
		hbox.add_child(rem_all)
		staged_metal_list.add_child(hbox)

func _rebuild_heat_and_preview() -> void:
	var heat: int = 0
	for metal: MetalData in staged_metals:
		heat += metal.rarity * staged_metals[metal]
	heat_label.text          = "Heat: %d" % heat
	activate_button.disabled = not forge.can_activate()

	if not forge.can_activate():
		preview_label.text = "Add resources to activate."
		return

	if staged_orbs.is_empty():
		var lines: Array[String] = []
		for metal: MetalData in staged_metals:
			var ability_desc: String = "new ability" if not metal.ability_pool.is_empty() else "no ability"
			var bonus_desc: String   = ", ".join(metal.stat_names.map(func(s: String): return "+%s" % s))
			lines.append("• %s → %s, stat bonus (%s)" % [metal.display_name, ability_desc, bonus_desc])
		preview_label.text = "Forging new orb:\n" + "\n".join(lines)
	else:
		var ability_names: Array[String] = []
		for orb: Orb in staged_orbs:
			for ability: AbilityData in orb.abilities:
				ability_names.append(ability.display_name if "display_name" in ability else ability.get_class())
		var stat_names: Array[String] = []
		for metal: MetalData in staged_metals:
			for stat: String in metal.stat_names:
				if not stat_names.has(stat):
					stat_names.append(stat)
		var lines: Array[String] = []
		lines.append("Inherited abilities:")
		for name: String in ability_names:
			lines.append("  • " + name)
		if not stat_names.is_empty():
			lines.append("Metal bonuses to: " + ", ".join(stat_names))
		preview_label.text = "\n".join(lines)

# ── staging ───────────────────────────────────────────────────────────────────
func _stage_orb(orb: Orb) -> void:
	staged_orbs.append(orb)
	forge.deposit_orb(orb)
	_rebuild_input_screen()

func _unstage_orb(orb: Orb) -> void:
	staged_orbs.erase(orb)
	forge.withdraw_orb(orb)
	_rebuild_input_screen()

func _stage_metal(metal: MetalData, count: int) -> void:
	staged_metals[metal] = staged_metals.get(metal, 0) + count
	forge.deposit_metal(metal, count)
	_rebuild_input_screen()

func _unstage_metal(metal: MetalData, count: int) -> void:
	var current: int = staged_metals.get(metal, 0)
	var remove:  int = mini(count, current)
	staged_metals[metal] = current - remove
	if staged_metals[metal] <= 0:
		staged_metals.erase(metal)
	forge.withdraw_metal(metal, remove)
	_rebuild_input_screen()

# ── buttons ───────────────────────────────────────────────────────────────────
func _on_activate_pressed() -> void:
	if not forge.can_activate():
		return
	# remove staged items from player inventory permanently
	var inventory: Node = player.get_node("Inventory")
	for orb: Orb in staged_orbs:
		inventory.remove_orb(orb)
	for metal: MetalData in staged_metals:
		inventory.remove_metals(metal, staged_metals[metal])
	forge.activate()
	_show_forging_screen()
	get_tree().paused = false

func _on_cancel_pressed() -> void:
	for orb: Orb in staged_orbs:
		forge.withdraw_orb(orb)
	for metal: MetalData in staged_metals:
		forge.withdraw_metal(metal, staged_metals[metal])
	forge.state = Forge.State.IDLE
	forge.input_orbs.clear()
	forge.metal_counts.clear()
	close()

func _on_collect_pressed() -> void:
	if forge.result == null:
		return
	var new_orb: Orb = _build_orb_from_result(forge.result)
	player.get_node("Inventory").add_orb(new_orb)
	forge.state = Forge.State.COMPLETE
	close()

func _on_forge_complete(result: ForgeResult) -> void:
	get_tree().paused = true
	_show_complete_screen(result)

# ── result screen ─────────────────────────────────────────────────────────────
func _populate_result(result: ForgeResult) -> void:
	for child in result_ability_list.get_children():
		child.queue_free()
	for child in result_stat_list.get_children():
		child.queue_free()

	# name from identity
	if result.identity is Orb:
		result_name_label.text = "Forged: %s" % (result.identity as Orb).display_name
	elif result.identity is MetalData:
		result_name_label.text = "Forged: %s Orb" % (result.identity as MetalData).display_name
	else:
		result_name_label.text = "Forged Orb"

	for ability: AbilityData in result.abilities:
		var label  := Label.new()
		var name: String = ability.display_name if "display_name" in ability else ability.get_class()
		label.text  = "• " + name
		result_ability_list.add_child(label)

	for stat: String in result.stat_bonuses:
		var label  := Label.new()
		var value: float = result.stat_bonuses[stat]
		label.text  = "+ %s  %.2f" % [stat, value]
		result_stat_list.add_child(label)

func _build_orb_from_result(result: ForgeResult) -> Orb:
	var orb := Orb.new()
	# identity visuals
	if result.identity is Orb:
		var src: Orb      = result.identity as Orb
		orb.display_name  = src.display_name
		orb.sprite_texture = src.sprite_texture
	elif result.identity is MetalData:
		var src: MetalData = result.identity as MetalData
		orb.display_name   = src.display_name + " Orb"
		orb.sprite_texture = src.sprite_texture
	# abilities
	for ability: AbilityData in result.abilities:
		orb.abilities.append(ability.duplicate(true))
	# stat bonuses applied to each ability's stats
	for ability: AbilityData in orb.abilities:
		if ability.stats == null:
			continue
		for stat: String in result.stat_bonuses:
			if stat in ability.stats:
				ability.stats[stat] += result.stat_bonuses[stat]
	return orb
