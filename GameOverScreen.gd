extends Control

# Ruta a la escena del primer nivel o el nivel al que deseas volver
const START_LEVEL_PATH = "res://Scenes/main.tscn"# ¡Asegúrate de que esta ruta sea correcta!

func _ready():
	# 1. Hacer el ratón visible
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# 2. Conectar la señal pressed usando la sintaxis de Nombre de Hijo Único (%)
	# Esto funciona porque PlayAgainButton está marcado con el icono % en el editor.
	if %PlayAgainButton:
		%PlayAgainButton.pressed.connect(_on_play_again_button_pressed)
	else:
		push_error("Error crítico: El nodo PlayAgainButton no se encontró usando el prefijo %.")


func _on_play_again_button_pressed():
	# Es crucial ocultar el cursor de nuevo si tu juego principal lo requiere
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Usar TransitionManager para cargar el nivel inicial/deseado.
	TransitionManager.transition_to_scene(START_LEVEL_PATH, "default")
