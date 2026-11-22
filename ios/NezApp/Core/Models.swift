import Foundation

// Les clés JSON du serveur sont en snake_case ; le décodeur convertit les propriétés en camelCase,
// mais PAS les clés des dictionnaires (data, fingerprint) qui restent "bme688_gas", "sgp41_voc"…

/// Capteurs de gaz affichés dans l'app (clés telles qu'envoyées par le serveur).
enum Channel: String, CaseIterable, Identifiable {
    case bme688Gas = "bme688_gas", sgp41Voc = "sgp41_voc", sgp41Nox = "sgp41_nox", ens160Tvoc = "ens160_tvoc"
    case mq3, mq4, mq135
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bme688Gas: return "BME688"
        case .sgp41Voc: return "COV"
        case .sgp41Nox: return "NOx"
        case .ens160Tvoc: return "COVT"
        case .mq3: return "Alcool"
        case .mq4: return "Méthane"
        case .mq135: return "Ammoniac"
        }
    }
    var unit: String {
        switch self {
        case .bme688Gas: return "Ω"
        case .sgp41Voc, .sgp41Nox: return "indice"
        case .ens160Tvoc: return "ppb"
        default: return "V"
        }
    }
}

struct Device: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var room: String?
    var lat: Double?
    var lon: Double?
    var state: String
    var lastSeen: Date?
    var calibrated: Bool
    var online: Bool
}

struct Odor: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var icon: String
    var color: String
    var alertLevel: String
    var description: String?
    var isAir: Bool
    var samples: Int
    var detections: Int
    var fingerprint: [String: Double]
    var lastDetected: Date?
}

struct OdorInput: Encodable {
    var name: String
    var icon: String
    var color: String
    var alertLevel: String
    var description: String?
}

struct Detection: Codable, Identifiable, Hashable {
    let id: Int
    let ts: Date
    let deviceId: String
    let odorId: Int?
    let label: String
    let confidence: Double
    let lat: Double?
    let lon: Double?
    let room: String?
}

struct AlertItem: Codable, Identifiable, Hashable {
    let id: Int
    let ts: Date
    let deviceId: String
    let level: String
    let title: String
    let message: String
    let odorId: Int?
    var acknowledged: Bool
}

struct TrainingSession: Codable, Identifiable, Hashable {
    let id: Int
    let deviceId: String
    let odorId: Int
    let targetWindows: Int
    let skipWindows: Int
    let collected: Int
    let status: String
    let createdAt: Date

    var progress: Double { targetWindows == 0 ? 0 : Double(collected) / Double(targetWindows) }
}

struct ModelInfo: Codable {
    struct Meta: Codable {
        struct Klass: Codable, Hashable { let odorId: Int; let name: String; let samples: Int }
        struct Feature: Codable, Hashable { let feature: String; let importance: Double }
        var trainedAt: String?
        var nSamples: Int?
        var accuracy: Double?
        var cvFolds: Int?
        var classes: [Klass]?
        var confusionMatrix: [[Int]]?
        var topFeatures: [Feature]?
    }
    let trained: Bool
    let meta: Meta
    let samplesPerOdor: [String: Int]
}

struct Stats: Codable {
    struct OdorCount: Codable, Hashable { let odorId: Int?; let label: String; let color: String; let icon: String; let count: Int }
    struct RoomCount: Codable, Hashable { let room: String; let count: Int }
    struct Hour: Codable, Hashable { let hour: String; let count: Int }
    let detectionsDay: Int
    let detectionsTotal: Int
    let unacknowledgedAlerts: Int
    let devicesOnline: Int
    let devicesTotal: Int
    let byOdor: [OdorCount]
    let byRoom: [RoomCount]
    let timeline: [Hour]
}

struct Health: Codable {
    let status: String
    let mqttConnected: Bool
    let modelTrained: Bool
}

// MARK: - Événements temps réel (WebSocket)

struct Prediction: Codable, Hashable {
    struct Probability: Codable, Hashable { let odorId: Int; let label: String; let color: String; let p: Double }
    let deviceId: String
    let odorId: Int?
    let label: String
    let confidence: Double
    let color: String
    let icon: String
    let alertLevel: String
    let probabilities: [Probability]
    let fingerprint: [String: Double]
    let ts: Date
}

struct ReadingEvent: Codable {
    let deviceId: String
    let ts: Date
    let warming: Bool
    let data: [String: Double]
}

struct ReadingPoint: Identifiable, Hashable {
    let id = UUID()
    let ts: Date
    let data: [String: Double]
}

struct EventType: Decodable { let type: String }
struct DetectionEvent: Decodable { let detection: Detection }
struct AlertEvent: Decodable { let alert: AlertItem }
struct DeviceEvent: Decodable { let device: Device }
struct TrainingEvent: Decodable { let session: TrainingSession }
struct CalibratedEvent: Decodable { let deviceId: String }
