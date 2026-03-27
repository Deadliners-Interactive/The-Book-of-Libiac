# Estructura del Proyecto

Este documento define la organizacion de carpetas y convenciones para mantener el proyecto limpio y escalable en Godot.

## Estructura actual recomendada

- `Scenes/`
  - `Scenes/Levels/` para niveles jugables (`main`, `level2`, `test`).
  - `Scenes/Characters/` para player, enemigos y proyectiles.
  - `Scenes/Gameplay/` para scripts de mecanicas de gameplay.
  - `Scenes/Gameplay/Behaviors/` para comportamientos reutilizables.
  - `Scenes/Gameplay/Triggers/` para zonas y triggers de nivel.
  - `Scenes/Props/` para props reutilizables.
  - `Scenes/Props/Pickups/` para pickups y loot instanciable.
  - `Scenes/Environment/` para escenas de entorno.
  - `Scenes/UI/` para escenas de interfaz (pantallas, menus, HUD).
- `Scripts/`
  - `Scripts/Autoload/` para singletons (autoloads).
  - `Scripts/Interactables/` para logica de objetos interactuables.
  - `Scripts/UI/` para scripts de interfaz.
- `assets/`
  - Recursos visuales y modelos.
  - `assets/Shaders/` para shaders.

## Convenciones de nombres

- Escenas y scripts nuevos: `snake_case`.
- Niveles: mantener nombres existentes (`main`, `level2`, `test`) para estabilidad de referencias.
- Evitar mezclar idiomas en nombres nuevos (elegir espanol o ingles por modulo).

## Reglas de mantenimiento

1. No dejar scripts o escenas nuevas en la raiz del repositorio.
2. Cada nuevo recurso debe ubicarse en una carpeta por dominio (`Levels`, `Characters`, `Gameplay`, `Props`, `UI`, etc).
3. Al mover archivos, actualizar referencias en:
   - Escenas `.tscn`
   - `project.godot` (autoloads)
   - Scripts con `preload()` o rutas hardcodeadas
4. Validar despues de mover:
   - Abrir la escena principal
   - Revisar errores de parseo
   - Hacer una corrida rapida del juego
5. Mantener [Scenes](Scenes) sin archivos `.tscn`, `.gd` o `.gd.uid` sueltos en la raiz.

## Checklist rapido para PRs

- [ ] No hay recursos sueltos en raiz
- [ ] Rutas `res://` actualizadas
- [ ] Sin errores en escenas clave (`main`, `level2`, `test`)
- [ ] Cambio documentado si se creo una nueva convencion
