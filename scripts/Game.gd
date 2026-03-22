extends Node2D

const EMOJIS = ["🐱", "🐶", "🐱", "🐶", "🐱", "🐶", "😺", "🐕", "🦄"]
const EMOJI_WEIGHTS = [20, 20, 20, 20, 15, 15, 10, 10, 1]  # unicorn is rare!
const BASKET_WIDTH = 90.0
const BASKET_SPEED = 400.0

var score: int = 0
var lives: int = 3
var combo: int = 0
var running: bool = false
var basket_x: float = 200.0
var target_x: float = 200.0
var spawn_timer: float = 0.0
var spawn_interval: float = 1.2
var animal_speed: float = 140.0
var frame_count: int = 0

@onready var basket = $Basket
@onready var score_label = $UI/ScoreLabel
@onready var lives_label = $UI/LivesLabel
@onready var combo_label = $UI/ComboLabel
@onready var overlay = $Overlay
@onready var overlay_title = $Overlay/Title
@onready var overlay_sub = $Overlay/Sub
@onready var play_button = $Overlay/PlayButton
@onready var combo_timer = $ComboTimer
@onready var rain_particles = $RainParticles

func _ready():
	show_start_screen()

func show_start_screen():
	running = false
	overlay.visible = true
	overlay_title.text = "🌧️ It's Raining\nCats & Dogs!"
	overlay_sub.text = "Catch them before they hit the ground.\nMiss 3 and it's game over!"
	play_button.text = "▶  Play!"

func _process(delta):
	if not running:
		return

	frame_count += 1

	# Smooth basket movement - mouse/touch
	var vp_size = get_viewport().get_visible_rect().size
	if Input.is_action_pressed("ui_left"):
		target_x -= BASKET_SPEED * delta
	if Input.is_action_pressed("ui_right"):
		target_x += BASKET_SPEED * delta

	target_x = clamp(target_x, BASKET_WIDTH / 2, 400 - BASKET_WIDTH / 2)
	basket_x = lerp(basket_x, target_x, 0.18 / delta * delta * 12)
	basket.position.x = basket_x

	# Spawn animals
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		spawn_animal()

	# Difficulty ramp every 10 seconds
	if frame_count % (60 * 10) == 0:
		animal_speed = min(animal_speed + 12.0, 320.0)
		spawn_interval = max(spawn_interval - 0.08, 0.45)

func _input(event):
	if not running:
		return
	# Mouse movement
	if event is InputEventMouseMotion:
		var vp = get_viewport().get_visible_rect().size
		var scale_x = 400.0 / vp.x
		target_x = event.position.x * scale_x
	# Touch
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var vp = get_viewport().get_visible_rect().size
		var scale_x = 400.0 / vp.x
		target_x = event.position.x * scale_x

func spawn_animal():
	var emoji = weighted_choice(EMOJIS, EMOJI_WEIGHTS)
	var label = Label.new()
	label.text = emoji
	label.add_theme_font_size_override("font_size", 32)
	label.position = Vector2(randf_range(30, 370), -40)

	var anim_script = load("res://scripts/Animal.gd")
	label.set_script(anim_script)
	label.speed = animal_speed + randf() * 40.0

	label.connect("animal_missed", _on_animal_missed)
	label.connect("animal_caught", _on_animal_caught.bind(label, emoji))

	add_child(label)

func weighted_choice(items: Array, weights: Array) -> String:
	var total = 0
	for w in weights:
		total += w
	var r = randi() % total
	var cumulative = 0
	for i in range(items.size()):
		cumulative += weights[i]
		if r < cumulative:
			return items[i]
	return items[0]

func _physics_process(_delta):
	if not running:
		return
	# Check catches
	var bx = basket_x
	var by = 560.0  # basket top Y
	for child in get_children():
		if child.get_script() and child.get_script().resource_path == "res://scripts/Animal.gd":
			if not child.caught and not child.missed:
				var cx = child.position.x
				var cy = child.position.y
				if abs(cx - bx) < BASKET_WIDTH / 2 + 10 and cy > by - 10 and cy < by + 40:
					child.call("catch_animal")

func _on_animal_caught(_node, emoji):
	score += (10 if emoji == "🦄" else 1)
	combo += 1
	update_ui()
	show_combo()
	spawn_catch_particles(basket_x, 560)

func _on_animal_missed():
	combo = 0
	lives -= 1
	update_ui()
	if lives <= 0:
		game_over()

func show_combo():
	if combo < 3:
		combo_label.visible = false
		return
	combo_label.visible = true
	if combo >= 10:
		combo_label.text = "💫 GODLIKE ×" + str(combo)
	elif combo >= 8:
		combo_label.text = "🌪️ UNSTOPPABLE ×" + str(combo)
	elif combo >= 5:
		combo_label.text = "🔥🔥 ON FIRE ×" + str(combo)
	else:
		combo_label.text = "🔥 Triple! ×" + str(combo)
	combo_timer.start()

func _on_combo_timer_timeout():
	combo_label.visible = false

func spawn_catch_particles(x: float, y: float):
	for i in range(8):
		var p = Label.new()
		p.text = "✨"
		p.add_theme_font_size_override("font_size", 20)
		p.position = Vector2(x + randf_range(-20, 20), y)
		add_child(p)
		var tween = create_tween()
		var tx = x + randf_range(-60, 60)
		var ty = y + randf_range(-80, -20)
		tween.tween_property(p, "position", Vector2(tx, ty), 0.5)
		tween.parallel().tween_property(p, "modulate:a", 0.0, 0.5)
		tween.tween_callback(p.queue_free)

func update_ui():
	score_label.text = "⭐ " + str(score)
	var hearts = ""
	for i in range(lives):
		hearts += "❤️"
	lives_label.text = hearts if lives > 0 else "💀"

func game_over():
	running = false
	var msg = ""
	if score < 5: msg = "The animals got away..."
	elif score < 20: msg = "Not bad!"
	elif score < 50: msg = "Impressive rescue!"
	else: msg = "🏆 Animal Hero!"

	overlay.visible = true
	overlay_title.text = "☔ Game Over!\nScore: " + str(score)
	overlay_sub.text = msg
	play_button.text = "▶  Play Again"

func _on_play_button_pressed():
	# Clear all animals
	for child in get_children():
		if child.get_script():
			child.queue_free()
	score = 0
	lives = 3
	combo = 0
	frame_count = 0
	animal_speed = 140.0
	spawn_interval = 1.2
	spawn_timer = 0.0
	basket_x = 200.0
	target_x = 200.0
	combo_label.visible = false
	overlay.visible = false
	running = true
	update_ui()
