#!/bin/bash
# Uso (dentro del contenedor): build.sh [fetch|sdl|configure|compile|package|wipe|all]
set -euo pipefail
PIN=37a04d14413454551a7b6aadbb4e93e67168accb      # commit de mkxp-z probado para este kit
SRC=/work/mkxp-z
BLD=/work/build
OUT=/out
KIT=/kit
STAGE="${1:-all}"
mkdir -p "$OUT"
log() { printf '\n==> %s\n' "$*"; }

fetch() {
  log "Descargando mkxp-z @ $PIN"
  if [ ! -d "$SRC/.git" ]; then git init -q "$SRC"; git -C "$SRC" remote add origin https://github.com/mkxp-z/mkxp-z; fi
  git -C "$SRC" fetch -q --depth 1 origin "$PIN"
  git -C "$SRC" reset -q --hard FETCH_HEAD
  git -C "$SRC" clean -qfd
  git -C "$SRC" submodule update --init --depth 1 2>/dev/null || true
}

sdl() {
  # Cabeceras y .so de enlace de SDL2 2.26.5 = la version exacta de la consola (libSDL2-2.0.so.0.2600.5).
  # Solo sirve para COMPILAR/ENLAZAR: en la consola se usa su propia libSDL2 (driver mali). Esta NO se empaqueta.
  # (Las cabeceras de Debian bullseye, 2.0.14, son demasiado viejas: faltan SDL_HINT_VIDEODRIVER, etc.)
  log "SDL2 2.26.5 (solo para enlazar)"
  if [ ! -f /work/sdl/lib/pkgconfig/sdl2.pc ]; then
    rm -rf /work/sdl-src /work/sdl-build
    # Descarga con reintentos (el git de bullseye falla a veces con "GnuTLS recv error -9")
    TAR=/work/SDL2-2.26.5.tar.gz; OK=0
    for i in 1 2 3 4 5; do
      curl -fsSL --retry 5 --retry-delay 3 -o "$TAR" \
        https://github.com/libsdl-org/SDL/releases/download/release-2.26.5/SDL2-2.26.5.tar.gz \
        && tar -tzf "$TAR" >/dev/null 2>&1 && { OK=1; break; }
      echo "reintento $i..."; rm -f "$TAR"; sleep 3
    done
    if [ "$OK" = 1 ]; then
      mkdir -p /work/sdl-src && tar -xzf "$TAR" -C /work/sdl-src --strip-components=1
    else
      echo "curl fallo; probando git con HTTP/1.1"
      git -c http.version=HTTP/1.1 clone -q --depth 1 --branch release-2.26.5 https://github.com/libsdl-org/SDL /work/sdl-src
    fi
    cat > /work/aarch64-toolchain.cmake <<'TC'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
TC
    cmake -S /work/sdl-src -B /work/sdl-build -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=/work/aarch64-toolchain.cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/work/sdl \
      -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF \
      -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_PULSEAUDIO=OFF -DSDL_JACK=OFF \
      -DSDL_PIPEWIRE=OFF -DSDL_ALSA=OFF -DSDL_OSS=OFF -DSDL_SNDIO=OFF -DSDL_ARTS=OFF -DSDL_ESD=OFF
    ninja -C /work/sdl-build install
  fi
  grep -q SDL_HINT_VIDEODRIVER /work/sdl/include/SDL2/SDL_hints.h && echo "SDL 2.26.5 OK en /work/sdl"
  aarch64-linux-gnu-readelf -d /work/sdl/lib/libSDL2-2.0.so.0 | grep -E "SONAME" || true
}

check_sdl() {
  if grep -q -- '-I/usr/include/SDL2' "$BLD/build.ninja" 2>/dev/null; then
    echo "ERROR: el build sigue usando las cabeceras SDL viejas de Debian (/usr/include/SDL2)."
    echo "Ejecuta:  .\\build.ps1 sdl   y luego   .\\build.ps1 configure"
    echo "Si persiste:  .\\build.ps1 wipe   y luego configure y compile (recompila todo, es lento)."
    exit 1
  fi
  grep -q -- '/work/sdl/include/SDL2' "$BLD/build.ninja" 2>/dev/null || { echo "ERROR: el build no usa /work/sdl (ejecuta sdl y configure)"; exit 1; }
  echo "OK: el build usa SDL 2.26.5 de /work/sdl"
}

configure() {
  log "meson setup (cross aarch64, GLES, SDL2 del sistema)"
  RECONF=""
  if [ -d "$BLD/meson-private" ]; then
    RECONF="--reconfigure"                       # conserva lo ya compilado (Ruby)
    meson configure "$BLD" --clearcache >/dev/null 2>&1 || true   # olvida la SDL vieja que meson dejo en cache
  fi
  # Notas:
  #  - sdl_system=enabled: se enlaza con libSDL2-2.0.so.0 (la de la consola, driver mali) y NO con una SDL vendida con KMSDRM.
  #  - sin pulseaudio/jack/pipewire/oss/openssl: no existen en la consola. Audio por ALSA (OpenAL la abre con dlopen).
  meson setup $RECONF "$BLD" "$SRC" --cross-file "$KIT/cross-aarch64.txt" \
    --buildtype=release \
    -Dgfx_backend=gles \
    -Ddefault_system=disabled \
    -Dsdl_system=enabled \
    -Dalsa=enabled -Dalsa_system=enabled \
    -Dpulseaudio=disabled -Djack=disabled -Dpipewire=disabled -Doss=disabled \
    -Dopenssl=disabled
  check_sdl
}

compile() {
  log "ninja (puede tardar; Ruby y FluidSynth son lo mas lento)"
  check_sdl
  ninja -C "$BLD"
}

package() {
  log "Empaquetando"
  BIN="$(find "$BLD" -maxdepth 3 -type f -name 'mkxp-z*' -perm -u+x | head -n 1)"
  [ -n "$BIN" ] || { echo "No se encontro el binario mkxp-z en $BLD"; exit 1; }
  P="$OUT/pokemonanil"; rm -rf "$P"; mkdir -p "$P/libs" "$P/licenses"
  cp "$BIN" "$P/mkxp-z"; aarch64-linux-gnu-strip "$P/mkxp-z"
  file "$P/mkxp-z"

  echo "--- glibc maxima requerida (la consola admite <= 2.33) ---"
  MAXG="$(aarch64-linux-gnu-objdump -T "$P/mkxp-z" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"; echo "$MAXG"
  echo "--- DT_NEEDED ---"
  aarch64-linux-gnu-readelf -d "$P/mkxp-z" | grep NEEDED | tee "$OUT/needed.txt"

  # Libs que SI vienen de la consola (no se copian)
  SKIP='^(libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libutil\.so|ld-linux|libSDL2|libasound|libEGL|libGLES|libGL\.)'
  for lib in $(aarch64-linux-gnu-readelf -d "$P/mkxp-z" | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/'); do
    echo "$lib" | grep -Eq "$SKIP" && continue
    for d in /usr/aarch64-linux-gnu/lib /usr/lib/aarch64-linux-gnu; do
      if [ -e "$d/$lib" ]; then cp -L "$d/$lib" "$P/libs/$lib"; echo "incluida: $lib"; break; fi
    done
  done
  # Siempre: runtime de C++ por si la consola no lo trae (leccion ya aprendida)
  for lib in libstdc++.so.6 libgcc_s.so.1; do
    [ -e "/usr/aarch64-linux-gnu/lib/$lib" ] && cp -L "/usr/aarch64-linux-gnu/lib/$lib" "$P/libs/$lib"
  done
  # libruby compartido si existe (zlib y otras extensiones solo estan en la .so)
  find "$BLD" -name 'libruby*.so*' -exec cp -L {} "$P/libs/" \; 2>/dev/null || true

  # FluidSynth va ENLAZADO ESTATICO en mkxp-z (-DSHARED_FLUID + BUILD_SHARED_LIBS=false): no hay libfluidsynth.so que empaquetar.
  # Dependencias de las libs incluidas (2 pasadas); las de la consola no se copian
  for pass in 1 2; do
    for f in "$P"/libs/*.so*; do
      for lib in $(aarch64-linux-gnu-readelf -d "$f" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/'); do
        echo "$lib" | grep -Eq "$SKIP" && continue
        [ -e "$P/libs/$lib" ] && continue
        for d in /usr/aarch64-linux-gnu/lib /usr/lib/aarch64-linux-gnu; do
          if [ -e "$d/$lib" ]; then cp -L "$d/$lib" "$P/libs/$lib"; echo "incluida (dependencia): $lib"; break; fi
        done
      done
    done
  done
  echo "--- NEEDED de las libs incluidas ---"
  for f in "$P"/libs/*.so*; do echo "# $(basename "$f")"; aarch64-linux-gnu-readelf -d "$f" | grep NEEDED; done > "$OUT/needed-libs.txt"
  cat "$OUT/needed-libs.txt"
  cp "$SRC/COPYING" "$P/licenses/mkxp-z-COPYING" 2>/dev/null || true
  git -C "$SRC" rev-parse HEAD > "$P/licenses/mkxp-z-commit.txt"
  cp "$KIT/build.sh" "$KIT/cross-aarch64.txt" "$KIT/Dockerfile" "$P/licenses/" 2>/dev/null || true
  ls -la "$P" "$P/libs"
  echo; echo "Listo: out/pokemonanil/ -> copiar mkxp-z y libs/ a SDCARD/Data/ports/pokemonanil/"
}

case "$STAGE" in
  fetch) fetch ;; wipe) rm -rf "$BLD"; echo "build borrado" ;; sdl) sdl ;; configure) configure ;; compile) compile ;; package) package ;;
  all) fetch; sdl; configure; compile; package ;;
  *) echo "etapa desconocida: $STAGE"; exit 2 ;;
esac
