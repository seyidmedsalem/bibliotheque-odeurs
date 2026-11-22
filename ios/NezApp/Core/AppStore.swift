import CoreLocation
import Foundation
import Observation

/// État global de l'application : données du serveur + flux temps réel.
@Observable
@MainActor
final class AppStore {
    // Connexion
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? AppStore.defaultServer

    /// Adresse par défaut, injectée à la compilation (NEZ_DEFAULT_SERVER), sinon localhost.
    static var defaultServer: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "NezDefaultServer") as? String) ?? ""
        return value.isEmpty || value.contains("$(") ? "http://localhost:8000" : value
    }
    var token: String? = UserDefaults.standard.string(forKey: "token")
    var isLoggedIn: Bool { token != nil }
    var liveConnected = false
    var health: Health?

    // Données
    var devices: [Device] = []
    var odors: [Odor] = []
    var alerts: [AlertItem] = []
    var detections: [Detection] = []
    var stats: Stats?
    var modelInfo: ModelInfo?
    var selectedDeviceId: String?

    // Temps réel
    var predictions: [String: Prediction] = [:]
    var readings: [String: [ReadingPoint]] = [:]
    var warming: [String: Bool] = [:]
    var activeSession: TrainingSession?

    // Interface
    var banner: AlertItem?
    var errorMessage: String?

    // Position réelle (GPS du téléphone)
    let location = LocationService()
    /// Appareil qui « suit » le téléphone : sa position est mise à jour avec le GPS (cartographie en marchant).
    var followDeviceId: String? = UserDefaults.standard.string(forKey: "followDeviceId") {
        didSet {
            UserDefaults.standard.set(followDeviceId, forKey: "followDeviceId")
            lastFollowSent = nil
            if followDeviceId != nil { location.start() }
        }
    }
    private var lastFollowSent: CLLocation?

    private let api = APIClient(baseURL: URL(string: "http://localhost:8000")!)
    private let socket = LiveSocket()
    private let maxPoints = 180

    var selectedDevice: Device? { devices.first { $0.id == selectedDeviceId } ?? devices.first }
    var unreadAlerts: Int { alerts.filter { !$0.acknowledged }.count }
    func odor(_ id: Int?) -> Odor? { odors.first { $0.id == id } }

    init() {
        api.baseURL = URL(string: serverURL) ?? api.baseURL
        api.token = token
        socket.onMessage = { [weak self] data in Task { @MainActor in self?.handle(data) } }
        socket.onState = { [weak self] up in Task { @MainActor in self?.liveConnected = up } }
        location.onUpdate = { [weak self] loc in Task { @MainActor in await self?.follow(loc) } }
        if followDeviceId != nil { location.start() }
    }

    /// Envoie la position du téléphone à l'appareil suivi (tous les 20 m environ).
    private func follow(_ loc: CLLocation) async {
        guard let id = followDeviceId, isLoggedIn, loc.horizontalAccuracy <= 65 else { return }
        if let last = lastFollowSent, loc.distance(from: last) < 20 { return }
        lastFollowSent = loc
        await placeDevice(id, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, moveHistory: false)
    }

    /// Place un appareil à une position réelle. moveHistory : ses anciennes détections le suivent.
    func placeDevice(_ id: String, latitude: Double, longitude: Double, moveHistory: Bool) async {
        struct Body: Encodable { let lat: Double; let lon: Double; let moveHistory: Bool }
        await run {
            let d: Device = try await api.request("PATCH", "/api/devices/\(id)",
                                                  body: Body(lat: latitude, lon: longitude, moveHistory: moveHistory))
            upsert(d)
        }
        if moveHistory { await loadDetections() }
    }

    // MARK: - Session

    func login(server: String, email: String, password: String) async throws {
        let cleaned = server.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: cleaned), url.scheme != nil else { throw APIError(message: "Adresse du serveur invalide") }
        #if !targetEnvironment(simulator)
        if let host = url.host, host == "localhost" || host == "127.0.0.1" {
            throw APIError(message: "Sur un vrai iPhone, « localhost » désigne le téléphone lui-même. "
                           + "Utilisez l'adresse IP du Mac sur le Wi-Fi, par exemple http://192.168.1.50:8000.")
        }
        #endif
        api.baseURL = url
        api.token = nil
        struct Login: Encodable { let email: String; let password: String }
        struct Token: Decodable { let accessToken: String }
        let t: Token = try await api.request("POST", "/api/auth/login", body: Login(email: email, password: password))
        serverURL = cleaned
        token = t.accessToken
        api.token = t.accessToken
        UserDefaults.standard.set(cleaned, forKey: "serverURL")
        UserDefaults.standard.set(t.accessToken, forKey: "token")
        await start()
    }

    func logout() {
        socket.disconnect()
        token = nil
        api.token = nil
        UserDefaults.standard.removeObject(forKey: "token")
        devices = []; odors = []; alerts = []; detections = []; predictions = [:]; readings = [:]
    }

    func start() async {
        guard isLoggedIn else { return }
        await refreshAll()
        if let url = api.webSocketURL() { socket.connect(to: url) }
    }

    func refreshAll() async {
        async let d: () = loadDevices()
        async let o: () = loadOdors()
        async let a: () = loadAlerts()
        async let s: () = loadStats()
        async let m: () = loadModel()
        async let det: () = loadDetections()
        async let h: () = loadHealth()
        _ = await (d, o, a, s, m, det, h)
        if let device = selectedDevice, readings[device.id] == nil { await loadHistory(device.id) }
    }

    // MARK: - Chargements

    private func run(_ work: () async throws -> Void) async {
        do { try await work() } catch {
            if let e = error as? APIError, e.message.contains("Connexion requise") { logout() }
            errorMessage = error.localizedDescription
        }
    }

    func loadDevices() async {
        await run {
            devices = try await api.get("/api/devices")
            if selectedDeviceId == nil || !devices.contains(where: { $0.id == selectedDeviceId }) {
                selectedDeviceId = devices.first(where: \.online)?.id ?? devices.first?.id
            }
        }
    }
    func loadOdors() async { await run { odors = try await api.get("/api/odors") } }
    func loadAlerts() async { await run { alerts = try await api.get("/api/alerts") } }
    func loadStats() async { await run { stats = try await api.get("/api/stats") } }
    func loadModel() async { await run { modelInfo = try await api.get("/api/model") } }
    func loadHealth() async { await run { health = try await api.get("/api/health") } }

    func loadDetections(hours: Int = 24 * 7, odorId: Int? = nil) async {
        var q = ["hours": String(hours), "limit": "1000"]
        if let odorId { q["odor_id"] = String(odorId) }
        await run { detections = try await api.get("/api/detections", query: q) }
    }

    func loadHistory(_ deviceId: String) async {
        struct M: Decodable { let ts: Date; let data: [String: Double] }
        await run {
            let rows: [M] = try await api.get("/api/devices/\(deviceId)/measurements", query: ["minutes": "5"])
            readings[deviceId] = rows.suffix(maxPoints).map { ReadingPoint(ts: $0.ts, data: $0.data) }
        }
    }

    // MARK: - Actions

    func updateDevice(_ id: String, name: String, room: String, lat: Double?, lon: Double?) async {
        struct Body: Encodable { let name: String; let room: String?; let lat: Double?; let lon: Double? }
        await run {
            let d: Device = try await api.request("PATCH", "/api/devices/\(id)",
                                                  body: Body(name: name, room: room.isEmpty ? nil : room, lat: lat, lon: lon))
            upsert(d)
        }
    }

    func calibrate(_ id: String) async { await run { try await api.send("POST", "/api/devices/\(id)/calibrate") } }
    func identify(_ id: String) async { await run { try await api.send("POST", "/api/devices/\(id)/identify") } }

    func saveOdor(_ input: OdorInput, id: Int?) async -> Bool {
        do {
            if let id {
                let _: Odor = try await api.request("PATCH", "/api/odors/\(id)", body: input)
            } else {
                let _: Odor = try await api.request("POST", "/api/odors", body: input)
            }
            await loadOdors()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteOdor(_ id: Int) async {
        await run { try await api.send("DELETE", "/api/odors/\(id)") }
        await loadOdors()
    }

    func startTraining(deviceId: String, odorId: Int, windows: Int) async {
        struct Body: Encodable { let deviceId: String; let odorId: Int; let windows: Int; let skipWindows: Int }
        await run {
            activeSession = try await api.request("POST", "/api/training/sessions",
                                                  body: Body(deviceId: deviceId, odorId: odorId, windows: windows, skipWindows: 2))
        }
    }

    func cancelTraining() async {
        guard let s = activeSession else { return }
        await run { activeSession = try await api.request("POST", "/api/training/sessions/\(s.id)/cancel", body: Optional<String>.none) }
    }

    func trainModel() async -> String? {
        do {
            modelInfo = try await api.request("POST", "/api/model/train", body: Optional<String>.none)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func acknowledge(_ alert: AlertItem) async {
        await run {
            let a: AlertItem = try await api.request("POST", "/api/alerts/\(alert.id)/ack", body: Optional<String>.none)
            if let i = alerts.firstIndex(where: { $0.id == a.id }) { alerts[i] = a }
        }
    }

    func acknowledgeAll() async {
        await run { try await api.send("POST", "/api/alerts/ack-all") }
        await loadAlerts()
    }

    // MARK: - Événements temps réel

    private func upsert(_ d: Device) {
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d } else { devices.append(d) }
        if selectedDeviceId == nil { selectedDeviceId = d.id }
    }

    private func handle(_ data: Data) {
        let dec = APIClient.decoder
        guard let kind = try? dec.decode(EventType.self, from: data).type else { return }
        switch kind {
        case "reading":
            guard let e = try? dec.decode(ReadingEvent.self, from: data) else { return }
            var list = readings[e.deviceId] ?? []
            list.append(ReadingPoint(ts: e.ts, data: e.data))
            if list.count > maxPoints { list.removeFirst(list.count - maxPoints) }
            readings[e.deviceId] = list
            warming[e.deviceId] = e.warming
            if !devices.contains(where: { $0.id == e.deviceId }) { Task { await loadDevices() } }
        case "prediction":
            if let p = try? dec.decode(Prediction.self, from: data) { predictions[p.deviceId] = p }
        case "detection":
            if let e = try? dec.decode(DetectionEvent.self, from: data) {
                detections.insert(e.detection, at: 0)
                Task { await loadStats() }
            }
        case "alert":
            if let e = try? dec.decode(AlertEvent.self, from: data) {
                alerts.insert(e.alert, at: 0)
                banner = e.alert
            }
        case "training_progress":
            if let e = try? dec.decode(TrainingEvent.self, from: data) {
                activeSession = e.session
                if e.session.status != "active" { Task { await loadOdors(); await loadModel() } }
            }
        case "device":
            if let e = try? dec.decode(DeviceEvent.self, from: data) { upsert(e.device) }
        case "calibrated":
            Task { await loadDevices() }
        default:
            break
        }
    }
}
