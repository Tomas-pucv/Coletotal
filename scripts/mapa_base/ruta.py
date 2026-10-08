"""Calcula una ruta con Valhalla en este computador, con los mismos datos de
ruteo que lleva la app (`assets/map/ruteo_valparaiso.tar`).

Lee la consulta de Valhalla (JSON) por la entrada estándar y escribe la
respuesta por la salida. La usa scripts/apply_recorridos_geometries.js para
recalcular los trazados guardados igual que los calcula el teléfono, sin
depender de ningún servidor.

    echo '{"locations": [...], "costing": "auto"}' | python scripts/mapa_base/ruta.py

Necesita pyvalhalla 3.9.1 (ver ruteo.py). Termina con código 1 si Valhalla no
encuentra ruta.
"""

import os
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
TAR = RAIZ / "assets" / "map" / "ruteo_valparaiso.tar"

# En Windows las DLL que trae pyvalhalla no quedan en el PATH (ver ruteo.py).
import valhalla  # noqa: E402

_libs = Path(valhalla.__file__).parent.parent / "pyvalhalla.libs"
if _libs.is_dir() and hasattr(os, "add_dll_directory"):
    os.add_dll_directory(str(_libs))

from valhalla import Actor, get_config  # noqa: E402


def main() -> None:
    actor = Actor(get_config(tile_extract=TAR, tile_dir=""))
    try:
        sys.stdout.write(actor.route(sys.stdin.read()))
    except RuntimeError as e:
        sys.stderr.write(f"{e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
