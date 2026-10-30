# Vulkan Solución — PS4 Artix (GPU Liverpool)

**Idioma:** [Español](README.md) · [English](README.en.md)

Carpeta autocontenida con el diagnóstico, las Mesas estables, los lanzadores y
un monitor de GPU para jugar con **Vulkan/DXVK sin que se cuelgue la GPU** en
esta PS4.

Fecha: 29/10/2026 · Kernel de referencia: `7.0.8-Strawberry-FullLTO-Baikal-+` ·
Mesa del sistema: 26.0.8

> Los ejemplos usan rutas ficticias (`/home/USER/...`,
> `/run/media/USER/External/Games/...`). Cámbialas por las tuyas. Dentro de los
> scripts todo se resuelve con `$HOME` y con la carpeta real del repositorio, así
> que puedes clonarlo donde quieras.

---

## 0. Instalación

### Recomendada: un solo comando

```bash
git clone https://github.com/YOUR-USER/YOUR-REPO.git
cd YOUR-REPO
./install.sh
```

Sustituye `YOUR-USER/YOUR-REPO` por la URL real. El nombre de la carpeta y del
repositorio da igual: cada script detecta su propia ubicación, así que puedes
clonarlo, moverlo o renombrarlo sin editar nada.

`install.sh` hace todo:

1. Detecta la distribución. **Solo está soportado en Arch Linux y derivados que
   usan pacman** (Artix, EndeavourOS, Manjaro, Garuda, CachyOS…). En cualquier
   otra distro avisa y pregunta si quieres continuar.
2. Comprueba las herramientas necesarias y ofrece instalarlas con `pacman`.
3. Arranca `ps4-monitor` en segundo plano **antes** de tocar nada, para que
   cualquier cuelgue de GPU o pérdida de vídeo quede registrado.
4. Descarga Mesa 25.3.5 + LLVM 21 y Mesa 26.0.4 + LLVM 22, verifica sus
   `sha256` y genera los ICD.
5. Hace una comprobación general de RADV y después **verifica cada versión
   individualmente**.
6. Si todo sale bien, explica cómo usar los lanzadores. Si algo falla, deja los
   logs y el informe del monitor.

Opciones útiles:

```bash
./install.sh --dry-run        # enseña el plan sin cambiar nada
./install.sh --yes            # acepta todas las preguntas
./install.sh --skip-download  # usa las Mesas ya descargadas
./install.sh --skip-tests     # no ejecuta pruebas de Vulkan
./install.sh --no-monitor     # no arranca el monitor
./install.sh --no-desktop     # no crea atajos de menú
```

### Instalación manual

```bash
./download-mesa.sh      # descarga Mesa/LLVM y genera los ICD (~650 MB)
./check.sh              # verifica RADV con cada versión
./check.sh 25.3.5       # verifica una versión concreta
```

El repositorio **no incluye los binarios** (Mesa + LLVM pesan ~650 MB y GitHub
rechaza archivos de más de 100 MB). `download-mesa.sh` los baja de las fuentes
originales (repo `ps4-video` y Arch Archive), comprueba su `sha256` y los deja en
`mesa-versions/`.

### Steam + Proton (recomendado)

Instala **Proton 8.0-5** en Steam **aunque tus juegos no sean de Steam**.
`vulkan-run.sh --proton` usa el Proton de Steam (y el Steam Linux Runtime) para
cualquier `.exe` de Windows, sea o no un juego de Steam. Proton 8.0-5 es la
versión probada; si falta Proton 8.0, el lanzador usa otro Proton instalado,
pero esa combinación no está verificada.

No hace falta para juegos nativos de Linux, `check.sh`, `vkcube`,
`vulkan-env.sh` ni Heroic (Heroic usa su propio Wine-GE/Proton-GE).

Además, algunos juegos necesitan que el **cliente de Steam esté abierto** porque
usan la Steam API (por ejemplo los PES/Football Life), incluso lanzándolos con
`vulkan-run.sh`.

`install.sh` crea un enlace `~/mesa-versions -> <repo>/mesa-versions` si esa ruta
no existe, para que las opciones de lanzamiento antiguas de Steam sigan
funcionando. Si ya tienes `~/mesa-versions`, te preguntará si quieres usarla.

---

## 1. El problema en 30 segundos

Con la Mesa 26.0.8 del sistema, RADV cuelga la GPU al primer frame de un juego
con DXVK:

```
amdgpu: ring gfx timeout, signaled seq=... emitted seq=...
amdgpu:  Process <juego> on pi ... thread dxvk-submit ...
amdgpu: GPU Recovery Failed: -110      -> pantalla negra, hay que reiniciar
```

OpenGL (radeonsi) y `vkcube` funcionan siempre: **el fallo es de RADV al
compilar/ejecutar los pipelines de DXVK** en la GPU gfx7 "Liverpool".

Probado y descartado: temperatura (69 °C en el fallo), relojes bajos
(`glxgears` 1621 FPS), `amdgpu.dpm=0`, wined3d, LLVM, GPL off, etc. Detalle
completo en [`reports/ps4-vulkan-diagnosis.md`](reports/ps4-vulkan-diagnosis.md).

**Solución:** usar RADV de **Mesa 25.3.5** (o 26.0.4) solo para el juego. No se
instala ni se modifica nada del sistema.

| RADV | Resultado |
|---|---|
| 26.0.8 (sistema) | cuelgue a los 10–20 s |
| **25.3.5** | estable (420 s probados, 33–52 FPS) |
| **26.0.4** | estable (240 s probados, 35–60 FPS) |

---

## 2. Contenido de la carpeta

```
repo/
├── README.md               este documento (español)
├── README.en.md            documentación en inglés
├── install.sh              instalación completa (descarga, monitor, pruebas)
├── vulkan-env.sh           núcleo: elige Mesa (se usa con source)
├── vulkan-env.fish         lo mismo para fish
├── vulkan-run.sh           lanzador universal (Steam, no-Steam, lo que sea)
├── heroic-mesa.sh          wrapper para Heroic Launcher (Flatpak o nativo)
├── prepare-heroic.sh       permisos + deps + prueba para Heroic
├── check.sh                verifica RADV/Mesa de cada versión
├── check-heroic.py         prueba Vulkan mínima (sirve dentro del sandbox)
├── download-mesa.sh        reconstruye mesa-versions/ con sha256
├── steam-options.txt       textos listos para pegar en Steam
├── activation.log          historial de activaciones (local, no se sube)
├── mesa-versions/          Mesas estables + LLVM + ICDs (no se sube)
├── monitor/
│   ├── ps4-monitor.sh          monitor de GPU/vídeo en segundo plano
│   ├── ps4-monitor-stop.sh     lo detiene
│   └── ps4-monitor-status.sh   estado y últimas líneas
├── logs/                   sesiones, instalación y errores (local, no se sube)
├── run/                    PIDs del monitor (local, no se sube)
├── reports/
│   ├── ps4-vulkan-diagnosis.md  informe técnico completo
│   ├── tests-2026-10-29.md      cronología de pruebas
│   ├── mesa-versions-README.txt inventario de mesa-versions
│   └── logs/                    logs históricos del monitor
├── desktop/                plantillas .desktop
└── tests/smoke-test.sh     prueba de humo (sintaxis, traducción, monitor)
```

Las copias de trabajo pueden vivir también en `~/mesa-versions` (la usan las
opciones de Steam antiguas). Los scripts usan primero `repo/mesa-versions` y,
si no existe, `~/mesa-versions`; puedes forzar otra carpeta con
`VULKAN_MESA_DIR=/ruta/a/mesa-versions`.

---

## 3. Uso rápido

### 3.1 Fish (shell por defecto)

```fish
source /path/to/repo/vulkan-env.fish
# a partir de aquí, todo lo que lances usa RADV de Mesa 25.3.5
```

Con otra versión o con HUD:

```fish
source /path/to/repo/vulkan-env.fish --mesa 26.0.4
source /path/to/repo/vulkan-env.fish --mesa 25.3.5 --hud fps
```

### 3.2 Bash / sh / zsh

```bash
. /path/to/repo/vulkan-env.sh              # Mesa 25.3.5
. /path/to/repo/vulkan-env.sh --mesa 26.0.4
. /path/to/repo/vulkan-env.sh --hud fps,devinfo
```

Las variables se quedan en esa terminal. Para un solo comando:

```bash
bash -c '. /path/to/repo/vulkan-env.sh; ./mi_programa'
```

### 3.3 Lanzador universal (sin tocar el shell)

```bash
vulkan-run.sh --mesa 25.3.5 -- vkcube
vulkan-run.sh --mesa 25.3.5 --hud -- ./programa_linux
vulkan-run.sh --wined3d --proton -- "/ruta/juego32bits.exe"
```

Ejecuta `vulkan-run.sh -h` para ver todas las opciones.

---

## 4. Steam (juego de Steam)

Propiedades del juego → **Opciones de lanzamiento**. Dos formas válidas:

**A) Con el lanzador (recomendada, respeta el `%command%` de Steam):**

```
/path/to/repo/vulkan-run.sh --mesa 25.3.5 -- %command% -force-d3d11
```

**B) Con `source` (más corta):**

```
bash -c '. /path/to/repo/vulkan-env.sh --mesa 25.3.5; exec "$@"' _ %command% -force-d3d11
```

Cambia `/path/to/repo` por la ruta real de tu clon. Para Mesa
26.0.4 cambia `--mesa 25.3.5` por `--mesa 26.0.4`. `-force-d3d11` solo es
necesario en juegos Unity que intenten D3D12.

Comprobar que el juego usa la Mesa buena: añade `--hud=fps,devinfo` (forma A) o
`DXVK_HUD=devinfo` (forma B); arriba a la izquierda debe decir
`Mesa 25.3.5 (git-39f24bf409)`.

---

## 5. Juegos NO Steam

### Opción 1 — sin Steam (el lanzador crea un prefijo por juego)

```bash
/path/to/repo/vulkan-run.sh --proton -- "/run/media/USER/External/Games/Example Game/game.exe"
```

El prefijo queda en `~/.local/share/vulkan-proton/<nombre-del-juego>/`.
Se puede forzar otro con `--prefix`:

```bash
/path/to/repo/vulkan-run.sh --proton --prefix ~/.local/share/wine/example -- "/ruta/game.exe"
```

### Opción 2 — añadido a Steam (prefijo gestionado por Steam)

1. Steam → *Añadir juego* → *Añadir juego no de Steam* → elegir el `.exe`.
2. Propiedades → *Forzar el uso de una herramienta de compatibilidad* →
   **Proton 8.0**.
3. Opciones de lanzamiento:

```
/path/to/repo/vulkan-run.sh --mesa 25.3.5 -- %command%
```

### ⚠️ Juegos de 32 bits

Los `.exe` de 32 bits necesitan un RADV de 32 bits, y **no existe** versión
antigua: solo hay `lib32-llvm` 23.x, que no sirve para Mesa 25.3.5/26.0.4. El
lanzador lo detecta y avisa.

Para esos juegos usa **wined3d (OpenGL)**, que en esta PS4 es estable:

```bash
/path/to/repo/vulkan-run.sh --wined3d --proton -- "/ruta/juego32.exe"
```

En Steam, para un juego de 32 bits: `PROTON_USE_WINED3D=1 %command%`.

---

## 5-bis. Heroic Games Launcher (Flatpak o nativo)

Sirve para **Heroic Flatpak y Heroic nativo**. El wrapper es el mismo; solo
cambia lo que hay que preparar:

- **Flatpak**: vive en un sandbox que no ve `/dev/dri` ni la carpeta de Mesas, y
  le faltan 3 librerías que el runtime no trae. `prepare-heroic.sh` lo arregla.
- **Nativo**: sin sandbox, ya ve `/dev/dri` y `/usr/lib`; no hace falta nada,
  el wrapper funciona tal cual (el script solo comprueba que RADV carga).

```bash
./prepare-heroic.sh     # detecta solo si Heroic es Flatpak o nativo
```

En Flatpak, ese script (sin root) hace:

1. `flatpak override --user` para dar a Heroic `--device=all` y acceso a la
   carpeta del repo y a `~/mesa-versions`.
2. Copia a `mesa-versions/deps/` las 3 librerías que no están en el runtime
   (`libdisplay-info.so.3`, `libSPIRV-Tools.so`, `libedit.so.0`).
3. Comprueba que RADV carga y ve la GPU (dentro del sandbox o en el sistema,
   según el tipo de Heroic).

Después, **por cada juego** (64 bits): Ajustes del juego (⚙) → **Advanced** →
**Wrapper command**:

```
Wrapper:    /path/to/repo/heroic-mesa.sh
Arguments:  (vacío)
```

Y, si quieres, en **Environment Variables** del mismo juego:

| Variable | Valor | Efecto |
|---|---|---|
| `HEROIC_MESA_HUD` | `fps` | contador de FPS de DXVK |
| `HEROIC_MESA` | `26.0.4` | usa la otra Mesa estable |
| `HEROIC_WINED3D` | `1` | juegos de **32 bits**: OpenGL/wined3d |

Notas:

- Heroic no trae Wine: instala primero **Wine-GE** o **Proton-GE** desde
  *Wine Manager* (menú lateral). El wrapper funciona con ambos.
- Para 32 bits no sirve RADV antiguo (no hay lib32 de LLVM 21/22): usa
  `HEROIC_WINED3D=1`.
- Si reinstalas Heroic, vuelve a ejecutar `./prepare-heroic.sh`.
- Heroic nativo usa las librerías del sistema: `mesa-versions/deps/` solo es
  necesario en el Flatpak.
- El wrapper añade sus rutas al final de `LD_LIBRARY_PATH`, así no pisa las
  librerías de Wine que coloca Heroic.

---

## 6. Comprobar y diagnosticar

```bash
/path/to/repo/check.sh              # vulkaninfo + vkcube con cada Mesa
/path/to/repo/check.sh 25.3.5       # solo una versión
/path/to/repo/vulkan-env.sh --show  # rutas que se usarían
tail -f /path/to/repo/activation.log  # historial de activaciones
```

### Monitor de GPU

`install.sh` y `vulkan-run.sh --monitor` arrancan el monitor en segundo plano.
Registra `dmesg`, temperatura, ventilador, VRAM/GTT, RAM, Xorg y el conector de
vídeo.

```bash
/path/to/repo/monitor/ps4-monitor-status.sh
/path/to/repo/monitor/ps4-monitor-stop.sh
```

Si detecta un cuelgue de GPU, una pérdida de vídeo, un fallo de Xorg o falta de
memoria, escribe un informe legible **que sobrevive al reinicio**:

```
/path/to/repo/ps4-monitor-error.log
/path/to/repo/logs/ps4-monitor-error-<fecha>.log
```

El informe explica qué pasó, el estado del sistema en ese momento y qué hacer
(reiniciar, usar Mesa 25.3.5, `--wined3d` para 32 bits, etc.). Las sesiones
completas quedan en `logs/session-*.log`.

---

## 7. Revertir / deshacer

Nada está instalado en el sistema:

- Quitar la opción de lanzamiento de Steam → vuelve a Mesa 26.0.8.
- `rm -rf ~/mesa-versions /path/to/repo ~/.local/share/vulkan-proton`
- Atajos: borrar los `.desktop` de `~/.local/share/applications`.
- Monitor: `./monitor/ps4-monitor-stop.sh`.

---

## 8. Añadir otra versión de Mesa (opcional)

1. Descargar el paquete `mesa-ps4-<ver>-x86_64.pkg.tar.zst` del repo
   `ps4-video` (DionKill) en el commit que corresponda.
2. Extraerlo: `mkdir mesa-<ver> && bsdtar -xf paquete.zst -C mesa-<ver>`
3. Extraer su LLVM (paquete `llvm-libs` de Arch Archive) en `llvm-<N>/`.
4. Copiar el ICD y apuntar `library_path` a
   `~/mesa-versions/mesa-<ver>/usr/lib/libvulkan_radeon.so`.
5. `./check.sh <ver>` y, si pasa, usarla con `--mesa <ver>`.

`vulkan-env.sh` detecta sola la `libLLVM` que necesita cada Mesa leyendo el ELF.

---

## 9. Prueba de la traducción / desarrollo

```bash
./tests/smoke-test.sh                # sintaxis, textos, selección de Mesa, monitor
./tests/smoke-test.sh --with-vulkan  # además enumera la GPU con cada Mesa
```

La prueba comprueba que no quedan rutas personales ni textos en español en los
scripts, que `fish`/`bash`/Python tienen sintaxis válida, que el monitor escribe
informes y que cada Mesa produce un entorno válido.

---

## 10. Notas

- Mesa 26.0.8 es un build del repo `ps4-video`; el parche PS4 solo añade
  LIVERPOOL/GLADIUS como GFX7, así que las Mesas antiguas del mismo repo son
  compatibles.
- El bug es de RADV, no del kernel ni del hardware: OpenGL y Vulkan "de carga
  ligera" funcionan bien.
- Si algún día se actualiza Mesa del sistema y el bug desaparece, basta con
  dejar de usar el lanzador (o `--mesa` con la versión nueva).
- Este repositorio es público: no contiene rutas de usuario ni binarios
  propietarios. Los ejemplos usan `/home/USER` y rutas ficticias.
