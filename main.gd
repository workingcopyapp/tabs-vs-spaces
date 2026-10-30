extends Node2D
## Tabs vs Spaces: pick the tab or the space as your key, and type the first letter of the words
## crawling down towards it to shoot them away, one letter at a time.

const WordScript := preload("res://word.gd")

# the title is laid out on a canvas of this size and scaled to fit the screen
const TITLE_SIZE := Vector2(2048, 2732)
const HERO_MARGIN := 24.0
# radians per second of the key swaying from side to side
const SWAY_SPEED := 0.8
# the first words spell out a sentence, coming in quickly from left to right
const INTRO := "Using the Files app it is easy to combine Git with Obsidian, Xogot & many other apps."
const INTRO_GAP := 0.3

@export var laser_color := Color(1.0, 0.15, 0.1)
@export var start_velocity := 200.0

@onready var background: Sprite2D = $Background
@onready var words_layer: Node2D = $Words
@onready var lasers: Node2D = $Lasers
@onready var heroes := {"tab": $Heroes/Tab, "space": $Heroes/Space}
@onready var title: Node2D = $Title
@onready var tab_key: Sprite2D = $Title/TabKey
@onready var space_key: Sprite2D = $Title/SpaceKey
@onready var subtitle: Label = $Title/Subtitle
@onready var keyboard: LineEdit = $Keyboard
@onready var laser_sound: AudioStreamPlayer = $LaserSound
@onready var blip_sound: AudioStreamPlayer = $BlipSound
@onready var laugh_sound: AudioStreamPlayer = $LaughSound

var source: Array[String] = []
var source_index := 0
var intro_count := 0
var intro_x := 0.0
var words: Array[WordScript] = []
var hero: Sprite2D
var lost := false
var game_time := 0.0
var since_last_word := 0.0
var last_word_length := 0
var key_bases := {}


func _ready() -> void:
	add_words(INTRO)
	intro_count = source.size()
	add_words(FileAccess.get_file_as_string("res://words.txt"))

	for key in [tab_key, space_key]:
		key_bases[key] = key.position
	float_key(tab_key, 2.0)
	float_key(space_key, 1.0)

	keyboard.text_changed.connect(_on_keyboard_text_changed)
	get_viewport().size_changed.connect(layout)
	layout()
	show_title()


# words without any of the letters a to z, such as [1] or &, are left out
func add_words(text: String) -> void:
	for token in text.replace("\n", " ").split(" ", false):
		for c in token.to_lower():
			if c >= "a" and c <= "z":
				source.append(token)
				break


func layout() -> void:
	var size := get_viewport_rect().size

	# the background covers the screen
	var picture := background.texture.get_size()
	var cover := maxf(size.x / picture.x, size.y / picture.y)
	background.scale = Vector2.ONE * cover
	background.position = 0.5 * (size - picture * cover)

	# the title fits the screen
	var fit := minf(size.x / TITLE_SIZE.x, size.y / TITLE_SIZE.y)
	title.scale = Vector2.ONE * fit
	title.position = 0.5 * (size - TITLE_SIZE * fit)


func show_title() -> void:
	title.visible = true
	title.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(title, "modulate:a", 1.0, 1.0)

	# the subtitle is typed out after a moment
	subtitle.visible_ratio = 0.0
	var typing := create_tween()
	typing.tween_interval(1.0)
	typing.tween_property(subtitle, "visible_ratio", 1.0, subtitle.text.length() / 12.0)


func float_key(key: Sprite2D, speed: float) -> void:
	var delay := 1.0 / speed
	var duration := delay + delay * randf()
	var target: Vector2 = key_bases[key] + Vector2(randf_range(-50.0, 50.0), randf_range(-25.0, 25.0))
	var tween := key.create_tween()
	tween.tween_property(key, "position", target, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(float_key.bind(key, speed))


func _unhandled_input(event: InputEvent) -> void:
	var tap = null
	if event is InputEventScreenTouch and event.pressed:
		tap = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap = event.position

	if hero == null and title.visible:
		if tap != null:
			for key in [tab_key, space_key]:
				if key.get_rect().has_point(key.to_local(tap)):
					pick_hero("tab" if key == tab_key else "space")
					return
		elif event is InputEventKey and event.pressed:
			if event.keycode == KEY_TAB:
				pick_hero("tab")
			elif event.keycode == KEY_SPACE:
				pick_hero("space")
	elif hero != null and not lost:
		if tap != null:
			keyboard.grab_focus()
		elif event is InputEventKey and event.pressed and not event.echo and event.unicode != 0:
			typed(char(event.unicode).to_lower())


func _on_keyboard_text_changed(text: String) -> void:
	for c in text:
		typed(c.to_lower())
	keyboard.clear()


func pick_hero(which: String) -> void:
	var key := tab_key if which == "tab" else space_key
	hero = heroes[which]
	hero.global_position = key.global_position
	hero.modulate.a = 1.0
	hero.visible = true

	var fade := create_tween()
	fade.tween_property(title, "modulate:a", 0.0, 0.4)
	fade.tween_callback(func(): title.visible = false)

	# keys reach the game through the text field, as a host such as Xogot keeps hardware key
	# presses to itself
	keyboard.grab_focus()
	lost = false
	game_time = 0.0
	since_last_word = 0.0
	last_word_length = 0


func _process(delta: float) -> void:
	if hero == null or lost:
		return

	game_time += delta
	since_last_word += delta
	var in_intro := source_index < intro_count
	if since_last_word > (INTRO_GAP if in_intro else time_between_letters() * last_word_length):
		add_next_word()

	# the key glides to the bottom, above the keyboard when one is shown, and sways from side
	# to side as far as the screen allows, which is further for the tab than the space
	var size := get_viewport_rect().size
	var sway := maxf(0.0, 0.5 * size.x - hero_half_width() - HERO_MARGIN)
	var target := Vector2(0.5 * size.x + sway * sin(SWAY_SPEED * game_time),
			size.y - keyboard_height() - hero_half_height() - HERO_MARGIN)
	hero.position = hero.position.lerp(target, 1.0 - exp(-6.0 * delta))

	for word in words:
		word.advance(delta)
		if word.position.y + 0.5 * word.letter_height >= hero.position.y - hero_half_height():
			lose()
			return


func time_between_letters() -> float:
	return 0.6 * exp(-0.01 * game_time)


func current_velocity() -> float:
	return start_velocity + 150.0 * log(1.0 + 0.001 * game_time)


func hero_half_width() -> float:
	return 0.5 * hero.texture.get_width() * hero.scale.x


func hero_half_height() -> float:
	return 0.5 * hero.texture.get_height() * hero.scale.y


func keyboard_height() -> float:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	# a host such as Xogot shrinks the game view to make room for the keyboard itself
	var window := DisplayServer.window_get_size()
	if window.y <= 0 or window.y < 0.9 * DisplayServer.screen_get_size().y:
		return 0.0
	var pixels := DisplayServer.virtual_keyboard_get_height()
	var height := pixels * get_viewport_rect().size.y / window.y
	return minf(height, 0.6 * get_viewport_rect().size.y)


func add_next_word() -> void:
	var in_intro := source_index < intro_count
	var text := source[source_index % source.size()]
	source_index += 1

	var word := WordScript.new()
	word.setup(text)
	word.velocity = current_velocity()
	word.letter_dropped.connect(blip_sound.play)

	var size := get_viewport_rect().size
	var half := 0.5 * word.width + 10.0
	var x := randf_range(half, maxf(half, size.x - half))
	if in_intro:
		# the sentence reads from left to right, starting over at the left edge when the next
		# word does not fit
		x = intro_x + half
		if x + half > size.x:
			x = half
		intro_x = x + half
	word.position = Vector2(x, 1.5 * word.letter_height)
	words_layer.add_child(word)
	words.append(word)

	since_last_word = 0.0
	last_word_length = word.letters.size()


func typed(c: String) -> void:
	if c.length() != 1 or c < "a" or c > "z":
		return
	# a letter shoots the oldest word waiting for it, so words sharing letters go in turn
	for word: WordScript in words:
		var point = word.typed(c)
		if point == null:
			continue
		shoot(point)
		if word.is_done():
			words.erase(word)
			var fade := word.create_tween()
			fade.tween_property(word, "modulate:a", 0.0, 1.0)
			fade.tween_callback(word.queue_free)
		return


func shoot(point: Vector2) -> void:
	var from := hero.global_position - Vector2(0.0, hero_half_height())
	var glow := Line2D.new()
	glow.points = [from, point]
	glow.width = 14.0
	glow.default_color = Color(laser_color, 0.35)
	var beam := Line2D.new()
	beam.points = [from, point]
	beam.width = 4.0
	beam.default_color = laser_color
	glow.add_child(beam)
	lasers.add_child(glow)

	var fade := glow.create_tween()
	fade.tween_property(glow, "modulate:a", 0.0, 0.4)
	fade.tween_callback(glow.queue_free)
	laser_sound.play()


func lose() -> void:
	lost = true
	keyboard.release_focus()
	create_tween().tween_property(hero, "modulate:a", 0.0, 1.0)
	for word in words:
		word.celebrate()

	# the words laugh, louder and louder
	for i in 3:
		get_tree().create_timer(0.6 * i + 0.4 * randf()).timeout.connect(func():
			laugh_sound.volume_db = linear_to_db(0.3 * (i + 1))
			laugh_sound.play())

	await get_tree().create_timer(6.0).timeout
	restart()


func restart() -> void:
	var fade := create_tween()
	fade.tween_property(words_layer, "modulate:a", 0.0, 1.2)
	await fade.finished

	for word in words_layer.get_children():
		word.queue_free()
	for laser in lasers.get_children():
		laser.queue_free()
	words.clear()
	words_layer.modulate.a = 1.0
	for each in heroes.values():
		each.visible = false
	hero = null
	show_title()
