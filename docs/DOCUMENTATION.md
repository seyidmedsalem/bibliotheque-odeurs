# Documentation complète — La bibliothèque des odeurs

**Nez électronique IoT** · Projet de **Seyid Cheikh**

Ce document explique chaque partie du projet : à quoi elle sert, comment elle fonctionne et comment les parties communiquent entre elles. Il est écrit pour être lu du début à la fin, mais chaque section peut aussi se lire seule.

---

## Sommaire

1. [Le projet en une page](#1-le-projet-en-une-page)
2. [Architecture générale](#2-architecture-générale)
3. [Organisation des dossiers](#3-organisation-des-dossiers)
4. [Le matériel](#4-le-matériel)
5. [Le firmware ESP32](#5-le-firmware-esp32)
6. [La communication MQTT](#6-la-communication-mqtt)
7. [Le backend (serveur Python)](#7-le-backend-serveur-python)
8. [La base de données](#8-la-base-de-données)
9. [Le machine learning](#9-le-machine-learning)
10. [L'API REST et le WebSocket](#10-lapi-rest-et-le-websocket)
11. [Le simulateur](#11-le-simulateur)
12. [L'application iPhone (SwiftUI)](#12-lapplication-iphone-swiftui)
13. [L'interface web (React)](#13-linterface-web-react)
14. [Déploiement avec Docker](#14-déploiement-avec-docker)
15. [Sécurité](#15-sécurité)
16. [Tests](#16-tests)
17. [Guide de démarrage pas à pas](#17-guide-de-démarrage-pas-à-pas)
18. [Dépannage](#18-dépannage)
19. [Limites et améliorations possibles](#19-limites-et-améliorations-possibles)
20. [Glossaire](#20-glossaire)

---

## 1. Le projet en une page

**L'idée.** L'odorat est le sens le moins utilisé en IoT. Ce projet construit un **nez électronique** : plusieurs capteurs de gaz mesurent l'air en continu. Chaque odeur fait réagir les capteurs d'une manière différente, ce qui forme une **empreinte olfactive**. Un modèle de **machine learning** apprend à associer chaque empreinte à une odeur (café, pain brûlé, poubelle, fruit trop mûr, fuite de gaz, produit chimique…).

**Ce que fait le système :**

| Fonction | Exemple |
|---|---|
| Mesurer l'air | 1 mesure par seconde sur 7 capteurs de gaz + température + humidité |
| Apprendre une odeur | « Je présente du café pendant 60 s » → 12 échantillons étiquetés « Café » |
| Reconnaître une odeur | « Fuite de gaz, 99 % de confiance » |
| Archiver | Chaque détection est horodatée et géolocalisée |
| Cartographier | Carte olfactive réelle (satellite) de la maison ou du quartier |
| Alerter | Bandeau dans l'app, notification Telegram |

**Les technologies :**

| Partie | Technologie |
|---|---|
| Matériel | ESP32-S3, Bosch BME688, Sensirion SGP41, ScioSense ENS160, MQ-3 / MQ-4 / MQ-135, ADS1115 |
| Firmware | C++ (Arduino) avec PlatformIO |
| Communication | Wi-Fi + MQTT (broker Mosquitto), messages JSON |
| Backend | Python, FastAPI, SQLAlchemy, aiomqtt, WebSocket, JWT |
| Base de données | PostgreSQL + TimescaleDB + PostGIS (SQLite en développement) |
| Machine learning | scikit-learn (Random Forest), NumPy |
| App mobile | Swift, SwiftUI, Swift Charts, MapKit, CoreLocation |
| Interface web | React, TypeScript, Vite, Recharts, Leaflet |
| Déploiement | Docker Compose, nginx |

---

## 2. Architecture générale

```
┌─────────────────┐   I2C / ADC   ┌──────────────┐   Wi-Fi + MQTT   ┌─────────────┐
│ Capteurs de gaz │ ────────────▶ │   ESP32-S3   │ ───────────────▶ │  Mosquitto  │
│ + temp./humidité│               │  (firmware)  │ ◀─────────────── │ (broker)    │
└─────────────────┘               └──────────────┘   commandes      └──────┬──────┘
                                     écran OLED,                            │ abonnement
                                     LED, buzzer                            ▼
                                                              ┌──────────────────────────┐
                                                              │   Backend FastAPI        │
                                                              │  • traitement des mesures│
                                                              │  • machine learning      │
                                                              │  • API REST + WebSocket  │
                                                              └─────┬──────────────┬─────┘
                                                                    │              │ temps réel
                                                     ┌──────────────▼───┐   ┌──────▼──────────────────┐
                                                     │ PostgreSQL       │   │ App iPhone (SwiftUI)    │
                                                     │ TimescaleDB      │   │ Interface web (React)   │
                                                     │ PostGIS          │   └─────────────────────────┘
                                                     └──────────────────┘
```

**Le trajet d'une mesure, étape par étape :**

1. L'**ESP32** lit tous les capteurs, chaque seconde.
2. Il publie un message JSON sur le topic MQTT `nose/<appareil>/raw`.
3. **Mosquitto** (le broker) transmet ce message au backend, abonné à `nose/+/raw`.
4. Le **backend** enregistre la mesure dans la base, puis l'ajoute à une fenêtre glissante de 10 mesures.
5. Toutes les 5 mesures, il calcule l'**empreinte** de la fenêtre et demande au **modèle** quelle odeur c'est.
6. Le résultat part vers les applications par **WebSocket**, et vers l'ESP32 par MQTT (`nose/<appareil>/prediction`) pour l'écran OLED et la LED.
7. Si l'odeur est nouvelle, une **détection** est enregistrée (avec la date et la position). Si l'odeur est dangereuse, une **alerte** est créée.

---

## 3. Organisation des dossiers

```
bibliotheque-odeurs/
├── firmware/              Programme de l'ESP32 (C++)
│   ├── platformio.ini     Carte, bibliothèques
│   ├── include/config.example.h   Wi-Fi, MQTT, brochage (à copier en config.h)
│   └── src/main.cpp       Lecture des capteurs, MQTT, écran, LED
├── backend/               Serveur Python
│   ├── app/
│   │   ├── main.py        Point d'entrée, démarrage, WebSocket, données initiales
│   │   ├── config.py      Réglages (variables d'environnement)
│   │   ├── db.py          Connexion à la base, TimescaleDB, PostGIS
│   │   ├── models.py      Tables de la base
│   │   ├── schemas.py     Formats JSON de l'API
│   │   ├── security.py    Mots de passe, jetons JWT
│   │   ├── features.py    Calcul de l'empreinte olfactive
│   │   ├── ml.py          Modèle Random Forest
│   │   ├── processing.py  Cœur : traitement de chaque mesure
│   │   ├── hub.py         MQTT, WebSocket, Telegram
│   │   └── routers/       Routes de l'API (auth, appareils, odeurs, apprentissage, carte/alertes)
│   ├── tests/test_api.py  Tests de bout en bout
│   ├── requirements.txt   Bibliothèques Python
│   └── Dockerfile
├── simulator/simulate.py  Faux nez électronique pour tester sans matériel
├── ios/                   App iPhone (Xcode)
│   ├── NezApp.xcodeproj
│   └── NezApp/
│       ├── NezApp.swift   Point d'entrée, onglets, bandeau d'alerte
│       ├── Core/          Thème, modèles, client API, WebSocket, GPS, état global
│       └── Views/         Écrans (Direct, Apprendre, Bibliothèque, Carte, Alertes, Réglages)
├── web/                   Interface web
│   ├── src/
│   │   ├── main.tsx       Point d'entrée, menu, routes
│   │   ├── api.ts         Types et appels à l'API
│   │   ├── store.tsx      État global + WebSocket
│   │   ├── styles.css     Style « parfumerie nocturne »
│   │   ├── components/ui.tsx   Radar, anneau de confiance, cartes…
│   │   └── pages/         Pages (Login, Dashboard, Learn, Library, MapPage, Alerts, Devices)
│   ├── nginx.conf, Dockerfile
├── mosquitto/config/mosquitto.conf
├── docker-compose.yml     Lance tout le serveur
├── .env.example           Mots de passe et réglages (à copier en .env)
├── .vscode/               Configuration VS Code (lancement, tâches, extensions)
└── docs/                  Cette documentation + la présentation PDF
```

---

## 4. Le matériel

### 4.1 Pourquoi plusieurs capteurs ?

Un seul capteur de gaz réagit à beaucoup de gaz à la fois : il ne peut pas distinguer le café de l'alcool. L'astuce d'un nez électronique est de combiner **plusieurs capteurs qui réagissent différemment**. C'est la *combinaison* de leurs réactions qui identifie l'odeur, comme les centaines de types de récepteurs de notre nez.

### 4.2 Les composants

| Composant | Rôle | Pourquoi ce choix |
|---|---|---|
| **ESP32-S3 DevKit** | Le cerveau : lit les capteurs, se connecte au Wi-Fi | Wi-Fi intégré, puissant, peut faire tourner un petit modèle ML (TinyML) |
| **Bosch BME688** | Gaz (résistance en ohms), température, humidité, pression | Conçu par Bosch pour la classification d'odeurs |
| **Sensirion SGP41** | Indice COV (composés organiques volatils) et indice NOx | Très stable, compensé en humidité |
| **ScioSense ENS160** (option) | COV totaux, eCO₂ | Plusieurs éléments sensibles |
| **MQ-3** | Alcool / éthanol | Fruit trop mûr, fermentation |
| **MQ-4** | Méthane | Fuite de gaz de ville |
| **MQ-135** | Ammoniac, benzène | Poubelle, air vicié |
| **ADS1115** | Convertisseur analogique → numérique 16 bits | Le convertisseur de l'ESP32 est imprécis |
| Ventilateur 5 V | Aspire l'air de façon régulière | Mesures reproductibles |
| OLED, LED RGB, buzzer | Affichage et alertes sur l'appareil | Le nez est utile même sans téléphone |

### 4.3 Câblage

```
                 ESP32-S3
              ┌────────────┐
   3,3 V ─────┤ 3V3        │
   GND   ─────┤ GND        │
   SDA   ─────┤ GPIO 8     ├──── BME688, SGP41, ENS160, ADS1115, OLED (bus I2C partagé)
   SCL   ─────┤ GPIO 9     │
   Vent. ─────┤ GPIO 10    ├──── transistor / MOSFET → ventilateur 5 V
   LED   ─────┤ GPIO 4/5/6 ├──── LED RGB (résistances 220 Ω)
   Buzz. ─────┤ GPIO 7     │
              └────────────┘

   Capteur MQ (alimenté en 5 V)
   sortie A0 ──[10 kΩ]──┬──── entrée ADS1115 (A0, A1 ou A2)
                       [20 kΩ]
                        │
                       GND
```

**Le pont diviseur.** Les capteurs MQ sortent jusqu'à 5 V, mais l'ADS1115 alimenté en 3,3 V ne doit pas recevoir plus de 3,3 V. Les deux résistances divisent la tension : `V_sortie = V_MQ × 20 / (10 + 20) = V_MQ × 0,667`. Le firmware remultiplie par 1,5 pour retrouver la vraie tension du capteur.

### 4.4 Précautions

- Les MQ chauffent (environ 150 mA chacun) : il faut une **alimentation 5 V / 3 A**.
- **Rodage de 24 à 48 h** la toute première fois, puis environ 3 minutes de chauffe à chaque démarrage. Le firmware signale cette chauffe (`warming: true`) et le serveur ignore ces mesures.
- Une **chambre de mesure** fermée avec le ventilateur rend les mesures beaucoup plus fiables qu'à l'air libre.

---

## 5. Le firmware ESP32

Fichier principal : `firmware/src/main.cpp`. Réglages : `firmware/include/config.h` (copie de `config.example.h`).

### 5.1 Ce que fait le programme

```
setup()
 ├─ crée les noms des topics : nose/<id>/raw, /status, /cmd, /prediction
 ├─ allume le ventilateur
 ├─ initSensors() : démarre chaque capteur présent (BME688, SGP41, ENS160, ADS1115, OLED, GPS)
 ├─ connectWifi()
 └─ configure MQTT (serveur, taille des messages, fonction de réception)

loop()  (tourne en continu)
 ├─ reconnecte le Wi-Fi ou MQTT si besoin (toutes les 5 s)
 ├─ mqtt.loop() : traite les messages reçus
 ├─ lit le GPS si présent
 └─ toutes les 1000 ms : sampleAndPublish()
```

### 5.2 `sampleAndPublish()` : une mesure

1. Calcule si l'appareil est encore en chauffe (`WARMUP_SECONDS`).
2. **BME688** : `performReading()` donne la résistance du gaz (en ohms ; elle *baisse* quand il y a des COV), la température, l'humidité et la pression.
3. **SGP41** : les 10 premières secondes servent au « conditionnement » du capteur. Ensuite il donne deux signaux bruts, transformés en **indices** (0–500) par l'algorithme officiel de Sensirion. Un indice de 100 correspond à « l'air habituel ». Le capteur reçoit la température et l'humidité pour se compenser.
4. **ENS160** (option) : COV totaux et eCO₂, compensés en température et humidité.
5. **MQ** via l'ADS1115 : lecture en volts, multipliée par 1,5 (pont diviseur).
6. Position : GPS si présent, sinon une position fixe de `config.h`, sinon rien (la position se règle alors depuis l'app).
7. Envoie le JSON sur `nose/<id>/raw`.

### 5.3 Messages reçus

| Topic | Contenu | Réaction |
|---|---|---|
| `nose/<id>/prediction` | `{label, confidence, color, alert_level}` | Affiche l'odeur sur l'OLED, colore la LED, 3 bips si danger |
| `nose/<id>/cmd` `calibrate` | — | Affiche « Calibrage », LED bleue |
| `nose/<id>/cmd` `learn` | `{odor}` | Affiche « Apprendre » + le nom de l'odeur, LED violette |
| `nose/<id>/cmd` `learn_done` | — | « Appris ! », LED verte, 2 bips |
| `nose/<id>/cmd` `identify` | — | Fait clignoter la LED (pour reconnaître l'appareil) |
| `nose/<id>/cmd` `reboot` | — | Redémarre l'ESP32 |

### 5.4 « Last Will » (dernière volonté)

À la connexion MQTT, l'ESP32 déclare un message « offline » au broker. Si l'appareil disparaît brutalement (coupure de courant), **le broker publie ce message lui-même**, et le serveur sait tout de suite que l'appareil est hors ligne.

### 5.5 Compiler et téléverser

```bash
cd firmware
cp include/config.example.h include/config.h   # puis remplir Wi-Fi, IP du serveur, capteurs présents
pio run -t upload
pio device monitor
```

Avec VS Code, l'extension **PlatformIO** fournit les mêmes boutons (✓ compiler, → téléverser).

---

## 6. La communication MQTT

**MQTT** est le protocole standard de l'IoT. Les appareils ne se parlent pas directement : ils passent par un **broker** (ici Mosquitto). On **publie** des messages sur des **topics** (des « canaux » nommés), et on **s'abonne** aux topics qui nous intéressent.

### 6.1 Les topics

| Topic | Qui publie | Qui écoute | Contenu |
|---|---|---|---|
| `nose/<id>/raw` | ESP32 | backend | Mesures (1 par seconde) |
| `nose/<id>/status` | ESP32 (+ broker pour le Last Will) | backend | `online` / `offline` |
| `nose/<id>/cmd` | backend | ESP32 | Commandes |
| `nose/<id>/prediction` | backend | ESP32 | Odeur reconnue |

Le `+` dans `nose/+/raw` est un joker : le backend reçoit les mesures de **tous** les appareils.

### 6.2 Exemple de message

```json
{
  "device": "nez-cuisine", "warming": false,
  "bme688_gas": 48211, "pressure": 1013.2,
  "sgp41_voc": 132, "sgp41_nox": 1,
  "mq3": 0.82, "mq4": 0.41, "mq135": 1.37,
  "temp": 22.4, "hum": 48.1
}
```

### 6.3 Alternative HTTP

Pour tester sans broker, ou pour un appareil sans MQTT, les mesures peuvent aussi arriver par `POST /api/ingest/<id>`, avec l'en-tête `X-Ingest-Key`. Le traitement est exactement le même.

---

## 7. Le backend (serveur Python)

Le backend est écrit avec **FastAPI**, un framework web Python moderne, rapide, qui génère automatiquement la documentation de l'API (http://localhost:8000/docs).

### 7.1 Démarrage (`main.py`)

Au lancement, la fonction `lifespan` :

1. crée les tables (`init_db`) et active TimescaleDB / PostGIS si on utilise PostgreSQL ;
2. crée le compte administrateur et les 7 odeurs de départ (`seed`) ;
3. charge le modèle ML s'il existe déjà ;
4. démarre la boucle MQTT en tâche de fond.

`main.py` définit aussi `/api/health`, `/api/ingest/<id>` et le WebSocket `/ws`.

### 7.2 Configuration (`config.py`)

Tous les réglages viennent de **variables d'environnement** (ou du fichier `.env`), avec des valeurs par défaut pour le développement. Les plus importants :

| Réglage | Défaut | Rôle |
|---|---|---|
| `DATABASE_URL` | SQLite local | Base de données |
| `MQTT_HOST`, `MQTT_USER`, `MQTT_PASSWORD` | localhost | Broker |
| `JWT_SECRET` | à changer ! | Signature des jetons de connexion |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | admin@nez.local / admin1234 | Compte créé au démarrage |
| `WINDOW_SIZE`, `WINDOW_STEP` | 10, 5 | Taille de la fenêtre et fréquence des prédictions |
| `CONFIDENCE_THRESHOLD` | 0,7 | En dessous : « odeur inconnue » |
| `DETECTION_COOLDOWN_S` | 30 | Pas deux détections identiques en moins de 30 s |
| `MQ4_DANGER_VOLTS`, `VOC_WARNING_INDEX` | 2,5 V, 400 | Seuils des alertes par règles |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | vide | Notifications Telegram (option) |

### 7.3 Le cœur : `processing.py`

La classe `Processor` reçoit **chaque mesure** et décide quoi en faire. Elle est volontairement **synchrone et sans réseau** : elle *retourne* des événements (pour le WebSocket) et des messages MQTT (pour l'ESP32). C'est le `Hub` qui les envoie. Cela la rend simple à tester.

Pour chaque appareil, elle garde en mémoire un `DeviceState` : la fenêtre des 10 dernières mesures, un compteur, la dernière détection et la dernière prédiction.

**`handle_reading()`, étape par étape :**

```
mesure reçue
  │
  ├─ 1. Enregistrer l'appareil (créé automatiquement s'il est nouveau), mettre à jour « vu à »
  ├─ 2. Stocker la mesure brute (table measurements)
  ├─ 3. En chauffe ? → s'arrêter là
  ├─ 4. Ajouter à la fenêtre ; attendre 10 mesures, puis traiter toutes les 5 mesures
  │
  ├─ 5. Pas de référence d'air propre (ou calibration demandée) ?
  │      → la fenêtre devient la RÉFÉRENCE (baseline) → fin
  │
  ├─ 6. Calculer l'empreinte (features.py)
  │
  ├─ 7. Session d'apprentissage active pour cet appareil ?
  │      → enregistrer un ÉCHANTILLON étiqueté → fin
  │
  ├─ 8. Alertes par règles (méthane trop haut, COV trop haut)
  │
  └─ 9. Prédiction par le modèle
         ├─ confiance < 70 % → « Odeur inconnue »
         ├─ « Air ambiant » → adapter doucement la référence (dérive des capteurs)
         └─ autre odeur, nouvelle → DÉTECTION (date + position + pièce)
                                    └─ niveau d'alerte ≠ aucun → ALERTE
```

**La référence d'air propre suit la dérive.** Les capteurs de gaz dérivent avec le temps (vieillissement, saison). Quand le modèle reconnaît de l'air propre, la référence est ajustée par une **moyenne mobile exponentielle** : `nouvelle = 0,9 × ancienne + 0,1 × mesure`. Sans modèle, l'ajustement est plus lent (0,02).

### 7.4 Le Hub (`hub.py`)

Il relie le monde **asynchrone** (réseau) au `Processor` **synchrone** :

- **MQTT** : `mqtt_loop()` reste connecté au broker, s'abonne à `nose/+/raw` et `nose/+/status`, et se reconnecte toutes les 5 s en cas de coupure.
- **Traitement** : le `Processor` tourne dans un thread séparé (`asyncio.to_thread`), pour ne jamais bloquer le serveur.
- **WebSocket** : `broadcast()` envoie chaque événement à toutes les applications connectées. Un client qui vient de se connecter reçoit tout de suite les dernières prédictions.
- **Telegram** : chaque alerte est envoyée au bot si les réglages sont remplis.

### 7.5 Sécurité (`security.py`)

- Les mots de passe sont **hachés avec bcrypt** (on ne stocke jamais le mot de passe lui-même).
- La connexion renvoie un **jeton JWT** signé, valable 7 jours. Il est envoyé dans l'en-tête `Authorization: Bearer …`.
- `current_user` est une dépendance FastAPI qui refuse (erreur 401) toute requête sans jeton valide.

### 7.6 Les routes (`routers/`)

| Fichier | Rôle |
|---|---|
| `auth.py` | Connexion, profil |
| `devices.py` | Appareils : liste, modification (nom, pièce, position), historique, calibration, identification |
| `odors.py` | Bibliothèque : liste avec empreinte moyenne et statistiques, création, modification, suppression |
| `training.py` | Sessions d'apprentissage, entraînement et état du modèle |
| `detections.py` | Détections, recherche autour d'un point (PostGIS), statistiques, alertes |

**Déplacer l'historique.** Quand on donne sa vraie position à un appareil avec `move_history: true`, ses anciennes détections faites à l'ancienne position le suivent. Cela corrige toute la carte d'un coup.

---

## 8. La base de données

### 8.1 Les tables

| Table | Contenu |
|---|---|
| `users` | Comptes (e-mail, mot de passe haché) |
| `devices` | Appareils : nom, pièce, position, état, dernière activité, **référence d'air propre** |
| `odors` | Bibliothèque : nom, emoji, couleur, niveau d'alerte, description, `is_air` |
| `measurements` | Mesures brutes (date, appareil, valeurs en JSON) |
| `training_sessions` | Sessions d'apprentissage (odeur, appareil, objectif, progression, statut) |
| `training_samples` | Empreintes étiquetées (vecteur de 23 nombres + empreinte lisible) |
| `detections` | Odeurs reconnues : date, appareil, odeur, confiance, latitude, longitude, pièce |
| `alerts` | Alertes : niveau, titre, message, lue ou non |

### 8.2 Les extensions PostgreSQL

- **TimescaleDB** transforme `measurements` en **hypertable** : la table est découpée automatiquement par périodes de temps. Avec une mesure par seconde et par appareil (86 400 par jour), les requêtes restent rapides. Une **politique de rétention** supprime les mesures brutes de plus de 90 jours.
- **PostGIS** ajoute à `detections` une colonne géographique `geom`, calculée automatiquement à partir de la latitude et de la longitude, avec un index spatial. La route `/api/detections/near` l'utilise pour trouver les détections dans un rayon donné (`ST_DWithin`).

En développement, **SQLite** suffit : le code détecte la base utilisée et ne crée les extensions qu'avec PostgreSQL. La recherche autour d'un point utilise alors la formule de haversine en Python.

---

## 9. Le machine learning

### 9.1 Pourquoi ne pas utiliser les valeurs brutes ?

Les valeurs brutes changent avec la température, l'humidité, l'usure du capteur et même d'un capteur à l'autre. Un modèle entraîné sur des valeurs brutes serait faux le lendemain. On mesure donc **l'écart par rapport à l'air propre**, qui reste comparable dans le temps.

### 9.2 L'empreinte olfactive (`features.py`)

Pour une fenêtre de 10 mesures et chacun des 7 capteurs de gaz :

```
écart relatif  r(t) = (valeur(t) − référence) / |référence|

moyenne = moyenne des r(t)                → intensité de la réaction
pente   = pente de la droite de r(t) × 10 → l'odeur monte ou descend ?
pic     = r(t) le plus éloigné de 0       → réaction maximale
```

On obtient 7 × 3 = 21 nombres, plus la température et l'humidité moyennes : un **vecteur de 23 caractéristiques**. Les *moyennes* forment aussi l'**empreinte lisible** affichée en radar dans les applications.

Exemple : pour le café, le BME688 baisse (résistance −45 %), le COV monte, et le MQ-135 monte (+60 %). Pour une fuite de gaz, c'est surtout le MQ-4 qui monte (×7).

### 9.3 Le modèle (`ml.py`)

- **Normalisation** (`StandardScaler`) : met toutes les caractéristiques à la même échelle.
- **Random Forest** de 200 arbres de décision : chaque arbre « vote » pour une odeur, la forêt donne la **probabilité** de chaque odeur. Ce modèle est robuste, rapide, et marche bien avec peu de données.
- `class_weight="balanced"` : une odeur avec moins d'échantillons n'est pas désavantagée.

### 9.4 L'entraînement

1. Il faut au moins **2 odeurs**, avec au moins **3 échantillons** chacune.
2. **Validation croisée** (jusqu'à 5 plis) : on entraîne sur une partie des données et on teste sur l'autre, plusieurs fois. La précision affichée est donc mesurée sur des données que le modèle n'a **jamais vues**. C'est une estimation honnête.
3. **Matrice de confusion** : pour chaque odeur réelle (ligne), combien de fois le modèle a prédit chaque odeur (colonne). Une diagonale bien remplie signifie un bon modèle. Les cases hors diagonale montrent les confusions.
4. **Importance des caractéristiques** : quelles mesures aident le plus à reconnaître les odeurs.
5. Le modèle final est entraîné sur toutes les données, puis sauvegardé (`model.joblib`).

### 9.5 La reconnaissance

- Le modèle donne une probabilité par odeur. La plus haute est retenue.
- Si elle est **inférieure à 70 %**, la réponse est « Odeur inconnue ». Il vaut mieux ne rien dire que se tromper.
- La classe **« Air ambiant »** est indispensable : sans elle, le modèle classerait l'air normal comme l'une des odeurs.

### 9.6 Le protocole d'apprentissage

1. Le nez se calibre seul sur ~10 s d'air propre.
2. Dans l'app, choisir l'odeur, puis « Démarrer l'enregistrement ».
3. Présenter l'odeur à environ 5 cm de la chambre de mesure.
4. Les **2 premières fenêtres sont ignorées** (le temps que l'odeur monte), puis chaque fenêtre devient un échantillon.
5. Recommencer à différents moments de la journée (humidité différente), avec **30 à 50 échantillons par odeur** pour de vrais capteurs.
6. Cliquer sur « Entraîner le modèle ».

### 9.7 Les alertes par règles

En plus du ML, deux règles simples déclenchent des alertes même sans modèle : méthane (MQ-4) au-dessus de 2,5 V, et indice COV au-dessus de 400. Chaque règle ne se redéclenche pas avant 5 minutes. C'est une sécurité qui ne dépend pas de l'apprentissage.

---

## 10. L'API REST et le WebSocket

La documentation interactive complète est sur http://localhost:8000/docs (Swagger). On peut y tester chaque route.

### 10.1 Routes principales

| Méthode | Route | Rôle |
|---|---|---|
| POST | `/api/auth/login` | Connexion → `{access_token}` |
| GET | `/api/auth/me` | Utilisateur connecté |
| GET | `/api/devices` | Liste des appareils (avec `online`, `calibrated`) |
| PATCH | `/api/devices/{id}` | Modifier nom, pièce, position (`move_history` option) |
| GET | `/api/devices/{id}/measurements?minutes=10` | Historique des mesures |
| POST | `/api/devices/{id}/calibrate` | Nouvelle référence d'air propre |
| POST | `/api/devices/{id}/identify` | Faire clignoter l'appareil |
| GET / POST | `/api/odors` | Bibliothèque / créer une odeur |
| PATCH / DELETE | `/api/odors/{id}` | Modifier / supprimer |
| POST | `/api/training/sessions` | Démarrer un enregistrement |
| GET | `/api/training/sessions/{id}` | Progression |
| POST | `/api/training/sessions/{id}/cancel` | Annuler |
| GET | `/api/model` | État du modèle, précision, matrice de confusion |
| POST | `/api/model/train` | Entraîner |
| GET | `/api/detections?hours=168&odor_id=…` | Détections |
| GET | `/api/detections/near?lat=…&lon=…&radius_m=500` | Détections autour d'un point |
| GET | `/api/stats` | Chiffres clés, par odeur, par pièce, sur 24 h |
| GET | `/api/alerts` | Alertes |
| POST | `/api/alerts/{id}/ack`, `/api/alerts/ack-all` | Marquer comme lue(s) |
| POST | `/api/ingest/{id}` | Envoyer une mesure en HTTP (clé `X-Ingest-Key`) |
| GET | `/api/health` | État du serveur, du MQTT, du modèle |

### 10.2 Le WebSocket `/ws?token=…`

Les applications ouvrent **une connexion permanente** et reçoivent des événements JSON au fil de l'eau, sans avoir à redemander :

| `type` | Quand | Contenu |
|---|---|---|
| `reading` | Chaque mesure | Valeurs des capteurs |
| `prediction` | Toutes les 5 mesures | Odeur, confiance, probabilités, empreinte |
| `detection` | Nouvelle odeur reconnue | Détection complète |
| `alert` | Nouvelle alerte | Alerte complète |
| `training_progress` | Chaque échantillon d'apprentissage | Progression de la session |
| `device` | Appareil en ligne / hors ligne | Appareil |
| `calibrated` | Nouvelle référence d'air | Référence |

---

## 11. Le simulateur

`simulator/simulate.py` remplace le matériel pour tout tester.

**Comment il imite un vrai nez :**
- une **référence** d'air propre pour chaque capteur ;
- un **profil** par odeur, qui multiplie ou ajoute aux valeurs (par exemple Fuite de gaz : MQ-4 × 7) ;
- une **montée progressive** de l'odeur (exponentielle), puis une descente ;
- du **bruit** (1,5 %), une **dérive lente** et un effet de l'humidité, comme de vrais capteurs.

**Modes :**

```bash
python simulate.py train                      # enregistre chaque odeur via l'API puis entraîne le modèle (~30 s)
python simulate.py live                       # mesures continues, odeurs aléatoires (HTTP)
python simulate.py live --transport mqtt      # comme un vrai ESP32, via le broker
python simulate.py live --odor "Café"         # toujours la même odeur
python simulate.py live --device nez-salon --room Salon   # un deuxième appareil
```

Par défaut, il n'envoie **pas de position** : on place l'appareil à sa vraie position depuis l'app. `--lat/--lon` permettent d'en forcer une.

> Les odeurs simulées sont très distinctes, d'où une précision proche de 100 %. Avec de vrais capteurs, la précision sera plus basse : c'est normal, et c'est justement le défi du projet.

---

## 12. L'application iPhone (SwiftUI)

Ouvrir `ios/NezApp.xcodeproj` dans Xcode. Cible : iOS 17 et plus.

### 12.1 Structure

| Fichier | Rôle |
|---|---|
| `NezApp.swift` | Point d'entrée : affiche la connexion ou les onglets, bandeau d'alerte, rafraîchissement au retour dans l'app |
| `Core/Theme.swift` | Couleurs, polices serif italiques, fond lumineux, cartes en verre, boutons |
| `Core/Models.swift` | Structures des données (Device, Odor, Detection, Prediction…) |
| `Core/APIClient.swift` | Appels HTTP (async/await), lecture des dates, messages d'erreur |
| `Core/LiveSocket.swift` | WebSocket avec reconnexion automatique et « ping » toutes les 20 s |
| `Core/LocationService.swift` | GPS du téléphone (CoreLocation) |
| `Core/AppStore.swift` | **État global** (`@Observable`) : données, temps réel, actions |
| `Views/DashboardView.swift` | Direct : odeur, probabilités, radar, courbes (Swift Charts) |
| `Views/LearnView.swift` | Apprendre : enregistrement, entraînement, matrice de confusion |
| `Views/LibraryView.swift` | Bibliothèque, fiche d'une odeur, éditeur |
| `Views/OdorMapView.swift` | Carte réelle (MapKit) et placement des appareils |
| `Views/AlertsView.swift` | Alertes |
| `Views/SettingsView.swift` | Réglages, appareils, position, « suivre mon téléphone » |
| `Views/Components.swift` | Radar, anneau de confiance, barres, tuiles… |

### 12.2 Fonctionnement

- **`AppStore`** est la source unique de vérité. Les vues l'observent : quand une donnée change (événement WebSocket), l'écran se met à jour tout seul.
- Le JSON du serveur est en `snake_case`. Le décodeur convertit les propriétés en `camelCase`, mais **pas les clés des dictionnaires** (`fingerprint`, `data`), qui restent `bme688_gas`, etc. C'est pourquoi l'énumération `Channel` utilise ces noms exacts.
- **Adresse du serveur** : sur un vrai iPhone, `localhost` désigne le téléphone lui-même. Il faut l'adresse IP du Mac (`http://192.168.x.x:8000`). L'app la propose automatiquement grâce au réglage de compilation `NEZ_DEFAULT_SERVER`, et affiche un message clair si on tape `localhost`.
- `NezApp-Info.plist` autorise le HTTP local (App Transport Security) et explique l'usage de la localisation.

### 12.3 La carte réelle

- Vue **satellite / hybride en relief** (Apple Plans), boussole, 3D, échelle, bouton « ma position ».
- Les détections sont **regroupées par lieu** : une bulle par endroit, avec l'odeur dominante et le nombre de détections.
- **Placer un appareil** : toucher la carte ou utiliser le GPS en étant à côté du nez.
- **Suivre la position de ce téléphone** : la position d'un nez porté en marchant est mise à jour tous les ~20 m (uniquement quand l'app est ouverte).

### 12.4 Installer sur un iPhone

1. Xcode → cible NezApp → *Signing & Capabilities* → choisir son **Team** (un compte Apple gratuit suffit).
2. Brancher l'iPhone, le choisir comme destination, puis ▶.
3. Sur l'iPhone : Réglages → Confidentialité et sécurité → **Mode développeur**. Puis Réglages → Général → **VPN et gestion de l'appareil** → faire confiance au compte.
4. Avec un compte gratuit, l'app doit être réinstallée tous les 7 jours.

---

## 13. L'interface web (React)

```bash
cd web && npm install && npm run dev     # http://localhost:5173
```

### 13.1 Structure

| Fichier | Rôle |
|---|---|
| `src/main.tsx` | Point d'entrée : menu latéral (barre du bas sur mobile), routes, bandeaux |
| `src/api.ts` | Types TypeScript des données, fonction `api()` (jeton, erreurs), dates relatives |
| `src/store.tsx` | État global (contexte React) : données, WebSocket avec reconnexion, actions |
| `src/styles.css` | Style « parfumerie nocturne », responsive |
| `src/components/ui.tsx` | Radar SVG, anneau de confiance, barres, tuiles, fenêtres, sélecteur d'appareil |
| `src/pages/Login.tsx` | Connexion |
| `src/pages/Dashboard.tsx` | Direct : odeur, probabilités, radar, courbe (Recharts), détections sur 24 h |
| `src/pages/Learn.tsx` | Apprendre : enregistrement, modèle, matrice, caractéristiques utiles |
| `src/pages/Library.tsx` | Bibliothèque, fiche, éditeur d'odeur |
| `src/pages/MapPage.tsx` | Carte réelle (Leaflet) : satellite Esri ou plan OpenStreetMap, placement des appareils |
| `src/pages/Alerts.tsx` | Alertes |
| `src/pages/Devices.tsx` | Appareils et état du serveur |

### 13.2 Fonctionnement

- En développement, **Vite** redirige `/api`, `/ws` et `/docs` vers le backend (port 8000) : l'interface et l'API ont la même adresse, donc pas de souci de sécurité entre domaines.
- En production, **nginx** fait la même chose (`web/nginx.conf`).
- Le jeton de connexion est gardé dans le navigateur (`localStorage`).
- La géolocalisation du navigateur ne fonctionne qu'en `https` ou sur `localhost`. Sur une adresse IP en `http`, on place les appareils en cliquant sur la carte.

---

## 14. Déploiement avec Docker

```bash
cp .env.example .env      # changer les mots de passe !
docker compose up -d --build
```

| Service | Image | Port | Rôle |
|---|---|---|---|
| `mosquitto` | eclipse-mosquitto | 1883 | Broker MQTT, mot de passe créé au démarrage |
| `db` | timescale/timescaledb-ha (inclut PostGIS) | 5432 | Base de données |
| `backend` | construit depuis `backend/` | 8000 | API, ML, MQTT, WebSocket |
| `web` | construit depuis `web/` (node → nginx) | 8080 | Interface web |

Les données sont gardées dans des **volumes** Docker (`db-data`, `model-data`, `mosquitto-data`) : elles survivent aux redémarrages.

**Où l'héberger ?** Sur l'ordinateur pour développer, sur un **Raspberry Pi** à la maison (allumé 24 h/24), ou sur un petit **serveur VPS** pour un accès depuis Internet (ajouter alors HTTPS, par exemple avec Caddy ou Traefik).

---

## 15. Sécurité

| Risque | Protection |
|---|---|
| Accès à l'API | Jeton JWT obligatoire sur toutes les routes (sauf connexion, santé et ingestion) |
| Mots de passe volés | Hachés avec bcrypt |
| Faux appareil qui envoie des mesures | MQTT avec mot de passe (`allow_anonymous false`), clé `X-Ingest-Key` pour l'HTTP |
| Secrets publiés sur GitHub | `.env` et `firmware/include/config.h` sont dans `.gitignore` |
| Écoute du réseau | Utiliser TLS (MQTT sur 8883, HTTPS) en production |
| Données de localisation | Stockées uniquement sur votre serveur |

> ⚠️ **Ce système ne remplace pas un détecteur de gaz ou de monoxyde de carbone certifié.** Il apporte une alerte précoce complémentaire.

**À faire avant une mise en ligne :** changer `JWT_SECRET`, `ADMIN_PASSWORD`, `MQTT_PASSWORD`, `INGEST_KEY`, `DB_PASSWORD`, et activer HTTPS.

---

## 16. Tests

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest -q
```

`tests/test_api.py` teste **tout le parcours** avec le simulateur et une base temporaire :

1. **Sécurité** : refus sans jeton, avec un mauvais mot de passe ou une mauvaise clé d'ingestion.
2. **Parcours complet** : calibration → apprentissage de 4 odeurs → entraînement (précision > 80 %) → présentation d'une fuite de gaz → détection géolocalisée → alerte danger → statistiques → bibliothèque → recherche autour d'un point → déplacement de l'historique vers une vraie position.
3. **Bibliothèque** : création, doublon refusé, modification, suppression, protection de « Air ambiant ».

---

## 17. Guide de démarrage pas à pas

**Sans matériel (5 minutes) :**

```bash
# 1. Backend
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
MQTT_ENABLED=false .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

```bash
# 2. Dans un autre terminal : entraîner puis simuler
cd simulator
python3 simulate.py train
python3 simulate.py live
```

```bash
# 3. Dans un autre terminal : l'interface web
cd web
npm install
npm run dev
```

4. Ouvrir http://localhost:5173 (identifiants : `admin@nez.local` / `admin1234`).
5. Optionnel : ouvrir `ios/NezApp.xcodeproj` dans Xcode et lancer l'app iPhone.

**Avec le matériel :**

1. Câbler (section 4.3), puis laisser roder les capteurs MQ 24 à 48 h.
2. Lancer le serveur avec Docker (section 14).
3. Remplir `firmware/include/config.h` (Wi-Fi, IP du serveur, mot de passe MQTT), puis téléverser.
4. Dans l'app, placer l'appareil à sa vraie position, enregistrer « Air ambiant » puis chaque odeur, et entraîner le modèle.

---

## 18. Dépannage

| Problème | Solution |
|---|---|
| « Serveur injoignable » sur iPhone | Utiliser l'IP du Mac (pas `localhost`), même Wi-Fi, autoriser le « réseau local » |
| L'app iPhone ne s'ouvre pas | Faire confiance au compte développeur (Réglages → Général → VPN et gestion de l'appareil) |
| Aucun appareil | Le backend tourne-t-il ? Le simulateur ou l'ESP32 envoie-t-il des mesures ? |
| « Appareil pas encore calibré » | Attendre ~10 s de mesures à l'air propre |
| L'entraînement est refusé | Il faut 2 odeurs (dont Air ambiant) avec 3 échantillons minimum chacune |
| Tout est « Odeur inconnue » | Plus d'échantillons, recalibrer à l'air propre, réentraîner |
| L'ESP32 ne se connecte pas à MQTT | Vérifier l'IP, le port 1883, l'utilisateur et le mot de passe dans `config.h` |
| Valeurs MQ incohérentes | Rodage pas terminé, pont diviseur mal câblé, alimentation trop faible |
| La carte web ne trouve pas ma position | Normal en `http` sur une IP : cliquer sur la carte pour placer l'appareil |

---

## 19. Limites et améliorations possibles

**Limites actuelles :**
- La précision réelle dépend beaucoup de la qualité des données collectées.
- Le mode « suivre mon téléphone » ne fonctionne que quand l'app est ouverte.
- Un seul compte utilisateur (l'administrateur).
- Le firmware n'a pas encore été testé sur le matériel réel.

**Améliorations :**
- **TinyML** : faire tourner le modèle directement sur l'ESP32 (Edge Impulse, TensorFlow Lite Micro) pour reconnaître les odeurs sans serveur.
- **Profils de chauffe du BME688** : faire varier la température du capteur donne une empreinte beaucoup plus riche (Bosch BME AI-Studio).
- **Réentraînement automatique** et détection de la dérive.
- **Notifications push** iPhone, widget, Apple Watch.
- **Plusieurs utilisateurs** et partage de cartes olfactives (quartier, école, bureau).
- **HTTPS et MQTT TLS** pour un déploiement sur Internet.

---

## 20. Glossaire

| Terme | Définition |
|---|---|
| **COV** | Composés organiques volatils : molécules qui s'évaporent facilement (parfums, solvants, aliments) |
| **Empreinte olfactive** | La façon dont l'ensemble des capteurs réagit à une odeur |
| **Référence (baseline)** | Valeurs des capteurs dans l'air propre, point de comparaison |
| **Dérive** | Changement lent des capteurs avec le temps |
| **Fenêtre glissante** | Les N dernières mesures, analysées ensemble |
| **MQTT** | Protocole léger de messages pour l'IoT, basé sur publier / s'abonner |
| **Broker** | Serveur MQTT qui distribue les messages (Mosquitto) |
| **Topic** | « Canal » MQTT nommé, par exemple `nose/nez-cuisine/raw` |
| **API REST** | Interface du serveur accessible par des adresses web (GET, POST…) |
| **WebSocket** | Connexion permanente qui permet au serveur d'envoyer des données en temps réel |
| **JWT** | Jeton signé qui prouve qu'on est connecté |
| **Random Forest** | Modèle de ML composé de nombreux arbres de décision qui votent |
| **Validation croisée** | Méthode pour mesurer la précision sur des données jamais vues |
| **Matrice de confusion** | Tableau qui montre quelles odeurs le modèle confond |
| **Hypertable** | Table TimescaleDB découpée automatiquement par périodes de temps |
| **PostGIS** | Extension PostgreSQL pour les données géographiques |
| **I2C** | Bus à 2 fils pour connecter plusieurs capteurs à un microcontrôleur |
| **ADC** | Convertisseur analogique → numérique |
| **TinyML** | Machine learning sur microcontrôleur |
