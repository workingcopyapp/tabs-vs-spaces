extends Node2D
## A word crawling down the screen. Its letters lean forward one after the other and drop a
## step, and once the last letter has dropped, the whole word has moved down one step.

signal letter_dropped

const LETTER_SCALE := 0.3
const SHAKE_ANGLE := 0.05 * PI

var velocity := 200.0
var width := 0.0
var letter_height := 0.0

var letters: Array[String] = []
var sprites: Array[Sprite2D] = []
var offsets: Array[float] = []
var shakes := {}
var drops := {}


func setup(text: String) -> void:
	for c in text.to_lower():
		if c < "a" or c > "z":
			continue
		var sprite := Sprite2D.new()
		sprite.texture = load("res://art/letters/%s.png" % c)
		sprite.scale = Vector2.ONE * LETTER_SCALE
		add_child(sprite)
		letters.append(c)
		sprites.append(sprite)
		offsets.append(0.0)
		width += sprite.texture.get_width() * LETTER_SCALE
		letter_height = maxf(letter_height, sprite.texture.get_height() * LETTER_SCALE)

	var x := -0.5 * width
	for sprite in sprites:
		var letter_width := sprite.texture.get_width() * LETTER_SCALE
		sprite.position = Vector2(x + 0.5 * letter_width, 0.0)
		x += letter_width


func is_done() -> bool:
	return letters.is_empty()


# removes the first letter when it is c, returning where it was, or null
func typed(c: String) -> Variant:
	if letters.is_empty() or letters[0] != c:
		return null

	var removed: Sprite2D = sprites.pop_front()
	letters.pop_front()
	offsets.pop_front()
	stop_shake(removed)
	var point := removed.global_position

	var fade := removed.create_tween()
	fade.tween_property(removed, "modulate:a", 0.0, 0.3)
	fade.tween_callback(removed.queue_free)
	return point


func advance(delta: float) -> void:
	if sprites.is_empty():
		return

	var step := 0.4 * letter_height
	var t := velocity * delta
	while t > 0.0:
		for i in sprites.size():
			var space := step - offsets[i]
			if space > 0.0:
				if t < space:
					offsets[i] += t
					t = 0.0
					shake(sprites[i])
				else:
					offsets[i] = step
					t -= space
					drop(sprites[i], step)
			if t <= 0.0:
				break

		# when the last letter has dropped, the word moves down and the letters back up
		if offsets[-1] >= step:
			for i in sprites.size():
				stop_shake(sprites[i])
				if drops.has(sprites[i]):
					drops[sprites[i]].kill()
					drops.erase(sprites[i])
				offsets[i] = 0.0
				sprites[i].position.y = 0.0
			position.y += step


func drop(sprite: Sprite2D, step: float) -> void:
	stop_shake(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "position:y", step, 0.05)
	drops[sprite] = tween
	letter_dropped.emit()


func shake(sprite: Sprite2D) -> void:
	if shakes.has(sprite):
		return
	var tween := sprite.create_tween().set_loops()
	tween.tween_property(sprite, "rotation", -SHAKE_ANGLE, 0.1)
	tween.tween_property(sprite, "rotation", SHAKE_ANGLE, 0.2)
	tween.tween_property(sprite, "rotation", 0.0, 0.1)
	shakes[sprite] = tween


func stop_shake(sprite: Sprite2D) -> void:
	if not shakes.has(sprite):
		return
	shakes[sprite].kill()
	shakes.erase(sprite)
	sprite.create_tween().tween_property(sprite, "rotation", 0.0, 0.1)


# the letters that made it all the way grow and gloat
func celebrate() -> void:
	for sprite in sprites:
		shake(sprite)
		sprite.create_tween().tween_property(sprite, "scale", Vector2.ONE * LETTER_SCALE * 10.0, 20.0)
