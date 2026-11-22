# -*- coding: utf-8 -*-
"""Présentation PDF « La bibliothèque des odeurs » - style parfumerie nocturne."""
import math
import random
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.fonts import addMapping

AUTEUR = "Seyid Cheikh"
DATE = "Novembre 2026"
OUT = "Presentation_Bibliotheque_Odeurs_IoT.pdf"
W, H = 960, 540

# ------------------------------------------------------------------ polices
AV = "/System/Library/Fonts/Avenir Next.ttc"
DI = "/System/Library/Fonts/Supplemental/Didot.ttc"
for name, path, idx in [("Av", AV, 7), ("AvB", AV, 2), ("AvI", AV, 4), ("AvBI", AV, 3),
                        ("AvH", AV, 8), ("AvL", AV, 10), ("AvM", AV, 5),
                        ("Di", DI, 0), ("DiI", DI, 1), ("DiB", DI, 2)]:
    pdfmetrics.registerFont(TTFont(name, path, subfontIndex=idx))
addMapping("Av", 0, 0, "Av"); addMapping("Av", 1, 0, "AvB")
addMapping("Av", 0, 1, "AvI"); addMapping("Av", 1, 1, "AvBI")

# ------------------------------------------------------------------ palette
BG = HexColor("#100C18")
INK = HexColor("#F4EFE8")
MUTED = HexColor("#A79FB5")
HAIR = HexColor("#2E2640")
GOLD = HexColor("#E8C27A")
ROSE = HexColor("#F27BA0")
MINT = HexColor("#6FE3C1")
LILAC = HexColor("#A98BFF")
SKY = HexColor("#6CB8FF")
EMBER = HexColor("#FF8A5B")

body = ParagraphStyle("b", fontName="Av", fontSize=12.5, leading=18, textColor=INK)
small = ParagraphStyle("s", parent=body, fontSize=11, leading=15.5, textColor=HexColor("#D9D2E3"))
lead = ParagraphStyle("l", parent=body, fontName="DiI", fontSize=21, leading=29)
cell = ParagraphStyle("c", parent=body, fontSize=10.5, leading=13.5, textColor=HexColor("#D9D2E3"))
cell_b = ParagraphStyle("cb", parent=cell, fontName="AvB", textColor=INK)

c = canvas.Canvas(OUT, pagesize=(W, H))
c.setTitle("La bibliothèque des odeurs - Nez électronique IoT")
c.setAuthor(AUTEUR)
c.setSubject("Présentation du projet IoT : matériel, backend, frontend, machine learning")
state = {"page": 0}
TOTAL = 17


# ------------------------------------------------------------------ primitives
def glow(x, y, r, color, strength=0.05, layers=14):
    c.saveState()
    c.setFillColor(color)
    for i in range(layers):
        c.setFillAlpha(strength)
        c.circle(x, y, r * (1 - i / layers), fill=1, stroke=0)
    c.restoreState()


def background(seed):
    c.setFillColor(BG)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    rnd = random.Random(seed)
    cols = [ROSE, LILAC, MINT, GOLD, SKY]
    for _ in range(3):
        glow(rnd.choice([rnd.uniform(-60, 200), rnd.uniform(760, 1020)]),
             rnd.uniform(-80, 620), rnd.uniform(160, 300), rnd.choice(cols), 0.022)
    # poussière d'odeur
    c.saveState()
    for _ in range(70):
        c.setFillColor(rnd.choice(cols))
        c.setFillAlpha(rnd.uniform(0.15, 0.5))
        c.circle(rnd.uniform(0, W), rnd.uniform(0, H), rnd.uniform(0.6, 1.8), fill=1, stroke=0)
    c.restoreState()


def spaced(text, x, y, font="AvB", size=9.5, color=GOLD, spacing=2.6):
    t = c.beginText(x, y)
    t.setFont(font, size)
    t.setCharSpace(spacing)
    t.setFillColor(color)
    t.textOut(text.upper())
    t.setCharSpace(0)  # l'espacement persiste sinon dans tout le PDF
    c.drawText(t)


def para(text, x, y_top, w, style=body):
    p = Paragraph(text, style)
    _, h = p.wrap(w, 2000)
    p.drawOn(c, x, y_top - h)
    return h


def slide(num, kicker, title, accent=GOLD):
    if state["page"]:
        c.showPage()
    state["page"] += 1
    background(num * 7)
    # grand numéro en contour
    c.saveState()
    c.setStrokeColor(accent)
    c.setStrokeAlpha(0.35)
    c.setLineWidth(0.8)
    t = c.beginText(W - 205, H - 128)
    t.setFont("DiI", 120)
    t.setTextRenderMode(1)
    t.textOut("%02d" % num)
    c.drawText(t)
    c.restoreState()
    spaced(kicker, 48, H - 50, color=accent)
    c.setFillColor(INK)
    c.setFont("DiI", 36)
    c.drawString(46, H - 92, title)
    c.setStrokeColor(accent)
    c.setLineWidth(1.2)
    c.line(48, H - 108, 108, H - 108)
    # pied de page
    c.setFillColor(MUTED)
    c.setFont("Av", 9)
    c.drawString(48, 22, AUTEUR + "   ·   La bibliothèque des odeurs")
    c.setFont("AvB", 9)
    c.drawRightString(W - 48, 22, "%02d / %02d" % (state["page"], TOTAL))


def glass(x, y_top, w, h, accent=None, r=14):
    c.saveState()
    c.setFillColor(INK)
    c.setFillAlpha(0.045)
    c.setStrokeColor(INK)
    c.setStrokeAlpha(0.13)
    c.setLineWidth(0.7)
    c.roundRect(x, y_top - h, w, h, r, fill=1, stroke=1)
    c.restoreState()
    if accent is not None:
        glow(x + 26, y_top - 26, 22, accent, 0.06, 8)
        c.setFillColor(accent)
        c.circle(x + 26, y_top - 26, 5, fill=1, stroke=0)


def card(x, y_top, w, h, title, items, accent, style=small, gap=5):
    glass(x, y_top, w, h, accent)
    c.setFillColor(INK)
    c.setFont("AvB", 14.5)
    c.drawString(x + 42, y_top - 31, title)
    y = y_top - 54
    if isinstance(items, str):
        para(items, x + 20, y, w - 40, style)
        return
    for it in items:
        c.setStrokeColor(accent)
        c.setLineWidth(1.4)
        c.line(x + 20, y - style.leading / 2 + 1, x + 29, y - style.leading / 2 + 1)
        hh = para(it, x + 38, y, w - 58, style)
        y -= hh + gap


def table(data, x, y_top, col_w, accent=GOLD):
    rows = []
    for i, r in enumerate(data):
        if i == 0:
            st = ParagraphStyle("h", parent=cell, fontName="AvB", fontSize=9, textColor=accent)
            rows.append([Paragraph(str(v).upper(), st) for v in r])
        else:
            rows.append([Paragraph(str(v), cell_b if j == 0 else cell) for j, v in enumerate(r)])
    t = Table(rows, colWidths=col_w)
    t.setStyle(TableStyle([
        ("LINEBELOW", (0, 0), (-1, 0), 1, accent),
        ("LINEBELOW", (0, 1), (-1, -1), 0.5, HAIR),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
    ]))
    _, h = t.wrap(sum(col_w), 2000)
    t.drawOn(c, x, y_top - h)
    return h


def node(x, y, r, label, sub, color):
    glow(x, y, r * 1.9, color, 0.05, 12)
    c.setFillColor(BG)
    c.setStrokeColor(color)
    c.setLineWidth(1.6)
    c.circle(x, y, r, fill=1, stroke=1)
    c.setFillColor(INK)
    c.setFont("AvB", 11.5)
    c.drawCentredString(x, y + 2, label)
    c.setFillColor(MUTED)
    c.setFont("Av", 8.5)
    c.drawCentredString(x, y - 12, sub)


def link(x1, y1, x2, y2, label=None, color=MUTED, curve=0):
    c.saveState()
    c.setStrokeColor(color)
    c.setStrokeAlpha(0.8)
    c.setLineWidth(1.1)
    c.setDash(3, 4)
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2 + curve
    p = c.beginPath()
    p.moveTo(x1, y1)
    p.curveTo(mx, my, mx, my, x2, y2)
    c.drawPath(p, stroke=1, fill=0)
    c.setDash()
    a = math.atan2(y2 - my, x2 - mx)
    c.setFillColor(color)
    p = c.beginPath()
    p.moveTo(x2, y2)
    p.lineTo(x2 - 8 * math.cos(a - 0.45), y2 - 8 * math.sin(a - 0.45))
    p.lineTo(x2 - 8 * math.cos(a + 0.45), y2 - 8 * math.sin(a + 0.45))
    p.close()
    c.drawPath(p, fill=1, stroke=0)
    c.restoreState()
    if label:
        c.setFillColor(GOLD)
        c.setFont("AvI", 9)
        c.drawCentredString(mx, my + (8 if curve >= 0 else -16), label)


# ================================================================== 01 Couverture
state["page"] = 1
background(3)
glow(720, 300, 300, ROSE, 0.03)
glow(820, 220, 230, LILAC, 0.035)
glow(650, 160, 170, MINT, 0.03)
# « molécule » d'odeur
rnd = random.Random(11)
pts = [(700 + 130 * math.cos(i * 2 * math.pi / 7 + 0.3) * rnd.uniform(0.6, 1.1),
        280 + 130 * math.sin(i * 2 * math.pi / 7 + 0.3) * rnd.uniform(0.6, 1.1)) for i in range(7)]
c.saveState()
c.setStrokeColor(INK)
c.setStrokeAlpha(0.25)
c.setLineWidth(0.7)
for i, (x, y) in enumerate(pts):
    c.line(700, 280, x, y)
    nx, ny = pts[(i + 2) % 7]
    c.line(x, y, nx, ny)
c.restoreState()
for (x, y), col in zip(pts, [ROSE, MINT, GOLD, LILAC, SKY, EMBER, MINT]):
    glow(x, y, 26, col, 0.08, 8)
    c.setFillColor(col)
    c.circle(x, y, 6, fill=1, stroke=0)
glow(700, 280, 50, GOLD, 0.08, 10)
c.setFillColor(GOLD)
c.circle(700, 280, 11, fill=1, stroke=0)

spaced("Projet IoT  ·  Nez électronique", 60, 420)
c.setFillColor(INK)
c.setFont("DiI", 64)
c.drawString(56, 340, "La bibliothèque")
c.drawString(56, 272, "des odeurs")
c.setStrokeColor(GOLD)
c.setLineWidth(1.2)
c.line(60, 246, 140, 246)
para("Un nez électronique connecté qui apprend à reconnaître, dater et "
     "cartographier les odeurs de son environnement.", 60, 230, 430,
     ParagraphStyle("cv", parent=body, fontSize=14, leading=20, textColor=HexColor("#D9D2E3")))
spaced("Présenté par", 60, 110, font="Av", size=9, color=MUTED, spacing=2.2)
c.setFillColor(INK)
c.setFont("Di", 30)
c.drawString(60, 76, AUTEUR)
c.setFillColor(MUTED)
c.setFont("Av", 10)
c.drawString(60, 54, DATE + "   ·   ESP32  ·  MQTT  ·  FastAPI  ·  SwiftUI  ·  React  ·  Machine Learning")

# ================================================================== 02 Concept
slide(2, "Pourquoi ce projet", "Le concept", ROSE)
para("« L'odorat est le sens le moins exploité de l'Internet des objets. »", 48, H - 135, 560, lead)
para("Ce projet construit un <b>nez électronique</b> : des capteurs de gaz capturent une "
     "<b>empreinte olfactive</b>, puis un modèle de machine learning apprend à associer "
     "chaque empreinte à une odeur.", 48, H - 210, 540, body)
items = [("Capturer", "Capteurs de COV, alcool, ammoniac, méthane sur un ESP32", MINT),
         ("Reconnaître", "Café, pain brûlé, poubelle, fruit trop mûr, produit chimique", LILAC),
         ("Archiver", "Chaque détection horodatée et géolocalisée", SKY),
         ("Alerter", "Aliment qui se gâte, début de fuite de gaz", ROSE)]
for i, (t, d, col) in enumerate(items):
    y = H - 140 - i * 82
    glass(640, y, 272, 70, col)
    c.setFillColor(INK)
    c.setFont("AvB", 14)
    c.drawString(682, y - 31, t)
    para(d, 682, y - 38, 215, ParagraphStyle("x", parent=small, fontSize=10, leading=13))
glass(48, 130, 560, 84)
para("<font color='#E8C27A'><b>Le défi</b></font> : rendre des capteurs fiables malgré la dérive, "
     "l'humidité et la température, et distinguer des odeurs proches. Un vrai sujet de recherche.",
     70, 112, 520, small)

# ================================================================== 03 Cas d'usage
slide(3, "Applications concrètes", "Cas d'usage", MINT)
uses = [("Cuisine & frigo", ["Fruit trop mûr (éthanol)", "Viande ou poisson avarié (ammoniac)", "Plat qui brûle (fumée, COV)"], GOLD),
        ("Sécurité", ["Signal précoce de fuite de gaz", "Solvants et produits chimiques", "Fumée inhabituelle"], EMBER),
        ("Confort & hygiène", ["Poubelle à sortir", "Pièce mal aérée", "Suivi de la qualité de l'air"], MINT),
        ("Cartographie", ["Carte olfactive maison, quartier, bureau", "Comparer plusieurs lieux", "Statistiques par pièce"], SKY)]
for i, (t, b, col) in enumerate(uses):
    card(48 + i * 220, H - 140, 205, 190, t, b, col, small, 10)
para("« Chaque odeur laisse une empreinte unique dans les capteurs : le projet apprend à la lire. »", 48, 160, 864, lead)

# ================================================================== 04 Architecture
slide(4, "Comment tout s'enchaîne", "Architecture", SKY)
N = {"cap": (110, 300, MINT, "Capteurs", "gaz + T/H"),
     "esp": (270, 300, MINT, "ESP32-S3", "firmware C++"),
     "mq": (430, 300, GOLD, "Mosquitto", "broker MQTT"),
     "api": (600, 300, LILAC, "FastAPI", "API + ML"),
     "db": (540, 140, SKY, "PostgreSQL", "Timescale+PostGIS"),
     "web": (790, 300, ROSE, "Apps", "iPhone · Web"),
     "al": (790, 140, EMBER, "Alertes", "apps · Telegram")}
link(152, 300, 226, 300, "I2C / ADC")
link(312, 300, 386, 300, "Wi-Fi MQTT")
link(472, 300, 556, 300, "abonnement")
link(644, 300, 746, 300, "WebSocket")
link(585, 260, 560, 184, None, MUTED, 0)
link(640, 270, 750, 160, None, MUTED, 0)
link(430, 345, 270, 345, "commandes : nose/{id}/cmd", MUTED, 40)
for k, (x, y, col, l, s) in N.items():
    node(x, y, 42, l, s, col)
c.setFillColor(MUTED)
c.setFont("AvI", 9)
c.drawString(582, 210, "stockage")
para("<b>Flux :</b> les capteurs mesurent l'air, l'ESP32 publie les mesures en JSON via MQTT, "
     "le backend les stocke, calcule l'empreinte, prédit l'odeur puis pousse le résultat en temps réel "
     "vers l'<b>app iPhone</b> et l'<b>interface web</b>. Tout le serveur tourne dans <b>Docker Compose</b>.", 48, 175, 400, small)

# ================================================================== 05 Matériel numérique
slide(5, "Hardware · le cerveau", "Microcontrôleur & capteurs", MINT)
card(48, H - 140, 280, 225, "ESP32-S3 DevKit", [
    "Wi-Fi intégré, beaucoup de RAM",
    "Instructions vectorielles : ML embarqué possible",
    "Alternative : ESP32 WROOM-32 si le ML reste sur le serveur",
    "Programmé avec <b>PlatformIO</b> (VS Code)",
], MINT, small, 9)
h = table([["Capteur", "Mesure", "Atout"],
           ["Bosch BME688", "Gaz (COV), température, humidité, pression", "Conçu pour classer les odeurs, profils de chauffe programmables"],
           ["Sensirion SGP41", "Indice COV et indice NOx", "Très stable dans le temps"],
           ["ScioSense ENS160", "COV totaux, eCO<sub>2</sub>, AQI", "Plusieurs éléments sensibles"]],
          355, H - 140, [120, 180, 255], MINT)
glass(355, H - 160 - h, 555, 90)
para("Tous en <b>I2C</b> (2 fils : SDA / SCL), en <b>3,3 V</b>, basse consommation. "
     "Ils forment le coeur fiable de l'empreinte olfactive.", 377, H - 180 - h, 515, small)

# ================================================================== 06 MQ
slide(6, "Hardware · le réseau MQ", "Capteurs analogiques MQ", GOLD)
h = table([["Capteur", "Gaz ciblés", "Odeurs visées"],
           ["MQ-2", "Fumée, GPL, combustibles", "Plat brûlé, fumée"],
           ["MQ-3", "Alcool, éthanol", "Fruit trop mûr"],
           ["MQ-4", "Méthane", "Fuite de gaz"],
           ["MQ-135", "Ammoniac, benzène, COV", "Poubelle, air vicié"],
           ["MQ-137", "Ammoniac (NH<sub>3</sub>)", "Viande ou poisson avariés"]],
          48, H - 140, [80, 180, 190], GOLD)
card(535, H - 140, 377, 210, "Précautions", [
    "Chauffage en <b>5 V</b>, environ 150 mA par capteur : alimentation 5 V / 3 A",
    "<b>Rodage 24 à 48 h</b>, puis 2 à 3 min de chauffe à chaque démarrage",
    "Sortie jusqu'à 5 V : <b>pont diviseur</b> vers 3,3 V",
    "ADC de l'ESP32 imprécis : utiliser un <b>ADS1115</b> 16 bits",
], EMBER, small, 9)
para("<font color='#E8C27A'><b>Recommandation</b></font> : BME688 + SGP41 + MQ-3, MQ-4, MQ-135. "
     "Plus l'empreinte est variée, mieux le modèle distingue les odeurs.", 48, H - 165 - h, 450, small)

# ================================================================== 07 BOM
slide(7, "Ce qu'il faut acheter", "Liste du matériel", GOLD)
table([["Composant", "Rôle", "Qté", "Prix indicatif"],
       ["ESP32-S3 DevKit", "Microcontrôleur Wi-Fi", "1", "10 à 15 EUR"],
       ["Bosch BME688", "Gaz + température / humidité / pression", "1", "15 à 25 EUR"],
       ["Sensirion SGP41", "Indices COV / NOx", "1", "10 à 15 EUR"],
       ["MQ-3, MQ-4, MQ-135", "Alcool, méthane, ammoniac", "3", "2 à 4 EUR pièce"],
       ["ADS1115", "Convertisseur analogique-numérique 16 bits", "1", "3 à 5 EUR"],
       ["Résistances", "Pont diviseur 5 V vers 3,3 V", "lot", "2 EUR"],
       ["Ventilateur 5 V 30 mm", "Flux d'air régulier", "1", "3 à 5 EUR"],
       ["Alimentation 5 V / 3 A", "Chauffage MQ + carte", "1", "8 à 12 EUR"],
       ["OLED SSD1306 · LED RGB · buzzer", "Affichage et alertes locales (option)", "1", "6 à 8 EUR"],
       ["GPS NEO-6M", "Géolocalisation extérieure (option)", "1", "6 à 10 EUR"],
       ["Breadboard, fils, boîtier", "Montage, chambre de mesure", "lot", "10 EUR"]],
      48, H - 135, [230, 330, 60, 120], GOLD)
glass(800, H - 135, 112, 150, GOLD)
c.setFillColor(INK)
c.setFont("DiI", 38)
c.drawCentredString(856, H - 210, "~100")
c.setFillColor(MUTED)
c.setFont("Av", 9.5)
c.drawCentredString(856, H - 230, "EUR au total")
c.drawCentredString(856, H - 244, "(80 à 120)")
c.setFont("AvI", 9)
c.drawString(48, 44, "Prix indicatifs, variables selon le fournisseur.")

# ================================================================== 08 MQTT
slide(8, "Protocole", "Communication MQTT", GOLD)
card(48, H - 140, 400, 200, "Pourquoi MQTT", [
    "Standard de l'IoT : léger, temps réel, publier / s'abonner",
    "Broker <b>Eclipse Mosquitto</b> dans Docker",
    "Messages <b>JSON</b> chaque seconde",
    "Mot de passe, TLS en production",
], GOLD, small, 7)
table([["Topic", "Sens", "Contenu"],
       ["nose/{id}/raw", "ESP32 vers serveur", "Mesures brutes"],
       ["nose/{id}/status", "ESP32 vers serveur", "En ligne, chauffe, erreur"],
       ["nose/{id}/cmd", "Serveur vers ESP32", "Calibrer, apprendre"]],
      475, H - 140, [140, 135, 160], GOLD)
glass(48, 190, 864, 140)
spaced("Exemple de message", 70, 166, size=8.5)
code = [('{ ', INK), ('"device"', MINT), (': ', INK), ('"nez-cuisine"', ROSE), (', ', INK), ('"ts"', MINT), (': ', INK), ('1763800000', GOLD), (',', INK)], \
       [('  "bme688_gas"', MINT), (': ', INK), ('48211', GOLD), (', ', INK), ('"sgp41_voc"', MINT), (': ', INK), ('132', GOLD), (', ', INK), ('"mq3"', MINT), (': ', INK), ('0.82', GOLD), (', ', INK), ('"mq135"', MINT), (': ', INK), ('1.37', GOLD), (',', INK)], \
       [('  "temp"', MINT), (': ', INK), ('22.4', GOLD), (', ', INK), ('"hum"', MINT), (': ', INK), ('48.1', GOLD), (', ', INK), ('"lat"', MINT), (': ', INK), ('48.8566', GOLD), (', ', INK), ('"lon"', MINT), (': ', INK), ('2.3522', GOLD), (' }', INK)]
for i, line in enumerate(code):
    t = c.beginText(70, 135 - i * 24)
    t.setFont("Courier", 12)
    for txt, col in line:
        t.setFillColor(col)
        t.textOut(txt)
    c.drawText(t)

# ================================================================== 09 Backend
slide(9, "Serveur & données", "Backend", LILAC)
table([["Rôle", "Technologie", "Pourquoi"],
       ["API REST", "Python + FastAPI", "Rapide, Swagger automatique, même langage que le ML"],
       ["Réception MQTT", "aiomqtt", "Asynchrone, intégré à FastAPI"],
       ["Base de données", "PostgreSQL", "Fiable, standard, gratuit"],
       ["Séries temporelles", "TimescaleDB", "Des millions de mesures, stockées efficacement"],
       ["Géolocalisation", "PostGIS", "Requêtes géographiques pour la carte olfactive"],
       ["Accès aux données", "SQLAlchemy + Alembic", "ORM et migrations"],
       ["Temps réel", "WebSocket", "Pousse les détections au navigateur"],
       ["Sécurité", "JWT + bcrypt", "Comptes et accès protégés"],
       ["Alertes", "Web push · Telegram · e-mail", "Prévenir partout"]],
      48, H - 135, [160, 220, 484], LILAC)
para("<font color='#A98BFF'><b>Données :</b></font> appareils · mesures · échantillons étiquetés · "
     "odeurs · détections (odeur, confiance, date, position) · alertes · utilisateurs",
     48, 75, 864, small)

# ================================================================== 10 ML
slide(10, "Intelligence", "Reconnaître une odeur", LILAC)
steps = [("Mesure", "Air propre 30 s, odeur 60 s, purge", MINT),
         ("Empreinte", "Écart à la référence, pente, maximum", GOLD),
         ("Modèle", "Random Forest / SVM (scikit-learn)", LILAC),
         ("Prédiction", "Odeur + % de confiance", ROSE)]
for i, (t, d, col) in enumerate(steps):
    x = 100 + i * 230
    glow(x, H - 190, 60, col, 0.05, 10)
    c.setFillColor(BG)
    c.setStrokeColor(col)
    c.setLineWidth(1.5)
    c.circle(x, H - 190, 34, fill=1, stroke=1)
    c.setFillColor(col)
    c.setFont("DiI", 26)
    c.drawCentredString(x, H - 199, str(i + 1))
    c.setFillColor(INK)
    c.setFont("AvB", 13)
    c.drawString(x + 46, H - 180, t)
    para(d, x + 46, H - 188, 140, ParagraphStyle("z", parent=small, fontSize=9.5, leading=12.5))
card(48, H - 260, 420, 215, "Outils", [
    "<b>NumPy · Pandas</b> : préparation des données",
    "<b>scikit-learn</b> : entraînement, validation croisée",
    "<b>joblib</b> : sauvegarde du modèle",
    "<b>Edge Impulse / TFLite Micro</b> : modèle sur l'ESP32",
    "<b>Bosch BME AI-Studio</b> : tests rapides BME688",
], LILAC, small, 4)
card(492, H - 260, 420, 215, "Règles d'or", [
    "30 à 50 échantillons minimum par odeur",
    "Température et humidité en entrée du modèle",
    "Classe <b>air ambiant / inconnu</b> obligatoire",
    "Sous 70 % de confiance : « odeur inconnue »",
    "Recalibrer et réentraîner contre la dérive",
], ROSE, small, 4)

def tiles(items, x0=430, top=H - 135, w=232, h=104, dy=118):
    for i, (t, d, col) in enumerate(items):
        x = x0 + (i % 2) * (w + 13)
        y = top - (i // 2) * dy
        glass(x, y, w, h, col)
        c.setFillColor(INK)
        c.setFont("AvB", 13.5)
        c.drawString(x + 42, y - 31, t)
        para(d, x + 20, y - 52, w - 37, small)


# ================================================================== 11 App iPhone
slide(11, "Interface mobile", "L'application iPhone", ROSE)
h = table([["Techno", "Usage"],
           ["Swift + SwiftUI", "Interface native, iOS 17+"],
           ["Xcode", "Compiler et installer sur l'iPhone"],
           ["Swift Charts", "Courbes des capteurs en direct"],
           ["MapKit", "Carte satellite en relief"],
           ["CoreLocation", "Position GPS du téléphone"],
           ["WebSocket", "Odeurs et alertes en temps réel"]],
          48, H - 135, [130, 220], ROSE)
para("Testée sur un <b>iPhone 14 Pro Max</b> : l'app propose l'adresse du serveur "
     "et se reconnecte toute seule.", 48, H - 155 - h, 350, small)
tiles([("Direct", "Odeur reconnue, confiance, radar, courbes", MINT),
       ("Apprendre", "Enregistrer une odeur, entraîner le modèle", GOLD),
       ("Bibliothèque", "Empreintes, création, niveaux d'alerte", LILAC),
       ("Carte", "Satellite réelle, GPS, détections par lieu", SKY),
       ("Alertes", "Bandeau en direct, marquer comme lue", EMBER),
       ("Réglages", "Appareils, calibration, position", ROSE)])

# ================================================================== 12 Interface web
slide(12, "Interface web", "Le site web", SKY)
h = table([["Techno", "Usage"],
           ["React + TypeScript", "Interface typée et rapide"],
           ["Vite", "Serveur de développement, build"],
           ["React Router", "Navigation entre les pages"],
           ["Recharts", "Courbes et détections sur 24 h"],
           ["Leaflet", "Carte satellite Esri ou plan OSM"],
           ["nginx", "Sert le site en production"]],
          48, H - 135, [130, 220], SKY)
para("Mêmes données et même temps réel que l'app iPhone : les deux interfaces "
     "parlent à la même API.", 48, H - 155 - h, 350, small)
tiles([("Mêmes pages", "Direct, Apprendre, Bibliothèque, Carte, Alertes, Appareils", MINT),
       ("Ordinateur et mobile", "Menu latéral, ou barre en bas sur téléphone", GOLD),
       ("Même style", "Parfumerie nocturne, comme la présentation", LILAC),
       ("En production", "Docker + nginx sur le port 8080", ROSE)])

# ================================================================== 13 Carte réelle
slide(13, "Géolocalisation", "La carte olfactive réelle", MINT)
para("« Chaque odeur détectée est placée là où elle a été sentie, sur une vraie carte. »", 48, H - 135, 864, lead)
tiles([("Vue satellite", "En relief sur iPhone (Apple Plans), Esri ou plan sombre sur le web", SKY),
       ("Position GPS", "Le point bleu du téléphone ; la carte se centre sur vous", MINT),
       ("Placer un appareil", "Toucher la carte ou utiliser le GPS à côté du nez", GOLD),
       ("Suivre le téléphone", "Un nez porté en marchant cartographie le quartier", ROSE),
       ("Par lieu", "Une bulle par endroit : odeur dominante + nombre", LILAC),
       ("Historique corrigé", "Les anciennes détections suivent la vraie position", EMBER)],
      x0=48, top=H - 195, w=422, h=86, dy=98)

# ================================================================== 14 Déploiement
slide(14, "DevOps", "Déploiement & outils", SKY)
svc = [("mosquitto", "broker MQTT", GOLD), ("db", "PostgreSQL + Timescale + PostGIS", SKY),
       ("backend", "FastAPI + modèle ML", LILAC), ("web", "Site React servi par nginx", ROSE)]
glass(48, H - 135, 520, 200)
spaced("docker compose up", 70, H - 160, font="AvB", size=9, color=SKY)
for i, (n, d, col) in enumerate(svc):
    y = H - 195 - i * 34
    c.setFillColor(col)
    c.roundRect(70, y - 6, 92, 22, 11, fill=1, stroke=0)
    c.setFillColor(BG)
    c.setFont("AvB", 10.5)
    c.drawCentredString(116, y + 1, n)
    c.setFillColor(INK)
    c.setFont("Av", 11.5)
    c.drawString(178, y + 1, d)
card(592, H - 135, 320, 200, "Hébergement", [
    "En local pour développer",
    "<b>Raspberry Pi</b> à la maison, 24 h / 24",
    "<b>VPS</b> pour un accès Internet",
], MINT, small, 8)
tools = ["VS Code + PlatformIO", "Xcode", "Git + GitHub", "Swagger", "MQTT Explorer",
         "Simulateur de capteurs", "pytest"]
spaced("Outils de développement", 48, 170, size=9, color=SKY)
x = 48
y = 132
for t in tools:
    w = pdfmetrics.stringWidth(t, "AvM", 11.5) + 30
    if x + w > 912:
        x, y = 48, y - 40
    c.saveState()
    c.setStrokeColor(SKY)
    c.setStrokeAlpha(0.6)
    c.setFillColor(SKY)
    c.setFillAlpha(0.08)
    c.roundRect(x, y, w, 26, 13, fill=1, stroke=1)
    c.restoreState()
    c.setFillColor(INK)
    c.setFont("AvM", 11.5)
    c.drawString(x + 15, y + 8.5, t)
    x += w + 10

# ================================================================== 13 Sécurité
slide(15, "Points d'attention", "Fiabilité & sécurité", EMBER)
card(48, H - 140, 420, 230, "Fiabilité des mesures", [
    "Chambre de mesure fermée + ventilateur",
    "Toujours comparer à une <b>référence d'air propre</b>",
    "Compenser température et humidité",
    "Chauffer les capteurs avant de mesurer",
    "Surveiller la <b>dérive</b> dans le temps",
], MINT, small, 10)
card(492, H - 140, 420, 230, "Sécurité", [
    "<font color='#FF8A5B'><b>Ne remplace pas un détecteur de gaz ou de CO certifié</b></font> : alerte précoce complémentaire",
    "MQTT protégé par mot de passe, TLS",
    "API protégée par JWT, mots de passe hachés",
    "Secrets dans un <b>.env</b> jamais publié",
    "Localisations stockées sur son propre serveur",
], EMBER, small, 10)

# ================================================================== 14 Plan
slide(16, "Où en est le projet", "Plan de réalisation", MINT)
phases = [("Firmware ESP32", "Capteurs, MQTT, mode apprentissage", MINT, "Écrit · à tester"),
          ("Backend", "MQTT, base, API REST, WebSocket", LILAC, "Terminé · testé"),
          ("Machine learning", "Collecte, entraînement, prédiction", GOLD, "Terminé · testé"),
          ("Interfaces", "App iPhone et site web", ROSE, "Terminé · sur l'iPhone"),
          ("Déploiement", "Docker, documentation, GitHub", SKY, "Terminé · publié"),
          ("Bonus TinyML", "Modèle exécuté sur l'ESP32", EMBER, "À venir")]
# courbe ondulée façon trace d'odeur
c.saveState()
c.setStrokeColor(INK)
c.setStrokeAlpha(0.25)
c.setLineWidth(1)
c.setDash(2, 5)
p = c.beginPath()
pos = [(110 + i * 148, 235 + (50 if i % 2 else -45)) for i in range(6)]
p.moveTo(*pos[0])
for (x0, y0), (x1, y1) in zip(pos, pos[1:]):
    p.curveTo(x0 + 75, y0, x1 - 75, y1, x1, y1)
c.drawPath(p, stroke=1, fill=0)
c.restoreState()
for i, ((x, y), (t, d, col, status)) in enumerate(zip(pos, phases)):
    glow(x, y, 48, col, 0.06, 10)
    c.setFillColor(BG)
    c.setStrokeColor(col)
    c.setLineWidth(1.5)
    c.circle(x, y, 26, fill=1, stroke=1)
    c.setFillColor(col)
    c.setFont("DiI", 22)
    c.drawCentredString(x, y - 8, str(i + 1))
    ty = y + 70 if i % 2 else y - 50
    c.setFillColor(INK)
    c.setFont("AvB", 12.5)
    c.drawCentredString(x, ty, t)
    hh = para(d, x - 68, ty - 6, 136, ParagraphStyle("pp", parent=small, fontSize=9.5, leading=12.5, alignment=1))
    done = status.startswith("Terminé")
    c.setFillColor(MINT if done else (GOLD if status.startswith("Écrit") else MUTED))
    c.setFont("AvB", 9.5)
    # au-dessus du nom pour les étapes du haut, sous la description pour celles du bas
    c.drawCentredString(x, ty + 17 if i % 2 else ty - 20 - hh, status)

# ================================================================== 17 Résumé
slide(17, "Conclusion", "En résumé", GOLD)
summary = [("Matériel", "ESP32-S3 · BME688 · SGP41 · MQ-3 / MQ-4 / MQ-135 · ADS1115", MINT),
           ("Communication", "Wi-Fi · MQTT (Mosquitto) · JSON", GOLD),
           ("Backend", "Python · FastAPI · PostgreSQL · TimescaleDB · PostGIS · WebSocket · JWT", LILAC),
           ("Machine learning", "scikit-learn · NumPy · Random Forest · validation croisée", SKY),
           ("App iPhone", "Swift · SwiftUI · Swift Charts · MapKit · CoreLocation", ROSE),
           ("Site web", "React · TypeScript · Vite · Recharts · Leaflet", LILAC),
           ("Déploiement", "Docker Compose · nginx · Raspberry Pi ou VPS · GitHub", EMBER)]
for i, (t, d, col) in enumerate(summary):
    y = H - 145 - i * 44
    c.setFillColor(col)
    c.circle(56, y + 4, 4, fill=1, stroke=0)
    c.setFillColor(col)
    c.setFont("AvB", 13)
    c.drawString(72, y, t)
    c.setFillColor(INK)
    c.setFont("Av", 12.5)
    c.drawString(250, y, d)
    c.setStrokeColor(HAIR)
    c.setLineWidth(0.6)
    c.line(48, y - 16, 912, y - 16)
c.setFillColor(MUTED)
c.setFont("Av", 10.5)
c.drawString(48, 60, "Code et documentation : github.com/seyidmedsalem/bibliotheque-odeurs")
c.setFillColor(GOLD)
c.setFont("DiI", 20)
c.drawRightString(912, 56, "Merci  ·  " + AUTEUR)

c.save()
print("OK", OUT)
