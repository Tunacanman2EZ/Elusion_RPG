# testrunner_4.gd - part 4 of the suite (testrunner.gd says how it is
# split): 36 tests, _test_windows_fit_a_thumb to _test_the_healer_aura.
extends "res://src/tools/testrunner_3.gd"


func _test_windows_fit_a_thumb() -> void:
	section("A WINDOW UNDER A THUMB - its × and its edges a finger can hit (0.56.2)")
	# ---- where the ×'s pad goes -------------------------------------------------------
	var button := Rect2(100, 10, 28, 28)
	var free: Rect2 = PanelWindow.close_pad_rect(button, 60.0, -INF, 80.0)
	check("the × answers a thumb-sized square around it, moved up so it stops at the header's bottom",
		free == Rect2(74, -20, 80, 80) and free.encloses(button), free)
	var walled: Rect2 = PanelWindow.close_pad_rect(button, 60.0, 90.0, 80.0)
	check("  and right, clear of another button in the header",
		walled == Rect2(90, -20, 80, 80) and walled.encloses(button), walled)
	check("  never smaller than the × itself",
		PanelWindow.close_pad_rect(button, 60.0, -INF, 10.0) == button)

	# ---- every window has a × to find, by its scene -----------------------------------------
	var without: Array = []
	for entry in WINDOW_PANELS:
		var text: String = FileAccess.get_file_as_string(entry[1])
		var found := false
		for header_path in PanelWindow.HEADER_PATHS:
			var rule := RegEx.create_from_string(
				"\\[node name=\"[^\"]*close[^\"]*\" type=\"Button\" parent=\"" + header_path)
			if rule.search(text) != null:
				found = true
		if not found:
			without.append(entry[2])
	check("every window has a × in its header for the pad to press", without.is_empty(), without)

	# ---- a window, as a phone draws it ---------------------------------------------------------
	TouchControls.set_active(false)
	PanelWindow.pixel_ratio_for_test = 2.0
	var options: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(options)
	await get_tree().process_frame
	var dressed: PanelWindow = options.get("_window") as PanelWindow
	options.open()
	await get_tree().process_frame
	await get_tree().process_frame
	options.global_position = Vector2(200, 100)
	var grip_right: Control = options.get_node("gripright") as Control
	var grip_left: Control = options.get_node("gripleft") as Control
	var grip_bottom: Control = options.get_node("gripbottom") as Control
	var grip_corner: Control = options.get_node("gripbottomright") as Control
	var grip_top: Control = options.get_node("griptop") as Control
	var mouse_grips: Array = [grip_left.offset_left, grip_right.offset_right, grip_bottom.offset_bottom,
		grip_corner.offset_right, grip_top.offset_top]
	check("with a mouse, the × has no pad and the grips sit on the edge",
		dressed != null and dressed.close_pad() == null and mouse_grips == [0.0, 0.0, 0.0, 0.0, 0.0], mouse_grips)
	TouchControls.set_active(true)
	await get_tree().process_frame
	var units: float = dressed.thumb_units() if dressed != null else 0.0
	var pad: Control = dressed.close_pad() if dressed != null else null
	var close_at: Rect2 = dressed.close_button.get_global_rect() if dressed != null else Rect2()
	var header_at: Rect2 = dressed.header.get_global_rect() if dressed != null else Rect2()
	var side: float = PanelWindow.THUMB_CLOSE * units
	check("on a touch screen the × answers a square THUMB_CLOSE CSS pixels across, over the × and no lower than the header",
		units > 1.2 and pad != null and pad.visible and pad.get_global_rect().size.is_equal_approx(Vector2(side, side))
		and pad.get_global_rect().encloses(close_at) and pad.get_global_rect().end.y <= header_at.end.y + 0.01,
		[units, str(pad.get_global_rect()) if pad != null else "no pad", close_at, header_at])
	var reach: float = PanelWindow.THUMB_GRIP * units
	check("  and the grips reach THUMB_GRIP CSS pixels out past the edge, and no further in",
		is_equal_approx(grip_left.offset_left, -reach) and is_equal_approx(grip_right.offset_right, reach)
		and is_equal_approx(grip_bottom.offset_bottom, reach) and is_equal_approx(grip_corner.offset_right, reach)
		and is_equal_approx(grip_corner.offset_bottom, reach)
		and grip_left.offset_right == PanelWindow.GRIP and grip_right.offset_left == -PanelWindow.GRIP
		and grip_bottom.offset_top == -PanelWindow.GRIP, [reach, grip_left.offset_left, grip_right.offset_right])
	check("  not the top, where the × reaches out, and the right edge only below the header",
		grip_top.offset_top == 0.0 and grip_right.offset_top >= header_at.end.y - options.global_position.y - 0.01,
		[grip_top.offset_top, grip_right.offset_top])
	# A PRESS AND A LET-GO ABOVE THE WINDOW, inside the pad: pushed into the
	# viewport, so the engine's own hit test is what finds the pad - and marked
	# as the copy Godot makes of a finger (DEVICE_ID_EMULATION), or TouchControls
	# hears a real mouse and puts the window back to a mouse's sizes first.
	var viewport: Viewport = get_viewport()
	var above: Vector2 = Vector2(close_at.get_center().x, options.global_position.y - 4.0)
	var on_screen: Transform2D = options.get_global_transform_with_canvas() * options.get_global_transform().affine_inverse()
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.device = InputEvent.DEVICE_ID_EMULATION
		click.position = on_screen * above
		click.global_position = click.position
		viewport.push_input(click, true)
		await get_tree().process_frame
	check("  a thumb just above the window's edge, over the ×, closes it",
		above.y < options.global_position.y and not options.visible, [above, options.visible])
	TouchControls.set_active(false)
	await get_tree().process_frame
	var back: Array = [grip_left.offset_left, grip_right.offset_right, grip_bottom.offset_bottom,
		grip_corner.offset_right, grip_right.offset_top]
	check("  and with a mouse again, a mouse's sizes",
		back == [0.0, 0.0, 0.0, 0.0, PanelWindow.CORNER] and (pad == null or not pad.visible), back)
	PanelWindow.pixel_ratio_for_test = 0.0
	options.queue_free()
	await get_tree().process_frame


func _test_a_phone_stays_cool_and_unburnt() -> void:
	section("SCREEN REST, PROJECTILE BRIGHTNESS, AND OPTIONS ON THE WELCOME (0.55.0)")
	const SettingsScript := preload("res://src/systems/settings.gd")

	# ---- the screen rests -------------------------------------------------------------
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	var finger := InputEventScreenTouch.new()
	finger.pressed = true
	var slid := InputEventScreenDrag.new()
	var still_mouse := InputEventMouseMotion.new()
	var moved_mouse := InputEventMouseMotion.new()
	moved_mouse.relative = Vector2(3, 0)
	var resting_stick := InputEventJoypadMotion.new()
	resting_stick.axis_value = 0.1
	check("a person is a key, a touch, a slide or a mouse that moved - not a mouse that did not, nor a stick at rest",
		SettingsScript.is_a_person(key) and SettingsScript.is_a_person(finger) and SettingsScript.is_a_person(slid)
		and SettingsScript.is_a_person(moved_mouse) and not SettingsScript.is_a_person(still_mouse)
		and not SettingsScript.is_a_person(resting_stick))
	check("  the screen rests after %d seconds with nobody, and never with it switched off" % roundi(SettingsScript.REST_AFTER),
		not SettingsScript.rest_due(SettingsScript.REST_AFTER - 1.0, true) and SettingsScript.rest_due(SettingsScript.REST_AFTER, true)
		and not SettingsScript.rest_due(SettingsScript.REST_AFTER * 5.0, false) and Settings.DEFAULTS.get("screen_rest") == true)
	check("  resting, it draws what a window in the background does: %d a second, or less if capped lower" % SettingsScript.BACKGROUND_FPS,
		SettingsScript.fps_cap_for(0, true, true, 0.0, false, false, true) == SettingsScript.BACKGROUND_FPS
		and SettingsScript.fps_cap_for(0, true, true, 0.0, true, true, true) == SettingsScript.BACKGROUND_FPS
		and SettingsScript.fps_cap_for(10, true, false, 0.0, false, false, true) == 10
		and SettingsScript.fps_cap_for(0, true, true, 0.0, false, true, false) == SettingsScript.PHONE_FPS)
	check("  and the veil is REST_DIM dark, or darker if the brightness asked for it",
		is_equal_approx(SettingsScript.veil_alpha(1.0, true), SettingsScript.REST_DIM)
		and is_equal_approx(SettingsScript.veil_alpha(0.5, false), 0.5)
		and is_equal_approx(SettingsScript.veil_alpha(1.0, false), 0.0) and SettingsScript.REST_DIM >= 0.7)
	var kept_rest: bool = bool(Settings.get_value("screen_rest"))
	Settings.set_value("screen_rest", true)
	var now: int = Time.get_ticks_msec()
	Settings.set("_last_input_msec", now - int(SettingsScript.REST_AFTER * 1000.0) - 1000)
	Settings.set("_last_rest_check_msec", now - 1000)
	Settings.check_rest()
	var rested: bool = Settings.is_resting()
	var rest_fps: int = Engine.max_fps
	var veil: ColorRect = Settings.get("_dimmer") as ColorRect
	var words: Label = Settings.get("_rest_words") as Label
	var veil_up: bool = veil != null and (veil.get_parent() as CanvasLayer).visible
	var words_up: bool = words != null and words.visible and words.text == SettingsScript.REST_WORDS
	var room: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var words_on_screen: bool = words != null and room.encloses(Rect2(words.position, words.size))
	var first_spot: Vector2 = words.position if words != null else Vector2.ZERO
	Settings.set("_rest_moved_msec", now - int(SettingsScript.REST_WORDS_MOVE * 1000.0) - 1000)
	Settings.set("_last_rest_check_msec", Time.get_ticks_msec() - 1000)
	Settings.check_rest()
	var moved_at: int = int(Settings.get("_rest_moved_msec"))
	check("left %d seconds, the screen rests: the veil comes down, the frames drop, and it says how to wake it" % roundi(SettingsScript.REST_AFTER),
		rested and rest_fps == SettingsScript.BACKGROUND_FPS and veil_up and words_up and words_on_screen,
		[rested, rest_fps, veil_up, words_up, words_on_screen])
	check("  its words move every %d seconds - words that never move are the one thing that could burn in" % roundi(SettingsScript.REST_WORDS_MOVE),
		moved_at > now - 500, [first_spot, moved_at, now])
	Settings._input(finger)
	var woke: bool = not Settings.is_resting()
	var veil_gone: bool = veil != null and (is_equal_approx(float(Settings.get_value("brightness")), 1.0) == not (veil.get_parent() as CanvasLayer).visible)
	var words_gone: bool = words != null and not words.visible
	check("  one touch wakes it at once: the veil gone, the words gone, the frames back",
		woke and veil_gone and words_gone and Engine.max_fps != SettingsScript.BACKGROUND_FPS,
		[woke, veil_gone, words_gone, Engine.max_fps])
	Settings.set("_last_input_msec", Time.get_ticks_msec() - int(SettingsScript.REST_AFTER * 4000.0))
	Settings.set("_last_rest_check_msec", Time.get_ticks_msec() - int(SettingsScript.REST_AFTER * 4000.0))
	Settings.check_rest()
	check("  a phone coming back from another app is not idle - the game was stopped, not left",
		not Settings.is_resting())
	Settings.set_value("screen_rest", false)
	Settings.set("_last_input_msec", Time.get_ticks_msec() - int(SettingsScript.REST_AFTER * 2000.0))
	Settings.set("_last_rest_check_msec", Time.get_ticks_msec() - 1000)
	Settings.check_rest()
	check("  and switched off in Options, it never rests", not Settings.is_resting())
	Settings.set_value("screen_rest", kept_rest)
	Settings.note_input()

	# ---- projectiles as bright as asked ------------------------------------------------
	var kept_glow: float = float(Settings.get_value("projectile_brightness"))
	Settings.set_value("projectile_brightness", 0.05)
	check("projectile brightness is 100%% as drawn, down to %d%%" % roundi(SettingsScript.PROJECTILE_MIN * 100.0),
		Settings.DEFAULTS.get("projectile_brightness") == 1.0
		and is_equal_approx(float(Settings.get_value("projectile_brightness")), SettingsScript.PROJECTILE_MIN))
	var plain_arrow: Node2D = (load("res://scene/projectiles/arrow.tscn") as PackedScene).instantiate() as Node2D
	var ice_arrow: Node2D = (load("res://scene/projectiles/icearrow.tscn") as PackedScene).instantiate() as Node2D
	var not_one := Sprite2D.new()
	var lob := Node2D.new()
	lob.set_script(load("res://src/world/bulletlob.gd"))
	check("  a projectile is anything the game's projectile scripts drive, and the large slime's lob - not any sprite",
		SettingsScript.is_projectile(plain_arrow) and SettingsScript.is_projectile(ice_arrow)
		and SettingsScript.is_projectile(lob) and not SettingsScript.is_projectile(not_one))
	not_one.free()
	lob.free()
	Settings.set_value("projectile_brightness", 0.5)
	var at := Node2D.new()
	at.position = Vector2(-5000, -5000)
	add_child(at)
	at.add_child(plain_arrow)
	at.add_child(ice_arrow)
	await get_tree().process_frame
	var ice_sprite: CanvasItem = ice_arrow.get_node_or_null("sprite2d") as CanvasItem
	var ice_mat: ShaderMaterial = ice_sprite.material as ShaderMaterial if ice_sprite != null else null
	# Never set is the shader's own 1.0.
	var glow_of := func(mat: ShaderMaterial) -> float:
		var set_to: Variant = mat.get_shader_parameter("brightness") if mat != null else null
		return 1.0 if set_to == null else float(set_to)
	var half_arrow: bool = is_equal_approx(plain_arrow.modulate.r, 0.5) and is_equal_approx(plain_arrow.modulate.a, 1.0)
	var half_ice: bool = ice_mat != null and is_equal_approx(glow_of.call(ice_mat), 0.5)
	check("a shot fired at 50% is drawn at half: its own modulate, which every plain sprite under it takes",
		half_arrow, plain_arrow.modulate)
	check("  and a shot drawn with the element shader, which no modulate reaches, has the shader's own brightness",
		half_ice, glow_of.call(ice_mat))
	Settings.set_value("projectile_brightness", 0.8)
	var followed: bool = (is_equal_approx(plain_arrow.modulate.r, 0.8)
		and ice_mat != null and is_equal_approx(glow_of.call(ice_mat), 0.8))
	Settings.set_value("projectile_brightness", 1.0)
	var restored: bool = (is_equal_approx(plain_arrow.modulate.r, 1.0)
		and ice_mat != null and is_equal_approx(glow_of.call(ice_mat), 1.0))
	check("  the slider moved, every shot in the air follows it - and at 100% it is as drawn again", followed and restored,
		[plain_arrow.modulate, glow_of.call(ice_mat)])
	at.queue_free()
	var field := BulletField.new()
	field.capacity = 16
	Settings.set_value("projectile_brightness", 0.6)
	add_child(field)
	var field_mat: ShaderMaterial = field.get("_shading") as ShaderMaterial
	var field_at_start: bool = field_mat != null and is_equal_approx(glow_of.call(field_mat), 0.6)
	Settings.set_value("projectile_brightness", 0.9)
	var field_follows: bool = field_mat != null and is_equal_approx(glow_of.call(field_mat), 0.9)
	field.queue_free()
	check("  the bullet field's bullets too, made at it and following it", field_at_start and field_follows,
		[field_at_start, field_follows])
	# A SHOT GONE BEFORE ITS DIMMING CAME (0.56.1): one that hit on the frame
	# it was made. The dimming is deferred to after its _ready(), and a freed
	# node handed to it was an engine error for every one - 19 in a run.
	var brief_errors := EngineErrorCounter.new()
	OS.add_logger(brief_errors)
	var brief: Node2D = (load("res://scene/projectiles/arrow.tscn") as PackedScene).instantiate() as Node2D
	brief.position = Vector2(-5000, -5000)
	add_child(brief)
	brief.free()
	await get_tree().process_frame
	await get_tree().process_frame
	OS.remove_logger(brief_errors)
	check("  a shot gone before its dimming came is passed over, with no engine error",
		brief_errors.count == 0, "%d: %s" % [brief_errors.count, "; ".join(brief_errors.where)])
	var shaders_obey: Array = []
	for path in ["res://src/shared/element_recolour.gdshader", "res://src/shared/hearth_warm.gdshader"]:
		var code: String = FileAccess.get_file_as_string(path)
		if not (code.contains("uniform float brightness : hint_range(0.0, 1.0) = 1.0;") and code.contains("COLOR.rgb *= brightness;")):
			shaders_obey.append(path)
	check("  each shader a projectile is drawn with has the brightness, at 1.0 for everything else drawn with it",
		shaders_obey.is_empty() and BulletField.SHADER_CODE.contains("* brightness"), shaders_obey)
	Settings.set_value("projectile_brightness", kept_glow)
	await get_tree().process_frame

	# ---- in Options ------------------------------------------------------------------------
	var options: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	add_child(options)
	await get_tree().process_frame
	options.refresh()
	var glow_slider: HSlider = options.get_node_or_null("%projectilebrightness") as HSlider
	var rest_switch: CheckButton = options.get_node_or_null("%screenrest") as CheckButton
	var power_words: Label = options.get_node_or_null("%batteryhint") as Label
	check("Options has a Projectile brightness slider over the setting's range, and a Rest the screen switch that says what it does",
		glow_slider != null and is_equal_approx(glow_slider.min_value, SettingsScript.PROJECTILE_MIN)
		and is_equal_approx(glow_slider.max_value, 1.0) and rest_switch != null
		and rest_switch.button_pressed == bool(Settings.get_value("screen_rest"))
		and power_words != null and power_words.text == SettingsScript.power_hint() and power_words.text.contains("2 minutes"),
		[glow_slider, rest_switch, power_words.text if power_words != null else ""])
	options.queue_free()
	await get_tree().process_frame

	# ---- the welcome says try Options -----------------------------------------------------------
	check("the welcome says to take a minute in Options first - brightness, attacks, the battery saver and the rest",
		ControlsPanel.welcome_words(false).contains("the button below, or Esc.") and ControlsPanel.welcome_words(true).contains("or Menu, then Options.")
		and ControlsPanel.welcome_words(false).contains("battery saver") and ControlsPanel.welcome_words(false).contains("how bright attacks are")
		and ControlsPanel.welcome_words(false).contains("Field"))
	var was_seen_path: String = ControlsPanel.seen_path
	ControlsPanel.seen_path = "user://_suite_seen_options.cfg"
	var card: ControlsPanel = (load("res://scene/ui/controls/controlspanel.tscn") as PackedScene).instantiate() as ControlsPanel
	add_child(card)
	await get_tree().process_frame
	var asked: Array = []
	card.options_requested.connect(func(): asked.append(true))
	TouchControls.set_active(true)
	card.open_welcome()
	await get_tree().process_frame
	var touch_card: Vector2 = card.size
	TouchControls.set_active(false)
	card.open_welcome()
	await get_tree().process_frame
	var mouse_card: Vector2 = card.size
	var screen: Vector2 = Vector2(1280, 720)
	check("  and the card still fits the screen, with a keyboard or a touch screen - its lines are broken by hand",
		mouse_card.x <= screen.x and mouse_card.y <= screen.y and touch_card.x <= screen.x and touch_card.y <= screen.y
		and Array(ControlsPanel.welcome_words(true).split("\n")).all(func(line: String) -> bool: return line.length() <= 76),
		[mouse_card, touch_card])
	var both_buttons: bool = card.options_button != null and card.options_button.visible and card.got_it_button.visible
	card.options_button.pressed.emit()
	check("  with an Open Options button beside Got it, which closes the card and asks for Options",
		both_buttons and not card.visible and asked.size() == 1, [both_buttons, card.visible, asked.size()])
	card.open_controls()
	check("  and neither button on the plain Controls card", not card.options_button.visible and not card.got_it_button.visible)
	card.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ControlsPanel.seen_path))
	ControlsPanel.seen_path = was_seen_path
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	check("  the HUD opens Options for it - opened, not toggled shut",
		_func_body(hud_code, "func _ensure_controls_panel(").contains("options_requested.connect(open_options)")
		and _func_body(hud_code, "func open_options(").contains("not options_screen.visible"))
	await get_tree().process_frame


# =============================================================================
# SAVED BEFORE YOU LEAVE (0.56.0)
# =============================================================================
# Found looking for why the owner's mage pet was not out a session later: a
# summon saved nothing, a door loaded the next area's player from a slot nobody
# had written, a closed tab compared that same stale slot, and the server's "you
# do not hold that pet" was thrown away. A failed or slow save could also land
# on the next account, and skill XP on the next character.

func _test_what_you_do_is_saved_before_you_leave() -> void:
	section("SAVED BEFORE YOU LEAVE - a summon, a door, a closed tab, a pet you no longer hold (0.56.0)")
	var player_code := _code_src("res://src/characters/player.gd")
	check("summoning a pet, or putting it away, saves it there and then",
		_func_body(player_code, "func summon_pet(").contains("CharacterData.save_character_state(self)")
		and _func_body(player_code, "func dismiss_pet(").contains("CharacterData.save_character_state(self)"))
	var door_code := _code_src("res://src/systems/scenetransition.gd")
	var door: String = _func_body(door_code, "func change_scene(")
	check("  every door captures the player before the scene goes (SceneTransition.change_scene())",
		door.find("_capture_player()") != -1 and door.find("_capture_player()") < door.find("await _fade_out()"))

	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nvar saves: int = 0\n" \
		+ "func save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\treturn true\n" \
		+ "func requests_before_leaving(_payload: Dictionary) -> Array:\n\treturn []\n"
	store_script.reload()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	var was_failed: bool = CharacterData.load_failed
	var was_index: int = CharacterData.active_character_index
	var was_slots: Array = CharacterData.character_slots.duplicate()
	var was_account: Dictionary = CharacterData.account_data.duplicate(true)
	CharacterData.storage = store_script.new()
	CharacterData.load_failed = false
	CharacterData.active_character_index = 0
	CharacterData.character_slots = [{"name": "Stand-in", "character": "warrior", "active_pet_id": ""}, null, null, null]
	var stand_script := GDScript.new()
	stand_script.source_code = "extends Node2D\nvar active_pet_id: String = \"petmage\"\nvar inventory_data: Array = []\nvar put_away: int = 0\n" \
		+ "func dismiss_pet() -> void:\n\tput_away += 1\n\tactive_pet_id = \"\"\n"
	stand_script.reload()
	var others: Array = get_tree().get_nodes_in_group("player")
	var stand := Node2D.new()
	stand.set_script(stand_script)
	stand.add_to_group("player")
	add_child(stand)
	SceneTransition._capture_player()
	var at_door: String = str(CharacterData.character_slots[0].get("active_pet_id", ""))
	stand.set("active_pet_id", "petsniper")
	CharacterData._on_page_leaving()
	var at_close: String = str(CharacterData.character_slots[0].get("active_pet_id", ""))
	check("a pet summoned a moment ago is in the save at a door, and when the tab closes",
		others.is_empty() and at_door == "petmage" and at_close == "petsniper", [others.size(), at_door, at_close])

	check("the server naming the pet in `ignored` is it refusing a pet this character does not hold",
		ServerStorage.pet_refused({"ignored": ["active_pet_id"]}) and not ServerStorage.pet_refused({"ignored": ["equipment"]})
		and not ServerStorage.pet_refused({}) and not ServerStorage.pet_refused(null))
	CharacterData.pet_not_held(0)
	check("  and the pet goes: off the slot, and put away in the world - it came back at every door",
		str(CharacterData.character_slots[0].get("active_pet_id", "x")) == "" and int(stand.get("put_away")) == 1
		and str(stand.get("active_pet_id")) == "", [CharacterData.character_slots[0].get("active_pet_id"), stand.get("put_away")])
	var ss_code := _code_src("res://src/systems/serverstorage.gd")
	check("  the save's answer is read for it now (_put_if_changed() -> heard_save())",
		_func_body(ss_code, "func _put_if_changed(").contains("heard_save(body, res.get(\"data\", {}))"))

	# ---- a true death takes the pet with the bag, unless the bank holds it ----
	var Gameover: Script = load("res://src/ui/menus/gameover.gd")
	var over: Control = Gameover.new()
	CharacterData.character_slots = [{"name": "Stand-in", "character": "warrior", "active_pet_id": "petmage",
		"inventory": [{"item_id": "petmage", "quantity": 1}], "gold": 5}, null, null, null]
	CharacterData.account_data["bank_inventory"] = []
	over._clear_carry_on_death("warrior")
	var gone_with_bag: String = str(CharacterData.character_slots[0].get("active_pet_id", "x"))
	CharacterData.character_slots = [{"name": "Stand-in", "character": "warrior", "active_pet_id": "petmage",
		"inventory": [], "gold": 5}, null, null, null]
	CharacterData.account_data["bank_inventory"] = [{"item_id": "petmage", "quantity": 1}]
	over._clear_carry_on_death("warrior")
	var kept_in_bank: String = str(CharacterData.character_slots[0].get("active_pet_id", ""))
	# THE SERVER'S ANSWER WINS (0.56.2): its respawn names the pet it left out.
	over._clear_carry_on_death("warrior", {"active_pet_id": "", "pet_lost": true})
	var server_put_away: String = str(CharacterData.character_slots[0].get("active_pet_id", "x"))
	CharacterData.character_slots = [{"name": "Stand-in", "character": "warrior", "active_pet_id": "petmage",
		"inventory": [], "gold": 5}, null, null, null]
	CharacterData.account_data["bank_inventory"] = []
	over._clear_carry_on_death("warrior", {"active_pet_id": "petmage", "pet_lost": false})
	var server_kept: String = str(CharacterData.character_slots[0].get("active_pet_id", ""))
	over.free()
	check("a true death takes the pet with the bag - and keeps it out when the bank holds it, as the server does",
		gone_with_bag == "" and kept_in_bank == "petmage", [gone_with_bag, kept_in_bank])
	check("  and what the server's respawn answers is what is kept, either way",
		server_put_away == "" and server_kept == "petmage", [server_put_away, server_kept])

	stand.queue_free()
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending
	CharacterData.load_failed = was_failed
	CharacterData.active_character_index = was_index
	CharacterData.character_slots = was_slots
	CharacterData.account_data = was_account

	# ---- a push belongs to its session ------------------------------------------------
	var push_store := ServerStorage.new()
	var kept_token: String = str(Api.token)
	Api.token = "first_session"
	push_store._pushing = true
	push_store._push_token = "first_session"
	var same: bool = not push_store.session_moved()
	Api.token = "next_account"
	var moved: bool = push_store.session_moved()
	push_store._pushing = false
	Api.token = kept_token
	check("a save still being sent after a logout stops at the next account's token - it wrote the old character into their slot",
		same and moved and _func_body(ss_code, "func _put_if_changed(").contains("if session_moved():")
		and _func_body(ss_code, "func _push(").contains("_push_token = str(Api.token)"))
	await get_tree().process_frame


# =============================================================================
# A PHONE CAN DO WHAT A MOUSE CAN (0.56.0)
# =============================================================================
# Found in a sweep of everything a touch screen cannot give: chat opened froze
# the character with no way to give the keyboard back; the stick covered the
# names of everybody on the left of the screen; the Players list opened its
# menu on a right-click only; a swipe selected chat text instead of scrolling;
# and Push to talk asked a phone to hold V.

func _test_a_phone_can_do_what_a_mouse_can() -> void:
	section("A PHONE CAN DO WHAT A MOUSE CAN - the keyboard given back, names, chat, voice (0.56.0)")
	const TouchScript := preload("res://src/systems/touchcontrols.gd")
	var kept_active: bool = TouchControls.active
	TouchControls.set_active(true)

	# ---- a thumb on the game gives the keyboard back ----------------------------------
	var box := LineEdit.new()
	add_child(box)
	box.grab_focus()
	var typing_before: bool = TouchControls.typing()
	var heard: Array = []
	var on_played := func() -> void: heard.append(true)
	TouchControls.played.connect(on_played)
	TouchControls.played_now()
	TouchControls.played.disconnect(on_played)
	check("a thumb on the game takes the keyboard from a text box, which froze the character",
		typing_before and not TouchControls.typing() and get_viewport().gui_get_focus_owner() == null and heard.size() == 1,
		[typing_before, TouchControls.typing(), heard.size()])
	box.queue_free()
	var tc_code := _code_src("res://src/systems/touchcontrols.gd")
	var pad_code := _code_src("res://src/ui/touchpad.gd")
	var all_played: bool = true
	for fn in ["func press_attack(", "func press_use(", "func press_skill(", "func toggle_sprint(", "func _unhandled_input("]:
		all_played = all_played and _func_body(tc_code, fn).contains("played_now()")
	check("  every one: Attack, Use, the skill, Run, a tap on the world, and the stick",
		all_played and _func_body(pad_code, "	func _gui_input(").contains("TouchControls.played_now()"))

	# ---- a name under the stick ------------------------------------------------------------
	var host_script := GDScript.new()
	host_script.source_code = "extends Node\nvar opened: Array = []\nfunc open_player_menu(who: String) -> void:\n\topened.append(who)\n"
	host_script.reload()
	var host := Node.new()
	host.set_script(host_script)
	host.add_to_group(&"player_menu_host")
	add_child(host)
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar display_name: String = \"Gary\"\nvar _plate: Label = null\nfunc plate() -> Label:\n\treturn _plate\n"
	body_script.reload()
	var hud := Control.new()
	hud.size = Vector2(1280, 720)
	add_child(hud)
	var pad: Control = TouchControls.attach(hud)
	await get_tree().process_frame
	var stick: Control = pad.get("stick")
	var spot_local := Vector2(120, 200)
	var spot: Vector2 = stick.get_global_transform_with_canvas() * spot_local
	var gary := Node2D.new()
	gary.set_script(body_script)
	gary.add_to_group(&"remoteplayers")
	var plate := Label.new()
	plate.text = "Gary"
	plate.size = Vector2(60, 16)
	gary.add_child(plate)
	gary.set("_plate", plate)
	add_child(gary)
	plate.global_position = spot - Vector2(30, 8)
	check("a name over a player is where it is drawn (TouchScript.plate_box())",
		TouchScript.plate_box(plate).has_point(spot) and not TouchScript.plate_box(plate).has_point(spot + Vector2(200, 0)))
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = spot_local
	press.pressed = true
	stick.call("_gui_input", press)
	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.position = spot_local
	lift.pressed = false
	stick.call("_gui_input", lift)
	var opened_by_tap: Array = (host.get("opened") as Array).duplicate()
	stick.call("_gui_input", press)
	var slid := InputEventScreenDrag.new()
	slid.index = 0
	slid.position = spot_local + Vector2(40, 0)
	stick.call("_gui_input", slid)
	lift.position = slid.position
	stick.call("_gui_input", lift)
	check("  a quick tap on the stick's half of the screen, on a name, opens their menu - the stick took every touch there",
		opened_by_tap == ["Gary"], opened_by_tap)
	check("  and a slide from it is still the stick, not a tap", (host.get("opened") as Array).size() == 1, host.get("opened"))
	gary.queue_free()
	host.queue_free()
	hud.queue_free()

	# ---- chat on a touch screen ------------------------------------------------------------
	var chat: Control = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	add_child(chat)
	var poll: Node = chat.get_node_or_null(^"ChatPoll")
	if poll is Timer:
		(poll as Timer).stop()
	chat.open()
	var awake_open: bool = chat.is_awake()
	var no_keyboard: bool = not chat.is_typing()
	var entry_box: Control = chat.get("entry") as Control
	TouchControls.played_now()
	var quiet: bool = not chat.is_awake() and chat.is_passing()
	var lets_through: bool = entry_box != null and entry_box.mouse_filter == Control.MOUSE_FILTER_IGNORE
	chat.toggle()
	var woken: bool = chat.visible and chat.is_awake() and not chat.is_passing()
	var restored: bool = entry_box != null and entry_box.mouse_filter != Control.MOUSE_FILTER_IGNORE
	chat.toggle()
	var shut: bool = not chat.visible
	check("on a touch screen chat opens awake but without the keyboard - a tap on the box types",
		awake_open and no_keyboard, [awake_open, no_keyboard])
	check("  a thumb back on the game quiets it, and quiet it lets touches through to the stick and the world",
		quiet and lets_through, [quiet, lets_through])
	check("  Chat on the bar wakes a quiet window rather than shutting it, and shuts an awake one",
		woken and restored and shut, [woken, restored, shut])
	var line := RichTextLabel.new()
	chat._suit_touch(line, true)
	var swipeable: bool = not line.selection_enabled and line.mouse_filter == Control.MOUSE_FILTER_PASS
	chat._suit_touch(line, false)
	var selectable: bool = line.selection_enabled and line.mouse_filter == Control.MOUSE_FILTER_STOP
	line.free()
	check("  a swipe scrolls the log: on a touch screen a line selects nothing and lets the drag through",
		swipeable and selectable and _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _node_for(").contains("_suit_touch(label, _on_touch())"))
	chat.queue_free()

	# ---- the Players list, Friends, voice ------------------------------------------------------
	check("the Players and Friends rows let a swipe through to their scroll (PASS, not a PanelContainer's STOP)",
		_func_body(_code_src("res://src/ui/players/playerspanel.gd"), "func _boxed(").contains("box.mouse_filter = Control.MOUSE_FILTER_PASS")
		and _func_body(_code_src("res://src/ui/friends/friendspanel.gd"), "func _add_row(").contains("frame.mouse_filter = Control.MOUSE_FILTER_PASS"))
	var panel: PartyPanel = (load("res://scene/ui/party/partypanel.tscn") as PackedScene).instantiate() as PartyPanel
	add_child(panel)
	var kept_mode: String = Voice.mode
	Voice.set_mode(Voice.MODE_PUSH)
	panel.render_voice()
	var back_to_open: bool = Voice.mode == Voice.MODE_OPEN
	var not_offered: bool = panel.voice_mode == null or (panel.voice_mode.is_item_disabled(1)
		and panel.voice_mode.get_item_text(1) == PartyPanel.PUSH_ON_TOUCH)
	TouchControls.set_active(false)
	panel.render_voice()
	var offered_again: bool = panel.voice_mode == null or not panel.voice_mode.is_item_disabled(1)
	Voice.set_mode(kept_mode)
	panel.queue_free()
	check("Push to talk is not offered on a touch screen, which has no key to hold - and a phone in it is put on Open mic",
		back_to_open and not_offered and offered_again, [back_to_open, not_offered, offered_again])

	# ---- what a mouse would hover ---------------------------------------------------------------
	check("a finger held still and lifted asks for the tooltip under it - a tap, or a slide, does not",
		TouchScript.shows_tip(TouchControls.TIP_HOLD_MSEC, 0.0) and not TouchScript.shows_tip(120, 0.0)
		and not TouchScript.shows_tip(900, TouchControls.TIP_SLIDE + 5.0))
	var holder := PanelContainer.new()
	holder.tooltip_text = "0 / 1,250 XP"
	var inner := Label.new()
	inner.text = "0 / 1,250"
	holder.add_child(inner)
	add_child(holder)
	var said: String = TouchScript.tip_of(inner, inner.get_global_transform_with_canvas() * Vector2(2, 2))
	holder.queue_free()
	check("  the tooltip is the control's own, or the nearest parent's that has one - the exact XP, a traded item's stats",
		said == "0 / 1,250 XP" and _func_body(_code_src("res://src/systems/touchcontrols.gd"), "func _input(").contains("_watch_for_tip(event)"), said)
	check("  and the Controls card says so", ControlsPanel.TOUCH_ROWS.any(func(row: Array) -> bool: return row[1] == "Hold it, then let go"))

	TouchControls.set_active(kept_active)
	await get_tree().process_frame


# =============================================================================
# THE CLIENT AND THE SERVER AGREE ABOUT ITEMS, AND FIGHTS HIT WHAT THEY AIM AT (0.56.0)
# =============================================================================
# From the same sweep: a trade edit dropped while a poll was out, a timeout read
# as "nothing happened", a potion spent with no heal, a cook's answer thrown
# away, gear dropped straight from the bank, a bin that destroyed more than it
# said; and pets, healer orbs and auto-aim spent on caged bosses and corpses.

func _test_items_agree_with_the_server() -> void:
	section("ITEMS AGREE WITH THE SERVER - no dropped edits, no silent timeouts (0.56.0)")
	const DataScript := preload("res://src/systems/characterdata.gd")
	check("a request with no answer is told apart from a refusal",
		DataScript.got_no_answer({"ok": false, "status": 0}) and not DataScript.got_no_answer({"ok": false, "status": 409})
		and not DataScript.got_no_answer({"ok": true, "status": 200}))

	# ---- the bag, purse and bank asked for again ---------------------------------------
	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nfunc save(_payload: Dictionary) -> bool:\n\treturn true\n"
	store_script.reload()
	var was_storage = CharacterData.storage
	var was_index: int = CharacterData.active_character_index
	var was_slots: Array = CharacterData.character_slots.duplicate()
	var was_account: Dictionary = CharacterData.account_data.duplicate(true)
	CharacterData.storage = store_script.new()
	CharacterData.active_character_index = 0
	CharacterData.character_slots = [{"name": "Stand-in", "character": "warrior", "gold": 5, "inventory": []}, null, null, null]
	var cells: Array = [{"item_id": "petmage", "quantity": 1}]
	for i in 29:
		cells.append(null)
	var bank_cells: Array = [{"item_id": "petsniper", "quantity": 1}]
	for i in 39:
		bank_cells.append(null)
	var asked: Array = []
	CharacterData.resync_request = func(path: String) -> Dictionary:
		asked.append(path)
		if path.begins_with("/api/character"):
			return {"ok": true, "status": 200, "data": {"slot": 0, "inventory": cells, "status": {"gold": 77}}}
		return {"ok": true, "status": 200, "data": {"bank_gold": 500, "bank_inventory": bank_cells}}
	var landed: bool = await CharacterData.resync_carry()
	var slot: Dictionary = CharacterData.character_slots[0]
	var resynced: bool = (landed and int(slot.get("gold", -1)) == 77
		and str((slot.get("inventory", []) as Array)[0].get("item_id", "")) == "petmage"
		and CharacterData.get_bank_gold() == 500 and CharacterData.bank_holds("petsniper"))
	CharacterData.resync_request = Callable()
	CharacterData.storage = was_storage
	CharacterData.active_character_index = was_index
	CharacterData.character_slots = was_slots
	CharacterData.account_data = was_account
	check("after a request that got no answer, the bag, the purse and the bank are asked for again, and drawn",
		resynced and asked == ["/api/character?slot=0", "/api/account"], [landed, asked, slot.get("gold")])
	var shop_code := _code_src("res://src/ui/shop/shopinventory.gd")
	var bank_code := _code_src("res://src/ui/bank/bankinventory.gd")
	var cd_code := _code_src("res://src/systems/characterdata.gd")
	var inv_code := _code_src("res://src/ui/inventory/inventoryscreen.gd")
	check("  a buy, a bank move, banked gold and a potion each do it - a second press was a second purchase",
		_func_body(shop_code, "func _on_buy_pressed(").contains("CharacterData.resync_carry()")
		and _func_body(bank_code, "func _handle_transfer_refusal(").contains("_resync_after_silence()")
		and _func_body(cd_code, "func _move_bank_gold(").contains("await resync_carry()")
		and _func_body(inv_code, "func _use_consumable(").contains("_container.refetch()"))

	# ---- a potion the server spent heals ------------------------------------------------
	var screen: Control = (load("res://scene/ui/inventory/inventory.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	var healer_script := GDScript.new()
	healer_script.source_code = "extends Node2D\nvar level: int = 1\nvar healed: int = 0\nfunc heal(amount: int) -> void:\n\thealed += amount\n"
	healer_script.reload()
	var drinker := Node2D.new()
	drinker.set_script(healer_script)
	add_child(drinker)
	screen.set_player(drinker)
	var potion := ItemData.new()
	potion.item_id = "suite_potion"
	potion.type = ItemData.Type.CONSUMABLE
	potion.restore_target = ItemData.RestoreTarget.HP
	potion.restore_amount = 25
	screen._restore_from(potion)
	check("a potion the server spent heals even when its stack was dragged off the key mid-request",
		int(drinker.get("healed")) == 25 and _func_body(inv_code, "func _use_consumable(").contains("_restore_from(data)"),
		drinker.get("healed"))
	screen.queue_free()
	drinker.queue_free()

	# ---- cooking, gear, the bin, trade -------------------------------------------------------
	var cook_code := _code_src("res://src/ui/cooking/cookingscreen.gd")
	var cook: String = _func_body(cook_code, "func _cook_one(")
	check("a cook's answer still reaches the bag and the skill when the panel shut mid-cook",
		cook.contains("if _firepit != firepit:") and cook.contains("_apply_inventory(quiet)") and cook.contains("_apply_skill(quiet)"))
	var bank_cell: InventorySlot = (load("res://scene/ui/inventory/inventoryslot.tscn") as PackedScene).instantiate()
	bank_cell.slot_type = InventorySlot.BANK_SLOT_TYPE
	var bag_cell: InventorySlot = (load("res://scene/ui/inventory/inventoryslot.tscn") as PackedScene).instantiate()
	check("gear goes on from the bag or a key - not straight from the bank or a loot bag, whose cell numbers mean nothing to the carry",
		not EquipmentSlot.is_carried(bank_cell) and EquipmentSlot.is_carried(bag_cell) and EquipmentSlot.is_carried(null))
	var shrimp := ItemData.new()
	shrimp.item_id = "suite_shrimp"
	var other := ItemData.new()
	other.item_id = "suite_other"
	bag_cell.stack = ItemStack.new(shrimp, 4)
	check("the bin asks again when the stack grew while its question was up - x3 named, four destroyed",
		TrashSlot.changed_since_asked(bag_cell, ItemStack.new(shrimp, 3))
		and not TrashSlot.changed_since_asked(bag_cell, ItemStack.new(shrimp, 4))
		and not TrashSlot.changed_since_asked(bag_cell, ItemStack.new(other, 3)))
	bank_cell.free()
	bag_cell.free()
	var Trade: Script = load("res://src/ui/trade/tradepanel.gd") as Script
	var trade: Control = Trade.new()
	trade.set("_busy", true)
	trade._push_offer()
	var kept_edit: bool = bool(trade.get("_offer_dirty"))
	trade.free()
	var trade_code := _code_src("res://src/ui/trade/tradepanel.gd")
	check("a trade edit made while the window was busy is kept and sent, not dropped - Accept traded the old offer",
		kept_edit and _func_body(trade_code, "func _poll(").contains("if _offer_dirty:")
		and _func_body(trade_code, "func _on_confirm_pressed(").contains("await _push_offer()"))
	await get_tree().process_frame


func _test_fights_hit_what_they_aim_at() -> void:
	section("FIGHTS HIT WHAT THEY AIM AT - pets, orbs, the aura, a quick click (0.56.0)")
	var aim_script := GDScript.new()
	aim_script.source_code = "extends Node2D\nvar ok: bool = true\nfunc can_be_aimed_at() -> bool:\n\treturn ok\n"
	aim_script.reload()
	var caged := Node2D.new()
	caged.set_script(aim_script)
	caged.set("ok", false)
	var open := Node2D.new()
	open.set_script(aim_script)
	var plain := Node2D.new()
	check("a pet shoots at nothing caged or dying - it spent a whole arena fight on a gated boss",
		not Pet.can_shoot_at(caged) and Pet.can_shoot_at(open) and Pet.can_shoot_at(plain)
		and _func_body(_code_src("res://src/pets/pet.gd"), "func _find_nearest_enemy(").contains("not can_shoot_at(enemy)"))
	caged.free()
	open.free()
	plain.free()
	var slime: Node = (load("res://scene/enemy/poisonslime.tscn") as PackedScene).instantiate()
	var aimable_alive: bool = slime.can_be_aimed_at()
	slime.set("_is_resolving", true)
	var aimable_dying: bool = slime.can_be_aimed_at()
	slime.free()
	check("  a slime dying or splitting is not aimed at either - its shapes are already off",
		aimable_alive and not aimable_dying, [aimable_alive, aimable_dying])
	var orb_code := _code_src("res://src/projectiles/turretprojectile.gd")
	check("a healer's orb looks for its enemy from where it is, on its first frame - from the world's origin it could swing off",
		not _func_body(orb_code, "func _ready(").contains("_homing_target = _find_nearest_enemy()")
		and _func_body(orb_code, "func _physics_process(").contains("_homing_target = _find_nearest_enemy()")
		and _func_body(orb_code, "func _enemy_in_reach(").contains("can_be_aimed_at"))
	var tank_code := _func_body(_code_src("res://src/characters/tank.gd"), "func _activate_aura(")
	check("the tank's aura pays its first tick on the way in - switching it off and on burned for free",
		tank_code.contains("if mana < mana_drain_cost:") and tank_code.contains("mana = clamp(mana - mana_drain_cost, 0, max_mana)"))
	var held_late: bool = true
	for path in ["res://src/projectiles/petelectricprojectile.gd", "res://src/projectiles/petfireprojectile.gd"]:
		var body: String = _func_body(_code_src(path), "func _enable_hitting_after(")
		held_late = held_late and body.contains("get_overlapping_bodies()") and body.contains("get_overlapping_areas()")
	check("a pet's orb hits what it entered in its first moments, when it could not hit yet", held_late)
	var player_code := _code_src("res://src/characters/player.gd")
	check("a click down and up inside one frame still attacks - a trackpad tap, or any click at 30 or 15 frames a second",
		_func_body(player_code, "func _unhandled_input(").contains("_left_click_came = true")
		and _func_body(player_code, "func _poll_attack_pressed(").contains("or _left_click_came"))
	var orb: Node = (load("res://scene/projectiles/magicprojectile.tscn") as PackedScene).instantiate()
	var has_life: bool = "lifetime" in orb and float(orb.get("lifetime")) > 0.0
	orb.free()
	check("an electric orb ends after its lifetime, like every other shot - aimed off the screen it flew forever",
		has_life and _func_body(_code_src("res://src/projectiles/magicprojectile.gd"), "func _ready(").contains("create_timer(lifetime)"))
	check("a death plays at its own speed, not the swing's", _func_body(player_code, "func die(").contains("sprite.speed_scale = 1.0")
		or player_code.contains("sprite.speed_scale = 1.0\n\t\t\tsprite.play(death_anim)"))
	check("a kill answered after a portal drops its bag at the player's feet in the new area, not at the old coordinates",
		_code_src("res://src/systems/combat.gd").contains("get_tree().current_scene != killed_in"))


func _test_other_players_attacks_switch() -> void:
	section("OTHER PLAYERS - drawn as their own scene sorts, and a switch for their attacks (0.40.1)")
	# The owner: "on my screen garys ring is over the character and i cannot
	# see his attacks we need a switch to allow the sight of player attacks that
	# are not their own".
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var kept: bool = bool(Settings.get_value("others_attacks"))
	var arena := Node2D.new()
	add_child(arena)
	var o := Vector2(-74000, -74000)

	# ---- sorted as their own scene sorts ----
	var tank_scene: Node2D = (load("res://scene/characters/tank.tscn") as PackedScene).instantiate() as Node2D
	var tank_sorts: bool = tank_scene.y_sort_enabled
	tank_scene.free()
	var tanky: Node2D = Remote.new()
	tanky.user_id = 641
	arena.add_child(tanky)
	tanky.set_identity({"id": 641, "name": "Gary", "cls": "tank", "lvl": 20, "v": 2})
	tanky.set_process(false)
	tanky.place(o)
	var body: Node2D = tanky.get_node_or_null(^"animatedsprite2d") as Node2D
	var fire: Node2D = tanky.get_node_or_null(^"firering") as Node2D
	var small: Node2D = tanky.get_node_or_null(^"ring") as Node2D
	check("a tank's picture y-sorts as the tank's own scene does, so its fire ring and small ring draw under it - and under everyone in the fire",
		tank_sorts and tanky.y_sort_enabled and body != null and fire != null and small != null
		and fire.position.y < body.position.y and small.position.y < body.position.y,
		[tanky.y_sort_enabled, str(fire.position.y) if fire else "no fire ring", str(body.position.y) if body else "no body"])
	# The mage stopped sorting in 0.68.1 (its picture sorted behind walls it
	# stood in front of - see _test_every_class_stands_in_front_of_a_wall()).
	check("  every class as its own: the warrior and tank sort, the healer and (since 0.68.1) the mage do not",
		Remote.class_sorted("warrior") and not Remote.class_sorted("mage") and Remote.class_sorted("tank")
		and not Remote.class_sorted("healer") and not Remote.class_sorted(""))

	# ---- the switch ----
	check("Options has the switch - on by default, as their attacks have been drawn since 0.19.0",
		Settings.DEFAULTS.get("others_attacks") == true
		and _func_body(_code_src("res://src/ui/menus/optionsscreen.gd"), "func _on_others_attacks_toggled(").contains("Settings.set_value(\"others_attacks\", pressed)")
		and _code_src("res://src/ui/menus/optionsscreen.gd").contains("others_attacks_toggle.button_pressed = bool(Settings.get_value(\"others_attacks\"))")
		and _code_src("res://scene/ui/menus/optionsscreen.tscn").contains("text = \"Other players' attacks\""))
	Settings.set_value("others_attacks", true)
	tanky.set_motion("idledown", ["ring", "firering"], "")
	var lit_on: bool = fire != null and fire.visible and small != null and small.visible
	var made: Array = RemoteAttacks.fire(tanky, ["slash", 0, o.x, o.y, o.x + 100.0, o.y, 0, 0])
	var drawn_on: int = made.size()
	for n in made:
		(n as Node).queue_free()
	Settings.set_value("others_attacks", false)
	var lit_off: bool = (fire != null and fire.visible) or (small != null and small.visible)
	var hidden_kinds: Array = []
	for attack in [["slash", 0, o.x, o.y, o.x + 100.0, o.y, 0, 0], ["axe", 0, o.x, o.y, o.x + 60.0, o.y, 0, 0],
			["stalag", 0, o.x, o.y, o.x + 4.0, o.y, 0, 0], ["meteor", 0, o.x, o.y, o.x, o.y, 0, 0],
			["dyn", 0, o.x, o.y, o.x + 30.0, o.y, 0, 0], ["orb", 0, o.x, o.y, o.x, o.y + 100.0, 0, 0]]:
		var got: Array = RemoteAttacks.fire(tanky, attack)
		if got.is_empty():
			hidden_kinds.append(attack[0])
		for n in got:
			(n as Node).queue_free()
	check("switched on, they are drawn: their wave, and the tank's rings lit", drawn_on == 1 and lit_on)
	check("switched off, none of them: no wave, axe, stalagmite, meteor, stick or orb",
		hidden_kinds == ["slash", "axe", "stalag", "meteor", "dyn", "orb"], hidden_kinds)
	check("  and their auras go out at once - the rings are their attacks too", not lit_off)
	tanky.set_motion("idledown", ["ring", "firering"], "")
	check("  and stay out as the steps keep coming", fire != null and not fire.visible and small != null and not small.visible)

	# A healer's aura still heals you, unseen - in it, or by its blobs.
	var heals: Array = RemoteAttacks.fire(tanky, ["heal", 0, o.x, o.y, o.x + 400.0, o.y, 0, 0])
	var unseen: HealAura = heals[0] if not heals.is_empty() and heals[0] is HealAura else null
	var inside: Node2D = _aura_patient(arena, o + Vector2(400, 2), 200)
	var outside: Node2D = _aura_patient(arena, o + Vector2(400 + 120, 40), 160)
	if unseen != null:
		(unseen.get_node(^"picture") as AnimatedSprite2D).stop()
		unseen.heal_target = inside
		for frame in [HealAura.LANDS_ON] + HealAura.TICK_FRAMES:
			unseen.reached(frame)
	check("switched off, a healer's aura is not drawn - beam, ring, light or blob - and it still heals you",
		unseen != null and unseen.unseen and not unseen.visible
		and (inside.get("got") as Array).size() == HealAura.TICK_FRAMES.size(),
		[unseen != null, inside.get("got") if inside else null])
	var unseen_blobs: Array = RemoteAttacks.fire(tanky, ["heal", 0, o.x, o.y, o.x + 400.0, o.y, 0, 0])
	var by_blob: HealAura = unseen_blobs[0] if not unseen_blobs.is_empty() and unseen_blobs[0] is HealAura else null
	var blobs_hidden: bool = by_blob != null
	if by_blob != null:
		(by_blob.get_node(^"picture") as AnimatedSprite2D).stop()
		by_blob.heal_target = outside
		by_blob.reached(HealAura.LANDS_ON)
		for blob in by_blob.blobs:
			blobs_hidden = blobs_hidden and is_instance_valid(blob) and not blob.visible
		for i in 60:
			for blob in by_blob.blobs:
				if is_instance_valid(blob) and not blob.arrived:
					blob.step(1.0 / 30.0)
	check("  outside it, its blobs fly unseen and heal you all the same",
		blobs_hidden and by_blob.blobs.size() == HealAura.BLOBS and (outside.get("got") as Array).size() == HealAura.BLOBS,
		[blobs_hidden, outside.get("got") if outside else null])
	Settings.set_value("others_attacks", true)
	check("switched back on, the tank's rings light again at once", fire != null and fire.visible and small != null and small.visible)
	Settings.set_value("others_attacks", kept)
	arena.queue_free()
	await get_tree().process_frame


func _test_every_class_answers_its_own_attack() -> void:
	section("EVERY CLASS - its own attack, damage and attack period (the healer lost all three in 0.40.0)")
	# The owner's log after 0.40.0: "player.gd:1545 @ attack_action(): Player:
	# missing animation 'attackright' - attack canceled ... like 16 errors". The
	# aura's rewrite of healer.gd took its ATTACK ACTION OVERRIDE with it, so
	# every click and Space ran the base swing, and the equipment panel read a
	# healer with no attack.
	var missing: Array = []
	for cls in ["warrior", "mage", "tank", "healer"]:
		var src: String = _code_src("res://src/characters/%s.gd" % cls)
		for header in ["func attack_action() -> void:", "func base_attack_damage() -> int:", "func attack_period() -> float:"]:
			if not src.contains("\n" + header):
				missing.append("%s %s" % [cls, header])
	check("all four classes answer attack_action(), base_attack_damage() and attack_period() themselves",
		missing.is_empty(), missing)
	var bare: Node = (load("res://src/characters/healer.gd") as GDScript).new()
	bare.attack_action()
	check("  the healer's click and Space are its orbs, never the base swing: its attack_action() starts nothing",
		not bool(bare.get("is_attacking")))
	var dmg: int = int(bare.call("base_attack_damage"))
	var period: float = float(bare.call("attack_period"))
	check("  and it says what it hits for and how often - the equipment panel's damage and dps",
		dmg == int(bare.get("damage_per_magic")) and dmg > 0 and period > 0.0
		and period <= float(bare.get("shot_cooldown")) + 0.0001, [dmg, period])
	bare.free()


func _test_other_players_attacks_are_pictures() -> void:
	section("OTHER PLAYERS' ATTACKS - drawn from the class's own scenes, touching nothing")
	var Remote := preload("res://src/characters/remoteplayer.gd")
	# Drawn: whatever this machine's Options say (0.40.1's switch), put back after.
	var kept_shown: bool = bool(Settings.get_value("others_attacks"))
	Settings.set_value("others_attacks", true)
	var warrior_consts: Dictionary = (load("res://src/characters/warrior.gd") as GDScript).get_script_constant_map()
	var mage_consts: Dictionary = (load("res://src/characters/mage.gd") as GDScript).get_script_constant_map()
	var tank_consts: Dictionary = (load("res://src/characters/tank.gd") as GDScript).get_script_constant_map()
	var healer_orb: PackedScene = RemoteAttacks.class_setting("healer", "projectile_scene") as PackedScene
	var healer_real: Node = (load("res://scene/characters/healer.tscn") as PackedScene).instantiate()
	var mage_real: Node = (load("res://scene/characters/mage.tscn") as PackedScene).instantiate()
	check("the pictures are the very scenes the classes spawn",
		(warrior_consts["SLASHWAVE_SCENE"] as PackedScene).resource_path == RemoteAttacks.SLASHWAVE_PATH
		and (warrior_consts["SPINNING_AXE_SCENE"] as PackedScene).resource_path == RemoteAttacks.SPINNING_AXE_PATH
		and (mage_consts["METEOR_SCENE"] as PackedScene).resource_path == RemoteAttacks.METEOR_PATH
		and (tank_consts["DYNAMITE_SCENE"] as PackedScene).resource_path == RemoteAttacks.DYNAMITE_PATH
		and healer_orb == healer_real.get("projectile_scene")
		and RemoteAttacks.class_setting("mage", "target_circle_scene") == mage_real.get("target_circle_scene"))
	check("  and a healer's orb flies at the healer's speed, in the healer's colour",
		is_equal_approx(float(RemoteAttacks.class_setting("healer", "projectile_speed")), float(healer_real.get("projectile_speed")))
		and RemoteAttacks.class_setting("healer", "projectile_tint") == healer_real.get("projectile_tint"))
	healer_real.free()
	mage_real.free()
	var fire_body := _func_body(_code_src("res://src/characters/remoteattacks.gd"), "static func fire(")
	var handled: Array = []
	for kind in RemoteAttacks.KINDS:
		if fire_body.contains("\"%s\":" % kind):
			handled.append(kind)
	check("every kind on the wire is drawn", handled == RemoteAttacks.KINDS, handled)

	var arena := Node2D.new()
	add_child(arena)
	var o := Vector2(-73000, -73000)
	var foe_at := func(offset: Vector2) -> BaseEnemy:
		var e: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
		e.position = o + offset
		arena.add_child(e)
		e.set_physics_process(false)
		return e
	var close: BaseEnemy = foe_at.call(Vector2(4, 0))
	var near: BaseEnemy = foe_at.call(Vector2(-70, 0))
	var them: Node2D = Remote.new()
	them.user_id = 611
	arena.add_child(them)
	them.set_identity({"id": 611, "name": "Student", "cls": "warrior", "lvl": 22, "v": 2})
	them.set_process(false)
	them.place(o + Vector2(0, 30))
	var scene_root: Node = get_tree().current_scene
	var before: Array = scene_root.get_children()
	for i in 3:
		await get_tree().physics_frame
	var close_hp: int = close.hp
	var near_at: Vector2 = near.global_position
	var ends_with := func(script_type: Variant) -> Array:
		var found: Array = []
		for child in scene_root.get_children():
			if not before.has(child) and is_instance_of(child, script_type):
				found.append(child)
		return found

	# ---- a meteor that pulls ----
	var made: Array = RemoteAttacks.fire(them, ["meteor", 0, o.x, o.y + 30.0, o.x, o.y, 0, RemoteAttacks.FLAG_PULL])
	var met: Meteor = made[0] if not made.is_empty() else null
	check("a meteor is dropped where they aimed it, pulling as theirs did, and a picture",
		met != null and met.cosmetic and met.pulls and met.global_position == o, made)
	if met != null:
		met.set_physics_process(false)
		for i in 3:
			await get_tree().physics_frame
		var guard: int = 0
		while not met.landed and guard < 200:
			met.advance(1.0 / 60.0)
			guard += 1
		await get_tree().physics_frame
	var craters: Array = ends_with.call(BurningCrater)
	var blasts: Array = ends_with.call(Blast)
	for crater in craters:
		(crater as BurningCrater).advance(BurningCrater.BURN_SECONDS)
	check("  it falls and lands, and hurts nothing it lands on, nor its crater after",
		met != null and met.landed and close.hp == close_hp and met.hit_count() == 0
		and not craters.is_empty() and (craters[0] as BurningCrater).cosmetic
		and (craters[0] as BurningCrater).burns_dealt == 0, [close.hp, close_hp, craters.size()])
	check("  pulls nothing - the monsters are the leader's", near.global_position == near_at
		and met != null and met.pulled_count() == 0, near.global_position - near_at)
	check("  and shakes nobody's camera", not blasts.is_empty() and not (blasts[0] as Blast).shakes, blasts.size())

	# ---- a stick of dynamite, beside a real one of yours ----
	var mine: Dynamite = (load(RemoteAttacks.DYNAMITE_PATH) as PackedScene).instantiate()
	arena.add_child(mine)
	mine.throw_from(o + Vector2(8, 0), o + Vector2(8, 0))
	mine.set_physics_process(false)
	mine.advance(Dynamite.FLIGHT_SECONDS + 0.01)
	made = RemoteAttacks.fire(them, ["dyn", 0, o.x, o.y + 30.0, o.x, o.y, 0, 0])
	var stick: Dynamite = made[0] if not made.is_empty() else null
	check("a stick is thrown from them to where they threw it, a picture",
		stick != null and stick.cosmetic and stick.landing_spot() == o, made)
	if stick != null:
		stick.set_physics_process(false)
		for i in 3:
			await get_tree().physics_frame
		stick.advance(Dynamite.FLIGHT_SECONDS + 0.01)
		stick.advance(Dynamite.FUSE_SECONDS + 0.05)
	check("  it goes off and hurts nothing", stick != null and stick.exploded and stick.hits_dealt == 0
		and close.hp == close_hp, [close.hp, close_hp])
	check("  and does not light a fuse of yours beside it", mine.state == Dynamite.State.FUSE and not mine.chained)
	mine.queue_free()

	# ---- the Double Axe, wide and bloody, out and home ----
	made = RemoteAttacks.fire(them, ["axe", 0, o.x, o.y + 30.0, o.x + 60.0, o.y + 30.0, 0,
		RemoteAttacks.FLAG_WIDE | RemoteAttacks.FLAG_BLOODY])
	var axe: SpinningAxe = made[0] if not made.is_empty() else null
	check("an axe flies from them, as they rolled it, and is theirs to call home",
		axe != null and axe.cosmetic and axe.wide and axe.bloody and axe.caster == them and them.get("axe") == axe
		and not axe.wounds, made)
	var on_path: BaseEnemy = foe_at.call(Vector2(30, 30))
	for i in 3:
		await get_tree().physics_frame
	var path_hp: int = on_path.hp
	if axe != null:
		axe.set_physics_process(false)
		for i in 90:
			axe.advance(1.0 / 30.0)
		await get_tree().physics_frame
		for i in 30:
			axe.advance(1.0 / 30.0)
	check("  it cuts nothing it passes or spins over, and opens no wound",
		axe != null and axe.hits_dealt == 0 and on_path.hp == path_hp and not on_path.has_meta(Bleed.META),
		[on_path.hp, path_hp])
	RemoteAttacks.fire(them, ["recall", 0, o.x, o.y + 30.0, o.x, o.y + 30.0, 0, 0])
	var home: bool = false
	for i in 120:
		if axe == null or not is_instance_valid(axe) or axe.is_queued_for_deletion():
			home = true
			break
		axe.advance(1.0 / 30.0)
	check("  called home, it flies back to them and is gone", home and them.get("axe") == null)

	# ---- the stalagmite, a slash wave and an orb ----
	made = RemoteAttacks.fire(them, ["stalag", 0, o.x, o.y + 30.0, o.x + 4.0, o.y, 0, 0])
	var spell: Node2D = made[0] if not made.is_empty() else null
	for i in 3:
		await get_tree().physics_frame
	if spell != null:
		spell.call("_apply_area_damage")
	check("a stalagmite comes down where they aimed it, and its impact hurts nothing",
		spell != null and spell.get("cosmetic") == true and spell.global_position == o + Vector2(4, 0)
		and close.hp == close_hp, [close.hp, close_hp])
	made = RemoteAttacks.fire(them, ["slash", 0, o.x, o.y + 30.0, o.x + 100.0, o.y + 30.0, 0, 0])
	var wave: SlashWave = made[0] if not made.is_empty() else null
	if wave != null:
		wave._try_hit(close)
	check("a slash wave flies the way they swung, and passes through a monster without a hit",
		wave != null and wave.cosmetic and wave.direction == Vector2.RIGHT and close.hp == close_hp,
		[str(wave.direction) if wave != null else "no wave", close.hp])
	made = RemoteAttacks.fire(them, ["orb", 0, o.x, o.y + 30.0, o.x, o.y + 130.0, 0, 0])
	var orb: Node2D = made[0] if not made.is_empty() else null
	if orb != null:
		orb.call("_hit", close)
	check("a healer's orb leaves them the way they fired, and goes out on a monster without a hit",
		orb != null and orb.get("cosmetic") == true and orb.get("direction") == Vector2.DOWN
		and is_equal_approx(float(orb.get("speed")), float(RemoteAttacks.class_setting("healer", "projectile_speed")))
		and orb.is_queued_for_deletion() and close.hp == close_hp, [close.hp, close_hp])

	# ---- when: as the playback reaches the moment they made it ----
	Remote.clock_override = 20.0
	them.place(o + Vector2(0, 30), 1000)
	Remote.clock_override = 20.6
	them.hear_attacks([["stalag", 1500, o.x, o.y + 30.0, o.x + 40.0, o.y, 0, 0],
		["laser", 1500, 0.0, 0.0, 0.0, 0.0, 0, 0], ["meteor", 1500]])
	them._process(1.0 / 60.0)
	check("an attack waits until the playback of them reaches the moment they made it",
		them.attacks_waiting() == 1, them.attacks_waiting())
	var circle_script: Script = load("res://src/projectiles/spelltargetcircle.gd")
	var spells_before: int = ends_with.call(circle_script).size()
	Remote.clock_override = 20.0 + 0.5 + Remote.PLAYBACK_DELAY + 0.001
	them._process(1.0 / 60.0)
	var spells_after: int = ends_with.call(circle_script).size()
	check("  and then it is drawn - one, the kind nobody knows and the broken one never",
		them.attacks_waiting() == 0 and spells_after == spells_before + 1, [them.attacks_waiting(), spells_before, spells_after])
	Presence._remotes[611] = them
	Presence.handle_message({"t": "x", "id": 611, "e": [["meteor", 1600, o.x, o.y, o.x, o.y, 0, 0]]})
	Presence.handle_message({"t": "x", "id": 612, "e": [["meteor", 1600, o.x, o.y, o.x, o.y, 0, 0]]})
	check("the presence link hands each attack to the picture of whoever made it, and nobody else's",
		them.attacks_waiting() == 1, them.attacks_waiting())
	# THEIR ATTACKS RIDE THE TICK (0.76.0): inside the moves, the same way.
	Presence.handle_message({"t": "moves", "p": [], "x": [
		[611, [["meteor", 1700, o.x, o.y, o.x, o.y, 0, 0]]],
		[612, [["meteor", 1700, o.x, o.y, o.x, o.y, 0, 0]]],
		["junk"], [611, "nope"], 7]})
	check("  and the attacks riding the tick's moves (0.76.0) the same way - the broken ones never",
		them.attacks_waiting() == 2, them.attacks_waiting())
	var my_id_was: int = Presence._my_id
	Presence._my_id = 611
	Presence.handle_message({"t": "moves", "p": [], "x": [[611, [["meteor", 1800, o.x, o.y, o.x, o.y, 0, 0]]]]})
	Presence.handle_message({"t": "x", "id": 611, "e": [["meteor", 1800, o.x, o.y, o.x, o.y, 0, 0]]})
	check("  and our own, coming back in the tick, are passed over", them.attacks_waiting() == 2,
		them.attacks_waiting())
	Presence._my_id = my_id_was
	Presence._remotes.erase(611)
	Remote.clock_override = -1.0
	for child in scene_root.get_children():
		if not before.has(child):
			child.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	print("  pictures: the scenes, meteor, stick, axe, stalagmite, slash, orb, when, routing")
	Settings.set_value("others_attacks", kept_shown)


# AND THIS GAME'S OWN (0.19.0): what it tells the presence server.

func _test_presence_sends_attacks() -> void:
	section("PRESENCE - this game's attacks and levers go out, with its clock on every step")
	Presence.set_process(false)
	Presence.stop()
	var sent: Array = []
	Presence.send_override = func(message: Dictionary) -> void:
		sent.append(message)
	var cleanup := func() -> void:
		Presence.send_override = Callable()
		Presence.clock_override_ms = -1
		Presence.stop()
		Presence._server_relays = false
		Presence._last_state = {}
		Presence.set_process(true)
	Presence._phase = "open"
	Presence.handle_message({"t": "welcome", "id": 7, "v": 2, "books": true})
	Presence.tell_attack("meteor", Vector2(1, 2), Vector2(3, 4))
	check("a server that does not pass attacks on is sent none", not Presence.relays()
		and Presence.attacks_queued().is_empty())
	Presence.handle_message({"t": "welcome", "id": 7, "v": 2, "books": true, "x": 1})
	Presence.clock_override_ms = 81234
	Presence.tell_attack("meteor", Vector2(100.04, 200.0), Vector2(140.26, 210.0), 0.25, RemoteAttacks.FLAG_PULL)
	check("one that does is: kind, this game's clock, where from and to (to a tenth), the delay in ms, the rolls",
		Presence.relays() and Presence.attacks_queued() == [["meteor", 81234, 100.0, 200.0, 140.3, 210.0, 250, 1]],
		Presence.attacks_queued())
	for i in 30:
		Presence.tell_attack("orb", Vector2.ZERO, Vector2.RIGHT)
	check("  no more between two sends than the server takes in one message",
		Presence.attacks_queued().size() == Presence.MAX_ATTACKS_PER_SEND, Presence.attacks_queued().size())

	var stand_script := GDScript.new()
	stand_script.source_code = "extends Node2D\nvar active_pet_id: String = \"\"\n"
	stand_script.reload()
	var stand: Node2D = stand_script.new()
	add_child(stand)
	stand.global_position = Vector2(100, 200)
	Presence._last_state = {}
	Presence._sync_pending = false
	Presence.send_tick(stand)
	check("a beat sends the state with this game's clock on it, then the attacks since the last beat",
		sent.size() == 2 and sent[0].get("t") == "s" and sent[0].get("ts") == 81234
		and sent[1].get("t") == "x" and (sent[1].get("e") as Array).size() == Presence.MAX_ATTACKS_PER_SEND
		and Presence.attacks_queued().is_empty(), sent.map(func(m: Dictionary) -> String: return str(m.get("t"))))
	sent.clear()
	Presence.clock_override_ms = 81334
	Presence.send_tick(stand)
	check("  standing still sends nothing, clock or no clock", sent.is_empty(), sent)
	stand.global_position = Vector2(110, 200)
	Presence.send_tick(stand)
	check("  a step sends one, with the new clock", sent.size() == 1 and sent[0].get("ts") == 81334
		and is_equal_approx(float(sent[0].get("x")), 110.0), sent)
	Presence.tell_attack("dyn", Vector2.ZERO, Vector2.ONE)
	var other_world := Node2D.new()
	add_child(other_world)
	Presence.world_override = other_world
	Presence._follow_world(stand)
	check("attacks made in a world just left are not sent into the next", Presence.attacks_queued().is_empty())
	Presence.world_override = null
	Presence._world = null
	other_world.queue_free()
	stand.queue_free()

	# ---- the class scripts say what they made ----
	var said := func(path: String, header: String, kind: String) -> bool:
		return _func_body(_code_src(path), header).contains("Presence.tell_attack(\"%s\"" % kind)
	check("the warrior's thrown axe and slash wave, the mage's stalagmite and meteor, the tank's sticks and the healer's orbs are told",
		said.call("res://src/characters/warrior.gd", "func throw_axe(", "axe")
		and said.call("res://src/characters/warrior.gd", "func _spawn_slashwave(", "slash")
		and said.call("res://src/characters/mage.gd", "func _drop_spike(", "stalag")
		and said.call("res://src/characters/mage.gd", "func _drop_meteor(", "meteor")
		and said.call("res://src/characters/tank.gd", "func _throw_stick(", "dyn")
		and said.call("res://src/characters/healer.gd", "func _spawn_projectile(", "orb"))
	var recall_body := _func_body(_code_src("res://src/projectiles/spinningaxe.gd"), "func recall(")
	check("  and an axe called home for any reason - but never a picture telling it back",
		recall_body.contains("Presence.tell_attack(\"recall\"") and recall_body.contains("not cosmetic"))
	cleanup.call()
	print("  sending: only to a server that takes them, the shape, the cap, the beat, the clock, a new world, the classes")


# LEVERS (0.19.0). The owner: "the had to lower the gate to boss" - a gate one
# player opened stayed shut on the other's screen.
func _test_levers_are_shared() -> void:
	section("LEVERS - one pull opens the gate on every screen in the area")
	var holder := Node2D.new()
	holder.name = "levertest"
	add_child(holder)
	var door_script := GDScript.new()
	door_script.source_code = "extends Node2D\nvar raised: bool = true\nfunc set_raised(up: bool) -> void:\n\traised = up\n"
	door_script.reload()
	var door: Node2D = door_script.new()
	door.name = "gate"
	holder.add_child(door)
	var lever_scene: PackedScene = load("res://scene/interactables/lever.tscn") as PackedScene
	var to_gate: Array[NodePath] = [NodePath("../gate")]
	var outside: Area2D = lever_scene.instantiate()
	outside.name = "leverout"
	outside.set("targets", to_gate)
	holder.add_child(outside)
	var inside: Area2D = lever_scene.instantiate()
	inside.name = "leverin"
	inside.set("targets", to_gate.duplicate())
	holder.add_child(inside)
	await get_tree().process_frame
	await get_tree().process_frame
	var out_name: String = Presence.lever_name(outside)
	var in_name: String = Presence.lever_name(inside)
	check("a lever is named by its path in the scene - the same in every game that loaded it",
		out_name == String(get_tree().current_scene.get_path_to(outside)) and out_name.ends_with("levertest/leverout")
		and in_name.ends_with("levertest/leverin"), [out_name, in_name])
	var field_text: String = FileAccess.get_file_as_string("res://scene/field.tscn")
	var rule := RegEx.create_from_string(Presence.LEVER_PATTERN)
	var field_levers: Array = []
	for found in RegEx.create_from_string("\\[node name=\"(lever[^\"]*)\" parent=\"([^\"]+)\"").search_all(field_text):
		field_levers.append("%s/%s" % [found.get_string(2), found.get_string(1)])
	var all_taken: bool = not field_levers.is_empty()
	for path in field_levers:
		all_taken = all_taken and rule.search(path) != null
	check("  and the Field's two boss-gate levers have names the server takes", all_taken and field_levers.size() == 2,
		field_levers)
	var odd: Area2D = lever_scene.instantiate()
	odd.name = "lever two"
	holder.add_child(odd)
	check("  a lever whose path the server would refuse is not named at all", Presence.lever_name(odd) == "")
	odd.free()

	Presence.set_process(false)
	Presence.stop()
	var sent: Array = []
	Presence.send_override = func(message: Dictionary) -> void:
		sent.append(message)
	Presence._phase = "open"
	Presence.handle_message({"t": "welcome", "id": 7, "v": 2, "books": true, "x": 1})
	Presence.tell_lever(outside, true)
	check("pulled here, it is told to the server by name", sent == [{"t": "l", "n": out_name, "on": true}], sent)
	sent.clear()
	Presence.handle_message({"t": "l", "id": 40, "n": out_name, "on": true})
	check("pulled by somebody else, it is pulled here: the gate goes down",
		outside.call("is_on") == true and door.get("raised") == false, [outside.call("is_on"), door.get("raised")])
	check("  the lever on the other side of the gate follows, as it does on their screen", inside.call("is_on") == true)
	check("  and nothing is told back: they already know", sent.is_empty(), sent)
	Presence.handle_message({"t": "l", "id": 7, "n": out_name, "on": false})
	Presence.handle_message({"t": "l", "id": 40, "n": "levertest/nothere", "on": false})
	Presence.handle_message({"t": "l", "id": 40, "n": out_name, "on": "no"})
	check("our own pull, a lever not in this scene, or an answer that is not yes or no changes nothing",
		outside.call("is_on") == true and door.get("raised") == false)
	Presence.handle_message({"t": "levers", "p": [[in_name, false], [out_name, true]]})
	check("walking in, the levers pulled before are pulled in the order they were - the gate ends where the last left it",
		door.get("raised") == false and outside.call("is_on") == true and inside.call("is_on") == true,
		[door.get("raised"), outside.call("is_on"), inside.call("is_on")])
	Presence.handle_message({"t": "levers", "p": [[out_name, false]]})
	check("  and a gate somebody shut again is shut", door.get("raised") == true and inside.call("is_on") == false)
	var interact_body := _func_body(_code_src("res://src/world/lever.gd"), "func _process(")
	check("a pull at the lever itself is the one that is told", interact_body.contains("Presence.tell_lever(self, _is_on)"))
	Presence.send_override = Callable()
	Presence.stop()
	Presence._server_relays = false
	Presence.set_process(true)
	holder.queue_free()
	await get_tree().process_frame
	print("  levers: the name, telling, following, partners, the order, the wiring")


# HELD KEYS (0.19.1). The first other player to play found it: Shift+right-click
# - a sprinting attack - opens Firefox's own menu, the key-up of the direction
# being held goes to the menu, and the character walks that way until the key
# is pressed again. He died of it. keybinds.gd, LETTING GO; settings.gd, THE
# KEYBOARD GOES ELSEWHERE.
func _test_held_keys_are_let_go() -> void:
	section("HELD KEYS - let go when the keyboard goes where the game cannot hear it")
	var key := func(code: Key, down: bool) -> void:
		var k := InputEventKey.new()
		k.physical_keycode = code
		k.pressed = down
		Input.parse_input_event(k)
		Input.flush_buffered_events()
	var click := func(down: bool, shift: bool) -> void:
		var c := InputEventMouseButton.new()
		c.button_index = MOUSE_BUTTON_RIGHT
		c.pressed = down
		c.shift_pressed = shift
		c.position = Vector2(-5000, -5000)
		Input.parse_input_event(c)
		Input.flush_buffered_events()
	var clean := func() -> void:
		Keybinds.let_go(true)
		key.call(KEY_F9, false)
		Input.flush_buffered_events()
		Settings.native_menu_on_shift_click = false

	# ---- the bug, and letting go ----
	key.call(KEY_S, true)
	for i in 3:
		await get_tree().physics_frame
	check("a direction whose key-up never comes stays held: the walk nobody could stop",
		Input.is_action_pressed("move_down") and Input.is_physical_key_pressed(KEY_S))
	key.call(KEY_SHIFT, true)
	key.call(KEY_F9, true)
	click.call(true, false)
	var gone: Array = Keybinds.let_go()
	Input.flush_buffered_events()
	check("let_go() lets go of it - the key and the walk - and of sprint",
		not Input.is_action_pressed("move_down") and not Input.is_physical_key_pressed(KEY_S)
		and not Input.is_action_pressed("sprint") and gone.has(KEY_S) and gone.has(KEY_SHIFT), gone)
	check("  and of nothing that is not a key the game holds: another key, the mouse unless asked",
		Input.is_physical_key_pressed(KEY_F9) and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	Keybinds.let_go(true)
	Input.flush_buffered_events()
	check("  asked, the mouse buttons too", not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	clean.call()

	# ---- Shift+right-click, where the browser opens its own menu ----
	Settings.native_menu_on_shift_click = true
	key.call(KEY_S, true)
	click.call(true, true)
	var walking_after: bool = Input.is_action_pressed("move_down")
	await get_tree().physics_frame
	var mouse_on_the_first_step: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	for i in 3:
		await get_tree().physics_frame
	check("Shift+right-click in Firefox lets go of the walk at once - the menu is about to take its key-up",
		not walking_after, walking_after)
	check("  and of the right button only after the physics step, so the click still attacks",
		mouse_on_the_first_step and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	key.call(KEY_S, true)
	click.call(true, false)
	await get_tree().physics_frame
	check("  a right-click without Shift lets go of nothing - no menu comes", Input.is_action_pressed("move_down"))
	clean.call()
	key.call(KEY_S, true)
	click.call(true, true)
	check("in a browser that keeps its menu shut (Chrome, Edge, Safari) a sprinting attack lets go of nothing",
		Input.is_action_pressed("move_down") and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	clean.call()
	var firefox := "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0"
	var firefox_android := "Mozilla/5.0 (Android 14; Mobile; rv:131.0) Gecko/131.0 Firefox/131.0"
	var chrome := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
	var edge := chrome + " Edg/129.0.0.0"
	var safari := "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
	var chromebook := "Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
	check("Firefox is the browser that opens its own menu; Chrome, Edge, Safari and a Chromebook are not",
		Keybinds.opens_its_own_menu(firefox) and Keybinds.opens_its_own_menu(firefox_android)
		and not Keybinds.opens_its_own_menu(chrome) and not Keybinds.opens_its_own_menu(edge)
		and not Keybinds.opens_its_own_menu(safari) and not Keybinds.opens_its_own_menu(chromebook))
	var ready_body := _func_body(_code_src("res://src/systems/settings.gd"), "func _ready(")
	check("  read from the browser itself, in the web build", ready_body.contains("OS.has_feature(\"web\")")
		and ready_body.contains("Keybinds.opens_its_own_menu(") and ready_body.contains("navigator.userAgent"))

	# ---- the window losing focus, and a text box taking the keyboard ----
	key.call(KEY_S, true)
	Settings._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("the game losing focus (another window, a tab, a prompt) lets go", not Input.is_action_pressed("move_down"))
	Settings._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	key.call(KEY_D, true)
	click.call(true, false)
	Settings._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	# The mouse's release is read with the next batch of input, as a real one is.
	Input.flush_buffered_events()
	check("  so does the window losing it, the mouse with it",
		not Input.is_action_pressed("move_right") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	var layer := CanvasLayer.new()
	var box := LineEdit.new()
	var button := Button.new()
	layer.add_child(box)
	layer.add_child(button)
	add_child(layer)
	key.call(KEY_W, true)
	button.grab_focus()
	var after_button: bool = Input.is_action_pressed("move_up")
	box.grab_focus()
	check("a text box taking the keyboard lets go - nobody walks while typing; a button does not",
		after_button and not Input.is_action_pressed("move_up"))
	box.release_focus()
	layer.queue_free()
	clean.call()
	print("  held keys: the bug, letting go, Firefox's menu, other browsers, focus, a text box")


# THE GIFTS LEDGER (0.20.0). The owner, 10 Oct: "make a ledger for anthing i
# give to players so its accounted for if i ever ask how much did i inflate my
# server". The server counts (test_gifts.py); the game says what each gift came
# to as it is given, and the GM panel's Testing tab asks for the totals.
func _test_gifts_are_counted() -> void:
	section("THE GIFTS LEDGER - what a gift came to, and what I've given")
	var pile: ItemData = ItemRegistry.get_item("goldpile")
	var sword: ItemData = ItemRegistry.get_item("ironsword")
	# Both icons are in the private art pack, so a clone has neither item and
	# this section is a skip there, not a failure.
	check_needs_pack("the catalogue has the Pile of Gold and the Iron Sword to say it with",
		pile != null and sword != null and pile.display_name == "Pile of Gold")
	if pile == null or sword == null:
		return

	# --- AS IT IS GIVEN --------------------------------------------------------
	var gold_worth: Dictionary = {"kind": "gold", "gold": 24975000.0, "lusions": 0.0, "value": 0.0, "sells_for": 0.0}
	check("money is said as money: gold with its commas, lusions counted",
		ItemSpawner.money_text(gold_worth) == "24,975,000 gold"
		and ItemSpawner.money_text({"kind": "lusions", "gold": 0, "lusions": 50}) == "50 lusions"
		and ItemSpawner.money_text({"kind": "lusions", "gold": 0, "lusions": 1}) == "1 lusion",
		ItemSpawner.money_text(gold_worth))
	check("  a sword is not money, and a server from before the ledger says nothing",
		ItemSpawner.money_text({"kind": "item", "gold": 0, "lusions": 0, "value": 400}) == ""
		and ItemSpawner.money_text(null) == "")
	var to_him: Dictionary = {"username": "allmind", "character": "tank", "granted_quantity": 999.0,
		"online": true, "worth": gold_worth}
	var line: String = ItemSpawner.gift_line(to_him, pile, 999)
	check("a give to a player says what it came to, before anybody asks",
		line == "Gave 999 × Pile of Gold (24,975,000 gold) to allmind's tank. Their game is told on its next poll.",
		line)
	to_him["worth"] = {"kind": "item", "gold": 0, "lusions": 0, "value": 400, "sells_for": 20}
	to_him["granted_quantity"] = 1
	check("  a sword's line is as it was", ItemSpawner.gift_line(to_him, sword, 1)
		== "Gave 1 × Iron Sword to allmind's tank. Their game is told on its next poll.",
		ItemSpawner.gift_line(to_him, sword, 1))
	check("your own bag says it too",
		ItemSpawner.added_line({"worth": gold_worth}, pile, 999) == "Added 999 × Pile of Gold to your bag (24,975,000 gold).",
		ItemSpawner.added_line({"worth": gold_worth}, pile, 999))
	check("  and an answer with no worth in it reads as before",
		ItemSpawner.added_line({}, pile, 2) == "Added 2 × Pile of Gold to your bag.")
	var panel_code: String = _code_src("res://src/ui/owner/ownerpanel.gd")
	check("the Testing tab's Give item says it the same way",
		panel_code.split("func _on_item_pressed")[1].split("\nfunc ")[0].contains("ItemSpawner.money_text("))

	# --- WHAT I'VE GIVEN -------------------------------------------------------
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var button: Button = gm.get_node_or_null("%giftsbutton") as Button
	var testing_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	check("the Testing tab has the Gifts ledger, under the item catalogue",
		button != null and testing_tab != null and testing_tab.is_ancestor_of(button)
		and button.get_index() == gm.get_node("%cataloguebutton").get_index() + 1
		and button.text == "Gifts ledger")
	if button == null:
		gm.queue_free()
		Api.is_owner = was_owner
		return
	var asked: Array = []
	# Through JSON and back, so every number is the float the real answer has.
	var report: Variant = JSON.parse_string(JSON.stringify({
		"totals": {"gifts": 14, "gold": 274750000, "lusions": 199, "item_value": 400, "item_sells_for": 20},
		"to_players": {"gifts": 13, "gold": 274750000, "lusions": 199, "item_value": 400, "item_sells_for": 20},
		"to_yourself": {"gifts": 1, "gold": 0, "lusions": 0, "item_value": 0, "item_sells_for": 0},
		"by_player": [{"username": "allmind", "gifts": 13, "gold": 274750000, "lusions": 199, "item_value": 400}],
		"by_item": [],
		"recent": [{"at": 1791598980, "by": "Tunacan", "username": "allmind", "kind": "gold", "item_id": "goldpile",
			"quantity": 999, "gold": 24975000, "lusions": 0, "item_value": 0, "source": "log"}],
		"economy": {"gold_now": 275000000, "lusions_now": 300, "gold_ever_made": 276000000},
		"share_of_gold_now": 0.9991, "ledger_since": 1791598000}))
	var answer: Array = [{"ok": true, "data": report}]
	gm.gifts_request = func(path: String) -> Dictionary:
		asked.append(path)
		await get_tree().process_frame
		return answer[0]
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var text: String = gm.results.get_parsed_text()
	check("pressing it asks the gifts route", asked == [gm.GIFTS_PATH] and gm.GIFTS_PATH.begins_with("/api/staff/gifts"),
		asked)
	check("  and prints the totals in words: everything, to players, to themselves",
		text.contains("THE GIFTS LEDGER") and text.contains("everything  : 274,750,000 gold, 199 lusions, items worth 400 (14 gifts)")
		and text.contains("to players  : 274,750,000 gold") and text.contains("to themselves: nothing (1 gift)"), text)
	check("  beside the gold in the game now, and the share of it",
		text.contains("275,000,000 gold in purses and banks") and text.contains("is 99.9% of that"), text)
	check("  by player, and the newest gift by the item's name",
		text.contains("allmind: 274,750,000 gold") and text.contains("allmind: 999 × Pile of Gold, 24,975,000 gold"), text)
	check("  and since when it counts", text.contains("counted from %s" % LocalTime.full(1791598000)), text)
	check("the button is back for the next press", not button.disabled)
	var unused: Dictionary = (report as Dictionary).duplicate(true)
	unused["share_of_gold_now"] = 4829.6111
	var panel_script: Variant = gm.get_script()
	var unused_lines: Array = panel_script.gift_report_lines(unused)
	var unused_text: String = "\n".join(unused_lines.map(func(l: Array) -> String: return str(l[0])))
	check("  piles given and not used yet are said as more than all of it, not as thousands of per cent",
		unused_text.contains("more than all of it") and not unused_text.contains("%"), unused_text)
	gm.results.clear()
	answer[0] = {"ok": true, "data": {"totals": {"gifts": 0}, "ledger_since": null}}
	await gm.show_what_i_have_given()
	check("nothing given yet is said so", gm.results.get_parsed_text().contains("Nothing given yet."),
		gm.results.get_parsed_text())
	answer[0] = {"ok": false, "status": 404, "error": "Not found."}
	await gm.show_what_i_have_given()
	check("a server from before the ledger is said to need updating",
		gm.results.get_parsed_text().contains("no gifts ledger yet"), gm.results.get_parsed_text())
	Api.is_owner = false
	var before: int = asked.size()
	await gm.show_what_i_have_given()
	check("anyone but the owner asks nothing", asked.size() == before)
	Api.is_owner = was_owner
	gm.queue_free()
	await get_tree().process_frame
	print("  gifts: money in the give lines, older servers, What I've given, nothing yet, an old server")


# THE ECONOMY'S NUMBERS ON THE CLIENT (0.74.0). The owner: "Economy numbers you
# can change without shipping ... Today, changing the trade tax or a price
# means a new version." The server holds them (the API's economyrules/,
# test_economyrules.py); these hold the game's half: the EconomyRules autoload
# reads them once a login, falls back to the catalogue's own, and the shop
# window draws with them.
func _test_economy_rules_on_the_client() -> void:
	section("ECONOMY RULES - the server's numbers on the client, and the shop")
	var rules_script: GDScript = load("res://src/systems/economyrules.gd") as GDScript
	var store: ShopData = load("res://data/shops/generalstore.tres") as ShopData
	var usual: Dictionary = rules_script.catalogue_numbers()
	check("the catalogue's four: the general store's markup and buy-back, the kingdom's tax and floor",
		usual == {"shop_price_multiplier": float(store.price_multiplier), "shop_sell_multiplier": float(store.sell_multiplier),
			"trade_tax_rate": float(GameConstants.KINGDOM_TAX_RATE), "trade_tax_minimum": float(GameConstants.KINGDOM_TAX_MINIMUM)},
		usual)
	check("  what the server sends is believed only inside its bounds, and only as numbers",
		rules_script.checked({"shop_price_multiplier": 1.5, "shop_sell_multiplier": 0.9, "trade_tax_rate": "0.1",
			"trade_tax_minimum": 3, "gold_from_nowhere": 2.0}) == {"shop_price_multiplier": 1.5, "trade_tax_minimum": 3.0}
		and rules_script.checked("not a dictionary") == {} and rules_script.checked({"trade_tax_rate": NAN}) == {})
	check("the server's arithmetic: up for a price, at least 1, down for a payment, the float's dust off",
		rules_script.price_for(100, 1.1) == 110 and rules_script.price_for(0, 1.0) == 1
		and rules_script.pays_for(400, 0.05) == 20 and rules_script.pays_for(19, 0.05) == 0)
	check("  and the tax: 5% rounded up, the floor under it, nothing on nothing",
		rules_script.tax_for(1000, 0.05, 1) == 50 and rules_script.tax_for(10, 0.05, 1) == 1
		and rules_script.tax_for(10, 0.05, 3) == 3 and rules_script.tax_for(0, 0.5, 9) == 0)
	check("  a share in words: 5%, 150%, 12.5%", rules_script.percent_text(0.05) == "5%"
		and rules_script.percent_text(1.5) == "150%" and rules_script.percent_text(0.125) == "12.5%")

	# --- THE HOLDER ---------------------------------------------------------------
	var kept_fetch: Callable = EconomyRules.fetch
	var kept_token: String = Api.token
	EconomyRules.forget()
	check("nothing read: the catalogue's numbers, and none of them is the owner's",
		is_equal_approx(EconomyRules.number("shop_price_multiplier"), float(store.price_multiplier))
		and EconomyRules.buy_price(200) == rules_script.price_for(200, float(store.price_multiplier))
		and EconomyRules.trade_tax(1000) == rules_script.tax_for(1000, GameConstants.KINGDOM_TAX_RATE, GameConstants.KINGDOM_TAX_MINIMUM)
		and not EconomyRules.differs("shop_price_multiplier"))
	var asked: Array = []
	var answer: Array = [{"ok": true, "status": 200, "data": {"rules": {"shop_price_multiplier": 1.5,
		"shop_sell_multiplier": 0.1, "trade_tax_rate": 0.2, "trade_tax_minimum": 5}}}]
	EconomyRules.fetch = func(path: String) -> Dictionary:
		asked.append(path)
		return answer[0]
	var heard: Array = []
	var on_changed := func() -> void: heard.append(true)
	EconomyRules.changed.connect(on_changed)
	Api.token = "suite-economy-token"
	EconomyRules.ensure()
	await get_tree().process_frame
	check("a login reads them once, from GET /api/economy/rules", asked == ["/api/economy/rules"], asked)
	check("  and the game draws with them: 150% prices, 10% buy-back, 20% tax with a floor of 5",
		EconomyRules.buy_price(200) == 300 and EconomyRules.sell_price(400) == 40 and EconomyRules.trade_tax(1000) == 200
		and EconomyRules.trade_tax(10) == 5 and EconomyRules.differs("shop_price_multiplier"))
	check("  said with `changed`, so a window can redraw", heard.size() == 1, heard.size())
	EconomyRules.ensure()
	await get_tree().process_frame
	check("  asked again in the same login: not read again", asked.size() == 1, asked)
	answer[0] = {"ok": false, "status": 0, "error": "unreachable"}
	Api.token = "suite-economy-token-2"
	await EconomyRules.refresh()
	check("a server that cannot be reached leaves what was held", asked.size() == 2
		and is_equal_approx(EconomyRules.number("shop_price_multiplier"), 1.5))
	EconomyRules.forget()
	answer[0] = {"ok": false, "status": 404, "error": "Not found."}
	await EconomyRules.refresh()
	check("  and a server from before them (404) is the catalogue's numbers - the game as it was",
		is_equal_approx(EconomyRules.number("shop_price_multiplier"), float(store.price_multiplier))
		and is_equal_approx(EconomyRules.number("trade_tax_rate"), GameConstants.KINGDOM_TAX_RATE))
	EconomyRules.ensure()
	await get_tree().process_frame
	check("  and is not asked again for the same 404 this login", asked.size() == 3, asked)
	answer[0] = {"ok": true, "status": 200, "data": {"rules": {"shop_price_multiplier": 99.0, "trade_tax_rate": 0.1}}}
	Api.token = "suite-economy-token-3"
	await EconomyRules.refresh()
	check("a number outside the server's own bounds is not believed; the rest are",
		is_equal_approx(EconomyRules.number("shop_price_multiplier"), float(store.price_multiplier))
		and is_equal_approx(EconomyRules.number("trade_tax_rate"), 0.1))
	EconomyRules._on_identity_changed("", "player")
	check("signed out: back to the catalogue's numbers", EconomyRules.numbers.is_empty()
		and is_equal_approx(EconomyRules.number("trade_tax_rate"), GameConstants.KINGDOM_TAX_RATE))
	var api_src: String = _code_src("res://src/systems/economyrules.gd")
	check("  and a login is heard from Api's identity, with a token", api_src.contains("Api.identity_changed.connect(")
		and _func_body(api_src, "func _on_identity_changed(").contains("Api.token != \"\""))

	# --- THE SHOP WINDOW -----------------------------------------------------------
	var bag := InventoryContainer.new()
	bag.is_carry = true
	add_child(bag)
	bag.load_save_array([{"item_id": "tinyhealthpotion", "quantity": 2}])
	var panel: Node = (load("res://scene/ui/shop/shopinventory.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.inventory_override = bag
	panel.shop_id = "generalstore"
	var potion: ItemData = ItemRegistry.get_item("tinyhealthpotion")
	panel.show_catalogue({"shop_id": "generalstore", "display_name": "General Store", "price_multiplier": 1.5,
		"sell_multiplier": 0.1, "stock": [
			{"item_id": "tinyhealthpotion", "display_name": "Tiny Health Potion", "price": 333, "tier": 1,
				"type_name": "CONSUMABLE"},
			{"item_id": "tinymanapotion", "display_name": "Tiny Mana Potion", "tier": 1, "type_name": "CONSUMABLE"}],
		"sell_prices": {"tinyhealthpotion": 20}})
	var notice: String = panel.notice_label.text
	check("the shelf says when the owner has the prices away from the usual",
		notice == "Prices today: 150% of the usual.", notice)
	check("  and the store's answer keeps the holder current: its two multipliers",
		is_equal_approx(EconomyRules.number("shop_price_multiplier"), 1.5)
		and is_equal_approx(EconomyRules.number("shop_sell_multiplier"), 0.1))
	var shop_script: Variant = panel.get_script()
	# 333, not the 300 its value at 150% would be: the till's own number wins.
	check("a row's price is the server's own when it sent one",
		shop_script.row_price({"item_id": "tinyhealthpotion", "price": 333}) == 333
		and shop_script.row_price({"item_id": "tinyhealthpotion", "price": 333}, true) == 0)
	var mana: ItemData = ItemRegistry.get_item("tinymanapotion")
	# THE REAL POTIONS (0.74.0, found at the merge in a clone without the art
	# pack): their .tres name pack icons, so without the pack ItemRegistry has
	# no such items and these two are the pack's to judge.
	check_needs_pack("  and for a row without one, its value at the markup in force, the server's way",
		potion != null and mana != null and shop_script.row_price({"item_id": "tinymanapotion"})
		== rules_script.price_for(mana.value if mana != null else 0, 1.5), shop_script.row_price({"item_id": "tinymanapotion"}))
	var drawn: Array[String] = []
	for row in panel.stock_list.get_children():
		var label: Node = row.find_child("price", true, false)
		if label is Label:
			drawn.append((label as Label).text)
	check_needs_pack("  and the shelf draws both", mana != null
		and drawn == ["333 g", "%s g" % GameConstants.commas(rules_script.price_for(mana.value if mana != null else 0, 1.5))],
		drawn)
	panel.set_mode("sell")
	await get_tree().process_frame
	# The Sell list needs something in the bag the shop will buy - the real
	# potion, which a clone without the art pack does not have.
	check_needs_pack("the Sell list's share is the one in force, in words: 10%",
		panel.notice_label.text == "The shop pays 10% of what things are worth.", panel.notice_label.text)
	EconomyRules.adopt({"shop_sell_multiplier": 0.2})
	panel.show_catalogue({"display_name": "General Store", "stock": [], "sell_prices": {"tinyhealthpotion": 40}})
	check_needs_pack("  and for an answer without one, the holder's",
		panel.notice_label.text == "The shop pays 20% of what things are worth.", panel.notice_label.text)
	panel.set_mode("buy")
	panel.show_catalogue({"shop_id": "generalstore", "display_name": "General Store", "price_multiplier": 1.0,
		"sell_multiplier": 0.05, "stock": [{"item_id": "tinyhealthpotion", "display_name": "Tiny Health Potion",
			"price": 200}]})
	check("the usual prices: the shelf says nothing about them", panel.notice_label.text == "", panel.notice_label.text)
	check("the shop reads the rules when it opens, if the login did not",
		_func_body(_code_src("res://src/ui/shop/shopinventory.gd"), "func open_for_shop(").contains("EconomyRules.ensure()"))
	panel.queue_free()
	bag.queue_free()
	EconomyRules.changed.disconnect(on_changed)
	EconomyRules.forget()
	EconomyRules.fetch = kept_fetch
	Api.token = kept_token
	await get_tree().process_frame


# THE ECONOMY TAB (0.74.0). The owner's "max power" economy, on the GM panel:
# "A daily report of where gold comes from and where it goes, by source", the
# numbers "you could adjust ... in a minute", and the canary that "would tell
# you the same day if gold or lusions appear or vanish without being
# recorded". The server decides all three (test_goldflow.py,
# test_economyrules.py, test_canary.py); these hold what the tab shows and
# sends, against stand-in servers.
func _test_the_gm_panel_economy_tab() -> void:
	section("ECONOMY TAB - the gold flow, the economy's numbers and the canary on the GM panel")
	var was_owner: bool = Api.is_owner
	var was_role: String = Api.role
	Api.is_owner = true
	Api.role = "owner"
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var tabs: TabContainer = gm.get_node_or_null("%ownertabs") as TabContainer
	var tab: EconomyTab = gm.get("economy_tab") as EconomyTab
	check("the GM panel has an Economy tab, after Events",
		tabs != null and tab != null and tab.get_parent() == tabs and tabs.get_tab_title(tab.get_index()) == "Economy"
		and tabs.get_tab_title(tab.get_index() - 1) == "Events")
	if tabs == null or tab == null:
		gm.queue_free()
		Api.is_owner = was_owner
		Api.role = was_role
		return
	tabs.current_tab = tab.get_index()
	var widest: float = 0.0
	for which in ["flow", "rules", "canary"]:
		tab.show_page(which)
		await get_tree().process_frame
		widest = maxf(widest, PanelWindow.content_minimum(gm).x)
	check("  and every page of it fits the panel's drawn width (370) - the GM panel is narrow (%d)" % widest,
		widest <= 370.0, widest)
	check("  three pages, one at a time, and nothing in them scrolls (an OptionButton's own list aside)",
		tab.find_children("*", "ScrollContainer", true, false).filter(func(n: Node) -> bool:
			var up: Node = n.get_parent()
			while up != null and up != tab:
				if up is PopupMenu:
					return false
				up = up.get_parent()
			return true).is_empty()
		and tab.pages["canary"].visible and not tab.pages["flow"].visible and not tab.pages["rules"].visible
		and tab.page_buttons["canary"].button_pressed and not tab.page_buttons["flow"].button_pressed,
		[tab.pages["canary"].visible, tab.pages["flow"].visible, tab.page_buttons["canary"].button_pressed])
	tab.show_page("flow")
	check("the panel reads it when it opens, for the owner and a co-owner (is_owner)",
		_func_body(_code_src("res://src/ui/owner/ownerpanel.gd"), "func _on_visibility_changed(").contains(
			"economy_tab.refresh()"))

	var now: int = int(Time.get_unix_time_from_system())
	var today: int = now - now % 86400
	var flow_days: Array = []
	for i in 7:
		var minted: int = [100, 0, 400, 200, 150, 350, 300][i]
		var burned: int = [50, 0, 100, 150, 0, 200, 100][i]
		flow_days.append({"day": Time.get_date_string_from_unix_time(today - (6 - i) * 86400), "start": today - (6 - i) * 86400,
			"minted": minted, "burned": burned, "net": minted - burned, "reasons": {}})
	var flow_view: Variant = JSON.parse_string(JSON.stringify({"days": 7, "from": today - 6 * 86400, "now": now,
		"gold": {"days": flow_days, "minted": 1500, "burned": 600, "net": 900,
			"reasons": [{"reason": "pile", "minted": 1200, "burned": 0, "net": 1200, "rows": 40},
				{"reason": "kingdom_tax", "minted": 0, "burned": 400, "net": -400, "rows": 8},
				{"reason": "shop_sell", "minted": 300, "burned": 0, "net": 300, "rows": 5},
				{"reason": "shop_buy", "minted": 0, "burned": 200, "net": -200, "rows": 2}],
			"in_world": {"carried": 100000, "banked": 23456, "total": 123456}},
		"lusions": {"days": [], "minted": 30, "burned": 25, "net": 5, "reasons": [], "in_world": {"total": 1234}}}))
	var rule_rows: Array = [
		{"key": "trade_tax_rate", "value": 0.05, "default": 0.05, "min": 0.0, "max": 0.5, "whole": false,
			"about": "Share of a trade's value burned as the kingdom tax.", "set": false, "updated_at": null, "updated_by": ""},
		{"key": "trade_tax_minimum", "value": 1.0, "default": 1.0, "min": 1.0, "max": 10000.0, "whole": true,
			"about": "The smallest kingdom tax a taxed trade pays, in gold.", "set": false, "updated_at": null, "updated_by": ""},
		{"key": "shop_price_multiplier", "value": 1.25, "default": 1.0, "min": 0.25, "max": 4.0, "whole": false,
			"about": "The general store's prices, times the item's value.", "set": true, "updated_at": now - 60,
			"updated_by": "Tunacan"}]
	var rules_view: Variant = JSON.parse_string(JSON.stringify({"rules": rule_rows, "can_change": true,
		"cache_seconds": 15, "changes": [{"at": now - 60, "key": "shop_price_multiplier", "old_value": null,
			"new_value": 1.25, "by": "Tunacan"}]}))
	var canary_view: Variant = JSON.parse_string(JSON.stringify({"checked_at": now - 720, "ok": true, "failures": [],
		"checks": [{"name": "gold conservation (ledger == held)", "ok": true, "detail": "recorded 5, held 5, drift 0"}],
		"age_seconds": 720, "stale": false, "mail": "already told"}))
	var asked: Array = []
	var views: Dictionary = {"flow": {"ok": true, "status": 200, "data": flow_view},
		"rules": {"ok": true, "status": 200, "data": rules_view}, "canary": {"ok": true, "status": 200, "data": canary_view}}
	tab.fetch = func(path: String) -> Dictionary:
		asked.append(path)
		return views["flow" if path.begins_with(EconomyTab.FLOW_PATH) else ("rules" if path == EconomyTab.RULES_PATH else "canary")]
	var sent: Array = []
	var check_answer: Array = [{"ok": true, "status": 200, "data": {"checked_at": now, "ok": true, "failures": [],
		"checks": []}}]
	tab.send = func(path: String, body: Dictionary) -> Dictionary:
		sent.append([path, body])
		return check_answer[0]
	var put: Array = []
	var put_answer: Array = [{}]
	tab.put_request = func(path: String, body: Dictionary) -> Dictionary:
		put.append([path, body])
		return put_answer[0]
	await tab.refresh()
	check("opened, it reads the flow (a week), the rules and the canary",
		asked == ["/api/owner/economy/flow?days=7", "/api/owner/economy/rules", "/api/owner/economy/canary"], asked)
	# FULL, NOT EMPTY: the panel's own layout test measures the tabs before
	# anything is read; filled, every page must still fit the drawn window,
	# 370 by 626, so reading the server never resizes it under the mouse.
	for key in tab.pages:
		(tab.pages[key] as Control).visible = false
	await get_tree().process_frame
	var without_it: float = tabs.get_combined_minimum_size().y
	# THE BUSIEST FLOW THERE IS: every number in the millions and more
	# sources and sinks than a line names, so every line wraps as far as it can.
	var busy: Dictionary = (flow_view as Dictionary).duplicate(true)
	busy["gold"]["in_world"] = {"carried": 41288012, "banked": 109341077, "total": 150629089}
	busy["gold"]["minted"] = 29550123
	busy["gold"]["burned"] = 27500456
	busy["gold"]["net"] = 2049667
	busy["gold"]["reasons"] = []
	for reason in ["royal_certification", "smith_temper", "kingdom_tax", "shop_buy", "revive", "death"]:
		busy["gold"]["reasons"].append({"reason": reason, "minted": 0, "burned": 1234567, "rows": 9})
	for reason in ["shop_sell", "staff_gold", "pile", "opening_balance", "dupe_pet"]:
		busy["gold"]["reasons"].append({"reason": reason, "minted": 2345678, "burned": 0, "rows": 9})
	busy["lusions"] = {"minted": 123456, "burned": 234567, "in_world": {"total": 3456789}}
	tab.show_flow(busy)
	tab._say_here("This server does not have the canary's Check now yet (404). Update the server, then Refresh.")
	var filled: Array = []
	for which in ["flow", "rules", "canary"]:
		tab.show_page(which)
		await get_tree().process_frame
		filled.append(Vector2(PanelWindow.content_minimum(gm).x, tabs.get_combined_minimum_size().y))
	tab.show_page("flow")
	tab.show_flow(flow_view)
	tab._say_here("")
	check("  and filled with the server's answers, every page still fits: 370 wide, no taller than the other tabs (%d)"
		% without_it, filled.all(func(need: Vector2) -> bool: return need.x <= 370.0 and need.y <= without_it + 0.5),
		filled)

	# --- GOLD FLOW -----------------------------------------------------------------
	check("the flow: each day drawn, minted against burned",
		tab.chart.days.size() == 7 and int(tab.chart.days[2]["minted"]) == 400 and int(tab.chart.days[3]["net"]) == 50)
	check("  the window's totals, and what the world holds now",
		tab.totals_label.text == "Minted 1,500 - burned 600 - net +900."
		and tab.world_label.text == "Held now: 123,456 (100,000 carried, 23,456 banked).",
		[tab.totals_label.text, tab.world_label.text])
	check("  where it came from and where it went, by source, the most first, in the owner's words",
		tab.sources_label.text == "Came from: gold piles 1,200, sold to the shop 300."
		and tab.sinks_label.text == "Went to: trade tax 400, bought from the shop 200.",
		[tab.sources_label.text, tab.sinks_label.text])
	check("  and lusions in a line", tab.lusions_label.text == "Lusions: 30 in, 25 out, 1,234 held.", tab.lusions_label.text)
	var many: Array = []
	for i in 6:
		many.append({"reason": "reason_%d" % i, "minted": 10 * (6 - i), "burned": 0})
	check("  more than three sources are three and a count", EconomyTab.reasons_text("Came from", many, "minted")
		== "Came from: reason 0 60, reason 1 50, reason 2 40, and 3 more."
		and EconomyTab.reasons_text("Went to", many, "burned") == "Went to: nothing.")
	var last_day: Array[String] = tab.chart.tooltip_lines(6)
	check("the chart's hover says the day and its three numbers",
		last_day == [GoldFlowChart.short_day(str(flow_days[6]["day"])) + " (UTC)", "Minted 300", "Burned 100", "Net +200"],
		last_day)
	check("  its axis ends at clean numbers, zero between minted and burned",
		tab.chart.scale() == Vector2i(500, 200) and GoldFlowChart.nice(0) == 0 and GoldFlowChart.nice(7) == 10
		and GoldFlowChart.nice(1200) == 2000 and GoldFlowChart.nice(5000) == 5000, tab.chart.scale())
	check("  its ticks are compact", GoldFlowChart.compact(900) == "900" and GoldFlowChart.compact(1200) == "1.2K"
		and GoldFlowChart.compact(12000) == "12K" and GoldFlowChart.compact(-3400000) == "-3.4M")
	check("  and a day as the owner reads it", GoldFlowChart.short_day("2026-10-22") == "Oct 22"
		and GoldFlowChart.short_day("soon") == "soon")
	tab.chart.size = Vector2(300, 94)
	check("  the mouse finds the day under it, and nothing off the plot",
		tab.chart.day_under(GoldFlowChart.PAD_LEFT + 1.0) == 0 and tab.chart.day_under(290.0) == 6
		and tab.chart.day_under(2.0) == -1 and tab.chart.day_under(299.0) == -1,
		[tab.chart.size, tab.chart.day_under(GoldFlowChart.PAD_LEFT + 1.0), tab.chart.day_under(290.0)])
	tab.days_pick.select(tab.days_pick.get_item_index(30))
	tab.days_pick.item_selected.emit(tab.days_pick.selected)
	await get_tree().process_frame
	check("picking 30 days asks for 30", asked.back() == "/api/owner/economy/flow?days=30", asked.back())

	# --- RULES ---------------------------------------------------------------------
	check("the rules: one row each, its number, its bounds beside it",
		tab.rule_boxes.size() == 3 and is_equal_approx((tab.rule_boxes["shop_price_multiplier"] as SpinBox).value, 1.25)
		and (tab.rule_bounds["trade_tax_rate"] as Label).text == "0-0.5"
		and is_equal_approx((tab.rule_boxes["trade_tax_rate"] as SpinBox).max_value, 0.5)
		and is_equal_approx((tab.rule_boxes["trade_tax_minimum"] as SpinBox).step, 1.0))
	check("  the owner may edit; Usual only where the owner set one; the last change said",
		(tab.rule_boxes["trade_tax_rate"] as SpinBox).editable and not (tab.rule_set_buttons["trade_tax_rate"] as Button).disabled
		and (tab.rule_usual_buttons["trade_tax_rate"] as Button).disabled
		and not (tab.rule_usual_buttons["shop_price_multiplier"] as Button).disabled
		and tab.last_change_label.text == "Last change: Shop prices usual -> 1.25, by Tunacan.", tab.last_change_label.text)
	check("  each row's hint: what it does, its bounds and the usual, and who set it",
		EconomyTab.rule_hint(rule_rows[2]) == "The general store's prices, times the item's value.\nFrom 0.25 to 4. The usual: 1.\nSet by Tunacan.")
	var after_set: Dictionary = (rules_view as Dictionary).duplicate(true)
	after_set["rules"][0]["value"] = 0.1
	after_set["rules"][0]["set"] = true
	after_set["changed"] = true
	put_answer[0] = {"ok": true, "status": 200, "data": after_set}
	(tab.rule_boxes["trade_tax_rate"] as SpinBox).value = 0.1
	var kept_rules: Dictionary = EconomyRules.numbers.duplicate()
	await tab.set_rule("trade_tax_rate")
	check("Set sends that one rule, by key, to the owner's PUT",
		put == [["/api/owner/economy/rules", {"key": "trade_tax_rate", "value": 0.1}]], put)
	check("  and says what it is now, here and in Results, and how soon every game hears it",
		tab.say_label.text == "Trade tax is now 0.1."
		and gm.results.get_parsed_text().contains("Trade tax is now 0.1 - every game within 15 seconds."),
		[tab.say_label.text, gm.results.get_parsed_text()])
	check("  and the owner's own game draws with it at once", is_equal_approx(EconomyRules.number("trade_tax_rate"), 0.1))
	var back: Dictionary = (rules_view as Dictionary).duplicate(true)
	back["changed"] = true
	put_answer[0] = {"ok": true, "status": 200, "data": back}
	await tab.usual_rule("trade_tax_rate")
	check("Usual sends null - the game's own number back", put.back() == ["/api/owner/economy/rules",
		{"key": "trade_tax_rate", "value": null}] and tab.say_label.text == "Trade tax is back to the usual, 0.05.",
		[put.back(), tab.say_label.text])
	put_answer[0] = {"ok": false, "status": 400, "error": "Bad Request",
		"data": {"error": "Bad Request", "message": "trade_tax_rate must be from 0 to 0.5 (you sent 0.9)."}}
	await tab.set_rule("trade_tax_rate")
	check("  a refusal says the server's own words",
		tab.say_label.text == "The server refused (400): trade_tax_rate must be from 0 to 0.5 (you sent 0.9).", tab.say_label.text)
	var co_view: Dictionary = (rules_view as Dictionary).duplicate(true)
	co_view["can_change"] = false
	tab.show_rules(co_view)
	var before_co: int = put.size()
	await tab.set_rule("trade_tax_rate")
	check("a co-owner reads them and cannot change them: nothing editable, nothing sent",
		not (tab.rule_boxes["trade_tax_rate"] as SpinBox).editable and (tab.rule_set_buttons["trade_tax_rate"] as Button).disabled
		and (tab.rule_usual_buttons["shop_price_multiplier"] as Button).disabled and put.size() == before_co
		and tab.rules_status.text.contains("the owner changes them") and tab.say_label.text.begins_with("Only the owner"),
		[put.size(), tab.say_label.text])
	EconomyRules.numbers = kept_rules

	# --- CANARY --------------------------------------------------------------------
	check("the canary: the last hourly check, how long ago, and what it found",
		tab.canary_status.text == "Every number adds up." and tab.canary_when.text.begins_with("Last hourly check: ")
		and tab.canary_when.text.contains("12m ago") and tab.canary_checks.text.begins_with("hold  gold conservation"),
		[tab.canary_status.text, tab.canary_when.text])
	tab.show_canary({"checked_at": now - 3 * 3600, "ok": false, "age_seconds": 3 * 3600, "stale": true, "mail": "not configured",
		"failures": [{"name": "gold conservation (ledger == held)", "detail": "recorded 0, held 5, drift 5"}], "checks": []})
	check("  broken: what broke and by how much; a timer that looks stopped; no mail set up, said",
		tab.canary_status.text == "BROKEN: gold conservation (ledger == held) (recorded 0, held 5, drift 5)."
		and tab.canary_when.text.contains("the timer may have stopped") and tab.canary_when.text.contains("No mail is set up"),
		[tab.canary_status.text, tab.canary_when.text])
	tab.show_canary({"checked_at": null, "ok": null, "failures": [], "checks": []})
	check("  never run: says the timer has not run, and where it is set up",
		tab.canary_status.text.begins_with("Never checked") and tab.canary_when.text.contains("update_server.sh"))
	await tab.check_now()
	check("Check now: POSTs to the canary and says what it found",
		sent == [["/api/owner/economy/canary", {}]] and tab.say_label.text == "Checked now: every number adds up.", sent)
	check_answer[0] = {"ok": true, "status": 200, "data": {"checked_at": now, "ok": false, "checks": [],
		"failures": [{"name": "lusion conservation (ledger == held)", "detail": "recorded 3, held 5, drift 2"}]}}
	await tab.check_now()
	check("  and when the books are broken, which and by how much - in Results too",
		tab.say_label.text == "Checked now: 1 check broke - lusion conservation (ledger == held) (recorded 3, held 5, drift 2)."
		and gm.results.get_parsed_text().contains("Checked now: 1 check broke - lusion conservation"), tab.say_label.text)

	# --- AN OLDER SERVER ----------------------------------------------------------
	views["flow"] = {"ok": false, "status": 404, "error": "Not found."}
	await tab.refresh_flow()
	check("a server from before the Economy tab: says to update it", tab.say_label.text
		== "This server does not have the gold flow yet (404). Update the server, then Refresh."
		and tab.chart.days.is_empty(), tab.say_label.text)
	Api.is_owner = was_owner
	Api.role = was_role
	gm.queue_free()
	await get_tree().process_frame


# THE HEALTH TAB (0.78.0). The owner, of the four next steps after the swarm:
# "work on this or if you have a even better idea lets hear it". The live
# server on the GM panel - players and crowds, data out and the month it adds
# up to, the tick, the machine, the slowest routes - and the kill receipts
# put to the server's own count, with the switch beside them. The API's half
# is test_serverhealth.py and test_presence.py P-13.
func _test_the_gm_panel_health_tab() -> void:
	section("HEALTH TAB - the live server and the kill receipts on the GM panel")
	var was_owner: bool = Api.is_owner
	var was_role: String = Api.role
	Api.is_owner = true
	Api.role = "owner"
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var tabs: TabContainer = gm.get_node_or_null("%ownertabs") as TabContainer
	var tab: HealthTab = gm.get("health_tab") as HealthTab
	check("the GM panel has a Health tab, after Economy",
		tabs != null and tab != null and tab.get_parent() == tabs and tabs.get_tab_title(tab.get_index()) == "Health"
		and tabs.get_tab_title(tab.get_index() - 1) == "Economy")
	if tabs == null or tab == null:
		gm.queue_free()
		Api.is_owner = was_owner
		Api.role = was_role
		return
	tab.timer.stop()
	tabs.current_tab = tab.get_index()
	check("the panel reads it when it opens, for the owner and a co-owner (is_owner)",
		_func_body(_code_src("res://src/ui/owner/ownerpanel.gd"), "func _on_visibility_changed(").contains(
			"health_tab.refresh()"))
	check("  and every REFRESH_SECONDS (%d) while it is on screen, quietly" % int(HealthTab.REFRESH_SECONDS),
		HealthTab.REFRESH_SECONDS == 30.0 and tab.timer.wait_time == 30.0
		and _func_body(_code_src("res://src/ui/owner/healthtab.gd"), "func _on_timer(").contains("is_visible_in_tree()"))

	var now: int = int(Time.get_unix_time_from_system())
	var view: Variant = JSON.parse_string(JSON.stringify({"now": now,
		"presence": {"reporting": true,
			"last": {"at": now - 20, "age_seconds": 20, "reporting": true, "connections": 12, "players": 9,
				"areas": 3, "crowd": [["town", 7], ["big_field", 2]], "ticks_per_second": 10.0, "late_ticks": 0,
				"bytes_per_second": 900000.0, "net_per_second": 1200000.0, "cpu": 4.0, "load1": 0.31,
				"mem_free_mb": 412},
			"day": {"samples": 900, "peak_players": 19, "peak_area": "big_field", "peak_area_players": 11, "late_ticks": 0},
			"week": {"samples": 6000, "peak_players": 40, "peak_area": "big_field", "peak_area_players": 34, "late_ticks": 3}},
		"month": {"source": "machine", "bytes_per_second": 200000.0, "gib": 520.4, "allowance_gib": 1000,
			"share": 0.52, "over_cost": 0.0},
		"budget": {"on": true, "level": "full", "crowd_cap": null, "allowance_gib": 1000, "used_gib": 12.345,
			"since": now - 86400 * 3, "affordable_per_second": 390000.0},
		"crowd": {"verdict": "watch", "by": "crowd", "watch_at": 32, "now_at": 96},
		"tick": {"verdict": "steady", "per_second": 10.0, "late_today": 0},
		"machine": {"cores": 1, "load1": 0.31, "mem_free_mb": 412, "disk_free_gb": 18.2, "disk_total_gb": 24.9,
			"db_mb": 120.4},
		"routes": {"uptime_seconds": 7200, "requests": 5000, "errors": 0, "slowest": [
			{"route": "POST login", "p99_ms": 98.0, "count": 40}, {"route": "POST combat_kill", "p99_ms": 12.4, "count": 900},
			{"route": "PUT save", "p99_ms": 9.0, "count": 800}, {"route": "GET status", "p99_ms": 2.0, "count": 70}]},
		"receipts": {"on": false, "verdict": "ready", "days": 7, "paid": 412, "backed": 405, "share": 0.983,
			"short": 2, "not_due": 0, "never": 5, "never_by_enemy": [["slime", 3], ["bat", 2]], "books_days": 7.0,
			"min_client_build": 0, "receipt_build": 7, "min_build_low": true, "ready_share": 0.98, "min_kills": 200,
			"as_of": now}}))
	var asked: Array = []
	var answers: Array = [{"ok": true, "status": 200, "data": view}]
	tab.fetch = func(path: String) -> Dictionary:
		asked.append(path)
		await get_tree().process_frame
		return answers[0]
	# Empty, measured as the other tabs are; then filled.
	for key in tab.pages:
		(tab.pages[key] as Control).visible = false
	await get_tree().process_frame
	var without_it: float = tabs.get_combined_minimum_size().y
	await tab.refresh()
	check("opened, it reads the server's health - the receipts as kept, not fresh", asked == ["/api/server/health"], asked)
	check("  the players: online, in an area, the biggest crowd; the most today and this week",
		tab.players_label.text == "12 online, 9 in an area; the biggest crowd: town, 7. Most today: 19 (big field 11). This week: 40 (big field 34).",
		tab.players_label.text)
	check("  the data going out: the machine's own, and the sockets' share",
		tab.data_label.text == "Now 1.2 MB/s from the machine, 900 KB/s of it the game's sockets (before a browser's compression).",
		tab.data_label.text)
	check("  the month at this week's rate, against what the droplet includes",
		tab.month_label.text == "A month at this week's rate: 520 GiB of the 1,000 included."
		and tab.month_label.get_theme_color("font_color") == HealthTab.SAY_WARN, tab.month_label.text)
	check("  the data guard: holding the month under the plan, the month counted, what it can still send",
		tab.guard_label.text == "Data guard: full speed. Counted this month: 12 GiB since %s; it can send 390 KB/s to the month's end." % LocalTime.date(now - 86400 * 3)
		and tab.guard_label.get_theme_color("font_color") == HealthTab.SAY_GOOD, tab.guard_label.text)
	check("  whether one area needs sending only what is near yet, and why",
		tab.nearby_label.text == "Sending each game only nearby players: worth planning - an area held 32 or more this week.",
		tab.nearby_label.text)
	check("  the tick and the machine",
		tab.tick_label.text == "Tick: 10.0 a second, steady. Late beats today: 0."
		and tab.machine_label.text == "Load 0.31 on 1 core, 412 MB memory free, disk 18.2 of 24.9 GB free, the database 120 MB.",
		[tab.tick_label.text, tab.machine_label.text])
	check("  the slowest three routes by p99, as words, and the errors - one worker's",
		tab.routes_label.text == "p99: login 98 ms, combat kill 12 ms, save 9.0 ms. No server errors in 2h 00m, one worker's.",
		tab.routes_label.text)
	check("the receipts: the verdict, the week in a line, the monsters never seen by name",
		tab.verdict_label.text == "Ready to switch on: a week of honest play is backed by the server's count."
		and tab.detail_label.text == "Of 412 kills paid in the last 7 days, 405 (98.3%%) had the server's count; 2 short, 0 not due, 5 never seen (%s 3, %s 2)." % [
			EnemyPortraits.display_name("slime"), EnemyPortraits.display_name("bat")]
		and tab.verdict_label.get_theme_color("font_color") == HealthTab.SAY_GOOD, [tab.verdict_label.text, tab.detail_label.text])
	check("  and, ready with the oldest build allowed in below 7, that it has to go first",
		tab.build_label.text.begins_with("Set Old versions must update to 7 first"), tab.build_label.text)
	check("  the switch beside them shows the server's, the owner's to throw",
		not tab.receipts_switch.button_pressed and not tab.receipts_switch.disabled)

	# FULL, IT STILL FITS: 370 wide, no taller than the other tabs.
	var busy: Dictionary = (view as Dictionary).duplicate(true)
	busy["presence"]["reporting"] = false
	busy["presence"]["last"]["age_seconds"] = 7200
	busy["presence"]["last"]["crowd"] = [["the_longest_area_name_there_is", 128]]
	busy["month"]["share"] = 34.1
	busy["month"]["gib"] = 34100.0
	busy["month"]["over_cost"] = 331.0
	busy["budget"] = {"on": true, "level": "alone", "crowd_cap": 1, "allowance_gib": 1000, "used_gib": 949.87,
		"since": now - 86400 * 29, "affordable_per_second": -5.0}
	busy["receipts"]["verdict"] = "monster"
	busy["receipts"]["never_by_enemy"] = [["elementallordboss", 9999], ["slime", 999], ["bat", 99]]
	busy["receipts"]["paid"] = 123456
	busy["receipts"]["min_build_low"] = true
	tab.show_answer(busy)
	tab._say_here("This server does not have the Health tab yet (404). Update the server, then Refresh.")
	var filled: Array = []
	for which in ["players", "data", "machine", "receipts"]:
		tab.show_page(which)
		await get_tree().process_frame
		filled.append(Vector2(PanelWindow.content_minimum(gm).x, tabs.get_combined_minimum_size().y))
	check("  filled to the brim, every page fits: 370 wide, no taller than the other tabs (%d)" % without_it,
		filled.all(func(need: Vector2) -> bool: return need.x <= 370.0 and need.y <= without_it + 0.5), filled)
	check("  and nothing in it scrolls; one page at a time",
		tab.find_children("*", "ScrollContainer", true, false).is_empty()
		and tab.pages["receipts"].visible and not tab.pages["players"].visible and not tab.pages["machine"].visible
		and not tab.pages["data"].visible
		and tab.page_buttons["receipts"].button_pressed and not tab.page_buttons["players"].button_pressed)
	tab.show_page("players")
	check("presence gone quiet: said, in red, with how long",
		tab.players_label.text.begins_with("presence.py has not written for 2h 00m - is it running?")
		and tab.players_label.get_theme_color("font_color") == HealthTab.SAY_BAD, tab.players_label.text)
	check("  the guard at its hardest: players alone, in red, and nothing left to send said by leaving it out",
		tab.guard_label.text.begins_with("Data guard: the month's data is nearly spent - players do not see each other")
		and tab.guard_label.text.ends_with("GiB since %s." % LocalTime.date(now - 86400 * 29))
		and tab.guard_label.get_theme_color("font_color") == HealthTab.SAY_BAD, tab.guard_label.text)
	check("  a month past what is included: what it would cost, in red",
		tab.month_label.text == "A month at this week's rate: 34,100 GiB of the 1,000 included - about $331 over."
		and tab.month_label.get_theme_color("font_color") == HealthTab.SAY_BAD, tab.month_label.text)
	tab._say_here("")

	# REFRESH, BY HAND: fresh receipts, and Results told.
	asked.clear()
	await tab.refresh(true)
	check("Refresh asks for the receipts fresh, and says what it read in Results",
		asked == ["/api/server/health?fresh=1"] and tab.say_label.text == "Read from the server."
		and gm.results.get_parsed_text().contains("Read from the server. 12 online"), asked)

	# THE SWITCH, FROM HERE: the Testing tab's handler, and both show it.
	var posted: Array = []
	gm.post_request = func(path: String, body: Dictionary) -> Dictionary:
		posted.append([path, body])
		await get_tree().process_frame
		return {"ok": true, "data": {"kill_receipts": true, "min_client_build": 7}}
	var testing_switch: CheckButton = gm.get_node_or_null("%receiptsbutton") as CheckButton
	answers[0] = {"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(view))}
	answers[0]["data"]["receipts"]["on"] = true
	answers[0]["data"]["receipts"]["verdict"] = "on"
	answers[0]["data"]["receipts"]["min_build_low"] = false
	tab.receipts_switch.button_pressed = true
	await get_tree().create_timer(0.1).timeout
	check("switched on from the Health tab: the owner's route, through the Testing tab's own handler",
		posted == [["/api/server/receipts", {"on": true}]], posted)
	check("  and both switches show it on; the tab reads again and says on",
		testing_switch != null and testing_switch.button_pressed and tab.receipts_switch.button_pressed
		and tab.verdict_label.text == "On: kills are paid only when the server's count agrees." and tab.build_label.text == "",
		[str(testing_switch.button_pressed) if testing_switch != null else "no switch", tab.verdict_label.text])
	gm.status_request = func(_path: String) -> Dictionary:
		await get_tree().process_frame
		return {"ok": true, "data": {"kill_receipts": false}}
	await gm._refresh_receipts()
	check("  thrown back elsewhere, the panel's read of it puts the Health tab's back too",
		not tab.receipts_switch.button_pressed and not testing_switch.button_pressed)
	Api.is_owner = false
	tab.show_switch(false)
	check("  a co-owner sees it, and cannot throw it", tab.receipts_switch.disabled)
	Api.is_owner = true

	# THE VERDICTS, EACH IN WORDS.
	check("every verdict in a sentence: no books, young, few, short, monster",
		HealthTab.verdict_text({"verdict": "no_books"}) == "Not yet: the server has not counted a fight yet."
		and HealthTab.verdict_text({"verdict": "young", "books_days": 3.5}) == "Not yet: the server has counted fights for 3.5 days; a week is wanted."
		and HealthTab.verdict_text({"verdict": "few", "paid": 12, "min_kills": 200}) == "Not yet: 12 kills paid this week; 200 are wanted to judge by."
		and HealthTab.verdict_text({"verdict": "short", "share": 0.9545, "ready_share": 0.98}) == "Not yet: 95.5% of kills had the server's count; 98% is wanted."
		and HealthTab.verdict_text({"verdict": "monster", "never_by_enemy": [["bat", 11]]}).begins_with(
			"Not yet: the server never saw %s die 11 times" % EnemyPortraits.display_name("bat")))
	check("  the crowd's: fine, watch by the data, now; nothing measured",
		HealthTab.nearby_text({"verdict": "fine", "watch_at": 32}) == "Sending each game only nearby players: not needed yet (watch from 32 in one area)."
		and HealthTab.nearby_text({"verdict": "watch", "by": "data"}).ends_with("the month is past half the data included.")
		and HealthTab.nearby_text({"verdict": "now", "by": "crowd", "now_at": 96}).ends_with("needed now - an area held 96 or more this week.")
		and HealthTab.nearby_text({}) == "Sending each game only nearby players: not enough measured yet.")
	check("  the guard's every level: half, a crowd cap, switched off, an older server",
		HealthTab.guard_text({"on": true, "level": "half"}) == "Data guard: holding - other players' steps at half rate, to stay under the plan."
		and HealthTab.guard_text({"on": true, "level": "crowd", "crowd_cap": 16}) == "Data guard: holding hard - half rate, and at most 16 players see each other in one area."
		and HealthTab.guard_text({"on": false}).begins_with("Data guard: switched off")
		and HealthTab.guard_text({}) == "Data guard: not on this server yet."
		and HealthTab.guard_colour({"on": true, "level": "half"}) == HealthTab.SAY_WARN)
	check("  rates in KB/s and MB/s, decimal, as the swarm said them",
		HealthTab.rate_text(200.0) == "0.2 KB/s" and HealthTab.rate_text(850000.0) == "850 KB/s"
		and HealthTab.rate_text(13400000.0) == "13.4 MB/s")
	check("  a server whose machine cannot be read (Windows): the sockets alone, said so",
		HealthTab.data_text({"presence": {"last": {"bytes_per_second": 5000.0, "net_per_second": null}}})
		== "Now 5.0 KB/s from the game's sockets (the machine's own network cannot be read here)."
		and HealthTab.month_text({"gib": 3.26, "allowance_gib": 1000, "over_cost": 0.0, "source": "presence"})
		== "A month at this week's rate: 3.3 GiB of the 1,000 included (the sockets alone).")
	check("  before presence.py has written a minute: says so",
		HealthTab.players_text({"presence": {"reporting": false, "last": null}}).begins_with("presence.py has not written a minute yet"))

	# AN OLDER SERVER.
	answers[0] = {"ok": false, "status": 404, "error": "Not found."}
	await tab.refresh(true)
	check("a server from before the Health tab: says to update it",
		tab.say_label.text == "This server does not have the Health tab yet (404). Update the server, then Refresh.",
		tab.say_label.text)
	Api.is_owner = was_owner
	Api.role = was_role
	gm.queue_free()
	await get_tree().process_frame


# THE CO-OWNERS (0.21.0). The owner: "i would promote allmind to owner but
# there can only be 1 however thats why i want to build another gate that
# allows him to enter", "maybe a switch in my gm panel that gives him access as
# long as i leave it on", and "i also need the ability to set a players level
# so they can try out the game". The server decides (test_coowner.py); these
# hold the game's half: the rank, the badge, the switch, the doors, the level.
func _test_coowners_and_their_levels() -> void:
	section("CO-OWNERS - the owner's switch, the rank, the doors, and a player's level")
	var was_owner: bool = Api.is_owner
	var was_role: String = Api.role
	var was_name: String = Api.username

	# --- THE RANK ---------------------------------------------------------------
	check("the ladder has the co-owner between dev and owner, as app.py's ROLES",
		Api.RANK_ORDER == PackedStringArray(["player", "mod", "dev", "coowner", "owner"]))
	Api.is_owner = true
	Api.role = "coowner"
	check("a co-owner has the owner's powers (is_owner) and is not THE owner",
		Api.own_rank() == "coowner" and not Api.is_the_owner()
		and Api.role_at_least("dev") and Api.role_at_least("coowner") and not Api.role_at_least("owner"))
	check("  god mode and the always-roll switches are his", Api.role_at_least(Api.GOD_MODE_MIN_ROLE))
	Api.role = "owner"
	check("the owner is the owner", Api.own_rank() == "owner" and Api.is_the_owner())
	check("a co-owner reads as a person says it", Api.rank_name("coowner") == "co-owner"
		and Api.rank_name("dev") == "dev")
	check("he wears CO-OWNER in the owner's gold, and only the owner the crown",
		NameTag.badge("coowner") == "CO-OWNER" and not NameTag.wears_crown("coowner")
		and NameTag.wears_crown("owner") and NameTag.badge_colour("coowner") == NameTag.badge_colour("owner"))
	var chat_script: Variant = load("res://src/ui/chat/chatpanel.gd")
	var desk_script: Variant = load("res://src/ui/staff/staffpanel.gd")
	check("the chat menu and the staff desk rank him on the same ladder",
		chat_script.rank_at("coowner") == 3 and desk_script.rank_index("coowner") == 3)
	var on_him: Dictionary = desk_script.actions_for("owner", {"role": "coowner", "actionable": true})
	check("the owner can kick him from the desk, and is not offered a demotion that would not move him",
		on_him["kick"] and on_him["demote_to"] == "" and on_him["promote_to"] == "", on_him)
	var by_him: Dictionary = desk_script.actions_for("coowner", {"role": "dev", "actionable": true})
	check("  and he can demote a dev, and promote nobody to a rank that is not grantable",
		by_him["demote_to"] == "mod" and by_him["promote_to"] == "", by_him)

	# --- THE GM PANEL -------------------------------------------------------------
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var switch: CheckButton = gm.get_node_or_null("%coownerbutton") as CheckButton
	var line: Label = gm.get_node_or_null("%coownerstatus") as Label
	var server_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/server")
	check("the Server tab has the co-owners' switch, with a line saying where it stands",
		switch != null and line != null and server_tab != null and server_tab.is_ancestor_of(switch)
		and server_tab.is_ancestor_of(line) and switch.text == "Co-owners in")
	if switch == null or line == null:
		gm.queue_free()
		Api.is_owner = was_owner
		Api.role = was_role
		return
	var got: Array = []
	var posted: Array = []
	var state: Array = [{"ok": true, "data": {"on": false, "names": ["AllMind"]}}]
	var post_answer: Array = [{"ok": true, "data": {"on": true, "names": ["AllMind"]}}]
	gm.coowner_request = func(path: String) -> Dictionary:
		got.append(path)
		await get_tree().process_frame
		return state[0]
	gm.post_request = func(path: String, body: Dictionary) -> Dictionary:
		posted.append([path, body])
		await get_tree().process_frame
		return post_answer[0]
	Api.is_owner = true
	Api.role = "owner"
	await gm.refresh_coowners()
	check("it asks the server, shows off, and says who it would let in",
		got == ["/api/server/coowners"] and not switch.button_pressed and not switch.disabled
		and line.text == "AllMind: out - just their own rank.", line.text)
	switch.button_pressed = true
	await get_tree().process_frame
	await get_tree().process_frame
	check("the owner throws it: on, to the switch route",
		posted.size() == 1 and posted[0][0] == "/api/server/coowners" and posted[0][1] == {"on": true}
		and switch.button_pressed and line.text.begins_with("AllMind: in"), [posted, line.text])
	check("  and the box says what that means",
		gm.results.get_parsed_text().contains("AllMind can use everything you can now"), gm.results.get_parsed_text())
	Api.role = "coowner"
	state[0] = {"ok": true, "data": {"on": true, "names": ["AllMind"]}}
	await gm.refresh_coowners()
	check("a co-owner sees it on, and cannot move it", switch.button_pressed and switch.disabled)
	switch.set_pressed_no_signal(false)
	gm._on_coowner_toggled(false)
	await get_tree().process_frame
	await get_tree().process_frame
	check("  even past the disabled button: nothing is sent, and it is put back",
		posted.size() == 1 and switch.button_pressed
		and gm.results.get_parsed_text().contains("Only the owner lets co-owners in"), posted.size())
	Api.role = "owner"
	state[0] = {"ok": true, "data": {"on": false, "names": []}}
	await gm.refresh_coowners()
	check("nobody named: the switch cannot be turned on, and the line says where to name them",
		switch.disabled and line.text.contains("ELUSION_CO_OWNERS"), line.text)
	state[0] = {"ok": false, "status": 404, "error": "Not found."}
	await gm.refresh_coowners()
	check("a server from before has no switch, and says so", switch.disabled
		and line.text == "This server has no co-owner switch yet.", line.text)
	check("the lines are short enough not to stretch the panel",
		[gm.coowner_line({"names": ["AllMind"], "on": true}), gm.coowner_line({"names": []}),
			gm.coowner_line({}, true)].all(func(t: String) -> bool: return t.length() <= 52))
	var ranks: Array = []
	for rank in ["owner", "coowner"]:
		Api.role = rank
		gm._populate_ranks()
		var offered: Array = []
		for i in gm.role_option.item_count:
			offered.append(gm.role_option.get_item_text(i))
		ranks.append(offered)
	check("the rank picker offers player, mod and dev - to the owner and to a co-owner - never co-owner",
		ranks == [["player", "mod", "dev"], ["player", "mod", "dev"]], ranks)
	Api.role = "owner"
	gm.queue_free()
	await get_tree().process_frame

	# --- THE DOORS FOLLOW THE SWITCH ------------------------------------------------
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var row: Control = hud.get_node_or_null("%staffrow") as Control
	Api.is_owner = false
	Api.role = "dev"
	hud._add_owner_button()
	check("a dev named in the .env, switched off, has the Staff button and no Owner button",
		row.visible and not row.has_node("ownerbutton"))
	Api.is_owner = true
	Api.role = "coowner"
	hud._on_rank_changed("AllMind", "coowner")
	check("the heartbeat lets him in: Owner and Powers appear, without signing in again",
		row.has_node("ownerbutton") and row.has_node("powersbutton"))
	Api.is_owner = false
	Api.role = "dev"
	hud._on_rank_changed("AllMind", "dev")
	check("switched off: they go again, and the Staff button stays",
		not row.has_node("ownerbutton") and not row.has_node("powersbutton") and row.visible)
	hud.free()
	check("the Powers window says co-owner", _code_src("res://src/ui/characterhud.gd").contains(
		"Api.rank_name(str(entry.get(\"rank\", \"?\"))).to_upper()"))

	# --- A PLAYER'S LEVEL, BESIDE GIVE TO -------------------------------------------
	Api.is_owner = true
	Api.role = "owner"
	Api.username = "boss"
	var menu: Control = (load("res://scene/ui/owner/itemspawner.tscn") as PackedScene).instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	var level_box: LineEdit = menu.get_node_or_null("%theirlevel") as LineEdit
	var level_button: Button = menu.get_node_or_null("%theirlevelbutton") as Button
	check("the catalogue has a level box and Set level, on the Give to row",
		level_box != null and level_button != null and level_box.get_parent() == menu.give_to.get_parent()
		and level_button.text == "Set level")
	var asked: Array = []
	var answer: Array = [{"ok": true, "data": {"username": "newbie", "character": "tank", "slot": 0,
		"level": 30, "was": 1, "sessions_ended": 1}}]
	menu.post_request = func(path: String, body: Dictionary) -> Dictionary:
		asked.append([path, body])
		await get_tree().process_frame
		return answer[0]
	menu.set_recipient("")
	level_box.text = "30"
	await menu.set_their_level()
	check("no name in Give to: nothing is asked, and it says where your own level is",
		asked.is_empty() and menu.status.text.contains("Testing tab"), menu.status.text)
	menu.set_recipient("newbie")
	# Two digits is all the box takes; 0 is the one it can hold and the server refuses.
	level_box.text = "0"
	await menu.set_their_level()
	check("  a level outside 1-99 is said, not sent", asked.is_empty() and menu.status.text.contains("1 to 99"))
	level_box.text = "30"
	level_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check("a name and a level: the level route, with their name and no slot",
		asked.size() == 1 and asked[0][0] == "/api/staff/level"
		and asked[0][1] == {"username": "newbie", "level": 30}, asked)
	check("  and it says what changed, and that their game was signed out to load it",
		menu.status.text == "newbie's tank is level 30 now (was 1). Their game was signed out to load it - they sign back in.",
		menu.status.text)
	check("an offline player is told it is theirs when they sign in",
		ItemSpawner.level_line({"username": "ivy", "character": "mage", "level": 5, "was": 2,
			"sessions_ended": 0}).ends_with("They are offline; it is theirs when they sign in."))
	answer[0] = {"ok": false, "status": 403, "error": "That is the owner's account - a co-owner cannot change it."}
	await menu.set_their_level()
	check("a refusal is said in the server's words",
		menu.status.text == "That is the owner's account - a co-owner cannot change it.", menu.status.text)
	menu.queue_free()
	check("the save history names the snapshot a level change takes",
		SaveHistory.REASON_WORDS.get("before-level", "") == "before a level change")

	# --- THE LEDGER SAYS WHO GAVE IT ---------------------------------------------------
	var panel_script: Variant = load("res://src/ui/owner/ownerpanel.gd")
	var two: Dictionary = {"totals": {"gifts": 3, "gold": 3000}, "to_players": {"gifts": 2, "gold": 2000},
		"to_yourself": {"gifts": 1, "gold": 1000},
		"by_giver": [{"username": "Tunacan", "gifts": 2, "gold": 2000}, {"username": "AllMind", "gifts": 1, "gold": 1000}],
		"recent": [{"at": 1791598980, "by": "AllMind", "username": "newbie", "item_id": "goldcoin",
			"quantity": 1, "gold": 1000}]}
	var lines: Array = panel_script.gift_report_lines(two)
	var text: String = "\n".join(lines.map(func(l: Array) -> String: return str(l[0])))
	check("with a co-owner giving too, the ledger says who gave what, and on each newest line",
		text.contains("--- who gave it ---") and text.contains("Tunacan: 2,000 gold (2 gifts)")
		and text.contains("AllMind: 1,000 gold (1 gift)") and text.contains("(by AllMind)"), text)
	two["by_giver"] = [{"username": "Tunacan", "gifts": 3, "gold": 3000}]
	lines = panel_script.gift_report_lines(two)
	text = "\n".join(lines.map(func(l: Array) -> String: return str(l[0])))
	check("  and with only the owner giving, it does not say so on every line",
		not text.contains("who gave it") and not text.contains("(by "), text)

	Api.is_owner = was_owner
	Api.role = was_role
	Api.username = was_name
	print("  co-owners: the rank, the badge, the switch, the doors, a player's level, the ledger")


func _test_founding_a_guild_shows_what_it_cost() -> void:
	section("GUILD - founding shows the purse and bank the server left")

	# Day 1: founding cost 5,000, paid 1,000 carried and 4,000 from the bank,
	# and the game went on showing 1,000 and 4,500 until a relog. The server
	# held 0 and 500; the panel read only the sentence out of its answer.
	var holder := GDScript.new()
	holder.source_code = "extends Node\nvar gold: int = 1000\nfunc set_gold(total: int) -> void:\n\tgold = total\n"
	holder.reload()
	var fake: Node = holder.new()
	add_child(fake)
	var others: Array = get_tree().get_nodes_in_group("player")
	fake.add_to_group("player")
	var kept_bank: int = CharacterData.get_bank_gold()
	CharacterData.account_data["bank_gold"] = 4500
	var panel: Control = (load("res://scene/ui/guild/guildpanel.tscn") as PackedScene).instantiate() as Control
	add_child(panel)
	var asked: Array = []
	panel.post_request = func(path: String, _body: Dictionary) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": {"guild": {}, "rank": "leader", "gold": 0,
			"carried_gold": 0, "bank_gold": 500, "paid": 5000, "from_carried": 1000, "from_bank": 4000}}
	await panel._act("/api/guild/create", {"name": "Day One", "slot": 0},
		"Day One is founded. You are its leader.")
	check("founding asks the server", asked == ["/api/guild/create"], asked)
	check("  the purse shows what the server left", others.is_empty() and fake.gold == 0, [others.size(), fake.gold])
	check("  and so does the bank", CharacterData.get_bank_gold() == 500, CharacterData.get_bank_gold())
	check("  and the notice says which pile paid",
		panel.notice.text.ends_with("1000 carried and 4000 from the bank."), panel.notice.text)

	fake.gold = 77
	panel.post_request = func(_path: String, _body: Dictionary) -> Dictionary:
		return {"ok": false, "status": 400, "error": "Founding a guild costs 5000 gold."}
	await panel._act("/api/guild/create", {"name": "Day Two", "slot": 0}, "founded")
	check("a refusal moves neither", fake.gold == 77 and CharacterData.get_bank_gold() == 500,
		[fake.gold, CharacterData.get_bank_gold()])
	panel.post_request = func(_path: String, _body: Dictionary) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"invited": "caster"}}
	await panel._act("/api/guild/invite", {"username": "caster"}, "Invited caster.")
	check("  nor does an answer with no gold in it", fake.gold == 77 and CharacterData.get_bank_gold() == 500,
		[fake.gold, CharacterData.get_bank_gold()])

	# THE OWNER'S GOLD GRANT had the same half: the purse was copied, the bank was not.
	check("the owner's gold grant copies the bank as well as the purse",
		_func_body(_code_src("res://src/ui/owner/ownerpanel.gd"), "func _on_gold_pressed(")
			.contains("CharacterData.adopt_server_gold("))

	panel.free()
	fake.free()
	CharacterData.account_data["bank_gold"] = kept_bank
	print("  gold the server took for a guild shows at once")


func _test_a_request_waiting_on_you_lights_its_button() -> void:
	section("FRIENDS AND GUILD - a request waiting on you lights its button")

	# Day 1: a friend request or guild invitation to somebody standing next to
	# you sat unseen until they opened the panel. The poll carries `asks` now.
	var hud_script: Script = load("res://src/ui/characterhud.gd") as Script
	hud_script._forget_asks()
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	var rows: Control = hud.message_rows
	var friends_button: Button = hud.get_node("%friendsbutton") as Button
	var guild_button: Button = hud.get_node("%guildbutton") as Button
	var guild_tip: String = guild_button.tooltip_text
	var asks := func(friends: int, who: String, at: int, guilds: int, guild: String, g_at: int) -> Dictionary:
		return {"latest_id": 0, "messages": [], "asks": {
			"friends": {"count": friends, "newest": who, "at": at},
			"guild": {"count": guilds, "newest": guild, "at": g_at}}}
	var toasts := func() -> Array:
		var out: Array = []
		for child in rows.get_children():
			out.append((child as Label).text)
		return out

	hud._apply_broadcast(asks.call(0, "", 0, 0, "", 0))
	check("nothing waiting: the buttons read as they always did",
		friends_button.text == "Friends" and guild_button.text == "Guild" and rows.get_child_count() == 0,
		[friends_button.text, guild_button.text])
	hud._apply_broadcast(asks.call(1, "caster", 1000, 0, "", 0))
	check("a friend request lights Friends", friends_button.text == "Friends •", friends_button.text)
	check("  says who is waiting", friends_button.tooltip_text == "caster is waiting on your answer",
		friends_button.tooltip_text)
	check("  and is said once", toasts.call() == ["caster asked to be your friend. Open Friends to answer."],
		toasts.call())
	hud._apply_broadcast(asks.call(1, "caster", 1000, 1, "Day One", 1005))
	check("an invitation lights Guild and is said", guild_button.text == "Guild •"
		and toasts.call().size() == 2 and toasts.call()[1] == "Day One invited you to join. Open Guild to answer.",
		[guild_button.text, toasts.call()])
	check("  and the same request is not said again", toasts.call().size() == 2, toasts.call())
	hud._apply_broadcast(asks.call(2, "medic", 1010, 1, "Day One", 1005))
	check("a second request is said, with the count",
		toasts.call()[-1] == "medic and 1 more asked to be your friend. Open Friends to answer."
		and friends_button.tooltip_text == "2 are waiting on your answer", [toasts.call()[-1], friends_button.tooltip_text])
	hud.free()

	# THROUGH A DOOR the new HUD lights its buttons from the last answer and
	# says nothing again.
	var next_area: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	next_area._build_message_box()
	next_area._paint_ask_buttons()
	next_area._apply_broadcast(asks.call(2, "medic", 1010, 1, "Day One", 1005))
	check("the next area's HUD keeps both lit and says nothing again",
		(next_area.get_node("%friendsbutton") as Button).text == "Friends •"
		and (next_area.get_node("%guildbutton") as Button).text == "Guild •"
		and next_area.message_rows.get_child_count() == 0, next_area.message_rows.get_child_count())
	check("  and a new area's HUD lights them before its first poll",
		_func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(").contains("_paint_ask_buttons()"))
	next_area._apply_broadcast(asks.call(0, "", 0, 0, "", 0))
	var after_guild: Button = next_area.get_node("%guildbutton") as Button
	check("answered, both go out, and Guild gets its own hint back",
		(next_area.get_node("%friendsbutton") as Button).text == "Friends"
		and after_guild.text == "Guild" and after_guild.tooltip_text == guild_tip, [after_guild.text, after_guild.tooltip_text])
	next_area.free()

	# ANOTHER ACCOUNT ON THIS MACHINE starts from nothing.
	hud_script._asks_said_by = "someoneelse"
	hud_script._asks_said = {"friends": 999999, "guild": 999999}
	var other: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	other._build_message_box()
	other._apply_broadcast(asks.call(1, "caster", 1000, 0, "", 0))
	check("a different account's waiting request is said to it",
		other.message_rows.get_child_count() == 1, other.message_rows.get_child_count())
	other.free()
	hud_script._forget_asks()
	print("  friend requests and guild invitations reach the player they wait on")


func _test_the_login_screen_asks_without_a_login() -> void:
	section("LOGIN - the screen asks if the server is there without a login")

	# Found in the browser build on day 1: the login screen's five-second probe
	# asked /api/auth/session, which answers 401 to nobody signed in, so the
	# console filled with a red "Failed to load resource" line every five
	# seconds and the server logged a 401 for every idle player.
	var probe := _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _on_reconnect_poll_timeout(")
	check("the login screen's probe asks /api/status",
		probe.contains("Api.get_json(\"/api/status\"") and not probe.contains("Api.get_json(\"/api/auth/session\""),
		probe.length())
	# AND OPENING THE GAME WITH NOTHING REMEMBERED asks nothing that needs a login:
	# the /api/status answer it already has says whether the server is there.
	var opening := _func_body(_code_src("res://src/systems/api.gd"), "func probe_and_resume(")
	var nothing_remembered: String = opening.substr(opening.find("\telse:"), 80)
	check("  and so does opening the game with no login remembered",
		opening.contains("var status_res: Dictionary = await refresh_build_info()")
		and nothing_remembered.contains("res = status_res") and not nothing_remembered.contains("auth/session"),
		nothing_remembered)


func _test_a_gateway_saying_no_answer_is_no_answer() -> void:
	section("API - a gateway's 502 or 504 is the server not answering")

	# Found in the browser build on day 1: behind the site's proxy, app.py down
	# answers 502 from the proxy, and the login screen said "Connected to the
	# Elusion server." Each answer below is handed to Api._read_answer() as an
	# HTTPRequest would hand it over, with no network.
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	var seen: Dictionary = {}
	for status in [502, 504, 503, 500, 401, 200]:
		Api.server_online = status == 502 or status == 504
		var http := HTTPRequest.new()
		add_child(http)
		var got: Array = []
		var reading := func() -> void:
			got.append(await Api._read_answer(http, "", "/api/status"))
		reading.call()
		http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, status, PackedStringArray(),
			"{}".to_utf8_buffer())
		var res: Dictionary = got[0] if not got.is_empty() else {}
		seen[status] = [int(res.get("status", -1)), Api.server_online]
	check("a 502 from the proxy reads as no answer, and offline", seen.get(502) == [0, false], seen.get(502))
	check("  so does a 504", seen.get(504) == [0, false], seen.get(504))
	check("  but the server's own 503, 500 and 401 are answers",
		seen.get(503) == [503, true] and seen.get(500) == [500, true] and seen.get(401) == [401, true],
		[seen.get(503), seen.get(500), seen.get(401)])
	check("  and a 200 is a 200", seen.get(200) == [200, true], seen.get(200))
	Api.server_online = kept_online
	Api.reachability_known = kept_known


func _test_a_lost_server_is_asked_for_more_often() -> void:
	section("CONNECTION - a lost server is asked for more often until it answers")

	# Day 1: a 16-second server restart showed "Connection lost" for 12 seconds
	# after the server was back, because the next poll was up to ten seconds
	# away. While the strip is up the poll runs every OFFLINE_POLL_SECONDS.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_status_strip()
	hud._build_message_box()
	var timer := Timer.new()
	timer.name = "BroadcastPoll"
	timer.wait_time = hud.BROADCAST_POLL_SECONDS
	hud.add_child(timer)
	var kept_token: String = Api.token
	Api.token = "test-not-a-real-token"
	hud._last_contact_msec = Time.get_ticks_msec() - int((hud.OFFLINE_GRACE_SECONDS + 5.0) * 1000.0)
	hud._tick_connection_status()
	check("past the grace, the strip is up and the poll asks every %.0f s" % hud.OFFLINE_POLL_SECONDS,
		hud.status_strip.visible and is_equal_approx(timer.wait_time, hud.OFFLINE_POLL_SECONDS),
		[hud.status_strip.visible, timer.wait_time])
	check("  which is quicker than the usual pace", hud.OFFLINE_POLL_SECONDS < hud.BROADCAST_POLL_SECONDS)
	hud._note_server_contact()
	check("the first answer puts the usual pace back and takes the strip down",
		is_equal_approx(timer.wait_time, hud.BROADCAST_POLL_SECONDS) and not hud.status_strip.visible,
		[timer.wait_time, hud.status_strip.visible])
	Api.token = kept_token
	hud.free()


func _test_the_bag_is_the_servers() -> void:
	section("THE BAG IS THE SERVER'S - a drag or the bin is a request, the grid drawn from the answer")

	# A save carried the whole bag, and the server trimmed it to what it had
	# granted (E-1): a gain was caught, and the arrangement and every loss were
	# this client's word. Now each change is one request (ONE CELL AT A TIME in
	# app.py, test_bagmoves.py), and a save carries no bag and no bank.
	var ss_code: String = _code_src("res://src/systems/serverstorage.gd")
	check("a save no longer sends the bag or the bank",
		not ss_code.contains("\"/api/character/inventory\"") and not ss_code.contains("\"/api/account/bank\""))
	check("  and the based_on bookkeeping went with it",
		not _code_src("res://src/systems/characterdata.gd").contains("func note_server_bag(")
		and not ss_code.contains("bag_base"))

	var kept_slots: Array = CharacterData.character_slots.duplicate(true)
	var kept_index: int = CharacterData.active_character_index
	CharacterData.character_slots = [{"character": "warrior", "inventory": [], "gold": 10},
		{"character": "mage", "inventory": [], "gold": 10}, null, null]
	CharacterData.active_character_index = 0

	# OUR OWN TWO ITEMS, so this runs without the art pack (the hotbar test's
	# way): a potion that stacks to 20 and a sword that does not stack.
	var potion := ItemData.new()
	potion.item_id = "zz_bag_test_potion"
	potion.display_name = "Bag Test Potion"
	potion.stackable = true
	potion.max_stack = 20
	var sword := ItemData.new()
	sword.item_id = "zz_bag_test_sword"
	sword.display_name = "Bag Test Sword"
	ItemRegistry._items[potion.item_id] = potion
	ItemRegistry._items[sword.item_id] = sword

	# A FAKE SERVER: every request is written down and answered, a frame
	# later, with whatever is next in `answers`.
	var sent: Array = []
	var answers: Array = []
	var fake := func(path: String, body: Dictionary) -> Dictionary:
		sent.append([path, body])
		await get_tree().process_frame
		return answers.pop_front() if not answers.is_empty() else {"ok": false, "status": 0, "error": "no answer"}
	var settle := func(grid: InventoryContainer) -> void:
		var frames := 0
		while grid.is_busy() and frames < 30:
			await get_tree().process_frame
			frames += 1
		await get_tree().process_frame

	var carry := InventoryContainer.new()
	carry.is_carry = true
	add_child(carry)
	carry.send_override = fake
	carry.load_save_array([{"item_id": "zz_bag_test_potion", "quantity": 5}, {"item_id": "zz_bag_test_sword", "quantity": 1}])

	# ---- a drag is drawn at once and sent as one move -------------------------
	var held_after: Array = [null, {"item_id": "zz_bag_test_sword", "quantity": 1}, null, null, null, null, null,
		{"item_id": "zz_bag_test_potion", "quantity": 5}]
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": held_after}})
	carry.get_slot_at(7)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(0)))
	check("a drag onto an empty cell is drawn at once",
		_hb_holds(carry.get_slot_at(7), "zz_bag_test_potion", 5) and carry.get_slot_at(0).is_empty())
	check("  and sent as one move, naming what was dragged",
		sent.size() == 1 and sent[0][0] == InventoryContainer.CARRY_MOVE_PATH
		and sent[0][1] == {"slot": 0, "from": 0, "to": 7, "item_id": "zz_bag_test_potion"}, sent)
	await settle.call(carry)
	check("  the answer agrees, and the grid is the server's",
		_hb_holds(carry.get_slot_at(7), "zz_bag_test_potion", 5) and _hb_holds(carry.get_slot_at(1), "zz_bag_test_sword", 1))

	# ---- two quick drags: in order, one at a time, only the last answer drawn -
	sent.clear()
	var first_answer: Array = [{"item_id": "zz_bag_test_sword", "quantity": 1}]
	var last_answer: Array = [{"item_id": "zz_bag_test_sword", "quantity": 1}, null, null,
		{"item_id": "zz_bag_test_potion", "quantity": 5}]
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": first_answer}})
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": last_answer}})
	carry.get_slot_at(0)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(1)))
	carry.get_slot_at(3)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(7)))
	check("two quick drags: the second waits for the first's answer", sent.size() == 1, sent.size())
	await settle.call(carry)
	check("  then goes, in the order made", sent.size() == 2
		and int(sent[0][1]["from"]) == 1 and int(sent[1][1]["from"]) == 7, sent)
	check("  and only the last answer is drawn - the first would flick the second drag back",
		_hb_holds(carry.get_slot_at(0), "zz_bag_test_sword", 1) and _hb_holds(carry.get_slot_at(3), "zz_bag_test_potion", 5),
		carry.to_save_array().slice(0, 4))

	# ---- a grid that was out of date is put right by the 409 ------------------
	# The resync names character 1, not the one being played, so no player the
	# suite may have left in the tree has its purse or its grid touched; the
	# real server names the requesting slot, and the HUD's grid is this one.
	sent.clear()
	var truth: Array = [{"item_id": "zz_bag_test_sword", "quantity": 1}, null, {"item_id": "zz_bag_test_potion", "quantity": 2}]
	answers.append({"ok": false, "status": 409, "error": "Your backpack changed on the server.",
		"data": {"resync": {"slot": 1, "gold": 10, "inventory": truth, "trade": null, "reason": "stale_save"}}})
	carry.get_slot_at(9)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(3)))
	await settle.call(carry)
	check("a move the server refused as stale redraws the grid it holds",
		_hb_holds(carry.get_slot_at(2), "zz_bag_test_potion", 2) and carry.get_slot_at(9).is_empty()
		and carry.get_slot_at(3).is_empty(), carry.to_save_array().slice(0, 10))
	check("  and the character's copy follows it, through apply_server_carry()",
		(CharacterData.character_slots[1].get("inventory", []) as Array).size() >= 3
		and CharacterData.character_slots[1]["inventory"][2] is Dictionary)
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	hud._on_carry_adopted({"reason": "stale_save", "inventory": [], "trade": null})
	check("  and puts up no message - the grid simply shows the truth", hud._unlogged_lines.is_empty(),
		hud._unlogged_lines)
	hud._on_carry_adopted({"inventory": [], "trade": null})
	check("  a resync for anything else, a trade, still does", hud._unlogged_lines.size() == 1,
		hud._unlogged_lines)
	hud.free()

	# ---- the bin ----------------------------------------------------------------
	sent.clear()
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": [{"item_id": "zz_bag_test_sword", "quantity": 1}]}})
	carry.request_discard(2, "zz_bag_test_sword")
	check("a bin that names the wrong item destroys nothing and sends nothing",
		_hb_holds(carry.get_slot_at(2), "zz_bag_test_potion", 2) and sent.is_empty())
	carry.request_discard(2, "zz_bag_test_potion")
	check("the bin takes the stack off at once",
		carry.get_slot_at(2).is_empty())
	check("  and asks the server to destroy it",
		sent.size() == 1 and sent[0][0] == InventoryContainer.CARRY_DISCARD_PATH
		and sent[0][1] == {"slot": 0, "position": 2, "item_id": "zz_bag_test_potion"}, sent)
	await settle.call(carry)

	# ---- no answer at all leaves the drawing alone, and says so --------------
	sent.clear()
	carry.get_slot_at(5)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(0)))
	await settle.call(carry)
	check("a move with no answer keeps what is drawn - the next answer puts it right",
		sent.size() == 1 and _hb_holds(carry.get_slot_at(5), "zz_bag_test_sword", 1))

	# ---- the bank's grid uses the bank's routes; a grid that is neither, none --
	var bank := InventoryContainer.new()
	bank.grid_width = 10
	bank.grid_height = 5
	bank.is_bank = true
	add_child(bank)
	bank.set_slot_type(InventorySlot.BANK_SLOT_TYPE)
	bank.send_override = fake
	bank.load_save_array([{"item_id": "zz_bag_test_sword", "quantity": 1}])
	sent.clear()
	var bank_truth: Array = [null, null, null, {"item_id": "zz_bag_test_sword", "quantity": 1}]
	answers.append({"ok": false, "status": 409, "error": "The bank changed on the server.",
		"data": {"account": {"bank_inventory": bank_truth}}})
	bank.get_slot_at(20)._drop_data(Vector2.ZERO, _hb_drag(bank.get_slot_at(0)))
	check("a drag inside the bank is a bank move, with no character slot",
		sent.size() == 1 and sent[0][0] == InventoryContainer.BANK_MOVE_PATH
		and sent[0][1] == {"from": 0, "to": 20, "item_id": "zz_bag_test_sword"}, sent)
	await settle.call(bank)
	check("  and a stale one redraws the bank the server holds",
		_hb_holds(bank.get_slot_at(3), "zz_bag_test_sword", 1) and bank.get_slot_at(20).is_empty())
	sent.clear()
	bank.request_discard(3, "zz_bag_test_sword")
	check("the bank's bin is the bank's discard",
		sent.size() == 1 and sent[0][0] == InventoryContainer.BANK_DISCARD_PATH
		and sent[0][1] == {"position": 3, "item_id": "zz_bag_test_sword"}, sent)
	await settle.call(bank)

	var loose := InventoryContainer.new()
	add_child(loose)
	loose.send_override = fake
	loose.load_save_array([{"item_id": "zz_bag_test_sword", "quantity": 1}])
	sent.clear()
	loose.get_slot_at(4)._drop_data(Vector2.ZERO, _hb_drag(loose.get_slot_at(0)))
	check("a grid that is neither the bag nor the bank sends nothing", sent.is_empty())

	# ---- the wiring, read from the code -------------------------------------
	check("the inventory screen marks its grid as the carry",
		_func_body(_code_src("res://src/ui/inventory/inventoryscreen.gd"), "func _wire_inventory_container(")
			.contains("_container.is_carry = true"))
	check("the bank marks its grid as the bank",
		_code_src("res://src/ui/bank/bankinventory.gd").contains("bank_container.is_bank = true"))
	check("the bin asks the grid to discard, naming the item the dialog showed",
		_func_body(_code_src("res://src/ui/inventory/trashslot.gd"), "func _on_delete_confirmed(")
			.contains("request_discard(_pending_source_slot.slot_index, named)"))
	var screen_src: String = _code_src("res://src/ui/inventory/inventoryscreen.gd")
	check("a pile of coins is cashed by the server, not added to the purse here",
		_func_body(screen_src, "func _cash_pile(").contains("/api/character/inventory/cash")
		and not screen_src.contains("player.add_gold(") and not screen_src.contains("player.add_lusions("))
	check("a potion's answer is drawn as the bag",
		_func_body(screen_src, "func _use_consumable(").contains("_adopt_carry("))

	carry.queue_free()
	bank.queue_free()
	loose.queue_free()
	ItemRegistry._items.erase(potion.item_id)
	ItemRegistry._items.erase(sword.item_id)
	CharacterData.character_slots = kept_slots
	CharacterData.active_character_index = kept_index
	print("  the bag: drags and the bin are requests, in order, drawn from the last answer")


func _test_the_map_comes_back() -> void:
	section("MAP - what you uncovered comes back at the next login")

	# Day 1: a walk of the field, a logout, and the map was blank again. Two
	# faults. The load built each character from /api/character, which carries
	# no map (the listing, /api/save, does), so every login started with none;
	# and the map rides a save only when WorldMap's revision moves, at most
	# every SAVE_REVISION_SECONDS, so a logout inside that window left the walk
	# behind. The first save after the next walk then wrote the few new tiles
	# over everything before.
	var storage_script: GDScript = load("res://src/systems/serverstorage.gd") as GDScript
	var map: Dictionary = {"field": {"w": 2, "h": 2, "ox": 0, "oy": 0, "bits": "x"}}
	var merged: Dictionary = storage_script.with_listing({"class_id": "warrior"}, {"slot": 0, "explored": map})
	check("a character from /api/character takes the map from the listing", merged.get("explored") == map,
		merged.get("explored"))
	var own: Dictionary = {"class_id": "warrior", "explored": {"elusion": {}}}
	check("  and one that already has a map keeps its own",
		storage_script.with_listing(own, {"explored": map}).get("explored") == {"elusion": {}})
	check("  the load builds every character that way",
		_func_body(_code_src("res://src/systems/serverstorage.gd"), "func load(")
			.contains("_slot_from_server(with_listing("))

	var kept_rev: int = WorldMap._revision
	var kept_pending: bool = WorldMap._revision_pending
	WorldMap._revision_pending = true
	WorldMap._revision_at_ms = Time.get_ticks_msec()
	var before: int = WorldMap.save_revision()
	check("a walk inside the window has not moved the revision yet", before == kept_rev, [before, kept_rev])
	check("flush_pending() counts it now", WorldMap.flush_pending() and WorldMap.save_revision() == before + 1)
	check("  and only once", not WorldMap.flush_pending())
	# LEAVING, through the real finish_saving(), with no time to wait: the walk
	# is counted and the character's save carries the map at the new revision.
	var kept_slots: Array = CharacterData.character_slots.duplicate(true)
	var kept_index: int = CharacterData.active_character_index
	CharacterData.character_slots = [{"character": "warrior"}, null, null, null]
	CharacterData.active_character_index = 0
	WorldMap._revision_pending = true
	var walked_at: int = WorldMap.save_revision()
	await CharacterData.finish_saving(0.0)
	check("leaving counts the walk and puts it in the save",
		int(CharacterData.character_slots[0].get("explored_rev", -1)) == walked_at + 1
		and CharacterData.character_slots[0].has("explored"), CharacterData.character_slots[0])
	CharacterData.character_slots = kept_slots
	CharacterData.active_character_index = kept_index
	WorldMap._revision = kept_rev
	WorldMap._revision_pending = kept_pending


func _test_enemies_keep_their_place_in_the_ring() -> void:
	section("FORMATION - a chasing enemy keeps its place on the ring")

	# Day 1, measured while timing the field: within a second 37 of the 40 ring
	# slots were owned by enemies not standing on them and none of 12 chasers
	# held one. Each 0.4 s review that found nothing better forgot the slot it
	# had without releasing it, so every enemy ran at the player's own position.
	var kept_owners: Dictionary = BaseEnemy._slot_owners.duplicate()
	BaseEnemy._slot_owners.clear()
	var holder := Node2D.new()
	add_child(holder)
	var anchor := CharacterBody2D.new()
	holder.add_child(anchor)
	anchor.global_position = Vector2(9000, 9000)
	var pack: PackedScene = load("res://scene/enemy/darkbushmage.tscn") as PackedScene
	var pack_of: Array = []
	for i in 6:
		var e: Node = pack.instantiate()
		holder.add_child(e)
		e.set_physics_process(false)
		e.set_process(false)
		e.global_position = anchor.global_position + Vector2.RIGHT.rotated(TAU * i / 6.0) * 150.0
		e.player = anchor
		pack_of.append(e)
	var holding := func() -> Array:
		var out: Array = []
		for e in pack_of:
			if e._claimed_slot != -1 and BaseEnemy._slot_owners.get(e._claimed_slot) == e:
				out.append(e._claimed_slot)
		return out
	var leaked := func() -> int:
		var n := 0
		for slot in BaseEnemy._slot_owners:
			var who = BaseEnemy._slot_owners[slot]
			if is_instance_valid(who) and who._claimed_slot != slot:
				n += 1
		return n
	for e in pack_of:
		e._ensure_slot_claimed()
	var first: Array = holding.call()
	check("six chasers each claim a slot of their own", first.size() == 6, first)
	# Five reviews each, the way 0.4 s ticks would bring them.
	for round_i in 5:
		for e in pack_of:
			e._slot_review_time = 0.0
			e._ensure_slot_claimed()
	var after: Array = holding.call()
	check("  and still hold one after five reviews", after.size() == 6, after)
	check("  no slot is owned by an enemy not standing on it", leaked.call() == 0, leaked.call())
	check("  six slots owned, not more", BaseEnemy._slot_owners.size() == 6, BaseEnemy._slot_owners.size())
	var leaver: Node = pack_of[0]
	var its_slot: int = leaver._claimed_slot
	leaver._release_slot()
	check("one that gives up its slot frees it for the others",
		not BaseEnemy._slot_owners.has(its_slot) and BaseEnemy._slot_owners.size() == 5, BaseEnemy._slot_owners.keys())
	holder.queue_free()
	BaseEnemy._slot_owners.clear()
	BaseEnemy._slot_owners.merge(kept_owners)
	print("  formation: %d chasers, %d held after the reviews" % [pack_of.size(), after.size()])


func _test_a_door_is_quick() -> void:
	section("DOORS - the fade is short, and the area is built under it")

	# 0.6 s of every 0.65 s door was the fade. Halved each way on day 1.
	check("a door fades for 0.15 s each way", is_equal_approx(SceneTransition.fade_duration, 0.15),
		SceneTransition.fade_duration)
	var body := _func_body(_code_src("res://src/systems/scenetransition.gd"), "func change_scene(")
	var out_at := body.find("await _fade_out()")
	var swap_at := body.find("change_scene_to_packed(")
	var in_at := body.find("await _fade_in()")
	check("  the new area is built while the screen is black",
		out_at != -1 and swap_at > out_at and in_at > swap_at, [out_at, swap_at, in_at])


func _test_the_emoji_font_is_chat_sized() -> void:
	section("EMOJI - the colour font is drawn at chat size, so it ships at chat size")

	# Google's Noto Color Emoji is 10.8 MB of 136x128 pictures, and it was three
	# quarters of the browser's game file. Chat draws emoji at 10-16 px, so the
	# shipped copy is scaled to 32 ppem by tools/shrink_emoji_font.py: every
	# emoji kept, 4.6 MB. Dropping Google's file back in adds 6 MB to every
	# browser player's download, on the first visit and after every update.
	var bytes := FileAccess.get_file_as_bytes(EMOJI_FONT)
	check("the emoji font is the chat-size build, under %.0f MB" % (EMOJI_FONT_MAX_BYTES / 1_000_000.0),
		bytes.size() > 0 and bytes.size() < EMOJI_FONT_MAX_BYTES, bytes.size())
	var ppem := _emoji_strike_ppem(bytes)
	check("  its pictures are one strike of 32 ppem", ppem == 32, ppem)
	var font := load(EMOJI_FONT) as FontFile
	var missing: Array = []
	for code in [0x1F600, 0x1F44D, 0x1F525, 0x1F41F, 0x2694, 0x1F6E1, 0x1F4B0, 0x1F389, 0x2764, 0x1F602, 0x1F62D, 0x1F64F]:
		if font == null or not font.has_char(code):
			missing.append("%X" % code)
	check("  and still has every emoji: the common ones are there", missing.is_empty(), missing)
	var supported: int = font.get_supported_chars().length() if font != null else 0
	# 1,493 is what Godot reports for Google's own file too (its cmap lists 1,494).
	check("  as many characters as Google's release", supported >= 1493, supported)


func _test_connections_are_kept_open() -> void:
	section("NETWORK - the desktop game keeps its connections to the server open")

	# Day 1, measured at a 50 ms ping and 60 fps: a request on a new connection
	# took 133 ms, one on a connection kept open 67 ms; the login's four requests
	# went from 0.7 s to 0.4 s. Over HTTPS a new connection costs one more round
	# trip again. See connectionpool.gd for the rules checked here.
	var pool = Api._pool
	check("the desktop game sends its JSON through kept-open connections", pool != null)
	if pool == null:
		return
	var fake := FakeHttpServer.new()
	add_child(fake)
	if not fake.start():
		check("a free local port for the suite's own server", false)
		fake.queue_free()
		return
	var kept_url: String = ApiForTests.BASE_URL
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	var kept_token: String = Api.token
	Api.token = ""
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % fake.port
	var opened: int = pool.connections_opened

	var oks := 0
	var seen_at := 0
	for i in 5:
		var one: Dictionary = await Api.get_json("/one")
		if one.get("ok", false) and one.data is Dictionary and one.data.get("path") == "/one":
			oks += 1
	check("five requests in a row are answered", oks == 5, oks)
	check("  over one connection", fake.accepted == 1 and pool.connections_opened - opened == 1,
		[fake.accepted, pool.connections_opened - opened])

	var together: Array = []
	for i in 3:
		(func() -> void: together.append(await Api.get_json("/together"))).call()
	var waited := 0.0
	while together.size() < 3 and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var all_ok := together.size() == 3
	for r in together:
		all_ok = all_ok and r.get("ok", false)
	check("three at once are all answered, each on its own connection",
		all_ok and fake.accepted == 3, [together.size(), fake.accepted])

	var gz: Dictionary = await Api.get_json("/gz")
	check("a compressed answer is unpacked", gz.get("ok", false) and gz.data is Dictionary
		and gz.data.get("path") == "/gz", gz)

	# Up to three connections are open now, so six requests to a server that
	# closes after each answer need at least three new ones - and no timeouts.
	fake.mode = "close"
	var before: int = fake.accepted
	var closing_from := Time.get_ticks_msec()
	oks = 0
	for i in 6:
		if (await Api.get_json("/closing")).get("ok", false):
			oks += 1
	seen_at = fake.seen.size()
	var closing_post: Dictionary = await Api.post("/closing", {"n": 1})
	check("a server that says it will close gets every request, without waiting for it (Flask's own does this)",
		oks == 6 and closing_post.get("ok", false) and fake.accepted - before >= 3
		and Time.get_ticks_msec() - closing_from < 2000,
		[oks, closing_post.get("status"), fake.accepted - before, Time.get_ticks_msec() - closing_from])

	fake.mode = "keep"
	await Api.get_json("/warm")
	fake.mode = "eat_next"
	seen_at = fake.seen.size()
	var again: Dictionary = await Api.get_json("/again")
	check("a GET lost on a reused connection is asked again once, and answered",
		again.get("ok", false) and fake.seen.slice(seen_at) == ["GET /again", "GET /again"],
		[again.get("status"), fake.seen.slice(seen_at)])

	await Api.get_json("/warm")
	fake.mode = "eat_next"
	seen_at = fake.seen.size()
	var buy: Dictionary = await Api.post("/buy", {"item_id": "ironsword"})
	check("a POST lost the same way is never sent twice: it fails as no answer",
		not buy.get("ok", true) and int(buy.get("status", -1)) == 0
		and fake.seen.slice(seen_at) == ["POST /buy"], [buy.get("status"), fake.seen.slice(seen_at)])

	fake.mode = "drop"
	await Api.get_json("/warm")
	fake.mode = "keep"
	await get_tree().create_timer(0.2).timeout
	seen_at = fake.seen.size()
	var after_drop: Dictionary = await Api.get_json("/after_drop")
	check("a connection the server dropped while idle is not used: the next request goes once and is answered",
		after_drop.get("ok", false) and fake.seen.slice(seen_at) == ["GET /after_drop"],
		[after_drop.get("status"), fake.seen.slice(seen_at)])
	# A POST is never asked twice, so this one only works if the dropped
	# connection is noticed before anything is sent on it.
	fake.mode = "drop"
	await Api.get_json("/warm")
	fake.mode = "keep"
	await get_tree().create_timer(0.2).timeout
	seen_at = fake.seen.size()
	var post_after_drop: Dictionary = await Api.post("/after_drop", {"n": 1})
	check("  and so is a POST: it is checked before it is sent on it",
		post_after_drop.get("ok", false) and fake.seen.slice(seen_at) == ["POST /after_drop"],
		[post_after_drop.get("status"), fake.seen.slice(seen_at)])

	pool.idle_close_seconds = 0.3
	await Api.get_json("/idle")
	var open_before: int = fake.open_connections()
	await get_tree().create_timer(0.6).timeout
	check("a connection left idle is closed by the game, before a server or proxy would",
		open_before >= 1 and fake.open_connections() == 0, [open_before, fake.open_connections()])
	pool.idle_close_seconds = pool.IDLE_CLOSE_SECONDS

	var started := Time.get_ticks_msec()
	var slow: Dictionary = await Api.get_json("/slow", 0.4)
	var took := Time.get_ticks_msec() - started
	check("a server that never answers times out on time", not slow.get("ok", true)
		and int(slow.get("status", -1)) == 0 and took < 1500, [slow.get("status"), took])
	var next_one: Dictionary = await Api.get_json("/after_slow")
	check("  and the request after it is answered, not handed the late reply",
		next_one.get("ok", false) and next_one.data is Dictionary and next_one.data.get("path") == "/after_slow",
		next_one.get("data"))

	fake.shutdown()
	await get_tree().create_timer(0.1).timeout
	var nothing: Dictionary = await Api.get_json("/nobody", 2.0)
	check("nothing listening is no answer, at once", int(nothing.get("status", -1)) == 0, nothing.get("status"))

	check("an address the pool cannot use is refused, not guessed at",
		PoolForTests.parse_base_url("example.com").is_empty() and PoolForTests.parse_base_url("ftp://x").is_empty())
	check("  and one it can is read in full",
		PoolForTests.parse_base_url("https://api.elusionrpg.com") == {"tls": true, "host": "api.elusionrpg.com", "port": 443, "prefix": ""}
		and PoolForTests.parse_base_url("http://127.0.0.1:5000/") == {"tls": false, "host": "127.0.0.1", "port": 5000, "prefix": ""}
		and PoolForTests.parse_base_url("https://example.com:8443/game") == {"tls": true, "host": "example.com", "port": 8443, "prefix": "/game"})

	ApiForTests.BASE_URL = kept_url
	Api.token = kept_token
	Api.server_online = kept_online
	Api.reachability_known = kept_known
	fake.queue_free()
	print("  network: %d connections opened by the pool for %d requests" % [pool.connections_opened - opened, fake.seen.size()])


# =============================================================================
# TOKEN LIFECYCLE (0.44.0) - the students' "token-lifecycle hardening"
# =============================================================================
#
# app.py's TOKEN LIFECYCLE does the work: a login from build 6 is bound to the
# copy of the game it was made on, a replaced token coming back is theft, a
# staff login is short, and the most powerful routes want the password again.
# The game's part is small, and all of it is asked here: say which copy it is
# on every request, ask for the password when the server wants it, say what an
# ended session means, and send nothing over plain http that leaves this
# computer.

func _test_token_lifecycle() -> void:
	section("TOKEN LIFECYCLE - which copy of the game, the password again, https only (0.44.0)")

	var consts: Dictionary = (load("res://src/systems/api.gd") as GDScript).get_script_constant_map()
	check("the install header's name matches the one app.py reads",
		str(consts.get("INSTALL_HEADER", "")) == "X-Elusion-Install", consts.get("INSTALL_HEADER"))
	check("  and this is build 6 or later, the first build the server binds",
		int(consts.get("BUILD", 0)) >= 6, consts.get("BUILD"))
	# The same count as the build stamp's, for the same reason: a builder that
	# forgot it sends a hardened token without its copy, which the server
	# reads as the token having been taken somewhere else.
	var code: String = _code_src("res://src/systems/api.gd")
	var builders: int = code.count("headers := PackedStringArray")
	var stamps: int = code.count("INSTALL_HEADER + \": \" + install_id()")
	check("every header builder says which copy of the game it is",
		builders >= 4 and stamps >= builders,
		"%d builders, %d stamped - one without it ends the player's session as stolen" % [builders, stamps])

	# ---- against the suite's own server ----------------------------------------
	var fake := FakeHttpServer.new()
	add_child(fake)
	if not fake.start():
		check("a free local port for the suite's own server", false)
		fake.queue_free()
		return
	var kept_url: String = ApiForTests.BASE_URL
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	var kept_token: String = Api.token
	var kept_handler: Callable = Api.confirm_handler
	Api.token = ""
	Api.confirm_handler = Callable()
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % fake.port
	var mine: String = "X-Elusion-Install: " + Api.install_id()

	var seen_at := fake.seen.size()
	await Api.get_json("/which")
	await Api.post_bytes("/which_bytes", PackedByteArray([1, 2, 3]), "application/octet-stream")
	await Api.get_bytes("/which_picture")
	var stamped: Array = []
	for i in range(seen_at, fake.heads.size()):
		stamped.append(fake.heads[i].contains(mine))
	check("  and on the wire: JSON, a raw upload and a picture all carry it",
		fake.seen.slice(seen_at) == ["GET /which", "POST /which_bytes", "GET /which_picture"]
		and stamped == [true, true, true], [fake.seen.slice(seen_at), stamped])

	# STEP-UP. The server answers 403 with confirm_password; the game asks for
	# the password (the HUD's prompt), confirms it, and sends the request again.
	var asked: Array = []
	var answer := ["right"]
	Api.confirm_handler = func(message: String) -> String:
		asked.append(message)
		return answer[0]
	fake.confirmed = false
	seen_at = fake.seen.size()
	var power: Dictionary = await Api.post("/power", {"n": 1})
	check("a route that wants the password asks for it, in the server's words",
		asked == ["Type your password to do this."], asked)
	check("  confirms it, sends the request again, and that is the answer",
		power.get("ok", false)
		and fake.seen.slice(seen_at) == ["POST /power", "POST /api/auth/confirm", "POST /power"],
		[power.get("status"), fake.seen.slice(seen_at)])
	var confirm_body: Variant = JSON.parse_string(fake.bodies[seen_at + 1]) \
		if fake.bodies.size() > seen_at + 1 else null
	check("  the password goes in the confirm's body and nowhere else",
		confirm_body is Dictionary and str((confirm_body as Dictionary).get("password", "")) == "right"
		and not fake.bodies[seen_at].contains("right") and not fake.bodies[seen_at + 2].contains("right")
		and not fake.heads[seen_at + 1].contains("right"))
	fake.confirmed = false
	asked.clear()
	seen_at = fake.seen.size()
	var again_get: Dictionary = await Api.get_json("/power")
	check("  a GET is sent again as a GET",
		again_get.get("ok", false) and asked.size() == 1
		and fake.seen.slice(seen_at) == ["GET /power", "POST /api/auth/confirm", "GET /power"],
		fake.seen.slice(seen_at))

	fake.confirmed = false
	asked.clear()
	answer[0] = ""
	seen_at = fake.seen.size()
	var cancelled: Dictionary = await Api.post("/power", {"n": 2})
	check("Cancel sends nothing more: the refusal is the answer",
		asked.size() == 1 and int(cancelled.get("status", 0)) == 403
		and fake.seen.slice(seen_at) == ["POST /power"], [cancelled.get("status"), fake.seen.slice(seen_at)])

	asked.clear()
	answer[0] = "wrong"
	seen_at = fake.seen.size()
	var wrong: Dictionary = await Api.post("/power", {"n": 3})
	var wrong_data: Variant = wrong.get("data", {})
	check("a wrong password is said, asked once, and the request is not sent again",
		asked.size() == 1 and int(wrong.get("status", 0)) == 403
		and wrong_data is Dictionary and str((wrong_data as Dictionary).get("message", "")) == "That is not your password."
		and fake.seen.slice(seen_at) == ["POST /power", "POST /api/auth/confirm"],
		[asked.size(), wrong.get("status"), fake.seen.slice(seen_at)])

	asked.clear()
	answer[0] = "right"
	seen_at = fake.seen.size()
	var forbidden: Dictionary = await Api.post("/forbidden", {})
	check("a 403 that does not ask for the password is not asked about",
		asked.is_empty() and int(forbidden.get("status", 0)) == 403
		and fake.seen.slice(seen_at) == ["POST /forbidden"], fake.seen.slice(seen_at))
	seen_at = fake.seen.size()
	var direct: Dictionary = await Api.post(ApiForTests.CONFIRM_PATH, {"password": "wrong"})
	check("  nor is the confirm itself - no asking in a circle",
		asked.is_empty() and int(direct.get("status", 0)) == 403
		and fake.seen.slice(seen_at) == ["POST /api/auth/confirm"], fake.seen.slice(seen_at))
	Api.confirm_handler = Callable()
	fake.confirmed = false
	seen_at = fake.seen.size()
	var nobody: Dictionary = await Api.post("/power", {})
	check("  and with nobody to ask (the login screen), the refusal is the answer",
		int(nobody.get("status", 0)) == 403 and fake.seen.slice(seen_at) == ["POST /power"],
		fake.seen.slice(seen_at))

	# A REMEMBERED LOGIN REFUSED, SAYING WHY. The game reopens, resumes, and is
	# told the login was stolen - or is from before the update.
	var kept_session: String = FileAccess.get_file_as_string(ApiForTests.SESSION_PATH) \
		if FileAccess.file_exists(ApiForTests.SESSION_PATH) else ""
	var kept_name: String = Api.username
	var kept_role: String = Api.role
	var kept_owner: bool = Api.is_owner
	var spoken: Array = []
	for refusal in [{"error": "Unauthorized", "token_stolen": true}, {"error": "Unauthorized", "old_login": true},
			{"error": "Unauthorized"}]:
		fake.resume_refusal = refusal
		Api.token = "remembered"
		var probe: Dictionary = await Api.probe_and_resume()
		spoken.append(str(probe.get("notice", "")))
		check("  (the remembered login is let go: %s)" % JSON.stringify(refusal),
			not probe.get("resumed", true) and Api.token == "", probe)
	check("a remembered login refused as stolen says so on the login screen, and so does one from before the update",
		spoken == [ApiForTests.TOKEN_STOLEN_NOTICE, ApiForTests.OLD_LOGIN_NOTICE, ""], spoken)
	check("  and the login screen says what the probe brought back",
		_func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _check_connection_and_resume(").contains(
			"_say(str(probe.get(\"notice\", \"\")), SAY_BLOCKED)"))
	fake.resume_refusal = {}
	if kept_session != "":
		var restore := FileAccess.open(ApiForTests.SESSION_PATH, FileAccess.WRITE)
		restore.store_string(kept_session)
		restore.close()
	Api._set_identity(kept_name, kept_role, kept_owner)

	ApiForTests.BASE_URL = kept_url
	Api.token = kept_token
	Api.server_online = kept_online
	Api.reachability_known = kept_known
	fake.shutdown()
	fake.queue_free()

	# ---- the prompt ------------------------------------------------------------
	var prompt := PasswordPrompt.new()
	add_child(prompt)
	prompt.ask("Type your password to do this.")
	check("the prompt says the server's words, and when it will ask again",
		prompt.message_label.text.begins_with("Type your password to do this.")
		and prompt.message_label.text.contains("quarter of an hour"), prompt.message_label.text)
	check("  and hides what is typed", prompt.box.secret)
	var got: Array = []
	prompt.answered.connect(func(typed: String) -> void: got.append(typed))
	prompt.box.text = "hunter2"
	prompt.ok_button.pressed.emit()
	check("Confirm answers with what was typed, and empties the box",
		got == ["hunter2"] and prompt.box.text == "", got)
	prompt.ok_button.pressed.emit()
	prompt.cancel_button.pressed.emit()
	check("  once: a second press says nothing more", got.size() == 1, got)
	prompt.queue_free()

	var by_enter := PasswordPrompt.new()
	add_child(by_enter)
	var entered: Array = []
	by_enter.answered.connect(func(typed: String) -> void: entered.append(typed))
	by_enter.box.text = "swordfish"
	by_enter.box.text_submitted.emit("swordfish")
	check("  Enter in the box is Confirm", entered == ["swordfish"], entered)
	by_enter.queue_free()

	var cancelling := PasswordPrompt.new()
	add_child(cancelling)
	var nothing: Array = []
	cancelling.answered.connect(func(typed: String) -> void: nothing.append(typed))
	cancelling.box.text = "half typed"
	cancelling.cancel_button.pressed.emit()
	check("Cancel answers with nothing, whatever was typed, and empties the box",
		nothing == [""] and cancelling.box.text == "", nothing)
	cancelling.queue_free()

	var escaped := PasswordPrompt.new()
	add_child(escaped)
	var by_escape: Array = []
	escaped.answered.connect(func(typed: String) -> void: by_escape.append(typed))
	escaped.box.text = "half typed"
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	escaped._unhandled_input(escape)
	check("  so does Escape", by_escape == [""], by_escape)
	escaped.queue_free()

	# ---- the HUD asks ----------------------------------------------------------
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	check("in the world, the HUD is who asks for the password",
		Api.confirm_handler.is_valid() and Api.confirm_handler.get_object() == hud
		and Api.confirm_handler.get_method() == &"ask_password")
	var typed_back: Array = []
	(func() -> void: typed_back.append(await hud.ask_password("Type your password to do this."))).call()
	await get_tree().process_frame
	var shown: PasswordPrompt = hud.password_prompt
	check("  it puts the prompt up, last on the HUD so it is over every window",
		shown != null and shown.get_parent() == hud and shown.get_index() == hud.get_child_count() - 1
		and shown.message_label.text.begins_with("Type your password"))
	# NOT AWAITED DIRECTLY. Broken, the second ask puts up a prompt of its own
	# and waits for it for ever - and an awaited hang is a suite that never
	# reports. Called aside and looked at a frame later, it is a failure.
	var second: Array = []
	(func() -> void: second.append(await hud.ask_password("Again?"))).call()
	await get_tree().process_frame
	check("  one at a time: a second ask while it is up gets nothing",
		second == [""] and hud.password_prompt == shown, second)
	if shown != null:
		shown.box.text = "hunter2"
		shown.ok_button.pressed.emit()
	await get_tree().process_frame
	check("  and hands back what was typed, and takes the prompt away",
		typed_back == ["hunter2"] and hud.password_prompt == null
		and (not is_instance_valid(shown) or shown.is_queued_for_deletion()), typed_back)
	hud.queue_free()
	await get_tree().process_frame
	check("a HUD gone (the login screen) asks nothing: the refusal is the answer",
		not Api.confirm_handler.is_valid())
	Api.confirm_handler = kept_handler

	# ---- what an ended session says ------------------------------------------
	check("a session ended as stolen says so, and what to do about it",
		ApiForTests.signout_notice_for({"data": {"token_stolen": true}}) == ApiForTests.TOKEN_STOLEN_NOTICE
		and ApiForTests.TOKEN_STOLEN_NOTICE.contains("change your password"))
	check("  a staff login that ran its course says how long one lasts",
		ApiForTests.signout_notice_for({"data": {"staff_session_ended": true}})
			== ApiForTests.STAFF_SESSION_ENDED_NOTICE
		and ApiForTests.STAFF_SESSION_ENDED_NOTICE.contains("12 hours"))
	check("  a login from before the update, ended when the minimum build reached 6, says that",
		ApiForTests.signout_notice_for({"data": {"old_login": true}}) == ApiForTests.OLD_LOGIN_NOTICE
		and ApiForTests.OLD_LOGIN_NOTICE.contains("updated"))
	check("  and the others read as they did",
		ApiForTests.signout_notice_for({"data": {"signed_in_elsewhere": true}}) == ApiForTests.SIGNED_IN_ELSEWHERE_NOTICE
		and ApiForTests.signout_notice_for({}) == ApiForTests.SIGNED_OUT_NOTICE)

	# ---- plain http only to this computer --------------------------------------
	var here := ["http://localhost:5000", "http://127.0.0.1:5000/", "http://127.4.5.6",
		"http://[::1]:5000", "http://[::1]", "http://LOCALHOST:5000"]
	var away := ["http://api.elusionrpg.com", "http://192.168.1.20:5000", "http://10.0.0.1",
		"http://127.evil.example", "http://127.0.0.1.evil.example", "http://[::1].evil.example",
		"http://localhost:80@evil.example", "http://localhost@evil.example/", "http://evil.localhost"]
	var wrong_here: Array = here.filter(func(url: String) -> bool: return not ApiForTests.is_this_computer(url))
	var wrong_away: Array = away.filter(func(url: String) -> bool: return ApiForTests.is_this_computer(url))
	check("this computer is localhost, 127.x.x.x and [::1] - exactly", wrong_here.is_empty(), wrong_here)
	check("  and a name that only begins like one is somewhere else", wrong_away.is_empty(), wrong_away)
	var let_out: Array = away.filter(func(url: String) -> bool:
		return ApiForTests._clean_base_url(url) != ApiForTests.DEFAULT_BASE_URL)
	check("an override over plain http to anywhere else is ignored, for the default",
		let_out.is_empty(), let_out)
	check("  https goes anywhere, and http stays for the server on this computer",
		ApiForTests._clean_base_url("https://api.elusionrpg.com/") == "https://api.elusionrpg.com"
		and ApiForTests._clean_base_url("http://127.0.0.1:5001") == "http://127.0.0.1:5001")
	check("  a browser page keeps its own address, http or not - it came over it",
		ApiForTests.web_base_url("http://192.168.1.20:8061") == "http://192.168.1.20:8061")
	print("  tokens: install id on %d header builders; step-up asked, confirmed and sent again" % builders)


# =============================================================================
# THE HEALER'S AIM (0.26.0)
# =============================================================================

func _test_the_healer_aims_from_its_middle() -> void:
	section("HEALER AND WARRIOR - the attack leaves the middle of the body, and a ring shows where it goes (0.26.0)")
	# The owner: auto fire "is broken between flipping from left auto fire to
	# top left and right to top right where as bottom directionals are fine",
	# and the ring under the character was the owner's idea. Not added to the
	# tree: player.gd's _ready() is the camera, the pets and the save.
	var healer: Node2D = (load("res://scene/characters/healer.tscn") as PackedScene).instantiate()
	healer.position = Vector2(300, 200)
	var middle: Vector2 = healer.aim_origin()
	check("a healer aims and fires from the middle of its body, 16 px above its feet",
		middle.is_equal_approx(Vector2(300, 184)), middle)
	var level: Vector2 = healer.aim_direction_to(middle + Vector2(-90, 0))
	var from_feet: float = rad_to_deg(absf(angle_difference((middle + Vector2(-90, 0) - healer.position).angle(), PI)))
	check("  so a cursor level with the chest, to the left, is straight left (from the feet it was %.0f degrees up)" % from_feet,
		level.is_equal_approx(Vector2.LEFT) and from_feet > 9.0, [level, from_feet])
	var up_left: Vector2 = healer.aim_direction_to(middle + Vector2(-60, -30))
	var down_left: Vector2 = healer.aim_direction_to(middle + Vector2(-60, 30))
	check("  and the upper and lower diagonals are mirror images of each other",
		is_equal_approx(up_left.x, down_left.x) and is_equal_approx(up_left.y, -down_left.y), [up_left, down_left])
	var spawn_body: String = _func_body(_code_src("res://src/characters/healer.gd"), "func _spawn_projectile(")
	check("  the orb is placed there too, and the others' picture of it leaves from there",
		spawn_body.contains("projectile.global_position = reach_short_of_wall(aim_origin())")
		and spawn_body.contains("Presence.tell_attack(\"orb\", aim_origin()"))

	healer.call("_add_aim_ring")
	var ring: AimRing = healer.get_node_or_null(^"aimring") as AimRing
	check("the healer carries an aim ring round its feet, drawn under its sprite",
		ring != null and healer.get_child(0) == ring and ring.position.y > -4.0, ring)
	if ring != null:
		ring.point_at(healer.aim_direction_to(middle + Vector2(-90, 0)))
		var left_ball: Vector2 = ring.ball_position()
		ring.point_at(healer.aim_direction_to(middle + Vector2(0, -90)))
		var top_ball: Vector2 = ring.ball_position()
		check("  its ball sits where the next shot goes: the left end for left, the far side for up",
			left_ball.is_equal_approx(Vector2(-AimRing.RADII.x, 0)) and top_ball.is_equal_approx(Vector2(0, -AimRing.RADII.y)),
			[left_ball, top_ball])
		var ball: Node2D = ring.get_node_or_null(^"ball") as Node2D
		check("  the ball is drawn a layer above the healer, so aiming up does not hide it behind the legs",
			ball != null and ball.z_index >= 1 and ball.z_as_relative, ball)
		ring.fired()
		check("  and it brightens as a shot leaves", ring.get("_glow") > 0.0)
	healer.free()

	# THE WARRIOR TOO - the owner: "add to warrior also". Its origin is already
	# the middle of its picture (sprite drawn 3 px above, feet 13 below), so it
	# aims from there; the ring goes round its feet.
	var warrior: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.position = Vector2(300, 200)
	warrior.call("_add_aim_ring")
	var wring: AimRing = warrior.get_node_or_null(^"aimring") as AimRing
	check("the warrior carries the ring too, round its feet 13 px below its origin, under its sprite",
		wring != null and warrior.get_child(0) == wring and wring.position.is_equal_approx(Vector2(0, 12.5)), wring)
	check("  and aims from its middle: a cursor level with it, to the left, is straight left",
		(warrior.aim_direction_to(Vector2(210, 200)) as Vector2).is_equal_approx(Vector2.LEFT))
	var swing_body: String = _func_body(_code_src("res://src/characters/warrior.gd"), "func attack_action(")
	var frame_body: String = _func_body(_code_src("res://src/characters/warrior.gd"), "func _physics_process(")
	check("  its swing and its ring read the same aim, and the ring brightens as it swings",
		swing_body.contains("_swing_aim_direction = aim_direction_to(aim_point())")
		and swing_body.contains("_aim_ring_fired()")
		and frame_body.contains("_point_aim_ring(aim_direction_to(aim_point()))"))
	warrior.free()
	var putting_on: Array[String] = []
	for kit in ["healer", "warrior", "mage", "tank"]:
		if _func_body(_code_src("res://src/characters/%s.gd" % kit), "func _ready(").contains("_add_aim_ring()"):
			putting_on.append(kit)
	check("all four classes put the ring on as they are set up (the mage and the tank since 0.33.0)",
		putting_on.size() == 4, putting_on)
	_test_the_mage_and_tank_aim_rings()


func _test_the_mage_and_tank_aim_rings() -> void:
	# THE MAGE AND THE TANK (0.33.0) - the owner: "meant mage and tank just aim
	# ring". Both attack a POINT, so the ball points at it from the middle of
	# the ring. The tank's body is y-sorted with its picture placed above its
	# feet, so its ring is placed above the picture - drawn first - and drawn
	# down at the feet. The mage's was too until 0.68.1, which sorted its
	# picture 19 px above its feet against the world - behind any wall it stood
	# in front of (the owner: "big error on walls"); now it is not y-sorted,
	# and its ring is simply its first child, at its feet.
	var mage: Node2D = (load("res://scene/characters/mage.tscn") as PackedScene).instantiate()
	mage.position = Vector2(300, 200)
	mage.call("_add_aim_ring")
	var mring: AimRing = mage.get_node_or_null(^"aimring") as AimRing
	var mage_picture: Node2D = mage.get_node(^"animatedsprite2d") as Node2D
	check("the mage carries the ring round the hem of its robe, a pixel above its origin",
		mring != null and mage.get_child(0) == mring and mring.line
		and (mring.position + mring.drawn_at).is_equal_approx(Vector2(0, -1)), mring)
	if mring != null:
		check("  drawn first - under the robe - by being its first child, at its feet (its body is not y-sorted)",
			not mage.y_sort_enabled and mage.get_child(0) == mring and is_zero_approx(mring.drawn_at.y)
			and mring.position.is_equal_approx(Vector2(0, -1)), [mring.position, mage_picture.position])
		check("  and its middle, in the world, is where it is drawn",
			mring.centre().is_equal_approx(Vector2(300, 199)), mring.centre())
		mage.call("_point_aim_ring_at", Vector2(210, 199))
		var left_ball: Vector2 = mring.ball_position()
		mage.call("_point_aim_ring_at", Vector2(300, 260))
		var down_ball: Vector2 = mring.ball_position()
		check("  its ball points at where the spell comes down, seen from the middle of the ring",
			left_ball.is_equal_approx(Vector2(-AimRing.RADII.x, 0)) and down_ball.is_equal_approx(Vector2(0, AimRing.RADII.y)),
			[left_ball, down_ball])
		mage.set("last_direction", Vector2.UP)
		mage.call("_point_aim_ring_at", mring.centre())
		check("  and a cursor on the middle of the ring keeps the facing",
			mring.ball_position().is_equal_approx(Vector2(0, -AimRing.RADII.y)), mring.ball_position())
	mage.free()
	var mage_src: String = _code_src("res://src/characters/mage.gd")
	check("  it follows the cursor every frame, and brightens as a stalagmite or a meteor is cast",
		_func_body(mage_src, "func _physics_process(").contains("_point_aim_ring_at(aim_point())")
		and _func_body(mage_src, "func _cast_stalagmite_drop(").contains("_aim_ring_fired()"))

	var tank: Node2D = (load("res://scene/characters/tank.tscn") as PackedScene).instantiate()
	tank.position = Vector2(300, 200)
	tank.call("_add_aim_ring")
	var tring: AimRing = tank.get_node_or_null(^"aimring") as AimRing
	var own: Node2D = tank.get_node(^"ring") as Node2D
	var own_middle: Vector2 = own.position + tank.OWN_RING_FROM_FRAME_MIDDLE * own.scale
	check("the tank's ball rides the orange ring it already wears: its middle, its size, and no second line",
		tring != null and tank.get_child(0) == tring and not tring.line
		and (tring.position + tring.drawn_at).is_equal_approx(own_middle)
		and tring.radii.is_equal_approx(tank.OWN_RING_HALF * own.scale), tring)
	if tring != null:
		check("  placed above the tank's picture, as the mage's is",
			tring.position.y < (tank.get_node(^"animatedsprite2d") as Node2D).position.y, tring.position)
		# The orange ellipse measured off the art's first frame: the outer edge
		# of its 2 px line along the middle row and the middle column.
		var art: Image = (load("res://art/maincharacter/smalltankring.png") as Texture2D).get_image()
		var frame_middle := Vector2i(64, 64)
		var row: int = frame_middle.y + int(tank.OWN_RING_FROM_FRAME_MIDDLE.y)
		var across: Array[int] = []
		var down: Array[int] = []
		for i in 128:
			if art.get_pixel(i, row).a > 0.08:
				across.append(i)
			if art.get_pixel(frame_middle.x, i).a > 0.08:
				down.append(i)
		var outer := Rect2()
		if not across.is_empty() and not down.is_empty():
			var left: int = across[0]
			var right: int = across[across.size() - 1] + 1
			var top: int = down[0]
			var bottom: int = down[down.size() - 1] + 1
			outer = Rect2(left, top, right - left, bottom - top)
		check("  the orange ring's size and middle are the art's",
			(outer.get_center() - Vector2(frame_middle)).is_equal_approx(tank.OWN_RING_FROM_FRAME_MIDDLE)
			and (outer.size / 2.0 - Vector2.ONE).is_equal_approx(tank.OWN_RING_HALF), outer)
		tank.call("_point_aim_ring_at", tring.centre() + Vector2(0, 200))
		check("  its ball points at the cursor: below, the near side of the orange ring",
			tring.ball_position().is_equal_approx(Vector2(0, tring.radii.y)), tring.ball_position())
		var far: Vector2 = tank.dynamite_landing(Vector2(300 + 1000, 200))
		check("  and with Dynamite on, at where the stick comes down - as far toward the cursor as a throw goes",
			far.is_equal_approx(Vector2(300 + tank.DYNAMITE_MAX_THROW, 200)), far)
	tank.free()
	var tank_src: String = _code_src("res://src/characters/tank.gd")
	check("  it follows every frame, and brightens as a stick is thrown or the aura lit",
		_func_body(tank_src, "func _physics_process(").contains("_point_aim_ring_at(aim_ring_point())")
		and _func_body(tank_src, "func aim_ring_point(").contains("return dynamite_landing(cursor)")
		and _func_body(tank_src, "func throw_dynamite(").contains("_aim_ring_fired()")
		and _func_body(tank_src, "func throw_dynamite(").contains("var landing: Vector2 = dynamite_landing(aimed_at)")
		and _func_body(tank_src, "func _activate_aura(").contains("_aim_ring_fired()"))


# =============================================================================
# THE TANK'S AURA BURNS ON THE GROUND (0.34.0)
# =============================================================================

func _test_the_tank_aura_burns() -> void:
	section("THE TANK'S AURA BURNS ON THE GROUND - glow, flames and embers while it is lit, scorch left behind (0.34.0)")
	# The owner, with a picture of the lit aura: "i want us to elavate the
	# animation by adding effects and born on the ground", and "Both" - the
	# floor inside the ring glowing with small flames, and scorch left behind.
	# The tank's own scene with its script taken off, so the real fire ring is
	# in the tree without player.gd's _ready() (the camera, the pets, the save).
	var scene_root: Node = get_tree().current_scene
	var ground := Node2D.new()
	ground.name = "ground"
	scene_root.add_child(ground)
	var body: Node2D = (load("res://scene/characters/tank.tscn") as PackedScene).instantiate()
	body.set_script(null)
	body.position = Vector2(400, 300)
	var fire: AnimatedSprite2D = body.get_node(^"firering") as AnimatedSprite2D
	fire.visible = false
	scene_root.add_child(body)
	var burn: AuraBurn = AuraBurn.on(body)
	await get_tree().process_frame
	if burn == null:
		check("a tank's fire ring gets a burn", false)
		body.queue_free()
		ground.queue_free()
		return
	check("a tank's fire ring gets a burn, once, as its first child, placed above its pictures - the fire ring's too - so it draws under them",
		AuraBurn.on(body) == burn and body.get_child(0) == burn
		and burn.position.y < fire.position.y
		and burn.position.y < (body.get_node(^"ring") as Node2D).position.y
		and burn.position.y < (body.get_node(^"animatedsprite2d") as Node2D).position.y, burn.position)

	# Round the fire ring's own ellipse, measured off its art - the third
	# frame, where no spark stands on the line at the middle row (in the first,
	# one sticks a pixel out past its right end).
	var art: Image = (load("res://art/maincharacter/largeringonly.png") as Texture2D).get_image()
	var frame_x: int = 256
	var row: int = int(AuraBurn.FIRE_FROM_FRAME_CORNER.y)
	var col: int = int(AuraBurn.FIRE_FROM_FRAME_CORNER.x)
	var across: Array[int] = []
	var down: Array[int] = []
	for i in 128:
		if art.get_pixel(frame_x + i, row).a > 0.08:
			across.append(i)
		if art.get_pixel(frame_x + col, i).a > 0.08:
			down.append(i)
	var outer := Rect2()
	if not across.is_empty() and not down.is_empty():
		outer = Rect2(across[0], down[0], across[across.size() - 1] + 1 - across[0], down[down.size() - 1] + 1 - down[0])
	check("  round the fire ring's own ellipse, measured off its art",
		outer.get_center().is_equal_approx(AuraBurn.FIRE_FROM_FRAME_CORNER)
		and (outer.size / 2.0 - Vector2.ONE).is_equal_approx(AuraBurn.FIRE_HALF), outer)
	var aura_shape: CollisionShape2D = body.get_node(^"aura/collisionshape2d") as CollisionShape2D
	var capsule: CapsuleShape2D = aura_shape.shape as CapsuleShape2D
	var aura_middle: Vector2 = (body.get_node(^"aura") as Node2D).position + aura_shape.position
	var aura_half := Vector2(capsule.height / 2.0, capsule.radius)
	check("  which is where the aura burns: its middle and its size within 2 px of the aura's own shape",
		burn.centre.distance_to(aura_middle) <= 2.0 and absf(burn.radii.x - aura_half.x) <= 2.0
		and absf(burn.radii.y - aura_half.y) <= 2.0, [burn.centre, burn.radii, aura_middle, aura_half])

	check("out while the aura is out: no glow, no flames, no embers, no light",
		not burn.lit and burn.heat == 0.0 and not burn.flames.emitting and not burn.embers.emitting and not burn.light.enabled)
	fire.visible = true
	burn._process(AuraBurn.LIGHT_UP_SECONDS)
	check("lit with the fire ring: flames and embers, and the glow up to full",
		burn.lit and burn.flames.emitting and burn.embers.emitting and is_equal_approx(burn.heat, 1.0))
	var ring_material: CanvasItemMaterial = fire.material as CanvasItemMaterial
	check("  the ring itself is unshaded - fire in the dark - and pulses brighter, never darker than its art",
		ring_material != null and ring_material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
		and fire.self_modulate.r >= 1.0 and fire.self_modulate.r <= 1.0 + AuraBurn.RING_PULSE + 0.001, fire.self_modulate)
	check("  the glow is brightest just inside the flames, dimmer in the middle, gone a little past them",
		is_equal_approx(AuraBurn.glow_band(0.0), AuraBurn.GLOW_MIDDLE) and is_equal_approx(AuraBurn.glow_band(0.9), 1.0)
		and AuraBurn.glow_band(1.05) > 0.0 and AuraBurn.glow_band(AuraBurn.GLOW_SPILL) == 0.0)
	var glow_material: CanvasItemMaterial = burn.material as CanvasItemMaterial
	check("  added and unshaded, so it lights the floor under it rather than painting over it",
		glow_material != null and glow_material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
		and glow_material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED)
	var on_floor: bool = true
	for point in burn.flames.emission_points:
		on_floor = on_floor and Vector2(point.x / burn.radii.x, point.y / burn.radii.y).length() <= 0.9
	var on_line: bool = true
	for point in burn.embers.emission_points:
		on_line = on_line and absf(Vector2(point.x / burn.radii.x, point.y / burn.radii.y).length() - 1.0) < 0.01
	check("  the flames rise off the floor inside the ring, the embers off its line",
		on_floor and on_line and burn.flames.position.is_equal_approx(burn.drawn_at()))
	check("  no light where it is not dark (no CanvasModulate here)", not burn.light.enabled)

	var dark := CanvasModulate.new()
	dark.color = Color.WHITE
	scene_root.add_child(dark)
	fire.visible = false
	fire.visible = true
	burn._process(0.05)
	check("  in a dark area a light flickers with it, switched by enabled - visible stays Settings' (\"simple\" hides it)",
		burn.light.enabled and burn.light.energy > 0.0
		and not _code_src("res://src/characters/auraburn.gd").contains("light.visible"))
	scene_root.remove_child(dark)
	dark.free()

	# THE SCORCH.
	var marks: ScorchMarks = ScorchMarks.of(get_tree())
	check("the scorch goes on the area's floor - a child of its \"ground\" - and only one",
		marks != null and marks.get_parent() == ground and ScorchMarks.of(get_tree()) == marks)
	if marks == null:
		body.queue_free()
		ground.queue_free()
		return
	marks.marks.clear()
	burn.set("_scorch_owed", 0.0)
	burn.set("_has_last_spot", false)
	burn._process(1.0)
	var middle: Vector2 = burn.to_global(burn.drawn_at())
	var inside: bool = true
	for mark in marks.marks:
		var off: Vector2 = marks.to_global(mark["at"]) - middle
		inside = inside and Vector2(off.x / burn.radii.x, off.y / burn.radii.y).length() <= AuraBurn.SCORCH_REACH + 0.05
	check("  standing still, SCORCH_PER_SECOND patches a second, all on the floor inside the ring",
		marks.marks.size() == int(AuraBurn.SCORCH_PER_SECOND) and inside, marks.marks.size())
	var before: int = marks.marks.size()
	body.position += Vector2(AuraBurn.SCORCH_EVERY_PX * 5.0, 0.0)
	burn._process(0.0)
	check("  walking lays more: one for every SCORCH_EVERY_PX the ring moves",
		marks.marks.size() - before == 5, marks.marks.size() - before)
	before = marks.marks.size()
	body.position += Vector2(AuraBurn.SCORCH_JUMP * 4.0, 0.0)
	burn._process(0.0)
	check("  and a jump (a portal, a respawn) is not a walk", marks.marks.size() == before, marks.marks.size() - before)
	check("a patch holds, then fades, and is gone by LIFE",
		ScorchMarks.fade(0.0) == 1.0 and ScorchMarks.fade(ScorchMarks.HOLD) == 1.0
		and ScorchMarks.fade((ScorchMarks.HOLD + ScorchMarks.LIFE) / 2.0) > 0.0
		and ScorchMarks.fade((ScorchMarks.HOLD + ScorchMarks.LIFE) / 2.0) < 1.0 and ScorchMarks.fade(ScorchMarks.LIFE) == 0.0)
	check("  its embers are hot as it is laid and out within EMBER_SECONDS",
		ScorchMarks.ember_heat(0.0, 1.0) == 1.0 and ScorchMarks.ember_heat(ScorchMarks.EMBER_SECONDS, 1.0) == 0.0
		and ScorchMarks.ember_heat(ScorchMarks.EMBER_SECONDS * 0.5, 0.5) == 0.0
		and ScorchMarks.EMBER_SECONDS < ScorchMarks.LIFE)
	var all_embered: bool = true
	for mark in marks.marks:
		all_embered = all_embered and (mark["embers"] as Array).size() >= 2 and (mark["embers"] as Array).size() <= 4
	check("  two to four embers in every patch", all_embered and not marks.marks.is_empty())
	fire.visible = false
	burn._process(AuraBurn.GO_OUT_SECONDS)
	before = marks.marks.size()
	burn._process(1.0)
	check("out again: the fire dies down and lays no more scorch",
		not burn.lit and burn.heat == 0.0 and not burn.flames.emitting and not burn.embers.emitting
		and not burn.light.enabled and marks.marks.size() == before)
	marks._process(ScorchMarks.LIFE + 0.01)
	check("  and what it left is gone once LIFE has passed", marks.marks.is_empty())
	for i in ScorchMarks.MOST + 20:
		marks.burn(middle)
	check("  at most ScorchMarks.MOST at once, the oldest going first", marks.marks.size() == ScorchMarks.MOST, marks.marks.size())
	marks.marks.clear()
	# NOT ON WATER: a ground of tiles is floor only where it has one.
	var tiles := TileMapLayer.new()
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(16, 16)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
	source.texture_region_size = Vector2i(16, 16)
	source.create_tile(Vector2i(0, 0))
	var source_id: int = tile_set.add_source(source)
	tiles.tile_set = tile_set
	tiles.set_cell(Vector2i(2, 2), source_id, Vector2i(0, 0))
	var tiled := ScorchMarks.new()
	tiles.add_child(tiled)
	scene_root.add_child(tiles)
	check("  and never off the floor: where the ground has no tile (water shows through) no patch is laid",
		tiled.burn(Vector2(40, 40)) and not tiled.burn(Vector2(100, 40)) and tiled.marks.size() == 1, tiled.marks.size())
	tiles.queue_free()
	var blots: Array[ImageTexture] = ScorchMarks.blot_textures()
	var widths: Array[int] = []
	for blot in blots:
		widths.append(blot.get_width())
	check("  drawn from ScorchMarks.VARIANTS small pixel blots, 16 to 30 px across",
		blots.size() == ScorchMarks.VARIANTS and widths.min() == 16 and widths.max() == 30, widths)

	body.queue_free()
	ground.queue_free()
	check("the tank puts it on as it is set up, and a remote tank gets one with its body",
		_func_body(_code_src("res://src/characters/tank.gd"), "func _ready(").contains("AuraBurn.on(self)")
		and _func_body(_code_src("res://src/characters/remoteplayer.gd"), "func _build_body(").contains("AuraBurn.on(self)"))


# =============================================================================
# THE MAGE'S SPELL, WITH EFFECTS (0.35.0)
# =============================================================================

func _test_the_mage_spell_effects() -> void:
	section("THE MAGE'S SPELL - motes off the staff, a frost ring and a shadow, the shatter, frost left to melt (0.35.0)")
	# The owner: "time to give the mages attack some effects", and all four of
	# the ones offered.
	var scene_root: Node = get_tree().current_scene
	var arena := Node2D.new()
	arena.name = "spelltest"
	scene_root.add_child(arena)

	# ---- the motes off the staff ----------------------------------------------
	# Where the gem is in each facing's cast, measured off mage.png: the cyan
	# pixels of the gem in the first frame of each attack animation.
	var sheet: Image = (load("res://art/maincharacter/mage.png") as Texture2D).get_image()
	var rows: Dictionary = {"down": 1344, "up": 1536, "left": 1472, "right": 1408}
	var off_by: Dictionary = {}
	for facing in rows:
		var sum := Vector2.ZERO
		var count: int = 0
		for y in 64:
			for x in 64:
				var c: Color = sheet.get_pixel(x, int(rows[facing]) + y)
				if c.a > 0.8 and c.b > 0.7 and c.g > 0.6 and c.r < 0.55:
					sum += Vector2(x, y)
					count += 1
		var gem: Vector2 = sum / maxf(count, 1.0) - Vector2(32, 32)
		off_by[facing] = snappedf(gem.distance_to(CastSparkle.GEM[facing]), 0.1)
	var all_close: bool = true
	for facing in off_by:
		all_close = all_close and float(off_by[facing]) <= 1.0
	check("the motes leave the staff's gem, wherever the cast holds it: each facing within a pixel of the art",
		all_close, off_by)
	var body := Node2D.new()
	var picture := Node2D.new()
	picture.name = "animatedsprite2d"
	picture.position = Vector2(0, -19)
	body.add_child(picture)
	body.position = Vector2(200, 200)
	arena.add_child(body)
	var frost: CastSparkle = CastSparkle.burst(body, "left", Vector2(100, 200))
	var streak: CPUParticles2D = frost.get_node_or_null(^"streak") as CPUParticles2D
	check("  a burst round the gem and a streak toward where the spell goes, both whole-pixel and unshaded",
		frost.get_parent() == body and frost.position.is_equal_approx(Vector2(0, -19) + CastSparkle.GEM["left"])
		and frost.emitting and frost.one_shot and streak != null and streak.emitting
		and streak.direction.x < -0.9 and frost.scale_amount_min == 1.0 and frost.scale_amount_max == 1.0
		and (frost.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED,
		[frost.position, streak])
	check("  and gone once the last of them is (it frees itself)",
		frost.finished.is_connected(frost.queue_free))
	var cold: Color = CastSparkle.colours(CastSparkle.FROST).sample(0.4)
	var hot: Color = CastSparkle.colours(CastSparkle.EMBER).sample(0.4)
	check("  frost for the stalagmite, embers for the meteor", cold.b > cold.r and hot.r > hot.b, [cold, hot])
	var cast_body: String = _func_body(_code_src("res://src/characters/mage.gd"), "func _cast_stalagmite_drop(")
	check("  thrown on every cast, the way the mage faces, toward the cursor",
		cast_body.contains("CastSparkle.burst(self, _direction_to_string(last_direction), aim_point(),")
		and cast_body.contains("CastSparkle.EMBER if meteor else CastSparkle.FROST"))
	var remote_src: String = _code_src("res://src/characters/remoteattacks.gd")
	var them: Node2D = (load("res://src/characters/remoteplayer.gd") as GDScript).new()
	them.set("anim", "attackleft")
	check("  and by a picture of somebody else's mage, facing the way it faces",
		_func_body(remote_src, "static func _stalagmite(").contains("CastSparkle.burst(body, facing_of(body), target, CastSparkle.FROST)")
		and _func_body(remote_src, "static func _meteor(").contains("CastSparkle.burst(body, facing_of(body), target, CastSparkle.EMBER)")
		and RemoteAttacks.facing_of(them) == "left")
	them.free()

	# ---- the frost ring and the shadow ------------------------------------------
	var spell: Node2D = (load("res://scene/projectiles/spelltargetcircle.tscn") as PackedScene).instantiate()
	spell.set("cosmetic", true)
	arena.add_child(spell)
	spell.global_position = Vector2(300, 260)
	await get_tree().process_frame
	var fall_anim: AnimatedSprite2D = spell.get_node(^"stalagmiteprojectile") as AnimatedSprite2D
	fall_anim.pause()
	fall_anim.frame = 0
	var at_cast: float = spell.call("fall_progress")
	fall_anim.set_frame_and_progress(2, 0.0)
	var halfway: float = spell.call("fall_progress")
	check("the ring frosts in and the shadow grows as the spike falls: 0 at the cast, halfway at frame 2",
		is_equal_approx(at_cast, 0.0) and is_equal_approx(halfway, 2.0 / 4.0), [at_cast, halfway])
	var src: String = _code_src("res://src/projectiles/spelltargetcircle.gd")
	var draw_body: String = _func_body(src, "func _draw(")
	check("  a 1 px ring, not antialiased, still exactly the hit; the meteor's pixel shadow under it",
		draw_body.contains("draw_arc(Vector2.ZERO, circle_radius, 0.0, TAU, 48, ring, 1.0, false)")
		and draw_body.contains("Blast.shadow_texture(") and not src.contains("Color(1.0, 0.1, 0.1")
		and is_equal_approx(float(spell.get("circle_radius")),
			((spell.get_node(^"targetcircle") as CollisionShape2D).shape as CircleShape2D).radius))

	# ---- the shatter, and the frost left behind ----------------------------------
	var before: Array = arena.get_children()
	fall_anim.frame = 4
	var made: Array = arena.get_children().filter(func(n: Node) -> bool: return not before.has(n))
	var shatter: Blast = null
	var mark: Sprite2D = null
	for n in made:
		if n is Blast:
			shatter = n
		elif n is Sprite2D and (n as Node).is_in_group("blastmarks"):
			mark = n
	check("it shatters as it lands: Blast's stalagmite kind, where it struck, beside the spell so it outlives it",
		shatter != null and shatter.kind == &"stalagmite" and shatter.global_position == Vector2(300, 260)
		and is_equal_approx(shatter.radius, float(spell.get("circle_radius"))), made)
	check("  a picture of somebody else's shakes nobody's camera",
		shatter != null and not shatter.shakes)
	var parts: Array[String] = []
	if shatter != null:
		for child in shatter.get_children():
			parts.append(str(child.name) if not (child is CPUParticles2D) else "particles")
	check("  a flash, a ring of air and three handfuls - mist, shards, glints",
		parts.has("flash") and parts.has("ring") and parts.count("particles") == 3, parts)
	var flash: Sprite2D = shatter.get_node_or_null(^"flash") as Sprite2D if shatter != null else null
	var flash_middle: Color = Color.BLACK
	if flash != null:
		var flash_image: Image = flash.texture.get_image()
		flash_middle = flash_image.get_pixel(flash_image.get_width() >> 1, flash_image.get_height() >> 1)
	check("  the flash is cold: blue-white, where a dynamite's is yellow-white",
		flash_middle.b > flash_middle.r - 0.01 and flash_middle.b > 0.95 and flash_middle.r < 0.95, flash_middle)
	check("  and the camera shakes least of all the blasts - a mage casts every second",
		Blast.SHAKE[&"stalagmite"].x < Blast.SHAKE[&"dynamite"].x and Blast.SHAKE[&"stalagmite"].x < Blast.SHAKE[&"meteor"].x)
	var frost_image: Image = mark.texture.get_image() if mark != null else null
	var pale: int = 0
	if frost_image != null:
		for y in frost_image.get_height():
			for x in frost_image.get_width():
				var c: Color = frost_image.get_pixel(x, y)
				if c.a > 0.0 and c.b >= c.r and c.b > 0.9:
					pale += 1
	check("frost is left on the floor - pale ice, on the floor's layer, glinting",
		mark != null and mark.z_index == -2 and not mark.z_as_relative and pale > 20
		and mark.get_node_or_null(^"twinkles") is CPUParticles2D, [mark, pale])
	check("  and it melts: it fades and draws in over the last part of Blast.MARK_SECONDS",
		_func_body(_code_src("res://src/projectiles/blast.gd"), "func _leave_mark(").contains(
			"t.parallel().tween_property(mark, \"scale\", Vector2(0.7, 0.7), MARK_SECONDS * 0.4)"))
	check("a disc's colours are part of what it is cached as - one size in two colours is two textures",
		Blast.disc_texture(9, Color.RED, Color.RED) != Blast.disc_texture(9, Color.BLUE, Color.BLUE))
	arena.queue_free()
	await get_tree().process_frame


# =============================================================================
# THE HEALER'S ORBS, MIXED WITH THE CRYPT'S (0.36.0)
# =============================================================================

func _test_the_healer_orbs() -> void:
	section("THE HEALER'S ORBS - the paid orb with the crypt bullet's glow, a fan of crypt orbs, wisps and a splash (0.36.0)")
	# The owner: keep the orb he paid for, mix in "the bullets from crypt", and
	# "adding a effect also" - with their patterns too.
	const HealerScript := preload("res://src/characters/healer.gd")
	var scene_root: Node = get_tree().current_scene
	var arena := Node2D.new()
	arena.name = "orbtest"
	scene_root.add_child(arena)

	var fanning: Array[int] = []
	for shot in range(1, 11):
		if HealerScript.fans_on(shot):
			fanning.append(shot)
	check("every fifth shot throws the fan", fanning == [5, 10] and HealerScript.FAN_EVERY == 5, fanning)
	var ways: Array[Vector2] = HealerScript.fan_directions(Vector2.RIGHT)
	var angles: Array[float] = []
	for way in ways:
		angles.append(snappedf(rad_to_deg(way.angle()), 0.01))
	angles.sort()
	check("  two orbs, FAN_SPREAD_DEGREES either side of the shot",
		HealerScript.FAN_ORBS == 2 and angles == [-HealerScript.FAN_SPREAD_DEGREES, HealerScript.FAN_SPREAD_DEGREES], angles)
	var healer_src: String = _code_src("res://src/characters/healer.gd")
	var fan_body: String = _func_body(healer_src, "func _spawn_fan(")
	check("  each a crypt orb for FAN_SHARE of the shot, set as one before it is added - its _ready() reads it",
		is_equal_approx(HealerScript.FAN_SHARE, 0.5)
		and fan_body.contains("orb.set(\"damage\", maxi(1, roundi(shot_damage * FAN_SHARE)))")
		and fan_body.find("orb.set(\"fan\", true)") >= 0
		and fan_body.find("orb.set(\"fan\", true)") < fan_body.find("add_child(orb)"))
	var fire_body: String = _func_body(healer_src, "func _fire_projectile(")
	var spawn_body: String = _func_body(healer_src, "func _spawn_projectile(")
	check("  thrown with the shot that fans, no mana of its own, and told to everyone with the shot",
		fire_body.contains("_spawn_projectile(direction, fans_on(_shots))")
		and fire_body.count("mana -=") == 1
		and spawn_body.contains("_spawn_fan(direction, shot_damage)")
		and spawn_body.contains("RemoteAttacks.FLAG_FAN if fanned else 0"))
	check("  motes where every orb leaves", fire_body.contains("CastSparkle.muzzle(self, AIM_FROM,"))

	# ---- the paid orb, dressed -------------------------------------------------------
	var orb_scene: PackedScene = load("res://scene/projectiles/turretprojectile.tscn") as PackedScene
	var orb: Area2D = orb_scene.instantiate() as Area2D
	orb.set("cosmetic", true)
	arena.add_child(orb)
	orb.global_position = Vector2(400, 300)
	var paid: AnimatedSprite2D = orb.get_node(^"animatedsprite2d") as AnimatedSprite2D
	var glow: Sprite2D = orb.get_node_or_null(^"glow") as Sprite2D
	var core: Sprite2D = orb.get_node_or_null(^"core") as Sprite2D
	var trail: CPUParticles2D = orb.get_node_or_null(^"trail") as CPUParticles2D
	check("the paid orb keeps its art, with the crypt bullet's glow behind it and a white-hot core on its ball",
		paid.visible and glow != null and orb.get_child(0) == glow and core != null
		and (glow.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
		and (core.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
		and core.texture.get_image().get_pixel(0, 0).r > 0.9, [glow, core])
	check("  and leaves green wisps behind it, a world pixel each, staying where they were left",
		trail != null and trail.emitting and not trail.local_coords
		and is_equal_approx(trail.global_scale.x, 1.0), trail)
	var homing: float = float(orb.get("homing_turn_rate"))
	var struck := Node2D.new()
	orb.call("_hit", struck)
	struck.free()
	var splash: Node = null
	var left_trail: CPUParticles2D = null
	for child in arena.get_children():
		if str(child.name) == "orbsplash":
			splash = child
		elif child is CPUParticles2D and str(child.name) == "trail":
			left_trail = child
	check("where it lands: a splash of green sparks and a small ring of air, over whoever it hit",
		splash != null and splash.get_node_or_null(^"sparks") is CPUParticles2D
		and splash.get_node_or_null(^"ring") != null and (splash as Node2D).z_index == 5
		and (splash as Node2D).global_position.is_equal_approx(Vector2(400, 300)), splash)
	check("  and its wisps stay a moment after it has gone, no longer coming",
		left_trail != null and not left_trail.emitting and orb.is_queued_for_deletion())
	check("  the paid orb still homes", homing > 0.0)

	# ---- a fan orb is a crypt bullet ----------------------------------------------------
	var fan_orb: Area2D = orb_scene.instantiate() as Area2D
	fan_orb.set("cosmetic", true)
	fan_orb.set("fan", true)
	arena.add_child(fan_orb)
	var crypt: Sprite2D = fan_orb.get_node_or_null(^"cryptorb") as Sprite2D
	var crypt_image: Image = crypt.texture.get_image() if crypt != null else null
	check("a fan orb is the crypt's bullet: the paid art hidden, a white core in a green body, 8 world pixels",
		crypt != null and not (fan_orb.get_node(^"animatedsprite2d") as CanvasItem).visible
		and crypt_image.get_pixel(3, 3) == Color.WHITE and crypt_image.get_pixel(1, 3).g > crypt_image.get_pixel(1, 3).r
		and is_equal_approx(crypt.global_scale.x * crypt_image.get_width(), 8.0), crypt)
	check("  and flies like one: straight, no homing, no weave",
		float(fan_orb.get("homing_turn_rate")) == 0.0 and float(fan_orb.get("weave_amplitude_deg")) == 0.0
		and fan_orb.get("_homing_target") == null)
	fan_orb.queue_free()

	# ---- THE DOUBLE (0.37.0) -------------------------------------------------------------
	# The owner: "add a 20% chance to deal dbl damage on 1 main projectile" -
	# "can make a diff color if needed".
	var healer: Node = (load("res://scene/characters/healer.tscn") as PackedScene).instantiate()
	healer.set("double_hit_chance", 1.0)
	var always: bool = healer.call("rolls_double_hit")
	healer.set("double_hit_chance", 0.0)
	var never: bool = healer.call("rolls_double_hit")
	healer.free()
	check("one main orb in five hits double", is_equal_approx(HealerScript.DOUBLE_HIT_CHANCE, 0.2)
		and HealerScript.DOUBLE_HIT == 2 and always and not never)
	var rolled_at: int = spawn_body.find("var doubled: bool = rolls_double_hit()")
	check("  rolled before the orb is added (it dresses itself gold), the fan figured from the shot before it doubles",
		rolled_at >= 0 and spawn_body.find("projectile.set(\"doubled\", doubled)") < spawn_body.find("add_child(projectile)")
		and spawn_body.find("_spawn_fan(direction, shot_damage)") < spawn_body.find("projectile.damage = shot_damage * DOUBLE_HIT")
		and spawn_body.contains("(RemoteAttacks.FLAG_DOUBLE if doubled else 0)"))
	var gold: Area2D = orb_scene.instantiate() as Area2D
	gold.set("cosmetic", true)
	gold.set("doubled", true)
	arena.add_child(gold)
	gold.global_position = Vector2(500, 300)
	var gold_trail: CPUParticles2D = gold.get_node_or_null(^"trail") as CPUParticles2D
	var gold_mid: Color = gold_trail.color_ramp.sample(0.35) if gold_trail != null else Color.BLACK
	check("  a double is gold - the halo's colour - flame, wisps and all",
		(gold.get_node(^"animatedsprite2d") as CanvasItem).self_modulate.is_equal_approx(gold.get("DOUBLE_TINT"))
		and gold_mid.r > gold_mid.b + 0.4 and gold_mid.r > 0.9, gold_mid)
	var big: Node2D = gold.call("splash", arena, Vector2(500, 300), true)
	var small: Node2D = gold.call("splash", arena, Vector2(520, 300))
	check("  and it lands bigger: twice the sparks, a wider ring, gold",
		(big.get_node(^"sparks") as CPUParticles2D).amount == 2 * (small.get_node(^"sparks") as CPUParticles2D).amount
		and float(big.get_node(^"ring").get("reach")) > float(small.get_node(^"ring").get("reach")))
	gold.queue_free()
	check("the wisps last longer - a line behind every orb - and glow",
		gold_trail != null and gold_trail.lifetime >= 0.8 and gold_trail.amount >= 24
		and (gold_trail.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
		gold_trail)

	# ---- somebody else's ---------------------------------------------------------------
	var them := Node2D.new()
	arena.add_child(them)
	them.global_position = Vector2(200, 200)
	var before: Array = scene_root.get_children()
	var made: Array = RemoteAttacks.fire(them, ["orb", 0, 200.0, 184.0, 300.0, 184.0, 0,
		RemoteAttacks.FLAG_FAN | RemoteAttacks.FLAG_DOUBLE])
	var fans: int = 0
	for child in scene_root.get_children():
		if not before.has(child) and child.get("fan") == true and child.get("cosmetic") == true:
			fans += 1
	check("a picture of somebody else's shot that fanned shows its fan too, touching nothing - and gold if it doubled",
		made.size() == 1 and made[0].get("fan") == false and made[0].get("doubled") == true
		and fans == HealerScript.FAN_ORBS, [made, fans])
	check("  with the motes where it left their picture", them.get_node_or_null(^"muzzle") is CastSparkle)
	for child in scene_root.get_children():
		if not before.has(child):
			child.queue_free()

	# ---- the server's books -------------------------------------------------------------
	var combat: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json")) as Dictionary).get("combat", {})
	var row: Dictionary = ((combat.get("classes", {}) as Dictionary).get("healer", {})) as Dictionary
	check("the fan and the double are in gamedata.json for the server's books (re-run the exporter if not)",
		int(row.get("fan_every", -1)) == HealerScript.FAN_EVERY and int(row.get("fan_orbs", -1)) == HealerScript.FAN_ORBS
		and is_equal_approx(float(row.get("fan_share", -1.0)), HealerScript.FAN_SHARE)
		and is_equal_approx(float(row.get("double_chance", -1.0)), HealerScript.DOUBLE_HIT_CHANCE)
		and is_equal_approx(float(row.get("double_hit", -1.0)), float(HealerScript.DOUBLE_HIT)), row)
	arena.queue_free()
	await get_tree().process_frame


# =============================================================================
# THE WARRIOR'S BLOWS, SEEN AND FELT (0.38.0, 0.39.0)
# =============================================================================

func _test_the_warrior_blows() -> void:
	section("THE WARRIOR - sparks, a hit-stop, the crypt's orbs and the third-swing finisher (0.38.0, 0.39.0)")
	# The owner: "the final character warrioe how can we make him better
	# also", and all four of what was offered. Then, of 0.38.0's arc and
	# trails: "its horrible ... no trails we can use projectiles from crypt to
	# elavate" - and all four ways the orbs were offered.
	const WarriorScript := preload("res://src/characters/warrior.gd")
	const Strike := preload("res://src/shared/strikefx.gd")
	var scene_root: Node = get_tree().current_scene
	var arena := Node2D.new()
	arena.name = "bladetest"
	scene_root.add_child(arena)
	var warrior_src: String = _code_src("res://src/characters/warrior.gd")
	var wave_src: String = _code_src("res://src/projectiles/slashwave.gd")
	# By what they are, not their names: siblings of one name get renamed.
	var new_orbs := func(was: Array) -> Array:
		return arena.get_children().filter(func(n: Node) -> bool: return not was.has(n) and n is BladeOrb)
	# Drawn unshaded - and false, not a SCRIPT ERROR, for one with no material.
	var unshaded := func(item: CanvasItem) -> bool:
		return item != null and item.material is CanvasItemMaterial \
			and (item.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED

	var finishing: Array[int] = []
	for swing in range(1, 10):
		if WarriorScript.finisher_on(swing):
			finishing.append(swing)
	check("every third swing is the finisher, at one and a half",
		finishing == [3, 6, 9] and is_equal_approx(WarriorScript.FINISHER_MULT, 1.5), finishing)
	check("no arc round the swing and no trail behind the wave any more - \"the trails are bad\" (0.39.0)",
		not _code_src("res://src/shared/strikefx.gd").contains("func arc(")
		and not warrior_src.contains("Strike.arc(") and not wave_src.contains("_leave_ghost")
		and not wave_src.contains("waveghost"))

	# ---- the sparks -----------------------------------------------------------------
	var steel: Node2D = Strike.sparks(arena, Vector2(100, 100))
	var gold_sparks: Node2D = Strike.sparks(arena, Vector2(120, 100), Strike.GOLD)
	check("where a blow lands: a flash and steel sparks over whoever was hit - gold, and more, for a finisher",
		steel.z_index == 5 and not steel.z_as_relative and steel.get_node_or_null(^"flash") is Sprite2D
		and (steel.get_node(^"sparks") as CPUParticles2D).amount < (gold_sparks.get_node(^"sparks") as CPUParticles2D).amount
		and steel.global_position == Vector2(100, 100))
	var try_body: String = _func_body(warrior_src, "func _try_damage(")
	check("  on every monster the sword lands on, at the middle of its hurtbox",
		try_body.contains("Strike.sparks(get_parent(), Strike.hit_point(target as Node2D),"))

	# ---- the hit-stop ----------------------------------------------------------------
	var victim := Node2D.new()
	var their_picture := AnimatedSprite2D.new()
	their_picture.name = "animatedsprite2d"
	their_picture.speed_scale = 1.25
	victim.add_child(their_picture)
	arena.add_child(victim)
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	# Its own picture, mid-swing: a swing of its own frames (not the art's, so
	# the numbers are known), on frame 1 of 6 and half through it, at 1.5x - so
	# 4.5 frames at 10 a second at 1.5x, 0.3 s, are left of it. Out of the
	# tree its `sprite` is never set, so it is set here.
	var swing_frames := SpriteFrames.new()
	swing_frames.add_animation(&"attackright")
	swing_frames.set_animation_loop(&"attackright", false)
	swing_frames.set_animation_speed(&"attackright", 10.0)
	for i in 6:
		swing_frames.add_frame(&"attackright", PlaceholderTexture2D.new())
	var own: AnimatedSprite2D = warrior.get_node(^"animatedsprite2d") as AnimatedSprite2D
	own.sprite_frames = swing_frames
	own.play(&"attackright")
	own.set_frame_and_progress(1, 0.5)
	own.speed_scale = 1.5
	warrior.set("sprite", own)
	var left: float = WarriorScript.swing_time_left(own)
	warrior.call("_hit_stop", victim)
	var frozen: float = their_picture.speed_scale
	var own_frozen: float = own.speed_scale
	await get_tree().create_timer(WarriorScript.HITSTOP_SECONDS + 0.05).timeout
	check("the first blow of a swing holds the monster's picture still a moment, then lets it go on as it was",
		frozen == 0.0 and is_equal_approx(their_picture.speed_scale, 1.25), [frozen, their_picture.speed_scale])
	# The swing lock ends when the swing's animation does: held and then
	# played at the same speed, every swing that hit would end - and the next
	# begin - a hit-stop later.
	check("  and the warrior's, then plays the rest of the swing faster - so it ends, and the next swing comes, when it would have",
		is_equal_approx(left, 0.3) and own_frozen == 0.0 and own.speed_scale > 1.5
		and is_equal_approx(WarriorScript.HITSTOP_SECONDS + left * 1.5 / own.speed_scale, left), [left, own_frozen, own.speed_scale])
	own.speed_scale = 1.0
	own.set_frame_and_progress(5, 0.9)
	warrior.call("_hit_stop", victim)
	check("  but not the warrior's so near the end of a swing that the rest would have to rush",
		own.speed_scale == 1.0 and WarriorScript.swing_time_left(own) < WarriorScript.HITSTOP_SECONDS, own.speed_scale)
	await get_tree().create_timer(WarriorScript.HITSTOP_SECONDS + 0.05).timeout
	check("  once a swing, with a small shake - a picture only, the fight goes on",
		try_body.contains("if not _stopped_this_swing:") and try_body.contains("_hit_stop(target)")
		and _func_body(warrior_src, "func _hit_stop(").contains("shake_camera(")
		and not _func_body(warrior_src, "func _hit_stop(").contains("is_attacking"))

	# ---- the crypt's orb ---------------------------------------------------------------
	var steel_orb: Image = BladeOrb.texture_for(BladeOrb.STEEL).get_image()
	var gold_orb: Image = BladeOrb.texture_for(BladeOrb.GOLD).get_image()
	# Within a step of eight bits: the image holds bytes.
	var near := func(a: Color, b: Color) -> bool:
		return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
	check("a crypt orb: the Field's bullet, 8 x 8 - a white-hot core, a steel or a gold body, a darker rim",
		steel_orb.get_width() == 8 and steel_orb.get_pixel(4, 4) == Color.WHITE
		and near.call(steel_orb.get_pixel(6, 4), BladeOrb.STEEL_BODY)
		and near.call(gold_orb.get_pixel(6, 4), BladeOrb.GOLD_BODY)
		and steel_orb.get_pixel(7, 4).v < steel_orb.get_pixel(6, 4).v and steel_orb.get_pixel(0, 0).a == 0.0,
		[steel_orb.get_pixel(6, 4), gold_orb.get_pixel(6, 4)])
	var dummy: CharacterBody2D = _weapon_dummy(arena, Vector2(530, 100))
	var orb: BladeOrb = BladeOrb.fire(arena, Vector2(500, 100), Vector2.RIGHT, 240.0, 100.0, 7)
	var picture: Sprite2D = orb.get_node(^"picture") as Sprite2D
	for i in 12:
		await get_tree().physics_frame
	check("  unshaded, so it shows in a dark crypt; it flies, hits the first monster it touches, and is gone",
		unshaded.call(picture)
		and dummy.get("taken") == [7] and bool(orb.get("_done")), [dummy.get("taken"), orb.flown])
	var passed_over: CharacterBody2D = _weapon_dummy(arena, Vector2(500, 160))
	var over: BladeOrb = BladeOrb.fire(arena, Vector2(500, 160), Vector2.DOWN, 240.0, 100.0, 7, BladeOrb.GOLD, false,
		passed_over.get_instance_id())
	var shown: BladeOrb = BladeOrb.fire(arena, Vector2(670, 220), Vector2.RIGHT, 240.0, 100.0, 7, BladeOrb.STEEL, true)
	var seen: CharacterBody2D = _weapon_dummy(arena, Vector2(700, 220))
	for i in 12:
		await get_tree().physics_frame
	check("  passing over the monster it is told to (where a burst starts), and a picture's touches nothing",
		passed_over.get("taken") == [] and not bool(over.get("_done")) and seen.get("taken") == [] and bool(shown.get("_done")),
		[passed_over.get("taken"), seen.get("taken")])
	var short: BladeOrb = BladeOrb.fire(arena, Vector2(600, 400), Vector2.UP, 240.0, 20.0, 7)
	short._physics_process(0.05)
	var half_way: bool = bool(short.get("_done"))
	short._physics_process(0.05)
	check("  and at its reach it pops where it is", not half_way and bool(short.get("_done")) and short.flown >= 20.0, short.flown)

	# ---- the sword fan -----------------------------------------------------------------
	var three: Array[Vector2] = BladeOrb.fan_ways(Vector2.RIGHT, 3, 18.0, false)
	var four: Array[Vector2] = BladeOrb.fan_ways(Vector2.RIGHT, 4, 12.0, true)
	var degrees := func(ways: Array) -> Array:
		return ways.map(func(v: Vector2) -> int: return roundi(rad_to_deg(v.angle())))
	check("a fan: one down the aim and the rest either side - or, beside a wave, none down it",
		degrees.call(three) == [-18, 0, 18] and degrees.call(four) == [12, -12, 24, -24], [degrees.call(three), degrees.call(four)])
	warrior.position = Vector2(200, 300)
	warrior.set("_swing_aim_direction", Vector2.RIGHT)
	var before: Array = arena.get_children()
	var flung: Array[BladeOrb] = warrior.call("fling_sword_fan", arena)
	var fan_reach: float = WarriorScript.SWORD_FAN_REACH
	var blade: Vector2 = Vector2(200, 300) + Vector2.RIGHT * WarriorScript.SWORD_FAN_FROM
	var off_the_blade := func(o: BladeOrb) -> bool:
		return o.palette == BladeOrb.STEEL and o.damage >= 1 and is_equal_approx(o.reach, fan_reach) \
			and o.global_position.is_equal_approx(blade)
	check("every sword swing flings SWORD_FAN_ORBS (3) steel orbs off the blade the way it aims, a short way",
		flung.size() == WarriorScript.SWORD_FAN_ORBS and new_orbs.call(before).size() == 3
		and flung.all(off_the_blade)
		and degrees.call(flung.map(func(o: BladeOrb) -> Vector2: return o.direction)) == [-18, 0, 18],
		flung.map(func(o: BladeOrb) -> Array: return [o.palette, o.damage, o.direction]))
	warrior.set("_finisher", true)
	var gold_flung: Array[BladeOrb] = warrior.call("fling_sword_fan", arena)
	warrior.free()
	var frame_body: String = _func_body(warrior_src, "func _on_frame_changed(")
	var fan_body: String = _func_body(warrior_src, "func fling_sword_fan(")
	check("  gold on the finisher; each for a tenth of a swing; on the first contact frame, once a swing",
		gold_flung.all(func(o: BladeOrb) -> bool: return o.palette == BladeOrb.GOLD)
		and fan_body.contains("maxi(1, int(_calculate_melee_damage() * SWORD_FAN_SHARE))")
		and is_equal_approx(WarriorScript.SWORD_FAN_SHARE, 0.1)
		and frame_body.contains("not _fanned_this_swing and _swing_hitbox != null")
		and frame_body.contains("fling_sword_fan()")
		# Never on the finisher (THE FINISHER, UNCLUTTERED, 0.41.0).
		and frame_body.find("if not _finisher:") >= 0 and frame_body.find("if not _finisher:") < frame_body.find("fling_sword_fan()")
		and _func_body(warrior_src, "func attack_action(").contains("_fanned_this_swing = false"))

	# ---- the plain wave, and its weave ---------------------------------------------------
	var wave_scene: PackedScene = load("res://scene/projectiles/slashwave.tscn") as PackedScene
	var wave: SlashWave = wave_scene.instantiate() as SlashWave
	wave.cosmetic = true
	arena.add_child(wave)
	wave.global_position = Vector2(400, 300)
	wave.shoot_vector(Vector2.RIGHT)
	var crescent: AnimatedSprite2D = wave.get_node(^"animatedsprite2d") as AnimatedSprite2D
	check("a plain wave looks as it did before 0.38.0: no glow behind it, drawn like the world around it",
		wave.get_node_or_null(^"glow") == null and crescent.material == null and crescent.modulate == Color.WHITE)
	before = arena.get_children()
	for i in 5:
		wave._physics_process(1.0 / 60.0)
	check("  and leaves nothing behind it as it flies", arena.get_children() == before,
		arena.get_children().filter(func(n: Node) -> bool: return not before.has(n)))
	var weave_of := func(of: SlashWave, palette: StringName) -> Array:
		return of.get_children().filter(func(n: Node) -> bool: return n is Sprite2D and str(n.name).begins_with("weave") \
			and (n as Sprite2D).texture == BladeOrb.texture_for(palette) \
			and unshaded.call(n))
	var weave: Array = weave_of.call(wave, BladeOrb.STEEL)
	check("two steel crypt orbs weave across it, unshaded", weave.size() == 2, wave.get_children())
	var quarter: float = (PI / 2.0) / SlashWave.WEAVE_RATE
	var a0: Vector2 = SlashWave.weave_point(Vector2.RIGHT, 0, quarter)
	var a1: Vector2 = SlashWave.weave_point(Vector2.RIGHT, 1, quarter)
	check("  crossing over: either side of its line, half a turn apart, over the crescent on the near half and under it on the far",
		SlashWave.weave_point(Vector2.RIGHT, 0, 0.0) == SlashWave.SPRITE_CENTRE + Vector2(SlashWave.WEAVE_ALONG, 0.0)
		and SlashWave.weave_point(Vector2.RIGHT, 1, 0.0) == SlashWave.SPRITE_CENTRE - Vector2(SlashWave.WEAVE_ALONG, 0.0)
		and is_equal_approx(absf(a0.y - SlashWave.SPRITE_CENTRE.y), SlashWave.WEAVE_ACROSS)
		and is_equal_approx(a0.y - SlashWave.SPRITE_CENTRE.y, -(a1.y - SlashWave.SPRITE_CENTRE.y))
		and SlashWave.weave_near(0, 0.0) and not SlashWave.weave_near(1, 0.0), [a0, a1])
	wave._process(0.05)
	# By name here, whatever they look like: the check above is the look.
	var w0: Sprite2D = wave.get_node_or_null(^"weave0") as Sprite2D
	var w1: Sprite2D = wave.get_node_or_null(^"weave1") as Sprite2D
	check("  turning as it flies",
		w0 != null and w1 != null
		and w0.position == SlashWave.weave_point(Vector2.RIGHT, 0, 0.05)
		and w1.position == SlashWave.weave_point(Vector2.RIGHT, 1, 0.05)
		and w0.z_index == (1 if SlashWave.weave_near(0, 0.05) else -1),
		[w0, w1])
	var cut_dummy: CharacterBody2D = _weapon_dummy(arena, Vector2(430, 300))
	before = arena.get_children()
	wave.call("_try_hit", cut_dummy)
	var is_sparks := func(n: Node) -> bool: return n.get_node_or_null(^"flash") is Sprite2D and n.get_node_or_null(^"sparks") is CPUParticles2D
	var cut_sparks: int = arena.get_children().filter(func(n: Node) -> bool: return not before.has(n) and is_sparks.call(n)).size()
	before = arena.get_children()
	wave.destroy_wave()
	await get_tree().process_frame
	var broke: int = arena.get_children().filter(func(n: Node) -> bool: return not before.has(n) and is_sparks.call(n)).size()
	check("  sparks where it cuts a monster, and where it breaks on a wall - and a plain wave never bursts",
		cut_sparks == 1 and broke == 1 and new_orbs.call(before).is_empty() and not wave.burst_done, [cut_sparks, broke])

	# ---- the finisher's wave -------------------------------------------------------------
	var big: SlashWave = wave_scene.instantiate() as SlashWave
	big.finisher = true
	big.hitbox_scale = SlashWave.FINISHER_SCALE
	big.damage = 40
	big.burst_damage = 6
	arena.add_child(big)
	big.global_position = Vector2(400, 500)
	big.shoot_vector(Vector2.RIGHT)
	var big_crescent: AnimatedSprite2D = big.get_node(^"animatedsprite2d") as AnimatedSprite2D
	var big_box: RectangleShape2D = (big.get_node(^"CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	check("a finisher's wave is gold and bigger - its picture and its hitbox both - unshaded",
		is_equal_approx(big_crescent.scale.x, crescent.scale.x * SlashWave.FINISHER_SCALE)
		and big_crescent.modulate.b < 0.6
		and is_equal_approx(big_box.size.y, SlashWave.HITBOX_SWEEP * SlashWave.FINISHER_SCALE)
		and is_equal_approx(WarriorScript.FINISHER_SCALE, SlashWave.FINISHER_SCALE)
		and unshaded.call(big_crescent),
		big_box.size)
	# The owner, after 0.41.0: "still double layerd" (0.45.1). The glow behind
	# it was a bigger copy of the crescent, grown from the middle of a picture
	# the crescent sits well off, so it showed as a second crescent ahead of it.
	var pictures: Array = []
	for n in big.get_children():
		if n is CanvasItem and not (n is CollisionShape2D) and not (n is VisibleOnScreenNotifier2D):
			pictures.append(n)
	check("  and it is ONE crescent: nothing drawn behind or over it - no copy, no glow",
		pictures == [big_crescent] and big.get_node_or_null(^"glow") == null, pictures)
	# The owner: "warriors critical attack is overlapped it looks bad" (0.41.0).
	check("  and nothing weaves over it - the gold wave and its fan are enough",
		weave_of.call(big, BladeOrb.GOLD).is_empty() and weave_of.call(big, BladeOrb.STEEL).is_empty(), big.get_children())
	var first_cut: CharacterBody2D = _weapon_dummy(arena, Vector2(440, 500))
	var second_cut: CharacterBody2D = _weapon_dummy(arena, Vector2(480, 500))
	before = arena.get_children()
	big.call("_try_hit", first_cut)
	var orbs_in_frame: int = new_orbs.call(before).size()
	await get_tree().process_frame
	var burst: Array = new_orbs.call(before)
	# A local const is not seen inside a lambda: where the cut was, worked out here.
	var cut_at: Vector2 = Strike.hit_point(first_cut)
	var from_the_cut := func(o: BladeOrb) -> bool:
		return o.palette == BladeOrb.GOLD and o.damage == 6 \
			and (o.global_position - o.direction * o.flown).is_equal_approx(cut_at + o.direction * SlashWave.BURST_FROM)
	var ring: Array = BladeOrb.ring_ways(Vector2.RIGHT, SlashWave.BURST_ORBS).map(func(v: Vector2) -> int: return roundi(rad_to_deg(v.angle())))
	check("THE BURST: where a finisher first cuts a monster, BURST_ORBS (8) gold orbs fly out from its edge, each for its burst damage",
		orbs_in_frame == 0 and burst.size() == SlashWave.BURST_ORBS and big.burst_done
		and burst.all(from_the_cut)
		and burst.map(func(o: BladeOrb) -> int: return roundi(rad_to_deg(o.direction.angle()))) == ring,
		[orbs_in_frame, burst.size()])
	before = arena.get_children()
	big.call("_try_hit", second_cut)
	await get_tree().process_frame
	var again: int = new_orbs.call(before).size()
	for i in 6:
		await get_tree().physics_frame
	check("  once a wave - and never back into the monster it came from (in at the end of the frame: the cut is a physics callback)",
		again == 0 and first_cut.get("taken") == [40], [again, first_cut.get("taken")])
	var walled: SlashWave = wave_scene.instantiate() as SlashWave
	walled.finisher = true
	walled.cosmetic = true
	arena.add_child(walled)
	walled.global_position = Vector2(200, 600)
	walled.shoot_vector(Vector2.UP)
	var offscreen: SlashWave = wave_scene.instantiate() as SlashWave
	offscreen.finisher = true
	offscreen.cosmetic = true
	arena.add_child(offscreen)
	offscreen.shoot_vector(Vector2.UP)
	before = arena.get_children()
	walled.destroy_wave()
	offscreen.destroy_wave(false)
	var offscreen_burst: bool = offscreen.burst_done
	await get_tree().process_frame
	var walled_orbs: Array = new_orbs.call(before)
	check("  or, having cut nothing, where it breaks on a wall - not off the edge of the screen; a picture's touch nothing",
		walled_orbs.size() == SlashWave.BURST_ORBS and not offscreen_burst
		and walled_orbs.all(func(o: BladeOrb) -> bool: return o.cosmetic and o.damage == 0), walled_orbs.size())
	var spawn_body: String = _func_body(warrior_src, "func _spawn_slashwave(")
	var attack_body: String = _func_body(warrior_src, "func attack_action(")
	check("  thrown on every third sword swing - not with the Double Axe - for one and a half its damage",
		attack_body.contains("_swings += 1") and attack_body.contains("_finisher = finisher_on(_swings)")
		and attack_body.find("throw_axe(aim_point())") >= 0
		and attack_body.find("_swings += 1") > attack_body.find("throw_axe(aim_point())")
		and spawn_body.contains("wave_damage_ratio * (FINISHER_MULT if _finisher else 1.0)")
		and spawn_body.find("wave.finisher = true") < spawn_body.find("wave.shoot_vector(")
		and spawn_body.contains("wave.burst_damage = maxi(1, int(wave.damage * FINISHER_ORB_SHARE))"))
	check("  with FINISHER_FAN_ORBS (4) gold orbs fanned beside it, as fast, each for 0.15 of it",
		spawn_body.contains("for pair in finisher_fan(wave.global_position, _swing_aim_direction):")
		and spawn_body.find("finisher_fan(") > spawn_body.find("if _finisher:", spawn_body.find("wave.shoot_vector("))
		and spawn_body.contains("wave.speed,") and spawn_body.contains("wave.burst_damage, BladeOrb.GOLD)")
		and WarriorScript.FINISHER_FAN_ORBS == 4 and is_equal_approx(WarriorScript.FINISHER_ORB_SHARE, 0.15)
		and spawn_body.contains("RemoteAttacks.FLAG_FINISHER if _finisher else RemoteAttacks.FLAG_SWORD_FAN"))
	# Each from the crescent's tip on its own side, clear of the wave.
	var fan_pairs: Array = WarriorScript.finisher_fan(Vector2(100, 100), Vector2.RIGHT)
	var wave_middle: Vector2 = Vector2(100, 100) + SlashWave.SPRITE_CENTRE
	var clear_of_it: bool = fan_pairs.size() == WarriorScript.FINISHER_FAN_ORBS
	for pair in fan_pairs:
		var off: Vector2 = (pair[0] as Vector2) - wave_middle
		clear_of_it = clear_of_it and is_equal_approx(off.length(), WarriorScript.FINISHER_FAN_TIP) \
			and absf(off.x) < 0.001 and signf(off.y) == signf((pair[1] as Vector2).y)
	check("  and they leave from the crescent's tips, each on the side it flies to, past its half-width - not over it",
		clear_of_it and WarriorScript.FINISHER_FAN_TIP > SlashWave.HITBOX_SWEEP * SlashWave.FINISHER_SCALE / 2.0,
		fan_pairs)

	# ---- somebody else's ------------------------------------------------------------------
	var them := Node2D.new()
	arena.add_child(them)
	# Where their game would put them: the area's projectiles, not the arena.
	var drawn_in: Node = RemoteAttacks._parent(them, true)
	var new_in := func(seen_before: Array) -> Array:
		return drawn_in.get_children().filter(func(n: Node) -> bool: return not seen_before.has(n) and n is BladeOrb)
	before = drawn_in.get_children()
	var made: Array = RemoteAttacks.fire(them, ["slash", 0, 200.0, 200.0, 300.0, 200.0, 0,
		RemoteAttacks.FLAG_FINISHER | RemoteAttacks.FLAG_SWORD_FAN])
	var their_orbs: Array = new_in.call(before)
	check("a picture of somebody else's finisher is gold and bigger, with its own fan and no sword's - even from a game that still flags one - pictures, no damage",
		made.size() == 1 and (made[0] as SlashWave).finisher and is_equal_approx((made[0] as SlashWave).hitbox_scale, SlashWave.FINISHER_SCALE)
		and their_orbs.size() == WarriorScript.FINISHER_FAN_ORBS
		and their_orbs.all(func(o: BladeOrb) -> bool: return o.cosmetic and o.damage == 0 and o.palette == BladeOrb.GOLD),
		their_orbs.size())
	before = drawn_in.get_children()
	made.append_array(RemoteAttacks.fire(them, ["slash", 0, 200.0, 200.0, 300.0, 200.0, 0, 0]))
	check("  and a plain swing from a game from before the orbs flings none",
		new_in.call(before).is_empty())
	for n in made:
		(n as Node).queue_free()

	# ---- the server's books -------------------------------------------------------------
	var combat: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json")) as Dictionary).get("combat", {})
	var row: Dictionary = ((combat.get("classes", {}) as Dictionary).get("warrior", {})) as Dictionary
	check("the finisher and the orbs are in gamedata.json for the server's books (re-run the exporter if not)",
		int(row.get("finisher_every", -1)) == WarriorScript.FINISHER_EVERY
		and is_equal_approx(float(row.get("finisher_mult", -1.0)), WarriorScript.FINISHER_MULT)
		and int(row.get("sword_fan_orbs", -1)) == WarriorScript.SWORD_FAN_ORBS
		and is_equal_approx(float(row.get("sword_fan_share", -1.0)), WarriorScript.SWORD_FAN_SHARE)
		and int(row.get("finisher_fan_orbs", -1)) == WarriorScript.FINISHER_FAN_ORBS
		and int(row.get("finisher_burst_orbs", -1)) == SlashWave.BURST_ORBS
		and is_equal_approx(float(row.get("finisher_orb_share", -1.0)), WarriorScript.FINISHER_ORB_SHARE), row)
	arena.queue_free()
	await get_tree().process_frame


# =============================================================================
# THE HEALER'S AURA (0.40.0)
# =============================================================================

func _test_the_healer_aura() -> void:
	section("THE HEALER'S AURA - right-click: a beam lands, the ring heals and burns, blobs heal those outside (0.40.0)")
	# The owner sent the art ("healer ff"), chose "Heal players + hurt
	# monsters", then: "nope hold right click to drop the aura", the orbs on
	# "left click", and "energy beam crashes down around the circle green orbs
	# spawn around the circle and each blob travels to players outside of the
	# circle giving them hp".
	const HealerScript := preload("res://src/characters/healer.gd")
	var arena := Node2D.new()
	arena.name = "auratest"
	get_tree().current_scene.add_child(arena)

	# ---- the art -------------------------------------------------------------------------
	var sheet: Texture2D = load(HealAura.SHEET) as Texture2D
	var frames: SpriteFrames = HealAura.sprite_frames()
	check("the art: 25 frames of 64 x 64 in one strip, at the artist's 70 ms, played once",
		sheet != null and sheet.get_width() == 64 * 25 and sheet.get_height() == 64
		and frames.get_frame_count(&"aura") == HealAura.FRAMES and HealAura.FRAMES == 25
		and is_equal_approx(frames.get_animation_speed(&"aura"), 1000.0 / 70.0) and not frames.get_animation_loop(&"aura"),
		[sheet, frames.get_frame_count(&"aura")])
	# The ring measured off its first frame on the floor: its left and right
	# ends, and the rows of its leftmost column.
	var art: Image = sheet.get_image() if sheet != null else null
	var lefts: Array[int] = []
	var xs: Array[int] = []
	if art != null:
		if art.is_compressed():
			art.decompress()
		for y in range(36, 64):
			for x in 64:
				if art.get_pixel(HealAura.LANDS_ON * 64 + x, y).a > 0.0:
					xs.append(x)
		var left_x: int = xs.min() if not xs.is_empty() else -1
		for y in range(36, 64):
			if art.get_pixel(HealAura.LANDS_ON * 64 + left_x, y).a > 0.0:
				lefts.append(y)
	var ring_mid := Vector2((float(xs.min()) + float(xs.max()) + 1.0) / 2.0 - 32.0,
		(float(lefts.min()) + float(lefts.max()) + 1.0) / 2.0 - 32.0) if not xs.is_empty() and not lefts.is_empty() else Vector2(-99, -99)
	check("  its ring measured off the art: the node is the ring's middle, 45 px across",
		ring_mid.distance_to(HealAura.RING_FROM_MIDDLE) <= 1.0
		and absf((float(xs.max()) - float(xs.min()) + 1.0) / 2.0 - HealAura.RADII.x) <= 1.0,
		[ring_mid, xs.min() if not xs.is_empty() else null, xs.max() if not xs.is_empty() else null])

	# ---- the beam, then the ring -------------------------------------------------------------
	var aura: HealAura = HealAura.drop(arena, Vector2(400, 400), 7)
	var picture: AnimatedSprite2D = aura.get_node(^"picture") as AnimatedSprite2D
	picture.stop()
	var aura_unshaded: bool = picture.material is CanvasItemMaterial \
		and (picture.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
	# The owner: "i can tell the image was streched keep it original size".
	# The dressing (0.40.0, "is there any way we can make the beam look
	# better?") is its own nodes beside his frames, never on them.
	var dressing: Array[String] = []
	for child in aura.get_children():
		if child != picture:
			dressing.append(str(child.name))
	dressing.sort()
	check("his art as he drew it - its own size, nothing stretched, nothing tinted, the dressing its own nodes beside it - the beam over everyone, unshaded",
		picture.scale == Vector2.ONE and aura.scale == Vector2.ONE and picture.offset == -HealAura.RING_FROM_MIDDLE
		and picture.modulate == Color.WHITE and picture.self_modulate == Color.WHITE and picture.get_child_count() == 0
		and aura_unshaded and (picture.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_MIX
		and dressing == ["beamglow", "light", "ringglow", "shaft", "sparkles"]
		and aura.z_index == HealAura.SKY_Z and not aura.z_as_relative,
		[picture.scale, dressing])
	var patient: Node2D = _aura_patient(arena, Vector2(410, 404), 200)
	aura.heal_target = patient
	aura.reached(HealAura.LANDS_ON)
	check("  and lands: a ring on the floor under whoever stands in it",
		aura.z_index == HealAura.FLOOR_Z)
	check("  not a dark area here, so its light stays out", not aura.dark and not aura.light.enabled)

	# ---- the beam, dressed: the shaft, the glow and light, the sparkles ---------------------
	# The owner: "is there any way we can make the beam look better?" - "Fade
	# the top", "Glow + light", "Falling sparkles".
	var dressed: HealAura = HealAura.drop(arena, Vector2(400, 1400), 0, true)
	(dressed.get_node(^"picture") as AnimatedSprite2D).stop()
	dressed.heal_target = _aura_patient(arena, Vector2(400, 2400), 100)
	dressed.dark = true
	# Whatever Settings' lighting made of it as it arrived.
	var light_shown: bool = dressed.light.visible if dressed.light != null else false
	var shaft_image: Image = dressed.shaft.texture.get_image() if dressed.shaft != null and dressed.shaft.texture != null else null
	# Each column of the shaft: the art's top row there at the foot, nothing
	# at the top, the alpha only ever growing going down, in whole quarters of
	# the art's alpha, in the art's colour.
	var seam: bool = shaft_image != null and art != null
	var fades: bool = seam
	if seam:
		for x in HealAura.PILLAR_WIDTH:
			var art_px: Color = art.get_pixel(HealAura.PILLAR_LEFT + x, 0)
			var foot: Color = shaft_image.get_pixel(x, HealAura.SHAFT_HEIGHT - 1)
			seam = seam and art_px.a > 0.0 and foot.to_rgba32() == art_px.to_rgba32()
			fades = fades and shaft_image.get_pixel(x, 0).a == 0.0
			var column_alpha: Array[float] = [0.0, 0.0, 0.0, 0.0]
			for y in HealAura.SHAFT_HEIGHT:
				var shaft_px: Color = shaft_image.get_pixel(x, y)
				column_alpha[floori(float(y) * 4.0 / float(HealAura.SHAFT_HEIGHT))] += shaft_px.a
				if shaft_px.a > 0.0:
					var quarters: float = shaft_px.a / art_px.a * 4.0
					# To the 8-bit step.
					fades = fades and shaft_px.a <= art_px.a + 0.003 and absf(shaft_px.a - roundf(quarters) / 4.0 * art_px.a) <= 1.5 / 255.0 \
						and is_equal_approx(shaft_px.r, art_px.r) and is_equal_approx(shaft_px.g, art_px.g) and is_equal_approx(shaft_px.b, art_px.b)
			fades = fades and column_alpha[0] < column_alpha[1] and column_alpha[1] < column_alpha[2] and column_alpha[2] < column_alpha[3]
	check("the shaft: light standing on the frame's top edge as the pillar falls - its own texture, the pillar's width, never scaled",
		dressed.shaft != null and dressed.shaft.texture.get_size() == Vector2(HealAura.PILLAR_WIDTH, HealAura.SHAFT_HEIGHT)
		and dressed.shaft.scale == Vector2.ONE and not dressed.shaft.centered
		and dressed.shaft.position == HealAura.pillar_top_left() - Vector2(0.0, HealAura.SHAFT_HEIGHT)
		and HealAura.pillar_top_left() == -HealAura.RING_FROM_MIDDLE - Vector2(32.0, 32.0) + Vector2(HealAura.PILLAR_LEFT, 0.0)
		and dressed.shaft.visible)
	check("  meeting his pillar without a seam: its foot is his top row, column by column", seam)
	check("  and fading to nothing going up - in whole quarters of his alpha, in his colours, dithered", fades)
	# The pillar where the art has it, in its falling frames.
	var pillar_where: bool = art != null
	if art != null:
		for f in HealAura.LANDS_ON:
			for x in [HealAura.PILLAR_LEFT, HealAura.PILLAR_LEFT + HealAura.PILLAR_WIDTH - 1]:
				pillar_where = pillar_where and art.get_pixel(f * 64 + x, 0).a > 0.0 \
					and art.get_pixel(f * 64 + x, HealAura.PILLAR_FOOT[f]).a > 0.0 and art.get_pixel(f * 64 + x, HealAura.PILLAR_FOOT[f] + 1).a == 0.0
			pillar_where = pillar_where and art.get_pixel(f * 64 + HealAura.PILLAR_LEFT - 1, 0).a == 0.0 \
				and art.get_pixel(f * 64 + HealAura.PILLAR_LEFT + HealAura.PILLAR_WIDTH, 0).a == 0.0
	check("  the pillar measured off the art: PILLAR_WIDTH across from PILLAR_LEFT, its sides ending on PILLAR_FOOT frame by frame",
		pillar_where and HealAura.PILLAR_FOOT.size() == HealAura.LANDS_ON)
	var glow_material: CanvasItemMaterial = dressed.beam_glow.material as CanvasItemMaterial if dressed.beam_glow != null else null
	var glow_feet: Array = []
	var glow_falls: bool = glow_material != null
	var sparkles_fall: bool = dressed.sparkles != null
	var light_rises: Array[float] = []
	for f in HealAura.LANDS_ON:
		dressed.reached(f)
		glow_feet.append(dressed.beam_glow.position.y + dressed.beam_glow.region_rect.size.y)
		glow_falls = glow_falls and dressed.beam_glow.visible and dressed.shaft.visible
		sparkles_fall = sparkles_fall and dressed.sparkles.emitting and dressed.sparkles.visible
		light_rises.append(dressed.light.energy if dressed.light.enabled else -1.0)
	var feet_wanted: Array = HealAura.PILLAR_FOOT.map(func(foot_row: int) -> float: return HealAura.frame_top_left().y + foot_row + 1.0)
	var glow_image: Image = dressed.beam_glow.texture.get_image() if dressed.beam_glow != null else null
	check("the glow: a halo added round the shaft and the falling pillar, its foot following where his pillar's sides end, frame by frame",
		glow_falls and glow_material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
		and glow_material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
		and glow_feet == feet_wanted
		and dressed.get_children().find(dressed.beam_glow) < dressed.get_children().find(dressed.get_node(^"picture")),
		[glow_feet, feet_wanted])
	check("  never scaled, wider than the pillar, fading in at the top as the shaft does",
		dressed.beam_glow.scale == Vector2.ONE and dressed.beam_glow.region_enabled
		and dressed.beam_glow.position == HealAura.pillar_top_left() - Vector2(HealAura.GLOW_SPREAD, HealAura.SHAFT_HEIGHT)
		and glow_image != null and glow_image.get_width() == HealAura.PILLAR_WIDTH + HealAura.GLOW_SPREAD * 2
		and glow_image.get_pixel(HealAura.GLOW_SPREAD + 20, 0).a == 0.0
		and absf(glow_image.get_pixel(HealAura.GLOW_SPREAD + 20, HealAura.SHAFT_HEIGHT + 4).a - HealAura.GLOW_ALPHA) < 0.01
		and glow_image.get_pixel(0, HealAura.SHAFT_HEIGHT + 4).a < glow_image.get_pixel(HealAura.GLOW_SPREAD, HealAura.SHAFT_HEIGHT + 4).a)
	check("the light, in a dark area: green, rising as the beam falls",
		light_rises.size() == 4 and light_rises[0] > 0.0 and light_rises[0] < light_rises[1] and light_rises[1] < light_rises[3]
		and dressed.light.color == HealAura.LIGHT_COLOUR, light_rises)
	check("the sparkles stream down the shaft and the pillar while it falls",
		sparkles_fall and dressed.sparkles.direction == Vector2.DOWN and dressed.sparkles.initial_velocity_min > 0.0
		and absf(dressed.sparkles.position.x - (HealAura.pillar_top_left().x + HealAura.PILLAR_WIDTH / 2.0)) < 0.5
		and dressed.sparkles.emission_rect_extents.x < HealAura.PILLAR_WIDTH / 2.0
		and dressed.sparkles.material is CanvasItemMaterial and (dressed.sparkles.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED)
	check("  the ring's glow waits under the floor until it lands", not dressed.ring_glow.visible)
	dressed.reached(HealAura.LANDS_ON)
	var landed_light: float = dressed.light.energy if dressed.light.enabled else -1.0
	check("as it lands: the shaft, the halo and the sparkles go with the beam",
		not dressed.shaft.visible and not dressed.beam_glow.visible and not dressed.sparkles.emitting and not dressed.sparkles.visible)
	check("  and the ring's glow shows round the ring, added, under it",
		dressed.ring_glow.visible and is_equal_approx(dressed.ring_glow.modulate.a, 1.0) and dressed.ring_glow.z_index < 0
		and dressed.ring_glow.material is CanvasItemMaterial and (dressed.ring_glow.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
		and dressed.ring_glow.position == Vector2.ZERO and dressed.ring_glow.scale == Vector2.ONE
		and dressed.ring_glow.texture.get_width() > HealAura.RADII.x * 2.0 and dressed.ring_glow.texture.get_height() > HealAura.RADII.y * 2.0)
	var halfway: int = floori(HealAura.RING_GLOW_FRAMES / 2.0)
	dressed.reached(HealAura.LANDS_ON + halfway)
	var half_glow: float = dressed.ring_glow.modulate.a
	var half_light: float = dressed.light.energy if dressed.light.enabled else -1.0
	dressed.reached(HealAura.LANDS_ON + HealAura.RING_GLOW_FRAMES)
	check("  fading over RING_GLOW_FRAMES, the light with it - full as it lands",
		is_equal_approx(half_glow, 1.0 - float(halfway) / float(HealAura.RING_GLOW_FRAMES)) and not dressed.ring_glow.visible
		and is_equal_approx(landed_light, HealAura.LIGHT_ENERGY) and half_light > 0.0 and half_light < landed_light,
		[half_glow, landed_light, half_light])
	dressed.reached(HealAura.LIGHT_OUT_ON)
	check("  and the light out by LIGHT_OUT_ON - switched with `enabled`, never `visible` (Settings' simple lighting hides lights with that)",
		not dressed.light.enabled and dressed.light.visible == light_shown and HealAura.LIGHT_OUT_ON < HealAura.FRAMES)
	dressed.queue_free()

	# ---- inside: the ring heals ---------------------------------------------------------------
	for frame in HealAura.TICK_FRAMES:
		aura.reached(frame)
	aura.reached(HealAura.TICK_FRAMES[HealAura.TICK_FRAMES.size() - 1])
	var got: Array = patient.get("got")
	check("a player inside the ring is healed on each of its four ticks - a quarter of their own maximum in all",
		got.size() == HealAura.TICK_FRAMES.size() and got.all(func(n: int) -> bool: return n == HealAura.heal_each(200))
		and HealAura.heal_each(200) * 4 >= 50 and aura.ticks_done == 4, got)
	check("  inside is the ring as drawn - a little past its line, measured at the feet",
		aura.inside(aura.global_position) and aura.inside(aura.global_position + Vector2(HealAura.RADII.x + HealAura.REACH_PAD - 1.0, 0.0))
		and not aura.inside(aura.global_position + Vector2(0.0, HealAura.RADII.y + HealAura.REACH_PAD + 2.0))
		and not aura.inside(aura.global_position + Vector2(HealAura.RADII.x + 10.0, 0.0)))
	check("  and the blobs, with nobody outside, lift off the ring and go to nobody",
		aura.blobs.size() == HealAura.BLOBS and aura.blobs.all(func(b: HealBlob) -> bool: return b.target == null and not b.heals))

	# ---- outside: the blobs -------------------------------------------------------------------
	var near: Node2D = _aura_patient(arena, Vector2(800, 540), 160)
	# Somebody else, further than SEEK_RANGE: a picture of them.
	var far_one: Node2D = Node2D.new()
	far_one.add_to_group(&"remoteplayers")
	arena.add_child(far_one)
	far_one.global_position = Vector2(800, 400 + HealAura.SEEK_RANGE + 60.0)
	var second: HealAura = HealAura.drop(arena, Vector2(800, 400), 7)
	(second.get_node(^"picture") as AnimatedSprite2D).stop()
	second.heal_target = near
	second.reached(HealAura.LANDS_ON)
	far_one.remove_from_group(&"remoteplayers")
	var each: int = ceili(160.0 * HealAura.HEAL_SHARE / float(HealAura.BLOBS))
	# On the ring's line - an ellipse RADII round its middle, to a whole pixel -
	# and each where ring_point() says.
	var on_ring: bool = true
	for i in second.blobs.size():
		var d: Vector2 = second.blobs[i].global_position - second.global_position
		on_ring = on_ring and d == HealAura.ring_point(i) \
			and absf(pow(d.x / HealAura.RADII.x, 2.0) + pow(d.y / HealAura.RADII.y, 2.0) - 1.0) < 0.15
	check("a player outside the ring, near it: the beam lands and green orbs lift off all round the ring, every one for them",
		second.blobs.size() == HealAura.BLOBS and on_ring
		and second.blobs.all(func(b: HealBlob) -> bool: return b.target == near and b.heals and b.amount == each),
		second.blobs.map(func(b: HealBlob) -> Array: return [b.target, b.amount]))
	for i in 60:
		for blob in second.blobs:
			if is_instance_valid(blob) and not blob.arrived:
				blob.step(1.0 / 30.0)
	var arrived: int = second.blobs.filter(func(b: HealBlob) -> bool: return is_instance_valid(b) and b.arrived).size()
	check("  each blob travels to them and gives them hp: a quarter of their maximum between them",
		arrived == HealAura.BLOBS and near.get("got") == Array([each, each, each, each, each, each, each, each])
		and each * HealAura.BLOBS >= 40, [arrived, near.get("got")])
	for tick in HealAura.TICK_FRAMES:
		second.reached(tick)
	check("  and the ring does not heal them twice as it ticks", (near.get("got") as Array).size() == HealAura.BLOBS,
		near.get("got"))
	check("  and none goes to someone further than SEEK_RANGE",
		second.blobs.all(func(b: HealBlob) -> bool: return not is_instance_valid(b) or b.target != far_one))

	var two_of_us: Node2D = _aura_patient(arena, Vector2(1200, 520), 120)
	var their_picture: Node2D = Node2D.new()
	their_picture.add_to_group(&"remoteplayers")
	arena.add_child(their_picture)
	their_picture.global_position = Vector2(1300, 400)
	var third: HealAura = HealAura.drop(arena, Vector2(1200, 400), 0, true)
	(third.get_node(^"picture") as AnimatedSprite2D).stop()
	third.heal_target = two_of_us
	third.reached(HealAura.LANDS_ON)
	var mine: Array = third.blobs.filter(func(b: HealBlob) -> bool: return b.target == two_of_us)
	var theirs: Array = third.blobs.filter(func(b: HealBlob) -> bool: return b.target == their_picture)
	their_picture.remove_from_group(&"remoteplayers")
	check("  with two outside, the blobs are shared out in turn: yours heal you, theirs are a picture of theirs",
		mine.size() == 4 and theirs.size() == 4
		and mine.all(func(b: HealBlob) -> bool: return b.heals and b.amount == ceili(120.0 * HealAura.HEAL_SHARE / 4.0))
		and theirs.all(func(b: HealBlob) -> bool: return not b.heals), [mine.size(), theirs.size()])
	var dying: Node2D = _aura_patient(arena, Vector2(1600, 400), 100)
	dying.set("is_dying", true)
	var fourth: HealAura = HealAura.drop(arena, Vector2(1600, 400), 0, true)
	(fourth.get_node(^"picture") as AnimatedSprite2D).stop()
	fourth.heal_target = dying
	for frame in range(HealAura.LANDS_ON, 11):
		fourth.reached(frame)
	check("  and nobody is healed back from dying", (dying.get("got") as Array).is_empty())

	# ---- the burn -----------------------------------------------------------------------------
	var in_ring: CharacterBody2D = _weapon_dummy(arena, Vector2(2000, 404))
	var out_ring: CharacterBody2D = _weapon_dummy(arena, Vector2(2000, 470))
	var burning: HealAura = HealAura.drop(arena, Vector2(2000, 400), 7)
	(burning.get_node(^"picture") as AnimatedSprite2D).stop()
	burning.heal_target = _aura_patient(arena, Vector2(2600, 2600))
	burning.reached(HealAura.LANDS_ON)
	burning.reached(HealAura.TICK_FRAMES[1])
	var shown: HealAura = HealAura.drop(arena, Vector2(2000, 400), 7, true)
	(shown.get_node(^"picture") as AnimatedSprite2D).stop()
	shown.heal_target = burning.heal_target
	shown.reached(HealAura.LANDS_ON)
	shown.reached(HealAura.TICK_FRAMES[1])
	check("the ring burns every monster in it, each tick - the healer's own; a picture of somebody else's burns nothing",
		in_ring.get("taken") == [7, 7] and (out_ring.get("taken") as Array).is_empty() and shown.damage == 0,
		[in_ring.get("taken"), out_ring.get("taken")])

	# ---- a right-click -----------------------------------------------------------------------------
	# The owner, of a hold that waited out the cooldown or the mana and then
	# dropped it: "i right click and hold takes like 5 seconds should just be
	# right click".
	var holder := Node2D.new()
	var healer: Node2D = (load("res://scene/characters/healer.tscn") as PackedScene).instantiate() as Node2D
	holder.add_child(healer)
	healer.position = Vector2(100, 100)
	healer.set("max_mana", 200)
	healer.set("mana", 200)
	var far_cursor: Vector2 = Vector2(100 + HealerScript.AURA_RANGE + 300.0, 100)
	check("a right-click drops it at the cursor, no further than AURA_RANGE from the healer",
		healer.call("aura_point", Vector2(150, 130)) == Vector2(150, 130)
		and (healer.call("aura_point", far_cursor) as Vector2).is_equal_approx(Vector2(100 + HealerScript.AURA_RANGE, 100)))
	var auras := func() -> Array: return holder.get_children().filter(func(n: Node) -> bool: return n is HealAura)
	var first_frame: HealAura = healer.call("_aura_click", 0.016, true, Vector2(150, 130))
	var dropped: Array = auras.call()
	check("  at once, the frame the button goes down - the mana paid, the cooldown begun",
		first_frame != null and dropped.size() == 1 and (dropped[0] as Node2D).global_position == Vector2(150, 130)
		and int(healer.get("mana")) == 200 - HealerScript.AURA_MANA_COST
		and is_equal_approx(float(healer.get("aura_cooldown_left")), HealerScript.AURA_COOLDOWN)
		and (dropped[0] as HealAura).damage >= 1, [dropped.size(), healer.get("mana"), healer.get("aura_cooldown_left")])
	healer.set("aura_cooldown_left", 0.0)
	for i in 30:
		healer.call("_aura_click", 0.2, true, Vector2(150, 130))
	var held_on: int = auras.call().size()
	healer.call("_aura_click", 0.016, false, Vector2(150, 130))
	healer.call("_aura_click", 0.016, true, Vector2(150, 130))
	var clicked_again: int = auras.call().size()
	check("  one a click: holding it on drops nothing more, ready or not - another click does",
		held_on == 1 and clicked_again == 2, [held_on, clicked_again])
	healer.call("_aura_click", 0.016, false, Vector2(150, 130))
	healer.call("_aura_click", 0.016, true, Vector2(150, 130))
	var cooling: int = auras.call().size()
	var why_cooling: String = healer.call("aura_refusal")
	healer.set("aura_cooldown_left", 0.0)
	healer.set("mana", HealerScript.AURA_MANA_COST - 1)
	var why_mana: String = healer.call("aura_refusal")
	check("  and a click before it is ready drops nothing, and says why over the healer",
		cooling == 2 and why_cooling == "Aura ready in %ds" % ceili(HealerScript.AURA_COOLDOWN - 0.016)
		and why_mana == "Not enough mana" and not bool(healer.call("aura_ready"))
		and _func_body(_code_src("res://src/characters/healer.gd"), "func _aura_click(").contains("show_notice(aura_refusal())"),
		[cooling, why_cooling, why_mana])
	var healer_src: String = _code_src("res://src/characters/healer.gd")
	check("  the right button read every frame - a click no window took - and the area told (\"heal\")",
		_func_body(healer_src, "func _physics_process(").contains("_aura_click(delta, right_click_held() or touched,")
		and _func_body(healer_src, "func _physics_process(").contains("if touched else aim_point())")
		and _func_body(healer_src, "func drop_aura(").contains("Presence.tell_attack(\"heal\", global_position, at)"))

	# ---- every class attacks on the left button --------------------------------------------------
	# The owner: "change all attacks to left click".
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	healer.call("_unhandled_input", right)
	var after_right: bool = bool(healer.get("_left_click_down"))
	var right_noted: bool = bool(healer.get("_right_click_down"))
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	healer.call("_unhandled_input", left)
	var player_src: String = _code_src("res://src/characters/player.gd")
	check("every class attacks on left-click (and Space) - a left-click no window took; the right button is the healer's aura",
		not after_right and right_noted and bool(healer.get("_left_click_down"))
		and _func_body(player_src, "func _poll_attack_pressed(").contains("left_click_attack_held()")
		and not _func_body(player_src, "func _poll_attack_pressed(").contains("right_click")
		and _func_body(healer_src, "func _is_attack_input_held(").contains("Input.is_action_pressed(\"attack\") or left_click_attack_held()")
		and not _func_body(healer_src, "func _is_attack_input_held(").contains("right_click"))
	check("  and a right-click a window took drops no aura - the bag's, a name in the players list",
		_func_body(player_src, "func right_click_held(").contains("return _right_click_down and not GameState.ui_absorbed_right_click"))
	holder.free()
	# A click is the world's only if no window took it - and the HUD laid its
	# bars out in a box over the whole screen that took every click: the
	# first recording of the click dropped nothing. Nothing laid over the whole
	# screen may take the mouse.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var covering: Array[String] = []
	for c in hud.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.anchor_left == 0.0 and ctl.anchor_top == 0.0 and ctl.anchor_right == 1.0 and ctl.anchor_bottom == 1.0 \
				and ctl.mouse_filter == Control.MOUSE_FILTER_STOP:
			covering.append(str(hud.get_path_to(ctl)))
	hud.free()
	check("  and nothing the HUD lays over the whole screen takes the click first - its bars' box lets it through",
		covering.is_empty(), covering)

	# ---- somebody else's ------------------------------------------------------------------------
	var them := Node2D.new()
	arena.add_child(them)
	var made: Array = RemoteAttacks.fire(them, ["heal", 0, 500.0, 500.0, 540.0, 480.0, 0, 0])
	check("a picture of somebody else's aura: at their ring, burning nothing - and it heals you if you are there",
		made.size() == 1 and made[0] is HealAura and (made[0] as HealAura).cosmetic and (made[0] as HealAura).damage == 0
		and (made[0] as Node2D).global_position == Vector2(540, 480) and (made[0] as Node).get_parent() == get_tree().current_scene)
	for n in made:
		(n as Node).queue_free()

	# ---- the server's books -------------------------------------------------------------------
	var combat: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json")) as Dictionary).get("combat", {})
	var row: Dictionary = ((combat.get("classes", {}) as Dictionary).get("healer", {})) as Dictionary
	check("the aura is in gamedata.json for the server's books and its healing check (re-run the exporter if not)",
		is_equal_approx(float(row.get("aura_cooldown", -1.0)), HealerScript.AURA_COOLDOWN)
		and is_equal_approx(float(row.get("aura_damage_share", -1.0)), HealerScript.AURA_DAMAGE_SHARE)
		and int(row.get("aura_ticks", -1)) == HealAura.TICK_FRAMES.size()
		and is_equal_approx(float(row.get("aura_heal_share", -1.0)), HealAura.HEAL_SHARE)
		and is_equal_approx(float(row.get("aura_reach", -1.0)), HealAura.SEEK_RANGE)
		and is_equal_approx(float(row.get("aura_range", -1.0)), HealerScript.AURA_RANGE), row)
	arena.queue_free()
	await get_tree().process_frame


# =============================================================================
# THE FLOOR IS UNDER WHAT LIES ON IT (0.34.1)
# =============================================================================
