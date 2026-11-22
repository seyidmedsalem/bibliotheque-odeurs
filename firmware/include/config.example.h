// Copie ce fichier en "config.h" puis remplis tes valeurs.
// config.h est ignoré par Git : tes mots de passe ne seront jamais publiés.
#pragma once

// ---------- Réseau ----------
#define WIFI_SSID       "MonWiFi"
#define WIFI_PASSWORD   "motdepasse"

// ---------- MQTT (adresse IP de l'ordinateur / Raspberry Pi qui fait tourner Docker) ----------
#define MQTT_HOST       "192.168.1.50"
#define MQTT_PORT       1883
#define MQTT_USER       "nez"
#define MQTT_PASSWORD   "change-moi"

// ---------- Identité de l'appareil ----------
#define DEVICE_ID       "nez-cuisine"

// ---------- Capteurs présents (1 = branché, 0 = absent) ----------
#define USE_BME688      1
#define USE_SGP41       1
#define USE_ENS160      0
#define USE_ADS1115     1   // capteurs MQ via ADS1115
#define USE_OLED        1
#define USE_GPS         0
#define USE_RGB_LED     1
#define USE_BUZZER      1

// ---------- Brochage ----------
#define PIN_SDA         8
#define PIN_SCL         9
#define PIN_FAN         10  // via transistor / MOSFET
#define PIN_LED_R       4
#define PIN_LED_G       5
#define PIN_LED_B       6
#define PIN_BUZZER      7
#define PIN_GPS_RX      17
#define PIN_GPS_TX      18

// Voies de l'ADS1115 pour les capteurs MQ (-1 = non utilisé)
#define ADS_CH_MQ3      0
#define ADS_CH_MQ4      1
#define ADS_CH_MQ135    2

// Pont diviseur : 10 kΩ (haut) + 20 kΩ (bas) → 5 V devient 3,33 V. Ratio = (10+20)/20
#define MQ_DIVIDER_RATIO 1.5f

// ---------- Temps ----------
#define SAMPLE_PERIOD_MS 1000   // une mesure par seconde
#define WARMUP_SECONDS   180    // chauffe des capteurs MQ avant les mesures fiables

// Position fixe si pas de GPS (laisser 0 pour la régler depuis l'application web)
#define FIXED_LAT       0.0
#define FIXED_LON       0.0
