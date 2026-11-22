# 👃 La bibliothèque des odeurs

**Nez électronique IoT** qui apprend à reconnaître, dater et cartographier les odeurs de son environnement.
Projet de **Seyid Cheikh**.

📖 **Documentation complète : [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)** · Présentation : [docs/Presentation_Bibliotheque_Odeurs_IoT.pdf](docs/Presentation_Bibliotheque_Odeurs_IoT.pdf)

```
[Capteurs gaz + T/H] → [ESP32-S3] ──Wi-Fi / MQTT──> [Mosquitto]
                                                       │
                                         [Backend FastAPI + Random Forest]
                                           │                        │
                          [PostgreSQL + TimescaleDB + PostGIS]   [WebSocket]
                                                                    │
                                       [App iOS SwiftUI]   [Interface web React]
```

| Dossier | Contenu | Outil |
|---|---|---|
| `firmware/` | Programme de l'ESP32 (C++ / Arduino) | VS Code + PlatformIO |
| `backend/` | API REST, MQTT, WebSocket, machine learning (Python) | VS Code |
| `simulator/` | Faux capteurs pour tout tester sans matériel | VS Code |
| `ios/` | Application iPhone / iPad en SwiftUI | Xcode |
| `web/` | Interface web (React + Vite + TypeScript) | VS Code |
| `mosquitto/` | Configuration du broker MQTT | Docker |

---

## 1. Démarrage rapide (sans matériel, sans Docker)

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
MQTT_ENABLED=false .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Dans un deuxième terminal :

```bash
cd simulator
python3 simulate.py train      # enregistre 7 odeurs simulées et entraîne le modèle (~30 s)
python3 simulate.py live       # envoie une mesure par seconde avec des odeurs aléatoires
```

- Documentation interactive de l'API : http://localhost:8000/docs
- Compte par défaut : `admin@nez.local` / `admin1234` (à changer dans `.env`)

Ensuite ouvre `ios/NezApp.xcodeproj` dans Xcode et lance l'app (▶).

## 1 bis. Interface web

```bash
cd web
npm install
npm run dev
```

Ouvre http://localhost:5173 (ou `http://IP-du-Mac:5173` depuis un autre appareil du Wi-Fi).
Pages : **Direct** (odeur reconnue, probabilités, radar, courbes, détections sur 24 h) · **Apprendre** (enregistrement, entraînement, matrice de confusion) · **Bibliothèque** · **Carte** satellite réelle (Esri) ou plan (CARTO / OpenStreetMap), avec placement des appareils par clic ou par géolocalisation du navigateur · **Alertes** · **Appareils**.

> La géolocalisation du navigateur ne fonctionne qu'en `https` ou sur `localhost`. Sur une adresse IP en `http`, place les appareils en cliquant sur la carte.

## 2. Version complète avec Docker

```bash
cp .env.example .env          # puis change les mots de passe
docker compose up -d --build
```

Services : **Mosquitto** (port 1883), **PostgreSQL + TimescaleDB + PostGIS** (5432), **backend** (8000), **interface web** servie par nginx sur http://localhost:8080.
Le simulateur peut alors passer par MQTT comme un vrai ESP32 :

```bash
pip install paho-mqtt
python3 simulator/simulate.py live --transport mqtt
```

## 3. Ouvrir le projet dans VS Code

```bash
code .
```

Le dossier `.vscode/` est déjà prêt :
- **Extensions conseillées** : Python, Pylance, PlatformIO, Docker, Swift.
- **Exécuter et déboguer (F5)** : « Backend FastAPI », « Simulateur : entraîner », « Simulateur : mesures en direct ».
- **Tâches** (⇧⌘P → *Run Task*) : installer le backend, lancer les tests, lancer Docker, ouvrir l'app dans Xcode.
- Tests : `cd backend && .venv/bin/python -m pytest -q`

## 4. Application iOS (Xcode)

1. Ouvre `ios/NezApp.xcodeproj`.
2. Cible **NezApp** → onglet *Signing & Capabilities* → choisis ton **Team** (compte Apple gratuit suffisant).
3. Choisis un simulateur ou ton iPhone, puis ▶.

**Sur un vrai iPhone :**
- Active le **mode développeur** : Réglages → Confidentialité et sécurité → Mode développeur.
- Au premier lancement : Réglages → Général → **VPN et gestion de l'appareil** → ton compte développeur → **Faire confiance**.
- Dans l'app, l'adresse du serveur est l'IP du Mac sur le Wi-Fi, par exemple `http://192.168.1.50:8000` (le téléphone et le Mac doivent être sur le même réseau).
- Avec un compte Apple gratuit, l'app doit être réinstallée depuis Xcode tous les 7 jours.

**Carte olfactive réelle** : vue satellite / hybride en relief (Apple Plans), position GPS du téléphone, détections regroupées par lieu. Chaque appareil se place à sa vraie position (toucher la carte ou GPS du téléphone), et ses anciennes détections peuvent le suivre. Le mode « Suivre la position de ce téléphone » met à jour la position d'un nez porté en marchant, pour cartographier un quartier.

Écrans : **Direct** (odeur reconnue, probabilités, empreinte radar, courbes) · **Apprendre** (enregistrer une odeur, entraîner le modèle, matrice de confusion) · **Bibliothèque** (odeurs, empreintes, création) · **Carte** olfactive · **Alertes** · **Réglages** (appareils, calibration, position).

## 5. Matériel et firmware ESP32

Câblage (I2C sur SDA = GPIO 8, SCL = GPIO 9) :

| Composant | Branchement |
|---|---|
| BME688, SGP41, ENS160, ADS1115, OLED | I2C (3,3 V, GND, SDA, SCL) |
| MQ-3 / MQ-4 / MQ-135 | 5 V, GND, sortie → **pont diviseur 10 kΩ / 20 kΩ** → ADS1115 A0 / A1 / A2 |
| Ventilateur 5 V | via transistor / MOSFET sur GPIO 10 |
| LED RGB | GPIO 4 / 5 / 6 (avec résistances 220 Ω) |
| Buzzer | GPIO 7 |

```bash
cd firmware
cp include/config.example.h include/config.h   # Wi-Fi, IP du serveur MQTT, capteurs présents
pio run -t upload && pio device monitor
```

Topics MQTT :

| Topic | Sens | Contenu |
|---|---|---|
| `nose/{id}/raw` | ESP32 → serveur | mesures brutes (1 par seconde) |
| `nose/{id}/status` | ESP32 → serveur | online / offline (Last Will) |
| `nose/{id}/cmd` | serveur → ESP32 | `calibrate`, `learn`, `learn_done`, `identify`, `reboot` |
| `nose/{id}/prediction` | serveur → ESP32 | odeur reconnue → écran OLED, LED, buzzer |

⚠️ Les capteurs MQ demandent **24 à 48 h de rodage** la première fois, puis ~3 min de chauffe à chaque démarrage.

## 6. Comment marche la reconnaissance

1. **Fenêtre glissante** de 10 mesures (une prédiction toutes les 5 mesures).
2. **Référence d'air propre** : la première fenêtre calibre l'appareil, puis elle suit lentement la dérive quand l'air est reconnu comme propre.
3. **Empreinte** : pour chaque capteur de gaz, l'écart relatif à la référence (moyenne, pente, pic), plus la température et l'humidité. Soit 23 caractéristiques.
4. **Random Forest** (scikit-learn, 200 arbres). La précision est mesurée par **validation croisée**.
5. Sous **70 % de confiance**, la réponse est « Odeur inconnue ».
6. Chaque odeur reconnue (hors air ambiant) devient une **détection** horodatée et géolocalisée. Selon son niveau d'alerte, elle crée aussi une **alerte** (WebSocket, Telegram en option).
7. **Alertes par règles**, indépendantes du ML : méthane (MQ-4) au-dessus de 2,5 V, indice COV au-dessus de 400.

> Le simulateur produit des odeurs très distinctes, d'où une précision proche de 100 %. Avec de vrais capteurs, attends-toi à moins : collecte **30 à 50 échantillons par odeur**, à différents moments et niveaux d'humidité, et réentraîne régulièrement.

## 7. API (résumé)

| Méthode | Route | Rôle |
|---|---|---|
| POST | `/api/auth/login` | connexion → jeton JWT |
| GET/PATCH | `/api/devices[/{id}]` | appareils (nom, pièce, position) |
| POST | `/api/devices/{id}/calibrate` | nouvelle référence d'air propre |
| GET | `/api/devices/{id}/measurements` | historique des mesures |
| GET/POST/PATCH/DELETE | `/api/odors` | bibliothèque d'odeurs |
| POST | `/api/training/sessions` | démarrer l'enregistrement d'une odeur |
| GET/POST | `/api/model`, `/api/model/train` | état du modèle / entraînement |
| GET | `/api/detections`, `/api/detections/near` | carte olfactive (PostGIS) |
| GET | `/api/stats` | statistiques |
| GET/POST | `/api/alerts`, `/api/alerts/{id}/ack` | alertes |
| POST | `/api/ingest/{device_id}` | envoi de mesures en HTTP (clé `X-Ingest-Key`) |
| WS | `/ws?token=…` | temps réel : reading, prediction, detection, alert, training_progress |

## ⚠️ Sécurité

Ce système **ne remplace pas un détecteur de gaz ou de monoxyde de carbone certifié**. Il donne une alerte précoce complémentaire.
