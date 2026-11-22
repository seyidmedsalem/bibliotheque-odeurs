/*
 * La bibliothèque des odeurs - firmware du nez électronique (ESP32 / ESP32-S3)
 * Auteur : Seyid Cheikh
 *
 * Toutes les secondes : lit les capteurs de gaz + température/humidité et publie
 * un JSON sur  nose/<id>/raw.  Écoute  nose/<id>/cmd  (calibration, apprentissage...)
 * et  nose/<id>/prediction  (odeur reconnue par le serveur → écran, LED, buzzer).
 */
#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "config.h"

#if USE_BME688
#include <Adafruit_BME680.h>
Adafruit_BME680 bme;
bool bmeOk = false;
#endif

#if USE_SGP41
#include <SensirionI2CSgp41.h>
#include <VOCGasIndexAlgorithm.h>
#include <NOxGasIndexAlgorithm.h>
SensirionI2CSgp41 sgp41;
VOCGasIndexAlgorithm vocAlgo;
NOxGasIndexAlgorithm noxAlgo;
bool sgpOk = false;
uint16_t sgpConditioningLeft = 10;  // 10 s de conditionnement au démarrage
#endif

#if USE_ENS160
#include <SparkFun_ENS160.h>
SparkFun_ENS160 ens;
bool ensOk = false;
#endif

#if USE_ADS1115
#include <Adafruit_ADS1X15.h>
Adafruit_ADS1115 ads;
bool adsOk = false;
#endif

#if USE_OLED
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
bool oledOk = false;
#endif

#if USE_GPS
#include <TinyGPSPlus.h>
TinyGPSPlus gps;
HardwareSerial gpsSerial(1);
#endif

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

String topicRaw, topicStatus, topicCmd, topicPrediction;
unsigned long bootMs = 0, lastSampleMs = 0, lastReconnectMs = 0;
float lastTemp = 25.0f, lastHum = 50.0f;

String screenLine1 = "Demarrage...";
String screenLine2 = "";
String screenLine3 = "";

// ------------------------------------------------------------------ affichage
void drawScreen() {
#if USE_OLED
  if (!oledOk) return;
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  oled.setTextSize(1);
  oled.setCursor(0, 0);
  oled.print("Nez ");
  oled.print(DEVICE_ID);
  oled.drawLine(0, 10, 127, 10, SSD1306_WHITE);
  oled.setTextSize(2);
  oled.setCursor(0, 16);
  oled.print(screenLine1.substring(0, 10));
  oled.setTextSize(1);
  oled.setCursor(0, 40);
  oled.print(screenLine2);
  oled.setCursor(0, 52);
  oled.print(screenLine3);
  oled.display();
#endif
}

void setLed(uint8_t r, uint8_t g, uint8_t b) {
#if USE_RGB_LED
  analogWrite(PIN_LED_R, r);
  analogWrite(PIN_LED_G, g);
  analogWrite(PIN_LED_B, b);
#endif
}

void setLedHex(const char *hex) {
  if (!hex || hex[0] != '#' || strlen(hex) < 7) return;
  long v = strtol(hex + 1, nullptr, 16);
  setLed((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

void beep(int times, int ms = 120) {
#if USE_BUZZER
  for (int i = 0; i < times; i++) {
    digitalWrite(PIN_BUZZER, HIGH);
    delay(ms);
    digitalWrite(PIN_BUZZER, LOW);
    delay(ms);
  }
#endif
}

// ------------------------------------------------------------------ réseau
void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  screenLine1 = "Wi-Fi...";
  drawScreen();
  Serial.print("Connexion Wi-Fi");
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? " OK " + WiFi.localIP().toString() : " ECHEC");
}

void publishStatus(const char *state) {
  JsonDocument doc;
  doc["device"] = DEVICE_ID;
  doc["state"] = state;
  doc["ip"] = WiFi.localIP().toString();
  doc["rssi"] = WiFi.RSSI();
  doc["uptime"] = (millis() - bootMs) / 1000;
  char buf[256];
  size_t n = serializeJson(doc, buf);
  mqtt.publish(topicStatus.c_str(), (const uint8_t *)buf, n, true);
}

void onMessage(char *topic, byte *payload, unsigned int length) {
  JsonDocument doc;
  if (deserializeJson(doc, payload, length)) return;
  String t(topic);

  if (t == topicPrediction) {
    const char *label = doc["label"] | "?";
    float conf = doc["confidence"] | 0.0f;
    screenLine1 = label;
    screenLine2 = "Confiance " + String((int)(conf * 100)) + " %";
    setLedHex(doc["color"] | "#000000");
    const char *level = doc["alert_level"] | "none";
    if (strcmp(level, "danger") == 0) beep(3);
    drawScreen();
    return;
  }

  if (t == topicCmd) {
    const char *cmd = doc["cmd"] | "";
    Serial.printf("Commande recue : %s\n", cmd);
    if (strcmp(cmd, "calibrate") == 0) {
      screenLine1 = "Calibrage";
      screenLine2 = "Air propre svp";
      setLed(0, 0, 80);
    } else if (strcmp(cmd, "learn") == 0) {
      screenLine1 = "Apprendre";
      screenLine2 = String((const char *)(doc["odor"] | ""));
      screenLine3 = "Presentez l'odeur";
      setLed(80, 0, 80);
      beep(1);
    } else if (strcmp(cmd, "learn_done") == 0) {
      screenLine1 = "Appris !";
      screenLine3 = "";
      setLed(0, 80, 0);
      beep(2, 60);
    } else if (strcmp(cmd, "identify") == 0) {
      for (int i = 0; i < 5; i++) { setLed(255, 255, 255); delay(150); setLed(0, 0, 0); delay(150); }
    } else if (strcmp(cmd, "reboot") == 0) {
      ESP.restart();
    }
    drawScreen();
  }
}

bool connectMqtt() {
  String clientId = String("nez-") + DEVICE_ID + "-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  // "Last Will" : si l'appareil disparaît, le broker publie "offline"
  String will = String("{\"device\":\"") + DEVICE_ID + "\",\"state\":\"offline\"}";
  if (!mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD, topicStatus.c_str(), 1, true, will.c_str())) {
    Serial.printf("MQTT echec, code %d\n", mqtt.state());
    return false;
  }
  mqtt.subscribe(topicCmd.c_str());
  mqtt.subscribe(topicPrediction.c_str());
  publishStatus("online");
  Serial.println("MQTT connecte");
  return true;
}

// ------------------------------------------------------------------ capteurs
void initSensors() {
  Wire.begin(PIN_SDA, PIN_SCL);

#if USE_BME688
  bmeOk = bme.begin(0x77) || bme.begin(0x76);
  if (bmeOk) {
    bme.setTemperatureOversampling(BME680_OS_8X);
    bme.setHumidityOversampling(BME680_OS_2X);
    bme.setPressureOversampling(BME680_OS_4X);
    bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
    bme.setGasHeater(320, 150);  // 320 °C pendant 150 ms
  }
  Serial.printf("BME688 : %s\n", bmeOk ? "OK" : "absent");
#endif

#if USE_SGP41
  sgp41.begin(Wire);
  uint16_t serial[3];
  sgpOk = sgp41.getSerialNumber(serial) == 0;
  Serial.printf("SGP41 : %s\n", sgpOk ? "OK" : "absent");
#endif

#if USE_ENS160
  ensOk = ens.begin();
  if (ensOk) ens.setOperatingMode(SFE_ENS160_STANDARD);
  Serial.printf("ENS160 : %s\n", ensOk ? "OK" : "absent");
#endif

#if USE_ADS1115
  adsOk = ads.begin(0x48);
  if (adsOk) ads.setGain(GAIN_ONE);  // ±4,096 V
  Serial.printf("ADS1115 : %s\n", adsOk ? "OK" : "absent");
#endif

#if USE_OLED
  oledOk = oled.begin(SSD1306_SWITCHCAPVCC, 0x3C);
#endif

#if USE_GPS
  gpsSerial.begin(9600, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX);
#endif
}

#if USE_ADS1115
float readMq(int channel) {
  if (!adsOk || channel < 0) return NAN;
  int16_t raw = ads.readADC_SingleEnded(channel);
  return ads.computeVolts(raw) * MQ_DIVIDER_RATIO;  // tension réelle en sortie du capteur (0-5 V)
}
#endif

void addIfValid(JsonDocument &doc, const char *key, float v, int decimals = 3) {
  if (!isnan(v)) doc[key] = serialized(String(v, decimals));
}

void sampleAndPublish() {
  JsonDocument doc;
  doc["device"] = DEVICE_ID;
  uint32_t elapsed = (millis() - bootMs) / 1000;
  bool warming = elapsed < WARMUP_SECONDS;
  doc["warming"] = warming;

#if USE_BME688
  if (bmeOk && bme.performReading()) {
    lastTemp = bme.temperature;
    lastHum = bme.humidity;
    doc["bme688_gas"] = (uint32_t)bme.gas_resistance;  // ohms : baisse quand il y a des COV
    doc["pressure"] = serialized(String(bme.pressure / 100.0, 1));
  }
#endif
  doc["temp"] = serialized(String(lastTemp, 2));
  doc["hum"] = serialized(String(lastHum, 2));

#if USE_SGP41
  if (sgpOk) {
    uint16_t rh = (uint16_t)(lastHum * 65535.0f / 100.0f);
    uint16_t tc = (uint16_t)((lastTemp + 45.0f) * 65535.0f / 175.0f);
    uint16_t srawVoc = 0, srawNox = 0;
    if (sgpConditioningLeft > 0) {
      sgp41.executeConditioning(rh, tc, srawVoc);
      sgpConditioningLeft--;
    } else if (sgp41.measureRawSignals(rh, tc, srawVoc, srawNox) == 0) {
      doc["sgp41_voc"] = vocAlgo.process(srawVoc);  // indice 0-500, 100 = air habituel
      doc["sgp41_nox"] = noxAlgo.process(srawNox);  // indice 1-500, 1 = air habituel
    }
  }
#endif

#if USE_ENS160
  if (ensOk) {
    ens.setTempCompensationCelsius(lastTemp);
    ens.setRHCompensationFloat(lastHum);
    doc["ens160_tvoc"] = ens.getTVOC();
    doc["ens160_eco2"] = ens.getECO2();
  }
#endif

#if USE_ADS1115
  addIfValid(doc, "mq3", readMq(ADS_CH_MQ3));
  addIfValid(doc, "mq4", readMq(ADS_CH_MQ4));
  addIfValid(doc, "mq135", readMq(ADS_CH_MQ135));
#endif

#if USE_GPS
  if (gps.location.isValid() && gps.location.age() < 5000) {
    doc["lat"] = serialized(String(gps.location.lat(), 6));
    doc["lon"] = serialized(String(gps.location.lng(), 6));
  }
#else
  if (FIXED_LAT != 0.0 || FIXED_LON != 0.0) {
    doc["lat"] = FIXED_LAT;
    doc["lon"] = FIXED_LON;
  }
#endif

  char buf[512];
  size_t n = serializeJson(doc, buf);
  if (mqtt.connected()) mqtt.publish(topicRaw.c_str(), (const uint8_t *)buf, n);
  Serial.println(buf);

  if (warming) {
    screenLine1 = "Chauffe";
    screenLine2 = String(WARMUP_SECONDS - elapsed) + " s restantes";
    drawScreen();
  }
}

// ------------------------------------------------------------------ setup / loop
void setup() {
  Serial.begin(115200);
  delay(300);
  bootMs = millis();
  topicRaw = String("nose/") + DEVICE_ID + "/raw";
  topicStatus = String("nose/") + DEVICE_ID + "/status";
  topicCmd = String("nose/") + DEVICE_ID + "/cmd";
  topicPrediction = String("nose/") + DEVICE_ID + "/prediction";

#if USE_RGB_LED
  pinMode(PIN_LED_R, OUTPUT);
  pinMode(PIN_LED_G, OUTPUT);
  pinMode(PIN_LED_B, OUTPUT);
#endif
#if USE_BUZZER
  pinMode(PIN_BUZZER, OUTPUT);
#endif
  pinMode(PIN_FAN, OUTPUT);
  digitalWrite(PIN_FAN, HIGH);  // le ventilateur tourne en continu

  initSensors();
  drawScreen();
  connectWifi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(1024);
  mqtt.setCallback(onMessage);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWifi();

  if (!mqtt.connected() && millis() - lastReconnectMs > 5000) {
    lastReconnectMs = millis();
    connectMqtt();
  }
  mqtt.loop();

#if USE_GPS
  while (gpsSerial.available()) gps.encode(gpsSerial.read());
#endif

  if (millis() - lastSampleMs >= SAMPLE_PERIOD_MS) {
    lastSampleMs = millis();
    sampleAndPublish();
  }
}
