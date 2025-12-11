extends Label3D

# Nota: ¡Asegúrate de que este nodo Label3D tenga una fuente asignada en el Inspector!

@export var float_speed: Vector3 = Vector3(0, 1.5, 0) # Velocidad hacia arriba
@export var duration: float = 0.8

func _ready():
	# 🚨 REVISIÓN EN EL EDITOR:
	# 1. En la escena .tscn, selecciona el Label3D.
	# 2. Configura 'Text > Pixel Size' a 0.05 o 0.1 para que sea visible.
	# 3. Configura 'Geometry > Billboard' a Enabled para que mire a la cámara.
	
	# Animar la posición (subir)
	var tween = create_tween()
	tween.tween_property(self, "position", position + float_speed, duration)
	
	# Animar la opacidad (desvanecer) y el tamaño (pop)
	var tween_fade = create_tween()
	tween_fade.tween_property(self, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	
	# Efecto de escala inicial (Pop)
	scale = Vector3.ZERO
	var tween_scale = create_tween()
	tween_scale.tween_property(self, "scale", Vector3(1.5, 1.5, 1.5), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween_scale.tween_property(self, "scale", Vector3.ONE, 0.1)

	# Eliminar al terminar
	await get_tree().create_timer(duration).timeout
	queue_free()

func set_damage(amount: int):
	text = str(amount)
