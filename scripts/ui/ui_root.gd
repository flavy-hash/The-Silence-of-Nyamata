extends CanvasLayer
## All in-game UI, built in code so it needs no hand-made scenes:
##   HUD (objectives, interaction prompt, stamina, objective marker, toasts, ambient subtitles)
##   dialogue box with typewriter text and numbered choices
##   cinematic captions, title cards, letterbox and fades
##   inventory, pause menu, save/load slots, settings, controls
## Title and content-warning screens reuse the settings and load panels from here.

const COL_TEXT := Color("efe9dd")
const COL_DIM := Color("b9b1a1")
const COL_ACCENT := Color("d9a441")
const COL_PANEL := Color(0.075, 0.07, 0.06, 0.9)

var gameplay := false
var cinematic := false

var _theme: Theme
var _hud: Control
var _obj_title: Label
var _obj_text: Label
var _side_box: VBoxContainer
var _objective_panel: PanelContainer
var _prompt: Label
var _stamina: ProgressBar
var _toasts: VBoxContainer
var _bark: Label
var _marker: Control
var _caption: Label
var _title_card: VBoxContainer
var _title_main: Label
var _title_sub: Label
var _skip_hint: Label
var _letterbox_top: ColorRect
var _letterbox_bottom: ColorRect
var _fade: ColorRect

var _dialogue: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _continue_hint: Label
var _reveal := 0.0
var _line_time := 0.0
var _has_choices := false

var _inventory: PanelContainer
var _inventory_list: VBoxContainer
var _menu_layer: Control          # dim background + current menu panel
var _menu_holder: CenterContainer
var _bark_timer := 0.0

## Optional callback returning a short "Carrying: ..." line for the inventory.
var carrying_text := Callable()


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()
	_build_hud()
	_build_dialogue()
	_build_inventory()
	_build_overlays()
	set_gameplay(false)

	DialogueManager.started.connect(_on_dialogue_started)
	DialogueManager.line_shown.connect(_on_line)
	DialogueManager.ended.connect(_on_dialogue_ended)
	MissionManager.objective_changed.connect(func(_id): refresh_objectives())
	MissionManager.mission_started.connect(func(_id): refresh_objectives())
	Settings.changed.connect(_apply_settings)
	_apply_settings()


# =============================================================================
# Public API
# =============================================================================

func set_gameplay(on: bool) -> void:
	gameplay = on
	_hud.visible = on
	if not on:
		_dialogue.hide()
		_inventory.hide()
		close_menu()
		set_cinematic(false)
		set_prompt("")
		_caption.text = ""
		_title_card.hide()
	refresh_objectives()


func set_cinematic(on: bool) -> void:
	cinematic = on
	_objective_panel.visible = not on
	_skip_hint.visible = on
	if on:
		set_prompt("")
	var h := 64.0 if on else 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_letterbox_top, "custom_minimum_size:y", h, 0.6)
	tw.tween_property(_letterbox_bottom, "custom_minimum_size:y", h, 0.6)


func set_skip_progress(p: float) -> void:
	_skip_hint.text = "Hold [Space] to skip" if p <= 0.0 else "Skipping… %d%%" % int(p * 100)


func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != "" and not cinematic


func set_stamina(value: float, max_value: float) -> void:
	_stamina.max_value = max_value
	_stamina.value = value
	_stamina.visible = value < max_value - 0.5


func toast(text: String, kind: String = "info") -> void:
	if _toasts == null:
		return
	var panel := PanelContainer.new()
	panel.theme = _theme
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	if kind == "mission":
		l.add_theme_color_override("font_color", COL_ACCENT)
	panel.add_child(l)
	_toasts.add_child(panel)
	var tw := panel.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(panel.queue_free)


## Short ambient line from a passer-by. Hidden if ambient subtitles are off.
func bark(speaker_name: String, text: String) -> void:
	if not Settings.subtitles_enabled or DialogueManager.is_active():
		return
	_bark.text = "%s: %s" % [speaker_name, text]
	_bark.show()
	_bark_timer = 4.0


func caption(text: String) -> void:
	_caption.text = text
	_caption.modulate.a = 0.0
	if text != "":
		create_tween().tween_property(_caption, "modulate:a", 1.0, 0.8)


func show_title_card(title: String, subtitle: String = "") -> void:
	_title_main.text = title
	_title_sub.text = subtitle
	_title_sub.visible = subtitle != ""
	_title_card.modulate.a = 0.0
	_title_card.show()
	create_tween().tween_property(_title_card, "modulate:a", 1.0, 1.2)


func hide_title_card(duration: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(_title_card, "modulate:a", 0.0, duration)
	tw.tween_callback(_title_card.hide)


func fade_out(duration: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, duration)
	await tw.finished


func fade_in(duration: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, duration)
	await tw.finished


func set_black(on: bool) -> void:
	_fade.color.a = 1.0 if on else 0.0


func is_menu_open() -> bool:
	return _menu_layer.visible


func refresh_objectives() -> void:
	if _obj_title == null:
		return
	for c in _side_box.get_children():
		c.queue_free()
	var active := MissionManager.active_missions()
	if active.is_empty() or not gameplay:
		_objective_panel.visible = false
		return
	_objective_panel.visible = not cinematic
	var main_id: String = active[0]
	var def := MissionManager.get_definition(main_id)
	_obj_title.text = def.get("title", main_id).to_upper()
	_obj_text.text = _objective_line(main_id)
	for id in active.slice(1):
		var l := Label.new()
		l.text = "%s — %s" % [MissionManager.get_definition(id).get("title", id), _objective_line(id)]
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", COL_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(l)


## World position of the main objective's marker, or null.
func current_marker_position():
	if not Settings.objective_markers:
		return null
	var active := MissionManager.active_missions()
	if active.is_empty():
		return null
	var marker_id: String = MissionManager.current_objective(active[0]).get("marker", "")
	if marker_id == "":
		return null
	for n in get_tree().get_nodes_in_group("markers"):
		if n.get("marker_id") == marker_id and n.is_visible_in_tree():
			return n.global_position + Vector3(0, 2.3, 0)
	return null


# =============================================================================
# Input
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not gameplay:
		return
	if event.is_action_pressed("pause"):
		if is_menu_open():
			close_menu()
			get_tree().paused = false
		else:
			open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if DialogueManager.is_active() and _dialogue.visible:
		if event.is_action_pressed("advance") or event.is_action_pressed("interact"):
			_on_advance_pressed()
			get_viewport().set_input_as_handled()
			return
		for i in range(4):
			if event.is_action_pressed("choice_%d" % (i + 1)) and _has_choices:
				_pick_choice(i)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("inventory") and not cinematic:
		toggle_inventory()
		get_viewport().set_input_as_handled()


func _on_advance_pressed() -> void:
	if Time.get_ticks_msec() / 1000.0 - _line_time < 0.15:
		return
	if _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		_show_choices_if_any()
	elif not _has_choices:
		DialogueManager.advance()


func _process(delta: float) -> void:
	_update_mouse_mode()
	# Typewriter reveal.
	if _dialogue.visible and _text.visible_ratio < 1.0:
		var total: int = max(_text.get_total_character_count(), 1)
		if Settings.text_speed <= 0.0:
			_text.visible_ratio = 1.0
		else:
			_reveal += Settings.text_speed * delta
			_text.visible_ratio = min(_reveal / total, 1.0)
		if _text.visible_ratio >= 1.0:
			_show_choices_if_any()
	_continue_hint.visible = _dialogue.visible and _text.visible_ratio >= 1.0 and not _has_choices
	if _bark_timer > 0.0:
		_bark_timer -= delta
		if _bark_timer <= 0.0:
			_bark.hide()
	_marker.queue_redraw()


func _update_mouse_mode() -> void:
	var want_visible := not gameplay or is_menu_open() or get_tree().paused \
		or (DialogueManager.is_active() and _has_choices) or _inventory.visible
	var mode := Input.MOUSE_MODE_VISIBLE if want_visible else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


# =============================================================================
# Dialogue box
# =============================================================================

func _on_dialogue_started(_id: String) -> void:
	set_prompt("")
	_bark.hide()
	_dialogue.show()


func _on_dialogue_ended(_id: String) -> void:
	_dialogue.hide()
	_clear_choices()


func _on_line(d: Dictionary) -> void:
	_dialogue.show()
	_clear_choices()
	_line_time = Time.get_ticks_msec() / 1000.0
	if d["narration"]:
		_speaker.text = ""
		_speaker.hide()
		_text.text = "[i]%s[/i]" % _escape(d["text"])
	else:
		_speaker.show()
		_speaker.text = d["name"]
		_speaker.add_theme_color_override("font_color", Color(d["color"]))
		_text.text = _escape(d["text"])
	_reveal = 0.0
	_text.visible_ratio = 0.0 if Settings.text_speed > 0.0 else 1.0
	_has_choices = not d["choices"].is_empty()
	for i in d["choices"].size():
		var b := Button.new()
		b.text = "%d.  %s" % [i + 1, d["choices"][i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", Settings.subtitle_font_size() - 2)
		b.pressed.connect(_pick_choice.bind(i))
		b.hide()
		_choices.add_child(b)
	if _text.visible_ratio >= 1.0:
		_show_choices_if_any()


func _show_choices_if_any() -> void:
	var first := true
	for b in _choices.get_children():
		if not b.visible:
			b.show()
			if first:
				b.grab_focus()
				first = false


func _pick_choice(i: int) -> void:
	if _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		_show_choices_if_any()
		return
	_has_choices = false
	DialogueManager.choose(i)


func _clear_choices() -> void:
	_has_choices = false
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()


func _escape(t: String) -> String:
	return t.replace("[", "[lb]")


# =============================================================================
# Inventory
# =============================================================================

func toggle_inventory() -> void:
	if _inventory.visible:
		_inventory.hide()
		return
	for c in _inventory_list.get_children():
		c.queue_free()
	if carrying_text.is_valid():
		var carrying: String = carrying_text.call()
		if carrying != "":
			_inventory_list.add_child(_label(carrying, 18, COL_ACCENT))
	if GameState.inventory.is_empty():
		_inventory_list.add_child(_label("You are carrying nothing yet.", 18, COL_DIM))
	for id in GameState.inventory:
		var info: Dictionary = GameState.items.get(id, {})
		_inventory_list.add_child(_label("%s  ×%d" % [GameState.item_name(id), GameState.item_count(id)], 20, COL_TEXT))
		if info.has("description"):
			var d := _label(info["description"], 16, COL_DIM)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_inventory_list.add_child(d)
	_inventory.show()


# =============================================================================
# Menus
# =============================================================================

func open_pause_menu() -> void:
	_inventory.hide()
	get_tree().paused = true
	var can_save := not GameState.is_locked()
	var box := _menu_panel("Paused")
	box.add_child(_button("Resume", func(): close_menu(); get_tree().paused = false))
	var save_btn := _button("Save Game", func(): open_slots("save", open_pause_menu))
	save_btn.disabled = not can_save
	if not can_save:
		save_btn.tooltip_text = "You can save once the current scene or conversation ends."
	box.add_child(save_btn)
	box.add_child(_button("Load Game", func(): open_slots("load", open_pause_menu)))
	box.add_child(_button("Settings", func(): open_settings(open_pause_menu)))
	box.add_child(_button("Controls", func(): open_controls(open_pause_menu)))
	box.add_child(_button("Quit to Title", func(): close_menu(); Router.go_to_title()))
	_show_menu(box)


func open_controls(on_back: Callable) -> void:
	var box := _menu_panel("Controls")
	var rows := [
		["Move", "W A S D / Left stick"], ["Look", "Mouse / Right stick"],
		["Sprint", "Shift / L3 (uses stamina)"], ["Interact / talk", "E / A"],
		["Continue dialogue", "Space, Enter or E / A"], ["Choose reply", "1–4 or click"],
		["Inventory", "Tab or I / Y"], ["Pause", "Esc / Start"],
		["Skip cinematic", "Hold Space"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	for r in rows:
		grid.add_child(_label(r[0], 18, COL_DIM))
		grid.add_child(_label(r[1], 18, COL_TEXT))
	box.add_child(grid)
	box.add_child(_button("Back", on_back))
	_show_menu(box)


func open_settings(on_back: Callable) -> void:
	var box := _menu_panel("Settings")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)

	grid.add_child(_label("Subtitle & dialogue size", 18, COL_TEXT))
	grid.add_child(_options(["small", "medium", "large"], Settings.subtitle_size,
		func(v): Settings.set_value("subtitle_size", v)))

	grid.add_child(_label("Text speed", 18, COL_TEXT))
	var speeds := {"Slow": 25.0, "Normal": 45.0, "Fast": 90.0, "Instant": 0.0}
	var current_speed := "Normal"
	for k in speeds:
		if is_equal_approx(speeds[k], Settings.text_speed):
			current_speed = k
	grid.add_child(_options(speeds.keys(), current_speed, func(v): Settings.set_value("text_speed", speeds[v])))

	grid.add_child(_label("Story intensity", 18, COL_TEXT))
	grid.add_child(_options(["full", "reduced"], Settings.intensity,
		func(v): Settings.set_value("intensity", v)))

	grid.add_child(_label("Reduced screen shake", 18, COL_TEXT))
	grid.add_child(_check(Settings.reduced_shake, func(v): Settings.set_value("reduced_shake", v)))

	grid.add_child(_label("Ambient chatter subtitles", 18, COL_TEXT))
	grid.add_child(_check(Settings.subtitles_enabled, func(v): Settings.set_value("subtitles_enabled", v)))

	grid.add_child(_label("Objective markers", 18, COL_TEXT))
	grid.add_child(_check(Settings.objective_markers, func(v): Settings.set_value("objective_markers", v)))

	grid.add_child(_label("Mouse sensitivity", 18, COL_TEXT))
	grid.add_child(_slider(0.05, 1.0, Settings.mouse_sensitivity, func(v): Settings.set_value("mouse_sensitivity", v)))

	grid.add_child(_label("Invert vertical look", 18, COL_TEXT))
	grid.add_child(_check(Settings.invert_y, func(v): Settings.set_value("invert_y", v)))

	grid.add_child(_label("Master volume", 18, COL_TEXT))
	grid.add_child(_slider(0.0, 1.0, Settings.master_volume, func(v): Settings.set_value("master_volume", v)))

	box.add_child(grid)
	var note := _label("Reduced intensity softens descriptions of distressing events. It does not change what happens in the story.", 15, COL_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 520
	box.add_child(note)
	box.add_child(_button("Back", on_back))
	_show_menu(box)


## mode: "save" or "load".
func open_slots(mode: String, on_back: Callable) -> void:
	var box := _menu_panel("Save Game" if mode == "save" else "Load Game")
	var slots: Array = SaveManager.MANUAL_SLOTS.duplicate()
	if mode == "load":
		slots.push_front("auto")
	for slot in slots:
		var info := SaveManager.read_slot(slot)
		var label := "Autosave" if slot == "auto" else "Slot %s" % slot
		if info.is_empty():
			label += "  —  empty"
		else:
			var ch := Router.chapter_info(info.get("chapter", ""))
			label += "  —  Ch. %s %s  ·  %s" % [str(ch.get("number", "?")), ch.get("title", ""), info.get("saved_at", "")]
		var b := _button(label, func():
			if mode == "save":
				if SaveManager.save_game(slot):
					toast("Game saved.")
				open_slots(mode, on_back)
			else:
				close_menu()
				get_tree().paused = false
				if not SaveManager.load_game(slot):
					toast("Could not load that save.")
		)
		b.disabled = mode == "load" and info.is_empty()
		box.add_child(b)
	box.add_child(_button("Back", on_back))
	_show_menu(box)


## A simple message panel with a single button.
func open_message(title: String, body: String, on_back: Callable, button_text := "Back") -> void:
	var box := _menu_panel(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var l := _label(body, 18, COL_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 650
	scroll.add_child(l)
	box.add_child(scroll)
	box.add_child(_button(button_text, on_back))
	_show_menu(box)


func close_menu() -> void:
	if _menu_holder == null:
		return
	for c in _menu_holder.get_children():
		c.queue_free()
	_menu_layer.hide()


func _show_menu(panel_box: VBoxContainer) -> void:
	for c in _menu_holder.get_children():
		_menu_holder.remove_child(c)
		c.queue_free()
	_menu_holder.add_child(panel_box.get_parent())
	_menu_layer.show()
	for c in panel_box.get_children():
		if c is Button and not c.disabled:
			c.grab_focus()
			break


func _menu_panel(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme = _theme
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 420
	panel.add_child(box)
	var t := _label(title, 30, COL_ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(HSeparator.new())
	return box


# =============================================================================
# Construction helpers
# =============================================================================

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _options(values: Array, current: String, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for v in values:
		o.add_item(String(v).capitalize())
	o.selected = max(values.find(current), 0)
	o.item_selected.connect(func(i): cb.call(values[i]))
	return o


func _check(value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(cb)
	return c


func _slider(lo: float, hi: float, value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.custom_minimum_size.x = 220
	s.value_changed.connect(cb)
	return s


func _objective_line(id: String) -> String:
	var obj := MissionManager.current_objective(id)
	var text: String = obj.get("text", "")
	var count := int(obj.get("count", 1))
	if count > 1:
		text += "  (%d/%d)" % [MissionManager.current_progress(id), count]
	return text


func _apply_settings() -> void:
	var size := Settings.subtitle_font_size()
	_text.add_theme_font_size_override("normal_font_size", size)
	_text.add_theme_font_size_override("italics_font_size", size)
	_speaker.add_theme_font_size_override("font_size", size - 2)
	_caption.add_theme_font_size_override("font_size", size + 2)
	_bark.add_theme_font_size_override("font_size", size - 4)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = COL_PANEL
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(18)
	panel.border_color = Color(COL_ACCENT, 0.25)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.05)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color(COL_ACCENT, 0.22)
	var focus := normal.duplicate()
	focus.bg_color = Color(COL_ACCENT, 0.12)
	focus.border_color = COL_ACCENT
	focus.set_border_width_all(1)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(1, 1, 1, 0.02)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, hover)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, COL_TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(COL_TEXT, 0.35))
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_color", "CheckButton", COL_TEXT)
	return t


func _full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_hud() -> void:
	_hud = Control.new()
	_hud.theme = _theme
	_full_rect(_hud)
	add_child(_hud)

	# Objectives, top-left.
	_objective_panel = PanelContainer.new()
	_objective_panel.position = Vector2(24, 24)
	_objective_panel.custom_minimum_size = Vector2(340, 0)
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ob := VBoxContainer.new()
	_obj_title = _label("", 14, COL_ACCENT)
	_obj_text = _label("", 19, COL_TEXT)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_text.custom_minimum_size.x = 320
	_side_box = VBoxContainer.new()
	ob.add_child(_obj_title)
	ob.add_child(_obj_text)
	ob.add_child(_side_box)
	_objective_panel.add_child(ob)
	_hud.add_child(_objective_panel)

	# Toasts, top-right.
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_toasts.offset_left = -420
	_toasts.offset_right = -24
	_toasts.offset_top = 24
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_toasts)

	# Objective marker (custom drawn).
	_marker = MarkerOverlay.new()
	_full_rect(_marker)
	_hud.add_child(_marker)

	# Prompt + stamina, bottom-centre.
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -200
	bottom.offset_right = 200
	bottom.offset_top = -150
	bottom.offset_bottom = -40
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt = _label("", 20, COL_TEXT)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	_stamina = ProgressBar.new()
	_stamina.show_percentage = false
	_stamina.custom_minimum_size = Vector2(220, 8)
	_stamina.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c9b98f")
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(4)
	_stamina.add_theme_stylebox_override("fill", fill)
	_stamina.add_theme_stylebox_override("background", bg)
	_stamina.hide()
	bottom.add_child(_prompt)
	bottom.add_child(_stamina)
	_hud.add_child(bottom)

	# Ambient subtitles, above the dialogue area.
	_bark = _label("", 22, COL_TEXT)
	_bark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bark.offset_left = -500
	_bark.offset_right = 500
	_bark.offset_top = -230
	_bark.offset_bottom = -170
	_bark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark.add_theme_color_override("font_outline_color", Color.BLACK)
	_bark.add_theme_constant_override("outline_size", 6)
	_bark.hide()
	_hud.add_child(_bark)


func _build_dialogue() -> void:
	_dialogue = PanelContainer.new()
	_dialogue.theme = _theme
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue.offset_left = -480
	_dialogue.offset_right = 480
	_dialogue.offset_top = -230
	_dialogue.offset_bottom = -28
	_dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_speaker = _label("", 24, COL_ACCENT)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(900, 40)
	_text.add_theme_color_override("default_color", COL_TEXT)
	_choices = VBoxContainer.new()
	_continue_hint = _label("Space ▸", 14, COL_DIM)
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_speaker)
	v.add_child(_text)
	v.add_child(_choices)
	v.add_child(_continue_hint)
	_dialogue.add_child(v)
	_dialogue.hide()
	add_child(_dialogue)


func _build_inventory() -> void:
	_inventory = PanelContainer.new()
	_inventory.theme = _theme
	_inventory.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_inventory.offset_left = -420
	_inventory.offset_right = -24
	_inventory.offset_top = -180
	_inventory.offset_bottom = 180
	var v := VBoxContainer.new()
	v.add_child(_label("INVENTORY", 16, COL_ACCENT))
	v.add_child(HSeparator.new())
	_inventory_list = VBoxContainer.new()
	v.add_child(_inventory_list)
	v.add_child(_label("Tab to close", 13, COL_DIM))
	_inventory.add_child(v)
	_inventory.hide()
	add_child(_inventory)


func _build_overlays() -> void:
	# Letterbox bars.
	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color.BLACK
	_letterbox_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_top)
	_letterbox_bottom = ColorRect.new()
	_letterbox_bottom.color = Color.BLACK
	_letterbox_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_letterbox_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_bottom)

	# Fade to black (above the world, below captions).
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_full_rect(_fade)
	add_child(_fade)

	# Cinematic captions.
	_caption = _label("", 28, COL_TEXT)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_caption.offset_left = -520
	_caption.offset_right = 520
	_caption.offset_top = -80
	_caption.offset_bottom = 80
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	# Title card.
	_title_card = VBoxContainer.new()
	_title_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title_card.offset_left = -600
	_title_card.offset_right = 600
	_title_card.offset_top = -80
	_title_card.offset_bottom = 80
	_title_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_main = _label("", 52, COL_TEXT)
	_title_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_sub = _label("", 22, COL_ACCENT)
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_card.add_child(_title_main)
	_title_card.add_child(_title_sub)
	_title_card.hide()
	add_child(_title_card)

	_skip_hint = _label("Hold [Space] to skip", 14, COL_DIM)
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -260
	_skip_hint.offset_top = -48
	_skip_hint.offset_right = -24
	_skip_hint.offset_bottom = -20
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.hide()
	add_child(_skip_hint)

	# Menus (pause, settings, slots) sit on top of everything.
	_menu_layer = Control.new()
	_menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(dim)
	_menu_holder = CenterContainer.new()
	_menu_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(_menu_holder)
	_menu_layer.hide()
	add_child(_menu_layer)


## Draws a small diamond over the current objective's world position,
## clamped to the screen edge when it is off-screen.
class MarkerOverlay extends Control:
	func _draw() -> void:
		if not UI.gameplay or UI.cinematic or DialogueManager.is_active():
			return
		var pos = UI.current_marker_position()
		var cam := get_viewport().get_camera_3d()
		if pos == null or cam == null:
			return
		var screen := get_viewport_rect().size
		var p: Vector2
		var behind := cam.is_position_behind(pos)
		p = cam.unproject_position(pos)
		if behind:
			p = screen - p
			p.y = screen.y - 60
		var margin := 40.0
		p.x = clamp(p.x, margin, screen.x - margin)
		p.y = clamp(p.y, margin, screen.y - margin)
		var s := 9.0
		var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
		draw_colored_polygon(pts, Color("d9a441"))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.5)
		var dist := int(cam.global_position.distance_to(pos))
		draw_string(get_theme_default_font(), p + Vector2(-14, 26), "%d m" % dist,
			HORIZONTAL_ALIGNMENT_CENTER, 28, 14, Color("efe9dd"))
