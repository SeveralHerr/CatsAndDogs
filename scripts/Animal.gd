extends Node2D

var speed: float = 150.0
var caught: bool = false
var missed: bool = false
var walk_dir: float = 1.0
var wobble_time: float = 0.0
var emoji: String = "🐱"

signal animal_missed
signal animal_caught

func _ready():
	wobble_time = randf() * TAU

func _process(delta):
	wobble_time += delta * 3.0
	
	if caught:
		return
	
	if missed:
		# Walk off screen
		position.x += walk_dir * 60.0 * delta
		modulate.a -= delta * 1.5
		if modulate.a <= 0:
			queue_free()
		return
	
	# Fall with wobble
	position.y += speed * delta
	position.x += sin(wobble_time) * 0.8
	
	# Check if hit ground
	if position.y > 620:
		_on_missed()

func _on_missed():
	if missed or caught:
		return
	missed = true
	walk_dir = 1.0 if position.x < 200 else -1.0
	emit_signal("animal_missed")

func catch_animal():
	if missed or caught:
		return
	caught = true
	emit_signal("animal_caught")
	# Pop animation then free
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.1)
	tween.tween_property(self, "scale", Vector2(0, 0), 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.05)
	tween.tween_callback(queue_free)
