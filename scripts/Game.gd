extends Node2D

# ============================================================
#  IT'S RAINING CATS & DOGS  —  AAA Build
#  Clawdia 🦞 — v4
# ============================================================

const ANIMAL_TYPES   = ["cat","dog","cat","dog","cat","dog","cat","dog","unicorn"]
const ANIMAL_WEIGHTS = [22, 22, 22, 22, 16, 16, 12, 12, 1]

const W             = 400.0
const H             = 600.0
const GROUND_Y      = 575.0
const BASKET_W      = 96.0
const BASKET_H      = 28.0
const BASKET_SPEED  = 420.0

# Palette
const C_CAT         = Color(0.98, 0.52, 0.70)
const C_CAT_EAR     = Color(0.85, 0.35, 0.52)
const C_DOG         = Color(0.88, 0.66, 0.34)
const C_DOG_EAR     = Color(0.70, 0.48, 0.20)
const C_UNICORN     = Color(0.98, 0.88, 0.22)
const C_BASKET      = Color(0.20, 0.56, 0.50)
const C_BASKET_RIM  = Color(0.38, 0.78, 0.58)
const C_BASKET_GLOW = Color(0.10, 0.92, 1.00)
const C_BG_TOP      = Color(0.04, 0.08, 0.16)
const C_BG_BOT      = Color(0.07, 0.20, 0.15)
const C_RAIN        = Color(0.45, 0.72, 1.00, 0.18)
const C_HEART_ON    = Color(0.95, 0.22, 0.32)
const C_HEART_OFF   = Color(0.22, 0.22, 0.28)
const C_SHADOW      = Color(0.00, 0.00, 0.00, 0.20)
const C_SCORE       = Color(0.10, 0.92, 1.00)
const C_COMBO       = Color(1.00, 0.82, 0.10)
const C_FLOATER     = Color(1.00, 1.00, 0.50)

var score        : int   = 0
var lives        : int   = 3
var combo        : int   = 0
var running      : bool  = false
var basket_x     : float = W / 2
var target_x     : float = W / 2
var spawn_timer  : float = 0.0
var spawn_ivl    : float = 1.15
var spd_base     : float = 138.0
var frame_n      : int   = 0

# Screen effects
var shake_t      : float = 0.0
var flash_t      : float = 0.0
var squish_t     : float = 0.0

var animals   : Array = []
var particles : Array = []
var floaters  : Array = []   # score pop-ups

@onready var overlay    = $Overlay
@onready var ov_title   = $Overlay/Title
@onready var ov_sub     = $Overlay/Sub
@onready var ov_btn     = $Overlay/PlayButton
@onready var lbl_score  = $UI/ScoreLabel
@onready var lbl_lives  = $UI/LivesLabel
@onready var lbl_combo  = $UI/ComboLabel
@onready var combo_tmr  = $ComboTimer

# ── Init ────────────────────────────────────────────────────
func _ready():
	lbl_lives.visible = false
	_show_start()

func _show_start():
	running = false
	overlay.visible = true
	ov_title.text = "It's Raining\nCats & Dogs!"
	ov_sub.text   = "Catch every animal!\n3 misses = Game Over"
	ov_btn.text   = "PLAY!"

# ── Main loop ───────────────────────────────────────────────
func _process(delta):
	if running:
		frame_n += 1
		_input_basket(delta)
		_tick_spawn(delta)
		_tick_animals(delta)
		_tick_particles(delta)
		_tick_floaters(delta)
		shake_t  = max(0.0, shake_t  - delta * 5.0)
		flash_t  = max(0.0, flash_t  - delta * 4.5)
		squish_t = max(0.0, squish_t - delta * 6.0)
		if frame_n % (60 * 12) == 0:
			spd_base  = min(spd_base  + 10.0, 290.0)
			spawn_ivl = max(spawn_ivl - 0.07, 0.44)
	queue_redraw()

func _input_basket(delta):
	if Input.is_action_pressed("ui_left"):
		target_x -= BASKET_SPEED * delta
	if Input.is_action_pressed("ui_right"):
		target_x += BASKET_SPEED * delta
	target_x = clamp(target_x, BASKET_W / 2.0, W - BASKET_W / 2.0)
	basket_x = lerp(basket_x, target_x, delta * 14.0)

func _input(event):
	if not running: return
	var vp  = get_viewport().get_visible_rect().size
	var scx = W / vp.x
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		target_x = clamp(event.position.x * scx, BASKET_W/2, W - BASKET_W/2)
	if event is InputEventScreenTouch and event.pressed:
		target_x = clamp(event.position.x * scx, BASKET_W/2, W - BASKET_W/2)

# ── Spawning ────────────────────────────────────────────────
func _tick_spawn(delta):
	spawn_timer += delta
	if spawn_timer >= spawn_ivl:
		spawn_timer = 0.0
		_spawn_animal()

func _spawn_animal():
	var idx = _wchoice(ANIMAL_WEIGHTS)
	animals.append({
		"type"      : ANIMAL_TYPES[idx],
		"x"         : randf_range(38.0, W - 38.0),
		"y"         : -38.0,
		"spd"       : spd_base + randf() * 38.0,
		"wobble"    : randf() * TAU,
		"alpha"     : 1.0,
		"sc"        : 1.0,
		"state"     : "fall",   # fall | catch_pop | miss_bounce | miss_walk
		"catch_t"   : 0.0,
		"miss_vy"   : 0.0,
		"walk_dir"  : 0.0,
		"floor_y"   : GROUND_Y - 22.0,
		"bounces"   : 0,
	})

func _wchoice(w: Array) -> int:
	var tot = 0
	for v in w: tot += v
	var r = randi() % tot
	var c = 0
	for i in range(w.size()):
		c += w[i]
		if r < c: return i
	return 0

# ── Animal logic ────────────────────────────────────────────
func _tick_animals(delta):
	var by   = GROUND_Y - BASKET_H - 8.0
	var rem  = []

	for i in range(animals.size()):
		var a = animals[i]
		a.wobble += delta * 2.8

		match a.state:
			"fall":
				a.y += a.spd * delta
				a.x += sin(a.wobble) * 0.7
				a.x = clamp(a.x, 20.0, W - 20.0)

				# Catch check
				if a.y + 24 >= by and a.y - 10 <= by + BASKET_H and abs(a.x - basket_x) < BASKET_W / 2.0 + 14:
					a.state   = "catch_pop"
					a.catch_t = 1.0
					score     += 10 if a.type == "unicorn" else 1
					combo     += 1
					squish_t  = 1.0
					_add_catch_fx(a.x, by)
					_add_floater(a.x, by - 20.0, "+1" if a.type != "unicorn" else "+10")
					_show_combo()
					update_ui()

				elif a.y > GROUND_Y + 10:
					a.state    = "miss_bounce"
					a.miss_vy  = -320.0
					a.floor_y  = GROUND_Y - 22.0
					a.walk_dir = 1.0 if a.x < W / 2.0 else -1.0
					a.bounces  = 0
					combo      = 0
					lives      -= 1
					shake_t    = 1.0
					flash_t    = 1.0
					update_ui()
					if lives <= 0:
						call_deferred("_game_over")

			"catch_pop":
				a.catch_t -= delta * 3.5
				a.sc       = 1.0 + sin(max(a.catch_t, 0.0) * PI) * 0.55
				if a.catch_t <= 0:
					rem.append(i)

			"miss_bounce":
				a.miss_vy  += 900.0 * delta
				a.y        += a.miss_vy * delta
				if a.y >= a.floor_y:
					a.y       = a.floor_y
					a.bounces += 1
					a.miss_vy = -220.0 / float(a.bounces + 1)
					_add_miss_fx(a.x, a.y)
					if a.bounces >= 2:
						a.state = "miss_walk"

			"miss_walk":
				a.x     += a.walk_dir * 68.0 * delta
				a.alpha -= delta * 1.4
				if a.alpha <= 0 or a.x < -40 or a.x > W + 40:
					rem.append(i)

	for i in range(rem.size() - 1, -1, -1):
		animals.remove_at(rem[i])

# ── Particles ───────────────────────────────────────────────
func _tick_particles(delta):
	var rem = []
	for i in range(particles.size()):
		var p = particles[i]
		p.x    += p.vx * delta * 60.0
		p.y    += p.vy * delta * 60.0
		p.vy   += p.get("grav", 0.10)
		p.life -= delta * p.get("decay", 1.8)
		if p.life <= 0: rem.append(i)
	for i in range(rem.size() - 1, -1, -1):
		particles.remove_at(rem[i])

func _add_catch_fx(x: float, y: float):
	for i in range(14):
		var ang = (TAU / 14.0) * i
		particles.append({
			"x": x, "y": y,
			"vx": cos(ang) * (1.0 + randf() * 2.5),
			"vy": sin(ang) * (1.0 + randf() * 2.5) - 1.8,
			"life": 1.0, "decay": 1.6, "grav": 0.08,
			"color": C_COMBO, "r": 5.5,
		})

func _add_miss_fx(x: float, y: float):
	for i in range(9):
		var ang = randf_range(-PI, 0.0)
		particles.append({
			"x": x, "y": y,
			"vx": cos(ang) * randf() * 1.8,
			"vy": sin(ang) * randf() * 1.8 - 0.5,
			"life": 1.0, "decay": 2.2, "grav": 0.15,
			"color": Color(0.95, 0.28, 0.18), "r": 4.0,
		})

# ── Floaters (score labels) ──────────────────────────────────
func _tick_floaters(delta):
	var rem = []
	for i in range(floaters.size()):
		var f = floaters[i]
		f.y    -= 38.0 * delta
		f.life -= delta * 1.4
		if f.life <= 0: rem.append(i)
	for i in range(rem.size() - 1, -1, -1):
		floaters.remove_at(rem[i])

func _add_floater(x: float, y: float, txt: String):
	floaters.append({"x": x, "y": y, "text": txt, "life": 1.0})

# ── Draw ────────────────────────────────────────────────────
func _draw():
	var ox = 0.0
	var oy = 0.0
	if shake_t > 0:
		ox = randf_range(-5.0, 5.0) * shake_t
		oy = randf_range(-4.0, 4.0) * shake_t
	draw_set_transform(Vector2(ox, oy))

	# Sky
	for row in range(0, int(H), 4):
		draw_rect(Rect2(0, row, W, 4), C_BG_TOP.lerp(C_BG_BOT, float(row)/H))

	# Rain
	for i in range(50):
		var rx = fmod(i * 163.0 + frame_n * 1.35, W)
		var ry = fmod(i * 83.0  + frame_n * 2.10, H)
		draw_line(Vector2(rx, ry), Vector2(rx - 2, ry + 12), C_RAIN, 1.0)

	# Ground line
	draw_line(Vector2(0, GROUND_Y), Vector2(W, GROUND_Y), Color(0.2, 0.5, 0.3, 0.4), 2.0)

	# Animals
	for a in animals:
		if a.state == "catch_pop" and a.catch_t <= 0: continue
		# Shadow
		if a.state == "fall":
			var d = clamp(1.0 - (GROUND_Y - a.y) / H, 0.0, 0.85)
			draw_circle(Vector2(a.x, GROUND_Y - 4.0), lerp(4.0, 16.0, d), Color(0,0,0, 0.22 * d))
		var col = _acolor(a.type)
		col.a = a.alpha
		_draw_animal(a.x, a.y, a.type, col, a.sc)

	# Particles
	for p in particles:
		var c = p.color; c.a = p.life
		draw_circle(Vector2(p.x, p.y), p.get("r", 4.5) * p.life, c)

	# Basket
	_draw_basket(basket_x, GROUND_Y - BASKET_H - 8.0)

	# Hearts
	_draw_hearts()

	# Floaters
	for f in floaters:
		var c = C_FLOATER; c.a = f.life
		# Draw as bright dot cluster (no font needed)
		draw_circle(Vector2(f.x, f.y), 6.0 * f.life, c)

	# Miss flash
	if flash_t > 0:
		draw_rect(Rect2(-10, -10, W+20, H+20), Color(1.0, 0.08, 0.08, flash_t * 0.28))

	draw_set_transform(Vector2.ZERO)

func _acolor(type: String) -> Color:
	match type:
		"dog":     return C_DOG
		"unicorn": return C_UNICORN
		_:         return C_CAT

func _draw_animal(x:float, y:float, type:String, color:Color, sc:float=1.0):
	var s = 15.0 * sc
	match type:
		"cat":
			# Sleek oval body
			draw_circle(Vector2(x, y + s*0.1), s, color)
			draw_circle(Vector2(x, y - s*0.35), s * 0.72, color)
			# Pointed ears — tall and sharp
			draw_circle(Vector2(x - s*0.58, y - s*1.05), s*0.30, C_CAT_EAR)
			draw_circle(Vector2(x + s*0.58, y - s*1.05), s*0.30, C_CAT_EAR)
			draw_circle(Vector2(x - s*0.58, y - s*1.35), s*0.15, C_CAT_EAR)
			draw_circle(Vector2(x + s*0.58, y - s*1.35), s*0.15, C_CAT_EAR)
			# Aloof narrow eyes
			draw_line(Vector2(x-s*0.52,y-s*0.22), Vector2(x-s*0.20,y-s*0.22), Color(0.06,0.04,0.06), 2.8)
			draw_line(Vector2(x+s*0.20,y-s*0.22), Vector2(x+s*0.52,y-s*0.22), Color(0.06,0.04,0.06), 2.8)
			# Tiny nose
			draw_circle(Vector2(x, y+s*0.10), s*0.10, Color(1.0,0.42,0.55))
			# Whiskers (3 per side)
			for k in range(3):
				var wy = y + s*(0.05 + k*0.09)
				draw_line(Vector2(x-s*0.9, wy), Vector2(x-s*0.15, wy+s*0.04), Color(1,1,1,0.45), 1)
				draw_line(Vector2(x+s*0.15, wy+s*0.04), Vector2(x+s*0.9, wy), Color(1,1,1,0.45), 1)
			# Long elegant tail
			draw_arc(Vector2(x+s*1.35, y+s*0.3), s*0.85, -PI*0.55, PI*0.05, 14, color, 3.2)
			draw_arc(Vector2(x+s*1.35, y-s*0.55), s*0.38, PI*0.05, PI*0.75, 9, color, 3.2)

		"dog":
			# Chunky round body — clearly wider/rounder than cat
			draw_circle(Vector2(x, y), s * 1.15, color)
			# BIG floppy ears drooping DOWN past chin
			draw_circle(Vector2(x-s*1.08, y+s*0.55), s*0.78, C_DOG_EAR)
			draw_circle(Vector2(x+s*1.08, y+s*0.55), s*0.78, C_DOG_EAR)
			draw_circle(Vector2(x-s*1.08, y+s*0.90), s*0.55, C_DOG_EAR)
			draw_circle(Vector2(x+s*1.08, y+s*0.90), s*0.55, C_DOG_EAR)
			# Big round happy eyes with shine
			draw_circle(Vector2(x-s*0.40, y-s*0.22), s*0.28, Color(0.07,0.04,0.02))
			draw_circle(Vector2(x+s*0.40, y-s*0.22), s*0.28, Color(0.07,0.04,0.02))
			draw_circle(Vector2(x-s*0.30, y-s*0.30), s*0.10, Color(1,1,1,0.90))
			draw_circle(Vector2(x+s*0.50, y-s*0.30), s*0.10, Color(1,1,1,0.90))
			# Big dark snout area
			draw_circle(Vector2(x, y+s*0.22), s*0.42, color.darkened(0.12))
			# Wet nose
			draw_circle(Vector2(x, y+s*0.12), s*0.30, Color(0.18,0.09,0.05))
			draw_circle(Vector2(x-s*0.1, y+s*0.06), s*0.07, Color(0.55,0.35,0.30,0.5))
			# Happy open mouth
			draw_arc(Vector2(x, y+s*0.42), s*0.28, 0.0, PI, 8, Color(0.12,0.04,0.02), 2.0)
			# Tongue lolling out
			draw_circle(Vector2(x, y+s*0.72), s*0.28, Color(0.98,0.32,0.42))
			draw_circle(Vector2(x, y+s*0.60), s*0.20, Color(0.98,0.32,0.42))
			# Wagging stubby tail
			var wag = sin(frame_n * 0.22) * 0.35
			draw_arc(Vector2(x+s*1.45, y-s*0.25), s*0.48, -PI*0.38+wag, PI*0.28+wag, 9, color, 4.0)

		"unicorn":
			draw_circle(Vector2(x, y), s, C_UNICORN)
			draw_circle(Vector2(x, y-s*0.3), s*0.72, C_UNICORN)
			# Glowing spiral horn
			draw_line(Vector2(x-s*0.08, y-s*0.9), Vector2(x, y-s*2.1), Color(1,0.45,0.82), 6)
			draw_line(Vector2(x+s*0.08, y-s*0.9), Vector2(x, y-s*2.1), Color(1,0.95,1.0,0.7), 2)
			# Glow tip
			draw_circle(Vector2(x, y-s*2.1), s*0.18, Color(1,0.8,1,0.6))
			# Rainbow mane
			var mc = [Color(1,.2,.4), Color(1,.6,.1), Color(.2,.8,.2), Color(.2,.5,1), Color(.8,.2,1)]
			for mi in range(mc.size()):
				draw_arc(Vector2(x-s*0.55, y-s*(0.15+mi*0.08)),
					s*(0.58-mi*0.05), 0.15, PI-0.15, 10+mi, mc[mi], 2.0-mi*0.25)
			# Sparkly eyes
			draw_circle(Vector2(x-s*0.36,y-s*0.18), s*0.20, Color(.42,.08,.75))
			draw_circle(Vector2(x+s*0.36,y-s*0.18), s*0.20, Color(.42,.08,.75))
			draw_circle(Vector2(x-s*0.27,y-s*0.26), s*0.08, Color(1,1,1,.92))
			draw_circle(Vector2(x+s*0.45,y-s*0.26), s*0.08, Color(1,1,1,.92))
			# Extra sparkles around unicorn
			if frame_n % 8 < 4:
				draw_circle(Vector2(x+s*1.5, y-s*1.2), s*0.12, Color(1,1,0.5,0.7))
				draw_circle(Vector2(x-s*1.3, y-s*0.8), s*0.10, Color(0.5,0.8,1,0.6))

func _draw_basket(x:float, y:float):
	var bw = BASKET_W
	var bh = BASKET_H
	var sx = 1.0 + squish_t * 0.18
	var sy = 1.0 - squish_t * 0.12
	var w  = bw * sx
	var h  = bh * sy
	# Glow halo
	draw_rect(Rect2(x-w/2-6, y-5, w+12, h+10), Color(C_BASKET_GLOW.r, C_BASKET_GLOW.g, C_BASKET_GLOW.b, 0.07 + squish_t*0.14))
	# Body
	draw_rect(Rect2(x-w/2, y, w, h), C_BASKET)
	# Weave horizontal
	for i in range(1, 4):
		var fy = y + h/4.0 * i
		draw_line(Vector2(x-w/2+2, fy), Vector2(x+w/2-2, fy), Color(1,1,1,0.10), 1)
	# Weave vertical
	for i in range(1, 7):
		var fx = x - w/2 + w/7.0 * i
		draw_line(Vector2(fx, y+2), Vector2(fx, y+h-2), Color(1,1,1,0.07), 1)
	# Rim
	draw_line(Vector2(x-w/2-2, y+3), Vector2(x+w/2+2, y+3), C_BASKET_RIM, 4.5)
	# Rim glow on squish
	if squish_t > 0.1:
		draw_line(Vector2(x-w/2-2, y+3), Vector2(x+w/2+2, y+3),
			Color(C_BASKET_GLOW.r, C_BASKET_GLOW.g, C_BASKET_GLOW.b, squish_t*0.7), 2.0)

func _draw_hearts():
	for i in range(3):
		var hx = W - 18.0 - i * 30.0
		var hy = 16.0
		_draw_heart(hx, hy, 10.0, C_HEART_ON if i < lives else C_HEART_OFF)

func _draw_heart(cx:float, cy:float, r:float, col:Color):
	draw_circle(Vector2(cx-r*0.48, cy-r*0.15), r*0.58, col)
	draw_circle(Vector2(cx+r*0.48, cy-r*0.15), r*0.58, col)
	draw_circle(Vector2(cx,        cy+r*0.48), r*0.52, col)
	draw_circle(Vector2(cx-r*0.28, cy+r*0.10), r*0.52, col)
	draw_circle(Vector2(cx+r*0.28, cy+r*0.10), r*0.52, col)

# ── UI ──────────────────────────────────────────────────────
func _show_combo():
	if combo < 3:
		lbl_combo.visible = false
		return
	lbl_combo.visible = true
	if combo >= 12:   lbl_combo.text = "G O D L I K E   x" + str(combo)
	elif combo >= 8:  lbl_combo.text = "UNSTOPPABLE   x" + str(combo)
	elif combo >= 5:  lbl_combo.text = "ON FIRE   x" + str(combo)
	else:             lbl_combo.text = "COMBO   x" + str(combo)
	combo_tmr.start()

func _on_combo_timer_timeout():
	lbl_combo.visible = false

func update_ui():
	lbl_score.text = "SCORE   " + str(score)

func _game_over():
	running = false
	var msg = "Better luck next time..."
	if score >= 60:   msg = "LEGENDARY RESCUER!"
	elif score >= 30: msg = "Animal Hero!"
	elif score >= 10: msg = "Not bad at all!"
	overlay.visible = true
	ov_title.text   = "GAME OVER\n" + str(score) + " pts"
	ov_sub.text     = msg
	ov_btn.text     = "PLAY AGAIN"

func _on_play_button_pressed():
	animals.clear()
	particles.clear()
	floaters.clear()
	score=0; lives=3; combo=0; frame_n=0
	spd_base=138.0; spawn_ivl=1.15; spawn_timer=0.0
	basket_x=W/2; target_x=W/2
	shake_t=0.0; flash_t=0.0; squish_t=0.0
	lbl_combo.visible = false
	overlay.visible = false
	running = true
	update_ui()
