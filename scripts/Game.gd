extends Node2D

# Animal types with canvas-drawn shapes (no emoji font dependency)
const ANIMAL_TYPES = ["cat", "dog", "cat", "dog", "cat", "dog", "special_cat", "special_dog", "unicorn"]
const ANIMAL_WEIGHTS = [20, 20, 20, 20, 15, 15, 10, 10, 1]

const BASKET_WIDTH = 90.0
const BASKET_SPEED = 400.0
const GROUND_Y = 570.0

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
var animals: Array = []
var particles: Array = []

# Colors
const CAT_COLOR = Color(1.0, 0.6, 0.8)      # pink cat
const DOG_COLOR = Color(0.9, 0.7, 0.4)       # tan dog
const SPECIAL_CAT_COLOR = Color(0.6, 0.4, 1.0)  # purple
const SPECIAL_DOG_COLOR = Color(0.4, 0.8, 1.0)  # blue
const UNICORN_COLOR = Color(1.0, 0.9, 0.2)   # gold
const BASKET_COLOR = Color(0.24, 0.61, 0.56)
const BASKET_RIM = Color(0.46, 0.79, 0.58)
const BG_TOP = Color(0.05, 0.1, 0.16)
const BG_BOT = Color(0.1, 0.26, 0.2)

@onready var overlay = $Overlay
@onready var overlay_title = $Overlay/Title
@onready var overlay_sub = $Overlay/Sub
@onready var play_button = $Overlay/PlayButton
@onready var score_label = $UI/ScoreLabel
@onready var lives_label = $UI/LivesLabel
@onready var combo_label = $UI/ComboLabel
@onready var combo_timer = $ComboTimer

func _ready():
	show_start_screen()

func show_start_screen():
	running = false
	overlay.visible = true
	overlay_title.text = "It's Raining\nCats & Dogs!"
	overlay_sub.text = "Catch the animals before\nthey hit the ground!\nMiss 3 = Game Over"
	play_button.text = "PLAY!"

func _process(delta):
	if running:
		frame_count += 1
		_handle_input(delta)
		_update_spawn(delta)
		_update_animals(delta)
		_update_particles(delta)
		if frame_count % (60 * 10) == 0:
			animal_speed = min(animal_speed + 12.0, 320.0)
			spawn_interval = max(spawn_interval - 0.08, 0.45)
	queue_redraw()

func _handle_input(delta):
	if Input.is_action_pressed("ui_left"):
		target_x -= BASKET_SPEED * delta
	if Input.is_action_pressed("ui_right"):
		target_x += BASKET_SPEED * delta
	target_x = clamp(target_x, BASKET_WIDTH / 2, 400 - BASKET_WIDTH / 2)
	basket_x = lerp(basket_x, target_x, delta * 12.0)

func _input(event):
	if not running:
		return
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		var vp = get_viewport().get_visible_rect().size
		var scale_x = 400.0 / vp.x
		target_x = clamp(event.position.x * scale_x, BASKET_WIDTH/2, 400 - BASKET_WIDTH/2)
	if event is InputEventScreenTouch and event.pressed:
		var vp = get_viewport().get_visible_rect().size
		var scale_x = 400.0 / vp.x
		target_x = clamp(event.position.x * scale_x, BASKET_WIDTH/2, 400 - BASKET_WIDTH/2)

func _update_spawn(delta):
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_animal()

func _spawn_animal():
	var type_idx = _weighted_choice(ANIMAL_WEIGHTS)
	animals.append({
		"type": ANIMAL_TYPES[type_idx],
		"x": randf_range(30, 370),
		"y": -30.0,
		"speed": animal_speed + randf() * 40.0,
		"wobble": randf() * TAU,
		"caught": false,
		"missed": false,
		"walk_dir": 1.0,
		"alpha": 1.0,
		"scale": 1.0,
		"catch_anim": 0.0,  # 0 = normal, >0 = catching animation
	})

func _weighted_choice(weights: Array) -> int:
	var total = 0
	for w in weights: total += w
	var r = randi() % total
	var cumulative = 0
	for i in range(weights.size()):
		cumulative += weights[i]
		if r < cumulative: return i
	return 0

func _update_animals(delta):
	var basket_top = GROUND_Y - 40
	var to_remove = []

	for i in range(animals.size()):
		var a = animals[i]
		a.wobble += delta * 3.0

		if a.catch_anim > 0:
			a.catch_anim -= delta * 4.0
			a.scale = 1.0 + sin(a.catch_anim * PI) * 0.5
			if a.catch_anim <= 0:
				to_remove.append(i)
			continue

		if a.caught:
			continue

		if a.missed:
			a.x += a.walk_dir * 60.0 * delta
			a.alpha -= delta * 1.5
			if a.alpha <= 0: to_remove.append(i)
			continue

		a.y += a.speed * delta
		a.x += sin(a.wobble) * 0.8

		# Check catch
		if (a.y + 20 >= basket_top and a.y - 20 <= basket_top + 35
				and abs(a.x - basket_x) < BASKET_WIDTH / 2 + 12):
			a.caught = true
			a.catch_anim = 1.0
			a.scale = 1.0
			score += 10 if a.type == "unicorn" else 1
			combo += 1
			_spawn_catch_particles(a.x, basket_top)
			_show_combo()
			update_ui()

		elif a.y > GROUND_Y:
			a.missed = true
			a.walk_dir = 1.0 if a.x < 200 else -1.0
			combo = 0
			lives -= 1
			update_ui()
			if lives <= 0:
				call_deferred("game_over")

	# Remove in reverse order
	for i in range(to_remove.size() - 1, -1, -1):
		animals.remove_at(to_remove[i])

func _update_particles(delta):
	var to_remove = []
	for i in range(particles.size()):
		var p = particles[i]
		p.x += p.vx * delta * 60
		p.y += p.vy * delta * 60
		p.vy += 0.15
		p.life -= delta * 2.0
		if p.life <= 0: to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		particles.remove_at(to_remove[i])

func _spawn_catch_particles(x: float, y: float):
	for i in range(10):
		var angle = (TAU / 10.0) * i
		particles.append({
			"x": x, "y": y,
			"vx": cos(angle) * (1.5 + randf() * 2.0),
			"vy": sin(angle) * (1.5 + randf() * 2.0) - 1.0,
			"life": 1.0,
			"color": Color(1.0, 0.9, 0.3, 1.0)
		})

func _draw():
	# Background gradient (manual)
	for y in range(0, 600, 4):
		var t = float(y) / 600.0
		var c = BG_TOP.lerp(BG_BOT, t)
		draw_rect(Rect2(0, y, 400, 4), c)

	# Rain streaks
	for i in range(40):
		var rx = fmod(i * 173.0 + frame_count * 1.5, 400.0)
		var ry = fmod(i * 97.0 + frame_count * 2.0, 600.0)
		draw_line(Vector2(rx, ry), Vector2(rx - 3, ry + 10),
			Color(0.4, 0.7, 1.0, 0.25), 1.0)

	# Animals
	for a in animals:
		if a.caught and a.catch_anim <= 0: continue
		var col = _get_animal_color(a.type)
		var alpha = a.alpha if a.missed else 1.0
		col.a = alpha
		_draw_animal(a.x, a.y, a.type, col, a.scale)

	# Particles
	for p in particles:
		var c = p.color
		c.a = p.life
		draw_circle(Vector2(p.x, p.y), 4.0 * p.life, c)

	# Basket
	_draw_basket(basket_x, GROUND_Y - 35)

func _get_animal_color(type: String) -> Color:
	match type:
		"cat", _: return CAT_COLOR
		"dog": return DOG_COLOR
		"special_cat": return SPECIAL_CAT_COLOR
		"special_dog": return SPECIAL_DOG_COLOR
		"unicorn": return UNICORN_COLOR
	return CAT_COLOR

func _draw_animal(x: float, y: float, type: String, color: Color, scale: float = 1.0):
	var s = 14.0 * scale  # half-size

	match type:
		"cat", "special_cat":
			# Body
			draw_circle(Vector2(x, y), s, color)
			# Ears (triangles) - use draw_line for simplicity
			var ear_col = color.darkened(0.3)
			draw_circle(Vector2(x - s * 0.55, y - s * 0.9), s * 0.35, ear_col)
			draw_circle(Vector2(x + s * 0.55, y - s * 0.9), s * 0.35, ear_col)
			# Eyes
			draw_circle(Vector2(x - s * 0.35, y - s * 0.1), s * 0.18, Color(0.1, 0.1, 0.1))
			draw_circle(Vector2(x + s * 0.35, y - s * 0.1), s * 0.18, Color(0.1, 0.1, 0.1))
			# Nose
			draw_circle(Vector2(x, y + s * 0.2), s * 0.12, Color(1.0, 0.5, 0.5))
			# Whiskers
			draw_line(Vector2(x - s * 0.8, y + s * 0.15), Vector2(x - s * 0.1, y + s * 0.25), Color(1,1,1,0.5), 1)
			draw_line(Vector2(x + s * 0.1, y + s * 0.25), Vector2(x + s * 0.8, y + s * 0.15), Color(1,1,1,0.5), 1)
			# Tail
			draw_arc(Vector2(x + s * 1.2, y + s * 0.5), s * 0.7, -PI * 0.5, PI * 0.3, 12, color, 2.5)

		"dog", "special_dog":
			# Body (rounder, fluffier)
			draw_circle(Vector2(x, y), s * 1.05, color)
			# Floppy ears
			var ear_col = color.darkened(0.25)
			draw_circle(Vector2(x - s * 0.9, y + s * 0.2), s * 0.55, ear_col)
			draw_circle(Vector2(x + s * 0.9, y + s * 0.2), s * 0.55, ear_col)
			# Eyes (bigger, happier)
			draw_circle(Vector2(x - s * 0.38, y - s * 0.15), s * 0.22, Color(0.1, 0.1, 0.1))
			draw_circle(Vector2(x + s * 0.38, y - s * 0.15), s * 0.22, Color(0.1, 0.1, 0.1))
			# Eye shine
			draw_circle(Vector2(x - s * 0.3, y - s * 0.22), s * 0.07, Color(1,1,1,0.8))
			draw_circle(Vector2(x + s * 0.46, y - s * 0.22), s * 0.07, Color(1,1,1,0.8))
			# Nose (bigger)
			draw_circle(Vector2(x, y + s * 0.25), s * 0.22, Color(0.3, 0.15, 0.1))
			# Tongue
			draw_circle(Vector2(x, y + s * 0.55), s * 0.2, Color(1.0, 0.4, 0.5))
			# Tail (wagging line)
			draw_arc(Vector2(x + s * 1.3, y - s * 0.3), s * 0.6, -PI * 0.3, PI * 0.4, 10, color, 2.5)

		"unicorn":
			# Body
			draw_circle(Vector2(x, y), s, UNICORN_COLOR)
			# Horn (use lines instead of polygon)
			draw_line(Vector2(x - s * 0.12, y - s * 0.85), Vector2(x, y - s * 1.8), Color(1,0.6,0.9), 4)
			draw_line(Vector2(x + s * 0.12, y - s * 0.85), Vector2(x, y - s * 1.8), Color(1,0.8,1), 2)
			# Mane
			draw_arc(Vector2(x - s * 0.5, y - s * 0.3), s * 0.5, 0, PI, 10, Color(0.9, 0.4, 1.0), 3)
			# Eyes (sparkle)
			draw_circle(Vector2(x - s * 0.35, y - s * 0.1), s * 0.18, Color(0.5, 0.1, 0.8))
			draw_circle(Vector2(x + s * 0.35, y - s * 0.1), s * 0.18, Color(0.5, 0.1, 0.8))
			draw_circle(Vector2(x - s * 0.28, y - s * 0.17), s * 0.07, Color(1,1,1,0.9))

func _draw_basket(x: float, y: float):
	var bw = BASKET_WIDTH
	var bh = 32.0

	# Glow
	draw_rect(Rect2(x - bw/2 - 4, y - 4, bw + 8, bh + 8),
		Color(0.0, 0.94, 1.0, 0.1), true, 1.0, true)

	# Body (rect approximation — no polygon color array needed)
	draw_rect(Rect2(x - bw/2, y, bw, bh), BASKET_COLOR)

	# Weave lines
	for i in range(1, 4):
		var fy = y + (bh / 4.0) * i
		var inset = (i / 4.0) * 6.0
		draw_line(Vector2(x - bw/2 + inset, fy), Vector2(x + bw/2 - inset, fy),
			Color(1,1,1,0.15), 1)

	# Rim
	draw_line(Vector2(x - bw/2 - 2, y + 3), Vector2(x + bw/2 + 2, y + 3),
		BASKET_RIM, 4.0)

func _show_combo():
	if combo < 3:
		combo_label.visible = false
		return
	combo_label.visible = true
	if combo >= 10: combo_label.text = "GODLIKE x" + str(combo) + "!"
	elif combo >= 8: combo_label.text = "UNSTOPPABLE x" + str(combo)
	elif combo >= 5: combo_label.text = "ON FIRE x" + str(combo)
	else: combo_label.text = "COMBO x" + str(combo)
	combo_timer.start()

func _on_combo_timer_timeout():
	combo_label.visible = false

func update_ui():
	score_label.text = "Score: " + str(score)
	var hearts = ""
	for i in range(lives): hearts += "<3 "
	lives_label.text = hearts.strip_edges() if lives > 0 else "x_x"

func game_over():
	running = false
	var msg = ""
	if score < 5: msg = "The animals got away!"
	elif score < 20: msg = "Not bad!"
	elif score < 50: msg = "Impressive rescuer!"
	else: msg = "ANIMAL HERO!"
	overlay.visible = true
	overlay_title.text = "GAME OVER\nScore: " + str(score)
	overlay_sub.text = msg + "\nMiss some next time too?"
	play_button.text = "PLAY AGAIN"

func _on_play_button_pressed():
	for a in animals: pass
	animals.clear()
	particles.clear()
	score = 0; lives = 3; combo = 0; frame_count = 0
	animal_speed = 140.0; spawn_interval = 1.2; spawn_timer = 0.0
	basket_x = 200.0; target_x = 200.0
	combo_label.visible = false
	overlay.visible = false
	running = true
	update_ui()
