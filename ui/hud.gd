class_name Hud
extends Control
## In-game display. Draws everything itself (no child nodes) from the local
## astronaut, the level's objectives and StationState:
##   top-left     objectives
##   top-right    station air: oxygen, CO2, pressure
##   bottom-left  health, suit oxygen, flashlight battery, carried item
##   right        crew status
##   centre       crosshair, "[E] ..." prompt and hold progress
##   bottom       radio subtitles; top centre: station announcements

const C_LINE := Color(0.45, 0.85, 1.0, 0.85)
const C_DIM := Color(0.45, 0.85, 1.0, 0.35)
const C_TEXT := Color(0.86, 0.93, 1.0, 0.95)
const C_WARN := Color(1.0, 0.72, 0.2)
const C_BAD := Color(1.0, 0.28, 0.22)
const C_OK := Color(0.35, 1.0, 0.55)
const C_PANEL := Color(0.02, 0.05, 0.08, 0.55)

var _font: Font
var _announcements: Array[Dictionary] = []
var _radio: Array[Dictionary] = []
var _level: Level
var _complete_shown := 0.0
var _breath: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_breath = AudioStreamPlayer.new()
	_breath.volume_db = -22.0
	add_child(_breath)


func _process(delta: float) -> void:
	var level := Level.instance
	if level != _level:
		_level = level
		_announcements.clear()
		_radio.clear()
		_complete_shown = 0.0
		if level != null:
			level.announcement.connect(_on_announcement)
			level.radio_message.connect(_on_radio)
	for list: Array in [_announcements, _radio]:
		for entry: Dictionary in list:
			entry["t"] -= delta
		while not list.is_empty() and list[0]["t"] <= 0.0:
			list.pop_front()
	_update_breathing()
	queue_redraw()


func _on_announcement(text: String) -> void:
	_announcements.append({"text": text, "t": 6.5})
	if _announcements.size() > 3:
		_announcements.pop_front()
	Sfx.play_ui("confirm", -12.0)


func _on_radio(speaker: String, color: Color, text: String) -> void:
	_radio.append({"speaker": speaker, "color": color, "text": text, "t": 7.0})
	if _radio.size() > 3:
		_radio.pop_front()
	Sfx.play_ui("click", -10.0)


func _update_breathing() -> void:
	var me := _level.get_local_astronaut() if _level != null else null
	var want := me != null and me.helmet_sealed and not me.downed
	if want and not _breath.playing:
		var stream := Sfx.get_stream("breath") as AudioStreamWAV
		if stream != null:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
			_breath.stream = stream
			_breath.play()
	elif not want and _breath.playing:
		_breath.stop()


# --- Drawing ------------------------------------------------------------------------------

func _text(pos: Vector2, text: String, size := 15, color := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, pos + Vector2(1, 1), text, align, width, size, Color(0, 0, 0, 0.6))
	draw_string(_font, pos, text, align, width, size, color)


func _bar(pos: Vector2, size: Vector2, frac: float, color: Color, label: String, value: String) -> void:
	draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(pos, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), color)
	draw_rect(Rect2(pos, size), C_DIM, false, 1.0)
	_text(pos + Vector2(0, -5), label, 12, C_TEXT)
	_text(pos + Vector2(0, -5), value, 12, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, size.x)


func _draw() -> void:
	if _level == null or _level.station == null:
		return
	var me := _level.get_local_astronaut()
	if me == null:
		return
	var vp := size
	var s := _level.station
	_draw_vignettes(me, vp)
	_draw_objectives(vp)
	_draw_atmosphere(me, s, vp)
	_draw_vitals(me, vp)
	_draw_crew(me, vp)
	_draw_centre(me, vp)
	_draw_messages(vp)
	if me.downed:
		_text(Vector2(0, vp.y * 0.4), "YOU ARE DOWN", 34, C_BAD, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		_text(Vector2(0, vp.y * 0.4 + 30), "A crew member must hold E on you to revive", 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	if s.is_true("complete"):
		_draw_complete(s, vp)


func _draw_vignettes(me: Astronaut, vp: Vector2) -> void:
	var hurt := me.get_hurt_flash()
	if hurt > 0.01:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.8, 0.0, 0.0, 0.28 * hurt))
	if me.helmet_sealed and me.suit_o2 < 25.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.05, (0.35 - me.suit_o2 * 0.01) * (0.6 + 0.4 * pulse)))
	if me.helmet_sealed:
		# Faint visor edge when the helmet is sealed.
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.4, 0.8, 1.0, 0.10), false, 14.0)


func _draw_objectives(vp: Vector2) -> void:
	if not _level.has_method("get_objectives"):
		return
	var list: Array = _level.call("get_objectives")
	var x := 22.0
	var y := 52.0
	var w := minf(430.0, vp.x * 0.4)
	_text(Vector2(x, y), "OBJECTIVES", 13, C_LINE)
	draw_line(Vector2(x, y + 6), Vector2(x + w, y + 6), C_DIM, 1.0)
	y += 26
	for o: Dictionary in list:
		var done: bool = o.get("done", false)
		var col := C_OK if done else (C_DIM.lightened(0.5) if o.get("optional", false) else C_TEXT)
		if done:
			col.a = 0.55
		draw_rect(Rect2(x, y - 11, 10, 10), col, done, -1.0 if done else 1.5)
		var lines := _wrap(o["text"], w - 22, 14)
		for line: String in lines:
			_text(Vector2(x + 18, y), line, 14, col)
			y += 18
		y += 4
	var prog: float = _level.call("get_breaker_progress") if _level.has_method("get_breaker_progress") else 0.0
	if prog > 0.0 and prog < 1.0:
		_bar(Vector2(x + 18, y + 12), Vector2(200, 8), prog, C_WARN, "BREAKERS ENGAGING", "")


func _wrap(text: String, width: float, font_size: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var attempt := word if line == "" else line + " " + word
		if _font.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = attempt
	if line != "":
		out.append(line)
	return out


func _draw_atmosphere(me: Astronaut, s: StationState, vp: Vector2) -> void:
	var o2: float = s.get_value("atm.o2", 20.9)
	var co2: float = s.get_value("atm.co2", 0.04)
	var pressure: float = s.get_value("atm.pressure", 101.0)
	var vacuum := me.in_zone("vacuum")
	var w := 250.0
	var x := vp.x - w - 22.0
	var y := 52.0
	_text(Vector2(x, y), "LOCAL ATMOSPHERE", 13, C_LINE)
	draw_line(Vector2(x, y + 6), Vector2(x + w, y + 6), C_DIM, 1.0)
	var o2c := C_OK if o2 >= 18.0 else (C_WARN if o2 >= 16.0 else C_BAD)
	var co2c := C_OK if co2 < 1.5 else (C_WARN if co2 < 3.0 else C_BAD)
	if vacuum:
		_text(Vector2(x, y + 28), "O2  0.0 %", 15, C_BAD)
		_text(Vector2(x + 95, y + 28), "CO2  0.0 %", 15, C_BAD)
		_text(Vector2(x + 195, y + 28), "0 kPa", 15, C_BAD)
		_text(Vector2(x, y + 50), "VACUUM: SUIT OXYGEN IN USE", 13, C_BAD)
	else:
		_text(Vector2(x, y + 28), "O2  %.1f %%" % o2, 15, o2c)
		_text(Vector2(x + 95, y + 28), "CO2  %.1f %%" % co2, 15, co2c)
		_text(Vector2(x + 195, y + 28), "%d kPa" % int(pressure), 15, C_TEXT)
		var status := "AIR BREATHABLE"
		var sc := C_OK
		if me.helmet_sealed:
			status = "NOT BREATHABLE: HELMET SEALED"
			sc = C_BAD
		elif o2 < 18.0 or co2 > 1.5:
			status = "AIR QUALITY FALLING"
			sc = C_WARN
		if s.is_true("vents"):
			status += "  |  CIRCULATION ON"
		_text(Vector2(x, y + 50), status, 13, sc)
	if me.is_floating:
		_text(Vector2(x, y + 70), "ZERO-G: Space = up, Ctrl = down, Space near a wall = push off", 12, C_WARN, HORIZONTAL_ALIGNMENT_RIGHT, w)


func _draw_vitals(me: Astronaut, vp: Vector2) -> void:
	var x := 22.0
	var y := vp.y - 118.0
	var bw := Vector2(210, 9)
	var hc := C_OK if me.health > 50 else (C_WARN if me.health > 25 else C_BAD)
	_bar(Vector2(x, y), bw, me.health / 100.0, hc, "HEALTH", "%d" % int(ceil(me.health)))
	var oc := C_LINE if me.suit_o2 > 30 else (C_WARN if me.suit_o2 > 12 else C_BAD)
	var o2_label := "SUIT OXYGEN (IN USE)" if me.helmet_sealed else "SUIT OXYGEN"
	_bar(Vector2(x, y + 34), bw, me.suit_o2 / 100.0, oc, o2_label, "%d%%" % int(me.suit_o2))
	var bc := Color(1.0, 0.95, 0.7) if me.battery > 20 else C_BAD
	_bar(Vector2(x, y + 68), bw, me.battery / 100.0, bc, "FLASHLIGHT [F] " + ("ON" if me.flashlight_on else "OFF"), "%d%%" % int(me.battery))
	if me.carrying != "":
		_text(Vector2(x, y + 100), "CARRYING: POWER CELL   [G] put down", 13, C_WARN)


func _draw_crew(me: Astronaut, vp: Vector2) -> void:
	var x := vp.x - 200.0
	var y := vp.y - 40.0 - 22.0 * _level.get_astronauts().size()
	_text(Vector2(x, y), "CREW", 13, C_LINE)
	y += 20
	for a in _level.get_astronauts():
		var col: Color = Astronaut.SUIT_COLORS[a.slot % 4]
		draw_circle(Vector2(x + 5, y - 5), 5.0, col)
		var status := "OK"
		var sc := C_TEXT
		if a.downed:
			status = "DOWN"
			sc = C_BAD
		elif a.health < 40.0:
			status = "HURT"
			sc = C_WARN
		elif a.helmet_sealed and not a.is_bot:
			status = "O2 %d%%" % int(a.suit_o2)
			sc = C_WARN if a.suit_o2 < 30 else C_TEXT
		var who := a.crew_name() + (" (you)" if a == me else (" (AI)" if a.is_bot else ""))
		_text(Vector2(x + 16, y), who, 13, C_TEXT)
		_text(Vector2(x + 16, y), status, 13, sc, HORIZONTAL_ALIGNMENT_RIGHT, 160)
		y += 22


func _draw_centre(me: Astronaut, vp: Vector2) -> void:
	var c := vp * 0.5
	draw_circle(c, 1.6, Color(1, 1, 1, 0.75))
	var f := me.focused
	if f == null or not is_instance_valid(f):
		return
	var prompt := f.get_prompt(me)
	if prompt == "":
		return
	var usable := f.can_use(me)
	var y := c.y + 46.0
	if usable:
		var verb := "Hold [E]  " if (f.hold_time > 0.0 or f.continuous) else "[E]  "
		_text(Vector2(0, y), verb + prompt, 17, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		if me.hold_progress > 0.0:
			var w := 180.0
			draw_rect(Rect2(c.x - w * 0.5, y + 10, w, 6), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(c.x - w * 0.5, y + 10, w * me.hold_progress, 6), C_LINE)
	else:
		_text(Vector2(0, y), prompt, 17, Color(C_TEXT, 0.55), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		_text(Vector2(0, y + 22), f.get_blocked_reason(me), 14, C_WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_messages(vp: Vector2) -> void:
	var y := 150.0
	for a: Dictionary in _announcements:
		var alpha := clampf(a["t"], 0.0, 1.0)
		var w := _font.get_string_size(a["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 36.0
		draw_rect(Rect2(vp.x * 0.5 - w * 0.5, y - 20, w, 30), Color(C_PANEL, 0.6 * alpha))
		draw_rect(Rect2(vp.x * 0.5 - w * 0.5, y - 20, 3, 30), Color(C_WARN, alpha))
		_text(Vector2(0, y), a["text"], 17, Color(C_TEXT, alpha), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 36
	y = vp.y - 150.0 - 24.0 * _radio.size()
	for r: Dictionary in _radio:
		var alpha := clampf(r["t"], 0.0, 1.0)
		var line := "%s:  %s" % [r["speaker"], r["text"]]
		var col: Color = (r["color"] as Color).lerp(Color.WHITE, 0.45)
		_text(Vector2(0, y), line, 16, Color(col, alpha), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 24


func _draw_complete(s: StationState, vp: Vector2) -> void:
	_complete_shown += get_process_delta_time()
	if _complete_shown > 14.0:
		_text(Vector2(0, 30), "LEVEL COMPLETE. Keep exploring, or press Esc for the menu", 13, C_OK, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		return
	var alpha := clampf(_complete_shown, 0.0, 1.0)
	draw_rect(Rect2(0, vp.y * 0.3, vp.x, 150), Color(0, 0, 0, 0.6 * alpha))
	_text(Vector2(0, vp.y * 0.3 + 52), "LEVEL COMPLETE", 40, Color(C_OK, alpha), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	var secs := int(s.get_value("complete.time", 0))
	_text(Vector2(0, vp.y * 0.3 + 84), "Power, air and communications restored in %d:%02d" % [secs / 60, secs % 60], 17, Color(C_TEXT, alpha), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_text(Vector2(0, vp.y * 0.3 + 116), "Something answered the transmission. It was not Mission Control.", 15, Color(C_WARN, alpha), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
