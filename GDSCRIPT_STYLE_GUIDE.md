# GDScript Style Guide (Supay's Gates)

Guia de buenas practicas para mantener el codigo consistente, legible y facil de mantener en Godot 4.x.

## 1. Objetivo

- Mantener un estilo uniforme en todos los scripts.
- Reducir errores comunes de tipado y acceso a propiedades.
- Facilitar colaboracion y refactorizacion futura.

## 2. Principios base

- Prioriza legibilidad sobre "atajos".
- Usa tipado explicito siempre que sea posible.
- Encapsula estado interno (variables privadas con prefijo `_`).
- Evita acoplamiento entre nodos por acceso directo a internals.
- Organiza cada archivo por secciones estables.

## 3. Estructura recomendada por archivo

Orden sugerido:

1. Comentario de clase (`##`) describiendo responsabilidad.
2. `extends`.
3. `Signals`.
4. `Enums`.
5. `Constants`.
6. `@export_group` + `@export var`.
7. Variables miembro.
8. Variables `@onready`.
9. Metodos ciclo de vida (`_ready`, `_process`, `_physics_process`).
10. Metodos publicos.
11. Metodos privados (agrupados por funcionalidad).

## 4. Convenciones de nombres

- Variables/metodos: `snake_case`.
- Constantes: `CONSTANT_CASE`.
- Clases (`class_name`): `PascalCase`.
- Variables privadas: prefijo `_`.

Ejemplos:

```gdscript
const KB_MULTIPLIER: float = 5.0
var _player_ref: CharacterBody3D
func _trigger_level_change(player: Node) -> void:
```

## 5. Tipado y firmas

- Declara tipo en variables cuando aplique.
- Declara tipo de retorno en todos los metodos (`-> void`, `-> bool`, etc.).
- En colecciones, usa tipo parametrizado si es posible.

```gdscript
var _notification_queue: Array[String] = []
func use_key() -> bool:
```

## 6. Encapsulacion y acceso seguro

- No accedas propiedades privadas de otro script.
- Expone metodos publicos para operaciones necesarias.
- Antes de llamar metodos dinamicos, valida con `has_method()`.

```gdscript
if player.has_method("refresh_ui_state"):
	player.refresh_ui_state()
```

## 7. Señales y conectividad

- Conecta señales en `_ready()`.
- Evita duplicar conexiones (verifica `is_connected` cuando corresponda).
- Nombra handlers con prefijo `_on_...`.

## 8. Flujo y estados

- Usa `enum State` para FSM.
- Centraliza transiciones en un metodo (`set_state(...)`).
- Evita logica de estado duplicada en varios metodos.

## 9. Manejo de nulls y validez

- Verifica referencias antes de uso (`if ref:`).
- Para nodos dinamicos, usa `is_instance_valid(ref)` cuando aplique.
- Usa `get_node_or_null` en lugar de asumir que el nodo existe.

## 10. Comentarios y documentacion

- Usa comentarios para explicar el "por que", no el "que" obvio.
- Mantener comentarios cortos y actualizados.
- Documenta scripts con `##` al inicio.

## 11. Formato y limpieza

- Mantener separadores de seccion consistentes.
- Dejar dos lineas entre funciones top-level para legibilidad.
- Eliminar warnings de parametros/variables no usados.
- Si un parametro no se usa por diseno, prefijarlo con `_`.

## 12. Errores comunes a evitar

- Colisiones de nombre entre variable y funcion.
- Acceso a propiedades que no existen en el tipo base.
- Llamar metodos privados de otro objeto directamente.
- Mezclar responsabilidades UI/gameplay en una sola clase.

## 13. Checklist rapido antes de commit

- [ ] No hay errores en panel Problems.
- [ ] No hay warnings evitables en scripts editados.
- [ ] Metodos con retorno tipado.
- [ ] Variables privadas con `_`.
- [ ] Sin accesos directos a internals de otros nodos.
- [ ] Secciones del archivo en orden.

## 14. Nota del proyecto

Este repositorio sigue un estilo orientado a Godot 4.x con fuerte tipado, encapsulacion y estructura por secciones. Si agregas scripts nuevos, usa esta guia como plantilla para mantener coherencia.
