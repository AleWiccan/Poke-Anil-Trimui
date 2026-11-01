# Pokémon Añil para Trimui Smart Pro

Port **no oficial** del fangame *Pokémon Añil* (RPG Maker XP + Pokémon Essentials) para la **Trimui Smart Pro**, usando el motor libre [mkxp-z](https://github.com/mkxp-z/mkxp-z) compilado para aarch64.

> **Este paquete NO incluye el juego.** Tienes que conseguir tu propia copia de *Pokémon Añil* desde la página de su autor y copiarla tú mismo (ver [Instalación](#instalación)).

## Estado

| | |
|---|---|
| Consola | Trimui Smart Pro (Allwinner A133, aarch64, 1 GB de RAM) |
| Firmware | JEB+ |

## Requisitos

- Trimui Smart Pro con el sistema Stock OS o un firmware derivado (probado en JEB+).
- PortMaster instalado (se usa su `gptokeyb` para convertir el mando en teclado; si no está, el juego arranca igualmente con el mando nativo).
- Los archivos de *Pokémon Añil* para Windows (carpeta con `Game.ini`, `Data/`, `Graphics/`, `Audio/`, `Fonts/`…).

## Instalación

1. Copia `PokemonAnil.sh` a:
   ```
   SDCARD/Roms/PORTS/
   ```
2. Copia la carpeta `pokemonanil/` a:
   ```
   SDCARD/Data/ports/
   ```
3. Copia los archivos del juego dentro de `pokemonanil/gamedata/` (debe existir `pokemonanil/gamedata/Game.ini`).
4. Reinicia el menú y lanza **Pokemon Anil** desde la lista de Ports.

Estructura final:

```
SDCARD/
├── Roms/PORTS/PokemonAnil.sh
└── Data/ports/pokemonanil/
    ├── mkxp-z                 ← motor (aarch64)
    ├── libs/                  ← librerías propias (libgcc_s, libstdc++)
    ├── mkxp.base.json         ← configuración del motor (editable)
    ├── mkxp.json              ← se genera solo en cada arranque
    ├── pokemonanil.gptk       ← mapeo mando → teclado
    ├── gamedata/              ← el juego (lo pones tú)
    ├── soundfont/             ← SoundFont MIDI (opcional)
    ├── licenses/
    └── log.txt                ← se crea al ejecutar
```

## Controles

Mapeo por defecto (editable en `pokemonanil.gptk`, no hace falta recompilar):

| Botón | Tecla | Acción en el juego |
|---|---|---|
| D-Pad / palanca izquierda | Flechas | Mover |
| A | Z | Aceptar / hablar |
| B | X | Cancelar / volver |
| X | A | Acción extra |
| Y | S | Acción extra |
| L1 / R1 | Q / W | Acciones extra |
| Select | Shift | Correr |
| Start | Enter | Menú / aceptar |
| Menú (central) | Esc | Menú |

## Configuración

- **`mkxp.base.json`**: pantalla completa con relación de aspecto fija, escalado sin suavizado, vsync, etc. Edita este archivo, no `mkxp.json`: el lanzador regenera `mkxp.json` en cada arranque añadiendo las rutas absolutas de `gamedata/` y del SoundFont.
- **Memoria**: el lanzador no crea swap por defecto. Si el juego se cierra con el código de salida 137 en `log.txt` (falta de memoria), crea un archivo vacío llamado `swap.on` dentro de `pokemonanil/`: la próxima vez se creará y activará un swapfile de 768 MB en la SD.

## Solución de problemas

Todo se registra en `pokemonanil/log.txt` (incluye el código de salida del motor).

| Síntoma | Posible causa |
|---|---|
| `Error creating window: kmsdrm not available` | mkxp-z fuerza `kmsdrm` si no se indica driver. El lanzador usa `mali`; si tu firmware usa otro nombre, ponlo en `pokemonanil/videodriver.txt` |
| Se cierra al empezar *Partida nueva* con `locale::facet::_S_create_c_locale name not valid` | La consola tiene un `LANG` que no existe; el lanzador fuerza `LC_ALL=C` |
| Se cierra al arrancar tras tocar el vsync en el menú de opciones | El menú reescribe `gamedata/mkxp.json`; el lanzador lo restaura desde `mkxp.json.orig` en cada arranque |
| No pasa de la pantalla de carga / no abre | Falta `mkxp-z` o `gamedata/Game.ini`; mira el log |
| Se cierra con código 137 | Falta de memoria: activa `swap.on` |
| No suena la música MIDI | Falta el SoundFont en `soundfont/` |
| Los botones salen intercambiados (A/B, X/Y) | mkxp-z lee el mando a la vez que `gptokeyb` y SDL nombra al revés los botones de esta consola. Ajusta `pokemonanil.gptk`; la opción experimental `ignore-pad.on` (ignorar el mando nativo) llegó a bloquear la consola en una prueba, úsala con cuidado |
| Quieres conservar cambios de las Opciones del juego (pantalla completa…) | Edita `gamedata/mkxp.json.orig`: el lanzador lo restaura sobre `mkxp.json` en cada arranque |
| El mando no responde como esperas | Ajusta `pokemonanil.gptk`; comprueba en el log que se encontró `gptokeyb` |
| `cannot load such file -- zlib` | Extensión de Ruby no incluida en esta compilación |
| Error de un script del juego | El juego usa algo de Windows (`Win32API`, DLL) que mkxp-z no cubre |

Si abres un *issue*, adjunta las últimas 30 líneas de `log.txt`.

## Compilar desde el código fuente

El binario `mkxp-z` se compila con Docker (Windows, Linux o macOS) mediante el kit incluido en este repositorio (`build/`):

- Base `debian:bullseye-slim` (glibc 2.31; la consola admite hasta 2.33).
- Cross-compilación a **aarch64** con meson, OpenGL ES y la **SDL2 de la consola** (se compila contra SDL 2.26.5 solo para enlazar; en ejecución se usa la de `/usr/trimui/lib`, con su driver de vídeo `mali`).
- Sin PulseAudio, JACK, PipeWire, OSS ni OpenSSL. Audio por ALSA.
- Commit de mkxp-z fijado en `build.sh`.

```powershell
cd build
.\build.ps1 image       # solo la primera vez
.\build.ps1 sdl
.\build.ps1 fetch
.\build.ps1 configure
.\build.ps1 compile
.\build.ps1 package     # deja out/pokemonanil/ (mkxp-z + libs + licencias)
```

## Licencias

- **mkxp-z** y este port: **GPL-2.0**. Se incluye la licencia en `licenses/`, el commit exacto de mkxp-z usado y los scripts para reproducir la compilación.
- **TimGM6mb.sf2** (si lo usas): GPL-2.
- **Pokémon Añil** pertenece a su autor y **no se distribuye aquí**.
- Proyecto de aficionados sin ánimo de lucro, sin relación con Nintendo, Game Freak ni Creatures Inc. *Pokémon* es marca registrada de sus respectivos propietarios.

## Créditos

- Autor de *Pokémon Añil*: Eric_Lostie.
- [mkxp-z](https://github.com/mkxp-z/mkxp-z) y [mkxp](https://github.com/Ancurio/mkxp): motor RGSS libre.
- [PortMaster](https://portmaster.games/): `gptokeyb` y la comunidad de ports.
- [Periko21/mkxp-z-r36s](https://github.com/Periko21/mkxp-z-r36s): referencia para adaptar mkxp-z a consolas portátiles.
