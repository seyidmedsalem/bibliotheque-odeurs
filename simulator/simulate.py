"""Simulateur de nez électronique : teste tout le système sans matériel.

Exemples :
  # 1) Entraîner un modèle avec des odeurs simulées (rapide, ~30 s)
  python simulate.py train

  # 2) Envoyer des mesures en continu (1 par seconde) avec des odeurs aléatoires
  python simulate.py live                       # via HTTP (aucun broker nécessaire)
  python simulate.py live --transport mqtt      # via MQTT, comme un vrai ESP32
  python simulate.py live --odor "Café"         # toujours la même odeur

Position : par défaut aucune (placez l'appareil depuis l'app iPhone), ou --lat 18.08 --lon -15.97

Plusieurs appareils : lancer plusieurs fois avec --device nez-salon --room Salon --lat ... --lon ...
"""
import argparse
import json
import math
import random
import sys
import time
import urllib.error
import urllib.request

BASE_AIR = {
    "bme688_gas": 120000.0,  # ohms
    "sgp41_voc": 100.0,      # indice
    "sgp41_nox": 1.0,        # indice
    "ens160_tvoc": 50.0,     # ppb
    "mq3": 0.35,             # volts
    "mq4": 0.40,
    "mq135": 0.80,
}

# Effet de chaque odeur à intensité 1 : ("mul", facteur) ou ("add", valeur)
PROFILES = {
    "Air ambiant": {},
    "Café": {"bme688_gas": ("mul", 0.55), "sgp41_voc": ("add", 150), "sgp41_nox": ("add", 5),
             "ens160_tvoc": ("add", 300), "mq3": ("mul", 1.3), "mq135": ("mul", 1.6)},
    "Pain brûlé": {"bme688_gas": ("mul", 0.35), "sgp41_voc": ("add", 260), "sgp41_nox": ("add", 60),
                   "ens160_tvoc": ("add", 700), "mq3": ("mul", 1.2), "mq4": ("mul", 1.1), "mq135": ("mul", 2.6)},
    "Poubelle": {"bme688_gas": ("mul", 0.6), "sgp41_voc": ("add", 120), "sgp41_nox": ("add", 10),
                 "ens160_tvoc": ("add", 250), "mq3": ("mul", 1.4), "mq4": ("mul", 1.3), "mq135": ("mul", 3.0)},
    "Fruit trop mûr": {"bme688_gas": ("mul", 0.5), "sgp41_voc": ("add", 180), "sgp41_nox": ("add", 2),
                       "ens160_tvoc": ("add", 400), "mq3": ("mul", 3.2), "mq135": ("mul", 1.3)},
    "Fuite de gaz": {"bme688_gas": ("mul", 0.85), "sgp41_voc": ("add", 30), "ens160_tvoc": ("add", 60),
                     "mq3": ("mul", 1.1), "mq4": ("mul", 7.0), "mq135": ("mul", 1.2)},
    "Produit chimique": {"bme688_gas": ("mul", 0.25), "sgp41_voc": ("add", 300), "sgp41_nox": ("add", 25),
                         "ens160_tvoc": ("add", 1100), "mq3": ("mul", 2.0), "mq4": ("mul", 1.1), "mq135": ("mul", 1.8)},
}


class Nose:
    """Capteurs virtuels : bruit, dérive lente, montée/descente progressive des odeurs."""

    def __init__(self, seed=None):
        self.rng = random.Random(seed)
        self.odor = "Air ambiant"
        self.level = 0.0       # intensité actuelle (0 → 1)
        self.target = 0.0
        self.strength = 1.0
        self.t = 0
        self.drift = {k: 1.0 for k in BASE_AIR}

    def expose(self, odor, strength=None):
        self.odor = odor
        self.target = 0.0 if odor == "Air ambiant" else 1.0
        self.strength = strength if strength is not None else self.rng.uniform(0.7, 1.2)

    def read(self, tau=4.0):
        self.t += 1
        self.level += (self.target - self.level) / tau  # montée exponentielle
        for k in self.drift:
            self.drift[k] *= 1 + self.rng.gauss(0, 0.0004)
        temp = 22 + 1.5 * math.sin(self.t / 600) + self.rng.gauss(0, 0.05)
        hum = 45 + 5 * math.sin(self.t / 900) + self.rng.gauss(0, 0.2)
        out = {}
        for key, base in BASE_AIR.items():
            v = base * self.drift[key] * (1 + (hum - 45) * 0.004)  # sensibilité à l'humidité
            effect = PROFILES.get(self.odor, {}).get(key)
            if effect:
                k = self.level * self.strength
                v = v * (1 + (effect[1] - 1) * k) if effect[0] == "mul" else v + effect[1] * k
            v *= 1 + self.rng.gauss(0, 0.015)
            out[key] = round(v, 3) if key.startswith("mq") else round(v, 1)
        out["temp"], out["hum"] = round(temp, 2), round(hum, 2)
        return out


# ------------------------------------------------------------------ transports
class Http:
    def __init__(self, api, ingest_key):
        self.api, self.key, self.token = api.rstrip("/"), ingest_key, None

    def call(self, method, path, body=None, auth=True):
        req = urllib.request.Request(self.api + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None)
        req.add_header("Content-Type", "application/json")
        if auth and self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            sys.exit(f"Erreur API {e.code} sur {path} : {e.read().decode()}")
        except urllib.error.URLError as e:
            sys.exit(f"API injoignable ({self.api}) : {e.reason}. Le backend est-il lancé ?")

    def login(self, email, password):
        self.token = self.call("POST", "/api/auth/login", {"email": email, "password": password}, auth=False)["access_token"]

    def send(self, device, payload):
        req = urllib.request.Request(f"{self.api}/api/ingest/{device}", method="POST", data=json.dumps(payload).encode())
        req.add_header("Content-Type", "application/json")
        req.add_header("X-Ingest-Key", self.key)
        urllib.request.urlopen(req, timeout=15).read()


class Mqtt:
    def __init__(self, host, port, user, password, device):
        try:
            import paho.mqtt.client as mqtt
        except ImportError:
            sys.exit("Installe paho-mqtt : pip install paho-mqtt")
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"sim-{device}")
        if user:
            self.client.username_pw_set(user, password)
        self.client.will_set(f"nose/{device}/status", json.dumps({"device": device, "state": "offline"}), retain=True)
        self.client.on_message = lambda c, u, m: print(f"  ← {m.topic} {m.payload.decode()}")
        self.client.connect(host, port)
        self.client.subscribe(f"nose/{device}/cmd")
        self.client.loop_start()
        self.client.publish(f"nose/{device}/status", json.dumps({"device": device, "state": "online"}), retain=True)

    def send(self, device, payload):
        self.client.publish(f"nose/{device}/raw", json.dumps(payload))


# ------------------------------------------------------------------ modes
def payload(args, reading):
    p = {"device": args.device, "warming": False, **reading}
    if args.lat is not None and args.lon is not None:
        p["lat"], p["lon"] = args.lat, args.lon
    return p


def setup_device(api, args):
    body = {"room": args.room} if args.room else {}
    if args.lat is not None and args.lon is not None:
        body.update(lat=args.lat, lon=args.lon)
    if body:
        api.call("PATCH", f"/api/devices/{args.device}", body)


def cmd_train(args):
    api = Http(args.api, args.ingest_key)
    api.login(args.email, args.password)
    nose = Nose(args.seed)
    odors = {o["name"]: o for o in api.call("GET", "/api/odors")}
    names = [n for n in PROFILES if n in odors]

    print("Calibration à l'air propre…")
    for _ in range(25):
        api.send(args.device, payload(args, nose.read()))
    setup_device(api, args)

    for rep in range(args.repeats):
        for name in names:
            session = api.call("POST", "/api/training/sessions",
                               {"device_id": args.device, "odor_id": odors[name]["id"], "windows": args.windows, "skip_windows": 2})
            nose.expose(name, strength=nose.rng.uniform(0.6, 1.3))
            sent = 0
            while True:
                api.send(args.device, payload(args, nose.read(tau=2.0)))
                sent += 1
                if sent % 5 == 0:
                    s = api.call("GET", f"/api/training/sessions/{session['id']}")
                    if s["status"] != "active":
                        break
            print(f"  [{rep + 1}/{args.repeats}] {name:<18} {s['collected']} échantillons")
            nose.expose("Air ambiant")
            for _ in range(15):  # purge entre deux odeurs
                api.send(args.device, payload(args, nose.read(tau=2.0)))

    print("Entraînement du modèle…")
    info = api.call("POST", "/api/model/train")
    print(f"Modèle entraîné : {info['meta']['n_samples']} échantillons, précision (validation croisée) "
          f"{info['meta']['accuracy'] * 100:.1f} %")


def cmd_live(args):
    nose = Nose(args.seed)
    if args.transport == "mqtt":
        tx = Mqtt(args.mqtt_host, args.mqtt_port, args.mqtt_user, args.mqtt_password, args.device)
    else:
        tx = Http(args.api, args.ingest_key)
    odors = [n for n in PROFILES if n != "Air ambiant" and n not in args.exclude]
    print(f"Simulation de « {args.device} » ({args.transport}), Ctrl+C pour arrêter")
    phase_end, phase = 0, "air"
    while True:
        now = time.time()
        if args.odor:
            if nose.odor != args.odor:
                nose.expose(args.odor)
        elif now >= phase_end:
            if phase == "air":
                phase, phase_end = "odor", now + random.uniform(25, 45)
                nose.expose(random.choice(odors))
            else:
                phase, phase_end = "air", now + random.uniform(30, 60)
                nose.expose("Air ambiant")
            print(f"→ {nose.odor}")
        try:
            tx.send(args.device, payload(args, nose.read()))
        except (urllib.error.URLError, OSError) as e:  # serveur redémarré : on continue
            print(f"  ! envoi impossible ({e}), nouvel essai…")
        time.sleep(args.period)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", choices=["train", "live"])
    p.add_argument("--device", default="nez-cuisine")
    p.add_argument("--room", default="Cuisine")
    # Sans --lat/--lon, le simulateur n'envoie pas de position : placez l'appareil
    # à sa vraie position depuis l'app iPhone (Carte ou Réglages).
    p.add_argument("--lat", type=float, help="position fixe envoyée avec chaque mesure (optionnel)")
    p.add_argument("--lon", type=float)
    p.add_argument("--api", default="http://localhost:8000")
    p.add_argument("--email", default="admin@nez.local")
    p.add_argument("--password", default="admin1234")
    p.add_argument("--ingest-key", default="dev-ingest-key")
    p.add_argument("--transport", choices=["http", "mqtt"], default="http")
    p.add_argument("--mqtt-host", default="localhost")
    p.add_argument("--mqtt-port", type=int, default=1883)
    p.add_argument("--mqtt-user", default="nez")
    p.add_argument("--mqtt-password", default="change-moi")
    p.add_argument("--odor", help="toujours la même odeur (mode live)")
    p.add_argument("--exclude", nargs="*", default=[], help="odeurs à ne pas simuler (mode live)")
    p.add_argument("--period", type=float, default=1.0, help="secondes entre deux mesures (mode live)")
    p.add_argument("--windows", type=int, default=8, help="échantillons par odeur et par passage (mode train)")
    p.add_argument("--repeats", type=int, default=2, help="nombre de passages par odeur (mode train)")
    p.add_argument("--seed", type=int)
    args = p.parse_args()
    try:
        cmd_train(args) if args.mode == "train" else cmd_live(args)
    except KeyboardInterrupt:
        print("\nArrêt.")


if __name__ == "__main__":
    main()
