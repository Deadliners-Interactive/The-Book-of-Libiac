extends CharacterBody3D

@export var move_speed: float
@export var jump_speed: float
var is_facing_right = true
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var animated_sprite = $Sprite3D

func _physics_process(delta):
	jump(delta)
	move()
	flip()
	move_and_slide()
	update_animations()

func update_animations():
	if not is_on_floor():
		if velocity.y<0:
			animated_sprite.play("jump")
		else: 
			animated_sprite.play("fall")
		return
	
	
	if velocity.x != 0 or velocity.z != 0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")
		
func jump(delta):
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_speed
		
	if not is_on_floor():
		velocity.y -= gravity * delta

func move():
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

func flip():
	if (is_facing_right and velocity.x < 0) or (not is_facing_right and velocity.x > 0):
		$Sprite3D.scale.x *= -1
		is_facing_right = not is_facing_right
	
