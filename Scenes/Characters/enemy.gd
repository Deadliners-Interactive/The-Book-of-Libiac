extends CharacterBody3D

@export var max_hp: int = 30
@export var defense: int = 0

var current_hp: int
var is_alive: bool = true
var is_taking_damage: bool = false

@onready var animated_sprite = $AnimatedSprite3D

func _ready():
	current_hp = max_hp
	print("=== ENEMIGO SPAWNEADO ===")
	print("HP Inicial: ", current_hp, "/", max_hp)
	print("========================")
	
	if animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")

func _physics_process(delta):
	if not is_alive:
		return
	
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	
	move_and_slide()

func take_damage(damage: int):
	if not is_alive or is_taking_damage:
		return
	
	var final_damage = max(damage - defense, 0)
	current_hp -= final_damage
	
	print("━━━━━━━━━━━━━━━━━━━━━━━")
	print("💥 ENEMIGO RECIBIÓ DAÑO")
	print("Daño recibido: ", final_damage)
	print("HP restante: ", current_hp, "/", max_hp)
	print("━━━━━━━━━━━━━━━━━━━━━━━")
	
	if current_hp <= 0:
		die()
	else:
		play_damage_animation()

func play_damage_animation():
	if is_taking_damage:
		return
	
	is_taking_damage = true
	
	if animated_sprite.sprite_frames.has_animation("damage"):
		animated_sprite.play("damage")
		get_tree().create_timer(0.3).timeout.connect(_on_damage_animation_finished)
	else:
		_flash_red()

func _flash_red():
	animated_sprite.modulate = Color(1, 0.3, 0.3)
	get_tree().create_timer(0.1).timeout.connect(func(): 
		animated_sprite.modulate = Color.WHITE
		_on_damage_animation_finished()
	)

func _on_damage_animation_finished():
	is_taking_damage = false
	if is_alive and animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")

func die():
	if not is_alive:
		return
	
	is_alive = false
	
	print("━━━━━━━━━━━━━━━━━━━━━━━")
	print("☠️  ENEMIGO ELIMINADO")
	print("━━━━━━━━━━━━━━━━━━━━━━━")
	
	if animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		get_tree().create_timer(0.5).timeout.connect(queue_free)
	else:
		var tween = create_tween()
		tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.5)
		tween.finished.connect(queue_free)
