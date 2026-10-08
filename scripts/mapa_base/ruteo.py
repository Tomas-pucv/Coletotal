"""Arma los datos de ruteo de Valhalla que la app usa sin conexión.

Lo llama build.js (paso `ruteo`); se puede correr solo:

    python scripts/mapa_base/ruteo.py chile-latest.osm.pbf regiones/valparaiso.geojson salida.tar

1. Construye el grafo de calles de Valhalla a partir del extracto de Chile de
   Geofabrik (unos 400 MB, en `.cache/valhalla`).
2. Guarda en un tar sólo las teselas que tocan la región (la misma que tiene
   todas las calles en el mapa base): unos 65 MB. Valhalla lo lee tal cual en
   el teléfono (`android/app/.../MainActivity.kt`).

Necesita pyvalhalla **3.9.1**, la misma versión de Valhalla que trae
valhalla-mobile 0.6.4 en la app (un motor más viejo podría no leer el
grafo), y shapely para cruzar las teselas con la región:

    pip install pyvalhalla==3.9.1 shapely
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import valhalla
from valhalla import get_config

VERSION_ESPERADA = "3.9.1"
TRABAJO = Path(__file__).parent / ".cache" / "valhalla"


def _bin(nombre: str) -> str:
    carpeta = Path(valhalla.__file__).parent / "bin"
    return str(carpeta / (nombre + (".exe" if os.name == "nt" else "")))


def _entorno() -> dict:
    # En Windows las DLL que trae pyvalhalla no quedan en el PATH, y su propio
    # `python -m valhalla valhalla_build_tiles` busca el ejecutable en el PATH
    # en vez de en su carpeta: se llama directo, con las DLL agregadas.
    libs = Path(valhalla.__file__).parent.parent / "pyvalhalla.libs"
    entorno = dict(os.environ)
    if libs.is_dir():
        entorno["PATH"] = str(libs) + os.pathsep + entorno.get("PATH", "")
    return entorno


def main(pbf: str, region: str, salida: str) -> None:
    # La consola de Windows usa cp1252 y no sabe imprimir los emoji.
    sys.stdout.reconfigure(encoding="utf-8")
    version = getattr(valhalla, "__version__", "")
    if not str(version).startswith(VERSION_ESPERADA):
        sys.exit(
            f"Se necesita pyvalhalla {VERSION_ESPERADA} (hay {version}): "
            f"pip install pyvalhalla=={VERSION_ESPERADA} shapely"
        )

    teselas = TRABAJO / "teselas"
    shutil.rmtree(teselas, ignore_errors=True)
    teselas.mkdir(parents=True)

    config = get_config(tile_extract="", tile_dir=teselas)
    config["mjolnir"]["concurrency"] = os.cpu_count() or 4
    archivo_config = TRABAJO / "valhalla.json"
    archivo_config.write_text(json.dumps(config))

    print("🔄 Construyendo el grafo de calles de Valhalla...", flush=True)
    subprocess.run(
        [_bin("valhalla_build_tiles"), "-c", str(archivo_config), str(Path(pbf).resolve())],
        env=_entorno(),
        check=True,
        stdout=subprocess.DEVNULL,
    )

    # La región como FeatureCollection, que es lo que lee valhalla_build_extract.
    carpeta_region = TRABAJO / "region"
    shutil.rmtree(carpeta_region, ignore_errors=True)
    carpeta_region.mkdir()
    geometria = json.loads(Path(region).read_text(encoding="utf-8"))
    (carpeta_region / "region.geojson").write_text(
        json.dumps(
            {
                "type": "FeatureCollection",
                "features": [{"type": "Feature", "properties": {}, "geometry": geometria}],
            }
        )
    )

    config["mjolnir"]["tile_extract"] = str(Path(salida).resolve())
    archivo_config.write_text(json.dumps(config))
    print("🔄 Guardando las teselas de la región...", flush=True)
    subprocess.run(
        [
            sys.executable,
            "-m",
            "valhalla.valhalla_build_extract",
            "-c",
            str(archivo_config),
            "-g",
            str(carpeta_region),
            "-O",
        ],
        env=_entorno(),
        check=True,
    )
    # El grafo de todo Chile (unos 400 MB) ya no hace falta: se rehace en
    # cada corrida.
    shutil.rmtree(teselas, ignore_errors=True)
    tamano = Path(salida).stat().st_size / 1024 / 1024
    print(f"✅ {Path(salida).name}: {tamano:.1f} MB", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
