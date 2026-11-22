import CoreLocation
import Observation

/// Position GPS réelle du téléphone (utilisée pour placer les appareils sur la carte).
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var status: CLAuthorizationStatus
    var onUpdate: ((CLLocation) -> Void)?

    var authorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var denied: Bool { status == .denied || status == .restricted }

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10  // mètres
    }

    func requestPermission() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func start() {
        requestPermission()
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    /// Attend une position précise (≤ 50 m) pendant quelques secondes.
    func currentLocation(timeout: Double = 8) async -> CLLocation? {
        start()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let loc = location, loc.horizontalAccuracy <= 50, abs(loc.timestamp.timeIntervalSinceNow) < 15 { return loc }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return location
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if authorized { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        location = last
        onUpdate?(last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
