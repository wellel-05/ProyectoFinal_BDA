"""
ElderCare — Scanner BLE para FeasyBeacon FSC-BP104D
Detecta el beacon via Bluetooth y envia las detecciones al API de Flask.

Uso:
  python scripts/beacon_scanner.py discover              # encuentra tu beacon
  python scripts/beacon_scanner.py monitor --beacon-id 1 --staff-id 4
  python scripts/beacon_scanner.py monitor --beacon-id 1 --staff-id 4 --mac AA:BB:CC:DD:EE:FF
"""

import asyncio
import argparse
import sys
import requests
from datetime import datetime

try:
    from bleak import BleakScanner
except ImportError:
    print("[ERROR] Instala bleak primero:  pip install bleak requests")
    sys.exit(1)

# ── Configuracion ─────────────────────────────────────────────────────────────

API_URL      = "http://localhost:8080/api/beacon"
API_KEY      = "eldercare_iot_2026_demo"   # debe coincidir con .env IOT_API_KEY
SCAN_TIMEOUT = 8.0    # segundos que dura cada escaneo BLE
RSSI_MIN     = -85    # dBm — señales mas debiles se ignoran (muy lejos)
LOOP_PAUSE   = 3.0    # segundos de espera entre ciclos de escaneo

# Nombres tipicos del FSC-BP104D (puede variar segun configuracion del dispositivo)
BEACON_NAMES = ["FSC-BP104D", "FeasyBeacon", "Feasy", "FSC", "104D"]

# ── Helpers ───────────────────────────────────────────────────────────────────

def ts():
    return datetime.now().strftime("%H:%M:%S")

def proximidad(rssi):
    if rssi is None:
        return "desconocida"
    if rssi > -55:
        return "muy cerca"
    if rssi > -70:
        return "cerca"
    if rssi > -85:
        return "lejos"
    return "muy lejos"

def nombre_coincide(device_name):
    if not device_name:
        return False
    return any(n.lower() in device_name.lower() for n in BEACON_NAMES)

# ── Modo discover ─────────────────────────────────────────────────────────────

async def discover():
    print(f"\n  Escaneando dispositivos BLE durante {SCAN_TIMEOUT:.0f} segundos...")
    print("  Acerca el beacon a tu laptop para que aparezca con mejor señal.\n")

    # return_adv=True devuelve {address: (BLEDevice, AdvertisementData)}
    results = await BleakScanner.discover(timeout=SCAN_TIMEOUT, return_adv=True)

    if not results:
        print("  No se encontraron dispositivos BLE.")
        print("  Verifica que el Bluetooth de tu laptop este activado.\n")
        return

    # Ordenar por RSSI descendente
    items = sorted(results.values(), key=lambda x: x[1].rssi or -999, reverse=True)

    print(f"  {'#':<4} {'Nombre':<28} {'MAC':<20} {'RSSI':<10} {'Proximidad'}")
    print("  " + "─" * 72)

    for i, (device, adv) in enumerate(items, 1):
        nombre = device.name or "(sin nombre)"
        rssi   = adv.rssi or 0
        marca  = " <-- TU BEACON" if nombre_coincide(device.name) else ""
        print(f"  {i:<4} {nombre:<28} {device.address:<20} {rssi:<10} dBm{marca}")

    print()
    feasy = [(d, a) for d, a in items if nombre_coincide(d.name)]
    if feasy:
        print(f"  Beacon FSC-BP104D encontrado: {feasy[0][0].address}")
        print(f"  Usa ese MAC en el modo monitor con --mac {feasy[0][0].address}\n")
    else:
        print("  FSC-BP104D no encontrado. Verifica que el beacon este encendido")
        print("  y acercalo a la laptop. Si el nombre es diferente, busca el")
        print("  dispositivo en la lista y usa su MAC con --mac <direccion>\n")

# ── Modo monitor ──────────────────────────────────────────────────────────────

async def monitor(id_beacon: int, id_staff: int, mac: str | None, nombre: str | None):
    filtro = f"MAC={mac}" if mac else f"nombre contiene '{nombre or 'FSC-BP104D'}'"
    print(f"\n  ElderCare Beacon Monitor")
    print(f"  Beacon BD  : id_beacon={id_beacon}")
    print(f"  Staff BD   : id_staff={id_staff}")
    print(f"  Filtro BLE : {filtro}")
    print(f"  RSSI minimo: {RSSI_MIN} dBm")
    print(f"  API        : {API_URL}")
    print(f"  Presiona Ctrl+C para detener\n")
    print(f"  {'Hora':<10} {'Estado':<20} {'RSSI':<12} {'Resultado'}")
    print("  " + "─" * 60)

    while True:
        try:
            results = await BleakScanner.discover(timeout=SCAN_TIMEOUT, return_adv=True)
        except Exception as e:
            print(f"  [{ts()}] Error BLE: {e}")
            await asyncio.sleep(LOOP_PAUSE)
            continue

        # Buscar el beacon por MAC o por nombre
        encontrado_dev = None
        encontrado_rssi = -999
        for address, (device, adv) in results.items():
            if mac and address.upper() == mac.upper():
                encontrado_dev  = device
                encontrado_rssi = adv.rssi or -999
                break
            if not mac and nombre_coincide(device.name or ""):
                encontrado_dev  = device
                encontrado_rssi = adv.rssi or -999
                break

        if not encontrado_dev:
            print(f"  [{ts()}] {'Sin señal':<20} {'—':<12} esperando beacon...")
            await asyncio.sleep(LOOP_PAUSE)
            continue

        rssi = encontrado_rssi

        if rssi < RSSI_MIN:
            prox = proximidad(rssi)
            print(f"  [{ts()}] {encontrado_dev.name or 'beacon':<20} {rssi} dBm ({prox}) — señal debil, ignorando")
            await asyncio.sleep(LOOP_PAUSE)
            continue

        # Señal suficiente — enviar al API
        prox = proximidad(rssi)
        print(f"  [{ts()}] {encontrado_dev.name or 'beacon':<20} {rssi} dBm ({prox}) — enviando...", end=" ", flush=True)

        try:
            resp = requests.post(
                API_URL,
                json={"id_beacon": id_beacon, "id_staff": id_staff},
                headers={"X-API-Key": API_KEY},
                timeout=5
            )
            data = resp.json()
            if data.get("ok"):
                print(f"OK (id_deteccion={data['id_deteccion']})")
            else:
                print(f"Error API: {data.get('msg')}")
        except requests.exceptions.ConnectionError:
            print("Error: Flask no esta corriendo en localhost:8080")
        except Exception as e:
            print(f"Error: {e}")

        await asyncio.sleep(LOOP_PAUSE)

# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="ElderCare BLE Beacon Scanner — FSC-BP104D",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("discover", help="Escanea y lista todos los dispositivos BLE cercanos")

    mon = sub.add_parser("monitor", help="Monitoreo continuo — envia detecciones al API")
    mon.add_argument("--beacon-id", type=int, required=True,
                     help="id_beacon en la BD (1=AlaA, 2=AlaB, 3=AlaB-SalaGrupal)")
    mon.add_argument("--staff-id",  type=int, required=True,
                     help="id_staff del trabajador que sera registrado")
    mon.add_argument("--mac",  type=str, default=None,
                     help="MAC address del beacon (ej: AA:BB:CC:DD:EE:FF)")
    mon.add_argument("--nombre", type=str, default=None,
                     help="Nombre BLE del beacon si es diferente a FSC-BP104D")

    args = parser.parse_args()

    if args.cmd == "discover":
        asyncio.run(discover())
    elif args.cmd == "monitor":
        asyncio.run(monitor(args.beacon_id, args.staff_id, args.mac, args.nombre))
    else:
        parser.print_help()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n  Scanner detenido.")
