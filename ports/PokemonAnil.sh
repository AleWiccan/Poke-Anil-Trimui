#!/bin/sh
# Pokemon Anil - lanzador para Trimui Smart Pro (JEB+) - motor mkxp-z (RPG Maker XP)
# Va en SDCARD/Roms/PORTS/ ; los datos en SDCARD/Data/ports/pokemonanil/  (o junto a este .sh en ./pokemonanil)
HERE="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR=""
for d in "$HERE/../../Data/ports/pokemonanil" "$HERE/pokemonanil"; do
  if [ -d "$d" ]; then GAMEDIR="$(cd "$d" && pwd)"; break; fi
done
[ -n "$GAMEDIR" ] || exit 1
cd "$GAMEDIR" || exit 1

LOGF="$GAMEDIR/log.txt"
echo "[launcher] version 8 - $(date)" > "$LOGF"

# Libs propias primero, luego la SDL2 de la consola. SDL_VIDEODRIVER sin definir (driver mali).
export LD_LIBRARY_PATH="$GAMEDIR/libs:/usr/trimui/lib:$LD_LIBRARY_PATH"
# OJO: si SDL_VIDEODRIVER esta vacio, mkxp-z FUERZA "kmsdrm" (que la consola no tiene: "kmsdrm not available").
# Hay que nombrar el driver de la consola. Por defecto "mali"; se puede cambiar con un archivo videodriver.txt.
VD="mali"
[ -f "$GAMEDIR/videodriver.txt" ] && VD="$(head -n 1 "$GAMEDIR/videodriver.txt" | tr -d '\r\n ')"
export SDL_VIDEODRIVER="$VD"
# System.user_language (la llama Essentials al empezar Partida nueva) hace std::locale("") y ABORTA si LANG/LC_ALL
# apuntan a un locale que la consola no tiene ("locale::facet::_S_create_c_locale name not valid"). "C" siempre existe.
echo "[launcher] LANG=$LANG LC_ALL=$LC_ALL (se fuerzan a C)" >> "$LOGF"
export LC_ALL=C
export LANG=C
unset LANGUAGE
echo "[launcher] SDL_VIDEODRIVER=$SDL_VIDEODRIVER" >> "$LOGF"
export HOME="$GAMEDIR"
export XDG_DATA_HOME="$GAMEDIR/saves"
export XDG_CONFIG_HOME="$GAMEDIR/saves"
mkdir -p "$XDG_DATA_HOME"

[ -f "$GAMEDIR/gamedata/Game.ini" ] || { echo "No hay juego en $GAMEDIR/gamedata (falta Game.ini)" >> "$LOGF"; exit 1; }
[ -f "$GAMEDIR/mkxp-z" ] || { echo "Falta el binario aarch64 mkxp-z en $GAMEDIR" >> "$LOGF"; exit 1; }
chmod +x "$GAMEDIR/mkxp-z"

# Si el menu de opciones del juego deja la configuracion en mal estado: crea un archivo reset-config.on
# y se borra el mkxp.json de usuario (NO las partidas guardadas).
if [ -f "$GAMEDIR/reset-config.on" ]; then
  find "$GAMEDIR/saves" -name mkxp.json -exec rm -f {} \; 2>/dev/null
  rm -f "$GAMEDIR/reset-config.on"
  echo "[launcher] configuracion de usuario (mkxp.json en saves) borrada" >> "$LOGF"
fi

# mkxp-z falla con un gameFolder RELATIVO ("Failed to check current path"): se genera mkxp.json con rutas absolutas
# a partir de mkxp.base.json (que es el que se edita).
SFPATH=""
for c in "$GAMEDIR/gamedata/soundfont.sf2" "$GAMEDIR/soundfont/TimGM6mb.sf2"; do
  if [ -f "$c" ]; then SFPATH="$c"; break; fi
done
{
  printf '{\n  "gameFolder": "%s/gamedata",\n' "$GAMEDIR"
  [ -n "$SFPATH" ] && printf '  "midiSoundFont": "%s",\n' "$SFPATH"
  tail -n +2 "$GAMEDIR/mkxp.base.json"
} > "$GAMEDIR/mkxp.json"
echo "[launcher] mkxp.json generado (gameFolder=$GAMEDIR/gamedata, soundfont=${SFPATH:-ninguno})" >> "$LOGF"

# El motor NO lee gamedata/mkxp.json (usa el de esta carpeta), pero el menu de opciones del juego (vsync...) lo REESCRIBE,
# y si queda vacio o roto el juego se cierra al arrancar (NameError HTTPLite::JSON::ParserError).
# Se guarda una copia original la primera vez y se restaura en cada arranque.
GJ="$GAMEDIR/gamedata/mkxp.json"
if [ -f "$GJ" ]; then
  [ -f "$GJ.orig" ] || { [ -s "$GJ" ] && cp "$GJ" "$GJ.orig"; }
  [ -f "$GJ.orig" ] && cp "$GJ.orig" "$GJ" && echo "[launcher] gamedata/mkxp.json restaurado desde .orig ($(wc -c < "$GJ") bytes)" >> "$LOGF"
else
  echo "[launcher] AVISO: no existe gamedata/mkxp.json" >> "$LOGF"
fi

# --- Diagnostico: que ha guardado el juego/menu de opciones (aparece en log.txt) ---
{
  echo "[launcher] archivos en saves:"; find "$GAMEDIR/saves" -type f 2>/dev/null | head -n 20
  for f in $(find "$GAMEDIR/saves" -name mkxp.json 2>/dev/null); do echo "[launcher] contenido de $f:"; cat "$f"; echo; done
  echo "[launcher] archivos de gamedata modificados despues de Game.ini:"
  find "$GAMEDIR/gamedata" -type f -newer "$GAMEDIR/gamedata/Game.ini" 2>/dev/null | head -n 20
} >> "$LOGF"

# --- Swap opcional (1 GB de RAM). Crea un archivo swap.on para activarlo ---
if [ -f "$GAMEDIR/swap.on" ] && ! grep -q "$GAMEDIR/swapfile" /proc/swaps 2>/dev/null; then
  [ -f "$GAMEDIR/swapfile" ] || { dd if=/dev/zero of="$GAMEDIR/swapfile" bs=1M count=768 >/dev/null 2>&1
                                  chmod 600 "$GAMEDIR/swapfile"; mkswap "$GAMEDIR/swapfile" >/dev/null 2>&1; }
  swapon "$GAMEDIR/swapfile" >/dev/null 2>&1 || echo "[launcher] swapon FALLO" >> "$LOGF"
fi

# --- Controles: gptokeyb de PortMaster (mando -> teclado) ---
GPTK=""
# Para probar SOLO con el mando nativo de mkxp-z (sin gptokeyb), crea un archivo vacio gptokeyb.off
if [ -f "$GAMEDIR/gptokeyb.off" ]; then
  echo "[launcher] gptokeyb DESACTIVADO (gptokeyb.off): solo el mando nativo de mkxp-z" >> "$LOGF"
else
for c in /mnt/SDCARD/Data/ports/PortMaster /mnt/SDCARD/Apps/PortMaster/PortMaster /mnt/SDCARD/Roms/PORTS/PortMaster \
         /mnt/SDCARD/Apps/PortMaster /opt/system/Tools/PortMaster /roms/ports/PortMaster "$HERE/PortMaster"; do
  if [ -x "$c/gptokeyb" ]; then GPTK="$c/gptokeyb"; break; fi
done
fi
if [ -n "$GPTK" ]; then
  echo "[launcher] gptokeyb: $GPTK" >> "$LOGF"
  CTRLDIR="$(dirname "$GPTK")"
  # Base de mandos de PortMaster (la usa gptokeyb para saber que boton es cual)
  [ -f "$CTRLDIR/gamecontrollerdb.txt" ] && export SDL_GAMECONTROLLERCONFIG_FILE="$CTRLDIR/gamecontrollerdb.txt"
  [ -d "$CTRLDIR/libs" ] && export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CTRLDIR/libs"
  "$GPTK" "mkxp-z" -c "$GAMEDIR/pokemonanil.gptk" >> "$LOGF" 2>&1 &
  GPTK_PID=$!
else
  echo "[launcher] AVISO: no se encontro gptokeyb; sin mapeo a teclado" >> "$LOGF"
fi

# --- Mando nativo de mkxp-z: se IGNORA (solo para mkxp-z; gptokeyb lo sigue leyendo) ---
# mkxp-z abre el mando por SDL_GameController y SDL llama "A" al boton fisico B de esta consola (y viceversa).
# Si se dejan activos a la vez el mando nativo y gptokeyb, se pisan y el mapeo de pokemonanil.gptk "no cambia nada".
# EXPERIMENTAL y desactivado por defecto (en una prueba la consola se bloqueo entera con esto activo).
# Para probarlo, crea un archivo vacio ignore-pad.on en la carpeta del port.
if [ -f "$GAMEDIR/ignore-pad.on" ]; then
  PADID=""; LASTI=""
  while IFS= read -r line; do
    case "$line" in
      I:*) LASTI="$line" ;;
      N:*Xbox*360*) V="${LASTI#*Vendor=}"; V="${V%% *}"; P="${LASTI#*Product=}"; P="${P%% *}"; PADID="0x$V/0x$P"; break ;;
    esac
  done < /proc/bus/input/devices 2>/dev/null
  if [ -n "$PADID" ]; then
    export SDL_GAMECONTROLLER_IGNORE_DEVICES="$PADID"
    echo "[launcher] mando nativo de mkxp-z ignorado: $PADID (solo gptokeyb)" >> "$LOGF"
  else
    echo "[launcher] AVISO: no se encontro el mando en /proc/bus/input/devices; mkxp-z usara su mando nativo" >> "$LOGF"
  fi
fi

sync 2>/dev/null   # que el log llegue a la SD aunque la consola se cuelgue
"$GAMEDIR/mkxp-z" >> "$LOGF" 2>&1
CODE=$?
echo "[launcher] codigo de salida: $CODE  (137 = falta de memoria)" >> "$LOGF"
[ "$CODE" = "137" ] && dmesg 2>/dev/null | grep -i -E "killed process|out of memory|oom" | tail -5 >> "$LOGF"
[ -n "$GPTK_PID" ] && kill "$GPTK_PID" 2>/dev/null
exit 0
