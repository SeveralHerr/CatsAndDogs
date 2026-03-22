extends Node2D

# Miyamoto Update v3:
# 1. Cats and dogs are now visually UNMISTAKABLE (shape language, not just color)
# 2. Miss feedback: screen flash + animal bounces before walking off
# 3. Lives drawn as hearts on canvas, not text
# 4. Shadow under falling animals for depth/readability

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
var screen_flash: float = 0.0        # miss flash intensity
var basket_squish: float = 0.0       # catch squish
var screen_flash_color: Color = Color(1, 0.2, 0.2, 0.0)

const CAT_COLOR       = Color(1.0, 0.55, 0.75)
const DOG_COLOR       = Color(0.85, 0.65, 0.35)
const SCAT_COLOR      = Color(0.7, 0.4, 1.0)
const SDOG_COLOR      = Color(0.3, 0.75, 1.0)
const UNICORN_COLOR   = Color(1.0, 0.9, 0.2)
const BASKET_COLOR    = Color(0.22, 0.58, 0.52)
const BASKET_RIM      = Color(0.42, 0.76, 0.55)
const BG_TOP          = Color(0.04, 0.09, 0.15)
const BG_BOT          = Color(0.08, 0.22, 0.16)
const HEART_COLOR     = Color(0.95, 0.25, 0.35)
const HEART_EMPTY     = Color(0.3, 0.3, 0.35)

@onready var overlay       = $Overlay
@onready var overlay_title = $Overlay/Title
@onready var overlay_sub   = $Overlay/Sub
@onready var play_button   = $Overlay/PlayButton
@onready var score_label   = $UI/ScoreLabel
@onready var lives_label   = $UI/LivesLabel
@onready var combo_label   = $UI/ComboLabel
@onready var combo_timer   = $ComboTimer

func _ready():
	lives_label.visible = false   # we draw hearts on canvas ourselves
	show_start_screen()

func show_start_screen():
	running = false
	overlay.visible = true
	overlay_title.text = "It's Raining\nCats & Dogs!"
	overlay_sub.text = "Catch the animals!\nMiss 3 = Game Over\nMove: Mouse / Arrow Keys"
	play_button.text = "PLAY!"

func _process(delta):
	if running:
		frame_count += 1
		_handle_input(delta)
		_update_spawn(delta)
		_update_animals(delta)
		_update_particles(delta)
		if screen_flash > 0:
			screen_flash = max(0.0, screen_flash - delta * 4.0)
		if basket_squish > 0:
			basket_squish = max(0.0, basket_squish - delta * 5.0)
		if frame_count % (60 * 10) == 0:
			animal_speed  = min(animal_speed + 12.0, 300.0)
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
		target_x = clamp(event.position.x * (400.0 / vp.x), BASKET_WIDTH/2, 400 - BASKET_WIDTH/2)
	if event is InputEventScreenTouch and event.pressed:
		var vp = get_viewport().get_visible_rect().size
		target_x = clamp(event.position.x * (400.0 / vp.x), BASKET_WIDTH/2, 400 - BASKET_WIDTH/2)

func _update_spawn(delta):
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_animal()

func _spawn_animal():
	var type_idx = _weighted_choice(ANIMAL_WEIGHTS)
	animals.append({
		"type": ANIMAL_TYPES[type_idx],
		"x": randf_range(35, 365),
		"y": -35.0,
		"speed": animal_speed + randf() * 40.0,
		"wobble": randf() * TAU,
		"caught": false,
		"missed": false,
		"walk_dir": 1.0,
		"alpha": 1.0,
		"scale": 1.0,
		"catch_anim": 0.0,
		"bounce_vy": 0.0,   # for miss bounce
		"on_ground": false,
	})

func _weighted_choice(weights: Array) -> int:
	var total = 0
	for w in weights: total += w
	var r = randi() % total
	var cum = 0
	for i in range(weights.size()):
		cum += weights[i]
		if r < cum: return i
	return 0

func _update_animals(delta):
	var basket_top = GROUND_Y - 40
	var to_remove  = []

	for i in range(animals.size()):
		var a = animals[i]
		a.wobble += delta * 3.0

		# Catch pop animation
		if a.catch_anim > 0:
			a.catch_anim -= delta * 4.0
			a.scale = 1.0 + sin(a.catch_anim * PI) * 0.6
			if a.catch_anim <= 0:
				to_remove.append(i)
			continue

		if a.caught: continue

		if a.missed:
			if not a.on_ground:
				# Bounce once on ground
				a.bounce_vy += 600.0 * delta
				a.y += a.bounce_vy * delta
				if a.y >= GROUND_Y - 20:
					a.y = GROUND_Y - 20
					a.on_ground = true
					a.bounce_vy = -150.0  # small bounce up
					_spawn_miss_particles(a.x, a.y)
			else:
				a.bounce_vy += 400.0 * delta
				a.y += a.bounce_vy * delta
				if a.y >= GROUND_Y - 20:
					a.y = GROUND_Y - 20
					a.bounce_vy = 0
				# Walk off screen
				a.x += a.walk_dir * 55.0 * delta
				a.alpha -= delta * 1.2
				if a.alpha <= 0: to_remove.append(i)
			continue

		# Normal fall + wobble
		a.y += a.speed * delta
		a.x += sin(a.wobble) * 0.8

		# Catch check
		if (a.y + 22 >= basket_top and a.y - 22 <= basket_top + 35
				and abs(a.x - basket_x) < BASKET_WIDTH / 2 + 14):
			a.caught = true
			a.catch_anim = 1.0
			score += 10 if a.type == "unicorn" else 1
			combo += 1
			basket_squish = 1.0
			_spawn_catch_particles(a.x, basket_top)
			_show_combo()
			update_ui()

		elif a.y > GROUND_Y + 10:
			a.missed = true
			a.walk_dir = 1.0 if a.x < 200 else -1.0
			a.bounce_vy = 0.0
			combo = 0
			lives -= 1
			screen_flash = 1.0
			update_ui()
			if lives <= 0:
				call_deferred("game_over")

	for i in range(to_remove.size() - 1, -1, -1):
		animals.remove_at(to_remove[i])

func _update_particles(delta):
	var to_remove = []
	for i in range(particles.size()):
		var p = particles[i]
		p.x   += p.vx * delta * 60
		p.y   += p.vy * delta * 60
		p.vy  += p.get("gravity", 0.12)
		p.life -= delta * p.get("decay", 2.0)
		if p.life <= 0: to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		particles.remove_at(to_remove[i])

func _spawn_catch_particles(x: float, y: float):
	for i in range(12):
		var angle = (TAU / 12.0) * i
		particles.append({
			"x": x, "y": y,
			"vx": cos(angle) * (1.2 + randf() * 2.5),
			"vy": sin(angle) * (1.2 + randf() * 2.5) - 1.5,
			"life": 1.0, "decay": 1.8, "gravity": 0.1,
			"color": Color(1.0, 0.95, 0.3), "size": 5.0,
		})

func _spawn_miss_particles(x: float, y: float):
	for i in range(8):
		var angle = randf() * TAU
		particles.append({
			"x": x, "y": y,
			"vx": cos(angle) * randf() * 1.5,
			"vy": -randf() * 2.0,
			"life": 1.0, "decay": 2.5, "gravity": 0.2,
			"color": Color(1.0, 0.3, 0.2), "size": 4.0,
		})

func _draw():
	# Background
	for row in range(0, 600, 4):
		var t = float(row) / 600.0
		draw_rect(Rect2(0, row, 400, 4), BG_TOP.lerp(BG_BOT, t))

	# Rain
	for i in range(45):
		var rx = fmod(i * 167.0 + frame_count * 1.4, 400.0)
		var ry = fmod(i * 89.0  + frame_count * 2.2, 600.0)
		draw_line(Vector2(rx, ry), Vector2(rx - 3, ry + 11), Color(0.4, 0.7, 1.0, 0.22), 1.0)

	# Animals + shadows
	for a in animals:
		if a.caught and a.catch_anim <= 0: continue
		var alpha = a.alpha if a.missed else 1.0
		# Drop shadow
		if not a.missed:
			var ground_dist = clamp((GROUND_Y - a.y) / GROUND_Y, 0.0, 1.0)
			var shadow_r = 10.0 + (1.0 - ground_dist) * 8.0
			draw_circle(Vector2(a.x, GROUND_Y - 5), shadow_r,
				Color(0.0, 0.0, 0.0, 0.18 * ground_dist))
		var col = _get_color(a.type)
		col.a = alpha
		_draw_animal(a.x, a.y, a.type, col, a.scale)

	# Particles
	for p in particles:
		var c = p.color
		c.a = p.life
		draw_circle(Vector2(p.x, p.y), p.get("size", 4.0) * p.life, c)

	# Basket
	_draw_basket(basket_x, GROUND_Y - 35)

	# Hearts (drawn on canvas, top-right)
	_draw_hearts()

	# Miss flash overlay
	if screen_flash > 0:
		draw_rect(Rect2(0, 0, 400, 600), Color(1.0, 0.1, 0.1, screen_flash * 0.25))

func _get_color(type: String) -> Color:
	match type:
		"dog":         return DOG_COLOR
		"special_cat": return SCAT_COLOR
		"special_dog": return SDOG_COLOR
		"unicorn":     return UNICORN_COLOR
		_:             return CAT_COLOR

func _draw_animal(x: float, y: float, type: String, color: Color, sc: float = 1.0):
	var s = 14.0 * sc
	match type:
		"cat", "special_cat":
			# CATS: sleek oval body + pointed ears + long tail
			# Elongated body (taller than wide = elegant)
			draw_circle(Vector2(x, y), s, color)
			draw_circle(Vector2(x, y - s * 0.3), s * 0.75, color)  # head bump
			# Pointed ears (triangular — use lines)
			var ear = color.darkened(0.25)
			draw_circle(Vector2(x - s * 0.6, y - s * 1.1), s * 0.28, ear)
			draw_circle(Vector2(x + s * 0.6, y - s * 1.1), s * 0.28, ear)
			# Narrow pointed tips
			draw_circle(Vector2(x - s * 0.6, y - s * 1.35), s * 0.15, ear)
			draw_circle(Vector2(x + s * 0.6, y - s * 1.35), s * 0.15, ear)
			# Narrow eyes (squinting = aloof cat energy)
			draw_line(Vector2(x - s*0.5, y - s*0.15), Vector2(x - s*0.18, y - s*0.15), Color(0.05,0.05,0.05), 3.0)
			draw_line(Vector2(x + s*0.18, y - s*0.15), Vector2(x + s*0.5, y - s*0.15), Color(0.05,0.05,0.05), 3.0)
			# Nose + whiskers
			draw_circle(Vector2(x, y + s * 0.15), s * 0.1, Color(1.0, 0.45, 0.55))
			draw_line(Vector2(x - s*0.85, y + s*0.1), Vector2(x - s*0.12, y + s*0.18), Color(1,1,1,0.55), 1)
			draw_line(Vector2(x + s*0.12, y + s*0.18), Vector2(x + s*0.85, y + s*0.1), Color(1,1,1,0.55), 1)
			draw_line(Vector2(x - s*0.8, y + s*0.25), Vector2(x - s*0.12, y + s*0.2), Color(1,1,1,0.35), 1)
			draw_line(Vector2(x + s*0.12, y + s*0.2), Vector2(x + s*0.8, y + s*0.25), Color(1,1,1,0.35), 1)
			# Long curvy tail
			draw_arc(Vector2(x + s*1.3, y + s*0.2), s * 0.9, -PI*0.6, PI*0.1, 14, color, 3.0)
			draw_arc(Vector2(x + s*1.3, y - s*0.5), s * 0.4, PI*0.1, PI*0.8, 8, color, 3.0)

		"dog", "special_dog":
			# DOGS: wide round body + BIG floppy ears hanging DOWN + happy open mouth
			var body_s = s * 1.12
			draw_circle(Vector2(x, y), body_s, color)
			# Big floppy ears that hang DOWN below head level
			var ear_col = color.darkened(0.3)
			draw_circle(Vector2(x - s * 1.1, y + s * 0.5), s * 0.72, ear_col)
			draw_circle(Vector2(x + s * 1.1, y + s * 0.5), s * 0.72, ear_col)
			# Round happy eyes
			draw_circle(Vector2(x - s*0.38, y - s*0.2), s * 0.26, Color(0.08,0.05,0.02))
			draw_circle(Vector2(x + s*0.38, y - s*0.2), s * 0.26, Color(0.08,0.05,0.02))
			draw_circle(Vector2(x - s*0.29, y - s*0.28), s * 0.09, Color(1,1,1,0.85))
			draw_circle(Vector2(x + s*0.47, y - s*0.28), s * 0.09, Color(1,1,1,0.85))
			# Big wet nose
			draw_circle(Vector2(x, y + s*0.18), s * 0.28, Color(0.2, 0.1, 0.07))
			draw_circle(Vector2(x - s*0.1, y + s*0.12), s * 0.07, Color(0.55,0.35,0.3,0.5))
			# Happy open mouth + tongue
			draw_arc(Vector2(x, y + s*0.35), s * 0.3, 0.0, PI, 8, Color(0.15,0.05,0.02), 2.0)
			draw_circle(Vector2(x, y + s * 0.65), s * 0.25, Color(1.0, 0.35, 0.45))
			# Short stubby tail (wag)
			var wag = sin(frame_count * 0.2) * 0.3
			draw_arc(Vector2(x + s*1.4, y - s*0.2), s * 0.5, -PI*0.4 + wag, PI*0.3 + wag, 8, color, 3.5)

		"unicorn":
			draw_circle(Vector2(x, y), s, UNICORN_COLOR)
			# Glowing horn
			draw_line(Vector2(x, y - s*0.85), Vector2(x, y - s*2.0), Color(1,0.5,0.85), 5)
			draw_line(Vector2(x, y - s*0.85), Vector2(x, y - s*2.0), Color(1,0.95,1,0.6), 2)
			# Rainbow mane
			draw_arc(Vector2(x - s*0.55, y - s*0.2), s * 0.55, 0.1, PI - 0.1, 12, Color(1.0,0.3,0.5), 3)
			draw_arc(Vector2(x - s*0.55, y - s*0.1), s * 0.40, 0.2, PI - 0.2, 10, Color(0.4,0.6,1.0), 2)
			# Sparkle eyes
			draw_circle(Vector2(x - s*0.35, y - s*0.15), s*0.2, Color(0.45, 0.1, 0.75))
			draw_circle(Vector2(x + s*0.35, y - s*0.15), s*0.2, Color(0.45, 0.1, 0.75))
			draw_circle(Vector2(x - s*0.27, y - s*0.23), s*0.07, Color(1,1,1,0.9))
			draw_circle(Vector2(x + s*0.43, y - s*0.23), s*0.07, Color(1,1,1,0.9))

func _draw_basket(x: float, y: float):
	var bw = BASKET_WIDTH
	var bh = 30.0
	var squish_x = 1.0 + basket_squish * 0.2
	var squish_y = 1.0 - basket_squish * 0.15
	var w = bw * squish_x
	var h = bh * squish_y

	# Glow
	draw_rect(Rect2(x - w/2 - 5, y - 5, w + 10, h + 10), Color(0.0, 0.94, 1.0, 0.08 + basket_squish * 0.15))
	# Body
	draw_rect(Rect2(x - w/2, y, w, h), BASKET_COLOR)
	# Weave
	for i in range(1, 4):
		var fy = y + (h / 4.0) * i
		draw_line(Vector2(x - w/2 + 3, fy), Vector2(x + w/2 - 3, fy), Color(1,1,1,0.12), 1)
	for i in range(1, 5):
		var fx = x - w/2 + (w / 5.0) * i
		draw_line(Vector2(fx, y + 2), Vector2(fx, y + h - 2), Color(1,1,1,0.08), 1)
	# Rim
	draw_line(Vector2(x - w/2 - 2, y + 3), Vector2(x + w/2 + 2, y + 3), BASKET_RIM, 4.0)

func _draw_hearts():
	# Draw 3 heart slots top-right
	var start_x = 340.0
	var y = 16.0
	for i in range(3):
		var hx = start_x - i * 28.0
		var filled = i < lives
		_draw_heart(hx, y, 9.0, HEART_COLOR if filled else HEART_EMPTY)

func _draw_heart(cx: float, cy: float, r: float, color: Color):
	# Heart = two circles + a V shape at bottom
	draw_circle(Vector2(cx - r * 0.5, cy - r * 0.2), r * 0.6, color)
	draw_circle(Vector2(cx + r * 0.5, cy - r * 0.2), r * 0.6, color)
	# Bottom point (triangle-ish with circles)
	draw_circle(Vector2(cx, cy + r * 0.5), r * 0.5, color)
	draw_circle(Vector2(cx - r * 0.3, cy + r * 0.1), r * 0.5, color)
	draw_circle(Vector2(cx + r * 0.3, cy + r * 0.1), r * 0.5, color)

func _show_combo():
	if combo < 3:
		combo_label.visible = false
		return
	combo_label.visible = true
	if combo >= 10:    combo_label.text = "G O D L I K E  x" + str(combo)
	elif combo >= 8:   combo_label.text = "UNSTOPPABLE  x" + str(combo)
	elif combo >= 5:   combo_label.text = "ON FIRE  x" + str(combo)
	else:              combo_label.text = "COMBO  x" + str(combo)
	combo_timer.start()

func _on_combo_timer_timeout():
	combo_label.visible = false

func update_ui():
	score_label.text = "SCORE  " + str(score)

func game_over():
	running = false
	var msg = "The animals escaped!"
	if score >= 50:    msg = "ANIMAL HERO!"
	elif score >= 20:  msg = "Impressive!"
	elif score >= 5:   msg = "Not bad!"
	overlay.visible = true
	overlay_title.text = "GAME OVER\n" + str(score) + " pts"
	overlay_sub.text = msg
	play_button.text = "PLAY AGAIN"

func _on_play_button_pressed():
	animals.clear()
	particles.clear()
	score = 0; lives = 3; combo = 0; frame_count = 0
	animal_speed = 140.0; spawn_interval = 1.2; spawn_timer = 0.0
	basket_x = 200.0; target_x = 200.0
	screen_flash = 0.0; basket_squish = 0.0
	combo_label.visible = false
	overlay.visible = false
	running = true
	update_ui()
