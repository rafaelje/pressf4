# PressF4

App nativa de macOS para capturar áreas de pantalla, mostrar miniaturas y anotarlas. Vive en la barra de menús, se invoca con **F4**.

- Lenguaje: **Swift 5.9 / SwiftUI / AppKit**
- Target: **macOS 14+** (Sonoma o superior)
- Captura: **ScreenCaptureKit** nativo
- Atajos globales: **Carbon HotKey API** (sin dependencias externas)
- Sandbox: **completo**, firmado ad-hoc para uso local

## Requisitos

- macOS 14.0 (Sonoma) o superior
- Xcode 15+ instalado (solo para `swiftc` / `codesign`; no se usa proyecto Xcode)

## Build

```bash
cd pressf4
make          # compila, ensambla .app, firma ad-hoc con entitlements
make test     # corre smoke tests (modelos + serialización)
make run      # build + abre la app
make install  # copia a /Applications
make clean
```

El binario queda en `build/pressf4.app`.

## Primer lanzamiento — permisos

1. Al primer intento de captura, macOS pedirá **permiso de Grabación de Pantalla**.
   - Acepta el prompt o entra a *Ajustes del Sistema → Privacidad y Seguridad → Grabación de Pantalla* y activa "PressF4".
   - Reabre la app después de conceder el permiso.
2. macOS también pedirá permiso de notificaciones (opcional, lo puedes denegar).

## Atajos por defecto

| Acción | Atajo |
|---|---|
| Capturar área | `F4` |
| Mostrar ventana principal | `⌃⌥⌘ H` |
| Abrir última captura en editor | `⌃⌥⌘ E` |

> ⚠️ **Sobre F4 en Mac**: por defecto macOS usa las F-keys para funciones de hardware. Activa *Ajustes del Sistema → Teclado → "Usar las teclas F1, F2, etc. como teclas de función estándar"* para que F4 dispare la captura directamente; si lo dejas desactivado tendrás que presionar `Fn+F4`.

## Cómo usar

1. Presiona `F4`. La pantalla se oscurece y aparece la mira.
2. Arrastra para seleccionar el área. Suelta para capturar. `Esc` cancela.
3. Aparece una miniatura flotante abajo a la derecha durante 4 s.
   - Click en la miniatura → abre el editor.
   - Botón ✎ → editor. Botón ⧉ → copiar al portapapeles.
4. La captura ya está copiada al portapapeles automáticamente.
5. En el editor: elige herramienta (recuadro, círculo, flecha, texto, resaltar), color, grosor; arrastra para crear; `Delete` borra la seleccionada; `⌘Z` deshace.
6. `⌘C` copia con las anotaciones aplicadas; `⌘S` guarda como archivo.

## Dónde se guardan las capturas

`~/Library/Containers/com.rafaelje.pressf4/Data/Library/Application Support/PressF4/`

Dentro hay:
- `<uuid>.png` — la imagen original sin anotaciones
- `<uuid>.json` — las anotaciones como capa editable (se pueden modificar después)
- `index.json` — índice maestro

Las anotaciones son **objetos editables**, no píxeles aplastados sobre el PNG. Al guardar con `⌘S` o copiar con `⌘C`, se aplanan al render final.

## Arquitectura

```
Sources/
├── App.swift                       # @main + AppDelegate + AppController
├── Models/
│   ├── Capture.swift               # Captura individual
│   └── Annotation.swift            # Tipos, colores, capa
├── Services/
│   ├── CaptureService.swift        # ScreenCaptureKit wrapper
│   ├── LibraryStore.swift          # Persistencia local
│   └── ShortcutsManager.swift      # Carbon hotkeys globales
├── Views/
│   ├── SelectionOverlay.swift      # Overlay full-screen para seleccionar
│   ├── ThumbnailHUD.swift          # Miniatura flotante post-captura
│   ├── EditorView.swift            # Canvas + herramientas
│   └── MainWindow.swift            # NSSplitView con sidebar
└── Tests/
    └── SmokeTest.swift             # `make test`
```

## Notas técnicas

- **LSUIElement=true**: la app vive en la barra de menús; el dock icon aparece solo cuando la ventana principal está abierta.
- **Multi-monitor**: el `SelectionOverlay` se instala en cada `NSScreen` y la captura detecta automáticamente el display donde está el rectángulo.
- **Sandbox**: las capturas se guardan dentro del container del sandbox; "Guardar como…" usa `NSSavePanel` que concede acceso al destino elegido por el usuario.
- **Firma ad-hoc**: suficiente para uso local. Para distribuir requerirías Developer ID + notarización.

## Desinstalar

```bash
rm -rf /Applications/pressf4.app
rm -rf ~/Library/Containers/com.rafaelje.pressf4
```

(Y revoca el permiso de Grabación de Pantalla en Ajustes del Sistema.)

## Reasignar atajos

Por simplicidad V1 los atajos están fijos en `Sources/Services/ShortcutsManager.swift`. Para cambiarlos, edita los `keyCode` y recompila. Una UI de Preferencias está pendiente para V2.
