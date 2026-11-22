import MapKit
import SwiftUI

/// Un endroit réel où des odeurs ont été détectées (détections regroupées par position).
struct OdorSpot: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let detections: [Detection]
    let room: String?

    static func == (a: OdorSpot, b: OdorSpot) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Odeurs présentes à cet endroit, de la plus fréquente à la plus rare.
    var counts: [(odorId: Int?, count: Int)] {
        Dictionary(grouping: detections, by: \.odorId).map { ($0.key, $0.value.count) }.sorted { $0.count > $1.count }
    }
}

enum MapLook: String, CaseIterable, Identifiable {
    case plan = "Plan", satellite = "Satellite", hybrid = "Hybride"
    var id: String { rawValue }
    var style: MapStyle {
        switch self {
        case .plan: return .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite: return .imagery(elevation: .realistic)
        case .hybrid: return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
    }
}

/// Carte olfactive réelle : positions GPS des appareils, ta position, vue satellite en relief.
struct OdorMapView: View {
    @Environment(AppStore.self) private var store
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var hours = 24 * 7
    @State private var odorFilter: Int?
    @State private var selection: String?
    @State private var look: MapLook = .hybrid
    @State private var placing: Device?

    private var located: [Detection] {
        store.detections.filter { $0.lat != nil && $0.lon != nil && (odorFilter == nil || $0.odorId == odorFilter) }
    }

    /// Regroupe les détections faites au même endroit (à ~1 m près).
    private var spots: [OdorSpot] {
        Dictionary(grouping: located) { String(format: "%.5f,%.5f", $0.lat!, $0.lon!) }
            .map { key, list in
                OdorSpot(id: key, coordinate: CLLocationCoordinate2D(latitude: list[0].lat!, longitude: list[0].lon!),
                         detections: list.sorted { $0.ts > $1.ts }, room: list.first?.room)
            }
    }

    private var unplaced: [Device] { store.devices.filter { $0.lat == nil || $0.lon == nil } }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $position, selection: $selection) {
                    UserAnnotation()
                    ForEach(spots) { spot in
                        let top = store.odor(spot.counts.first?.odorId ?? nil)
                        let color = Color(hex: top?.color ?? "#8A8494")
                        MapCircle(center: spot.coordinate, radius: 6 + 3 * Double(min(spot.detections.count, 12)))
                            .foregroundStyle(color.opacity(0.25))
                            .stroke(color.opacity(0.7), lineWidth: 1)
                        Annotation(spot.room ?? "", coordinate: spot.coordinate) {
                            SpotBubble(spot: spot, selected: selection == spot.id)
                        }
                        .tag(spot.id)
                    }
                    ForEach(store.devices.filter { $0.lat != nil && $0.lon != nil }) { dev in
                        Annotation(dev.name, coordinate: CLLocationCoordinate2D(latitude: dev.lat!, longitude: dev.lon!), anchor: .top) {
                            Image(systemName: store.followDeviceId == dev.id ? "figure.walk" : "sensor.fill")
                                .font(.system(size: 10)).foregroundStyle(Theme.bg)
                                .padding(5).background(Circle().fill(dev.online ? Theme.mint : Theme.muted))
                                .offset(y: 18)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(look.style)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapPitchToggle()
                    MapScaleView()
                }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 10) {
                    header
                    if !unplaced.isEmpty && selection == nil { unplacedBanner }
                    Spacer()
                    if let id = selection, let spot = spots.first(where: { $0.id == id }) { detail(spot) } else { roomsCard }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .task {
                store.location.start()
                await store.loadDetections(hours: hours)
            }
            .onChange(of: hours) { _, h in Task { await store.loadDetections(hours: h) } }
            .sheet(item: $placing) { dev in PlaceDeviceView(device: dev) }
        }
    }

    // MARK: - En-tête et filtres

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Carte olfactive").font(.display(24)).foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    Picker("Vue", selection: $look) { ForEach(MapLook.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Période", selection: $hours) {
                        Text("24 heures").tag(24)
                        Text("7 jours").tag(24 * 7)
                        Text("30 jours").tag(24 * 30)
                    }
                } label: {
                    Label("\(look.rawValue) · \(hours == 24 ? "24 h" : hours == 24 * 7 ? "7 j" : "30 j")", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Toutes", color: Theme.gold, active: odorFilter == nil) { odorFilter = nil }
                    ForEach(store.odors.filter { !$0.isAir }) { o in
                        chip("\(o.icon) \(o.name)", color: Color(hex: o.color), active: odorFilter == o.id) { odorFilter = o.id }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.bg.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hair))
    }

    private func chip(_ text: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Theme.bg : Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(active ? color : Color.white.opacity(0.08)))
        }
    }

    private var unplacedBanner: some View {
        Menu {
            ForEach(unplaced) { d in Button("Placer « \(d.name) »") { placing = d } }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.slash").foregroundStyle(Theme.ember)
                Text("\(unplaced.count) appareil(s) sans position réelle. Touchez pour les placer.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bg.opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ember.opacity(0.5)))
        }
    }

    // MARK: - Cartes du bas

    private var roomsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Kicker("Par lieu", color: Theme.gold)
                Spacer()
                Text("\(located.count) détections · \(spots.count) lieux").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            if spots.isEmpty {
                Text("Aucune détection géolocalisée sur cette période. Placez vos appareils à leur vraie position (bouton ci-dessus ou Réglages).")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                ForEach(spots.sorted { $0.detections.count > $1.detections.count }.prefix(4)) { spot in
                    let top = store.odor(spot.counts.first?.odorId ?? nil)
                    Button {
                        selection = spot.id
                        withAnimation { position = .camera(MapCamera(centerCoordinate: spot.coordinate, distance: 400, pitch: 50)) }
                    } label: {
                        HStack {
                            Text(spot.room ?? "Lieu sans nom").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(top?.icon ?? "") \(top?.name ?? "")").font(.system(size: 12))
                                .foregroundStyle(Color(hex: top?.color ?? "#A79FB5"))
                            Text("\(spot.detections.count)").font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(Theme.muted).frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.bg.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hair))
    }

    private func detail(_ spot: OdorSpot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.room ?? "Lieu").font(.display(24)).foregroundStyle(Theme.ink)
                    Text(String(format: "%.5f, %.5f", spot.coordinate.latitude, spot.coordinate.longitude))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.muted) }
            }
            ForEach(spot.counts.prefix(4), id: \.odorId) { item in
                let odor = store.odor(item.odorId)
                ProbabilityBar(label: "\(odor?.icon ?? "❔") \(odor?.name ?? "Inconnue")",
                               value: Double(item.count) / Double(spot.detections.count),
                               color: Color(hex: odor?.color ?? "#8A8494"))
            }
            if let last = spot.detections.first {
                Text("Dernière : \(last.label) \(last.ts.relative) · \(Int(last.confidence * 100)) %")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.bg.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.gold.opacity(0.5)))
    }
}

/// Bulle d'un lieu : odeur dominante + nombre de détections.
struct SpotBubble: View {
    @Environment(AppStore.self) private var store
    let spot: OdorSpot
    let selected: Bool

    var body: some View {
        let top = store.odor(spot.counts.first?.odorId ?? nil)
        let color = Color(hex: top?.color ?? "#8A8494")
        ZStack(alignment: .topTrailing) {
            Text(top?.icon ?? "❔").font(.system(size: selected ? 24 : 18))
                .padding(selected ? 9 : 7)
                .background(Circle().fill(Theme.bg.opacity(0.9)))
                .overlay(Circle().stroke(color, lineWidth: 2))
                .shadow(color: color, radius: 8)
            if spot.detections.count > 1 {
                Text("\(spot.detections.count)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(color))
                    .offset(x: 8, y: -6)
            }
        }
        .animation(.spring, value: selected)
    }
}

/// Placer un appareil à sa vraie position : GPS du téléphone ou toucher la carte.
struct PlaceDeviceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var moveHistory = true
    @State private var locating = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $camera) {
                        UserAnnotation()
                        if let coordinate {
                            Annotation(device.name, coordinate: coordinate) {
                                Image(systemName: "sensor.fill").foregroundStyle(Theme.bg)
                                    .padding(8).background(Circle().fill(Theme.mint)).shadow(color: Theme.mint, radius: 8)
                            }
                        }
                    }
                    .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
                    .mapControls { MapUserLocationButton(); MapCompass() }
                    .onTapGesture { point in
                        if let c = proxy.convert(point, from: .local) { coordinate = c }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Touchez la carte à l'endroit exact où se trouve le nez, ou utilisez le GPS du téléphone en étant à côté.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Button {
                        Task {
                            locating = true
                            if let loc = await store.location.currentLocation() {
                                coordinate = loc.coordinate
                                camera = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 250, pitch: 45))
                            }
                            locating = false
                        }
                    } label: {
                        Label(locating ? "Recherche du GPS…" : "Utiliser ma position actuelle", systemImage: "location.fill")
                    }
                    .buttonStyle(GhostButtonStyle(color: Theme.sky))
                    if store.location.denied {
                        Text("Localisation refusée : Réglages → Confidentialité → Service de localisation → Nez.")
                            .font(.system(size: 12)).foregroundStyle(Theme.ember)
                    }
                    Toggle("Déplacer aussi ses anciennes détections", isOn: $moveHistory).font(.system(size: 14))
                    if let c = coordinate {
                        Text(String(format: "%.6f, %.6f", c.latitude, c.longitude)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
                    }
                    Button("Enregistrer la position") {
                        guard let c = coordinate else { return }
                        Task {
                            saving = true
                            await store.placeDevice(device.id, latitude: c.latitude, longitude: c.longitude, moveHistory: moveHistory)
                            saving = false
                            dismiss()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.mint))
                    .disabled(coordinate == nil || saving)
                    .opacity(coordinate == nil ? 0.5 : 1)
                }
                .padding(20)
                .background(Theme.bg)
            }
            .navigationTitle("Placer \(device.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .onAppear {
                store.location.start()
                if let lat = device.lat, let lon = device.lon {
                    let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    coordinate = c
                    camera = .camera(MapCamera(centerCoordinate: c, distance: 400, pitch: 0))
                }
            }
        }
    }
}
