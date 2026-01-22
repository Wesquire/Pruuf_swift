import Foundation
import CoreLocation
import Combine

/// Service for handling location-related functionality
/// Used for in-person ping verification
/// Phase 6 Section 6.2: Ping Completion Methods - In-Person Verification
@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = LocationService()

    // MARK: - Published Properties

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isUpdatingLocation: Bool = false
    @Published private(set) var lastError: LocationServiceError?

    // MARK: - Private Properties

    private let locationManager: CLLocationManager
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration

    /// Minimum accuracy required for in-person verification (in meters)
    static let minimumAccuracy: CLLocationAccuracy = 100

    /// Timeout for location requests (in seconds)
    static let locationTimeout: TimeInterval = 30

    // MARK: - Initialization

    override init() {
        locationManager = CLLocationManager()
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone

        // Get initial authorization status
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Authorization

    /// Check if location services are available and authorized
    var isLocationAvailable: Bool {
        CLLocationManager.locationServicesEnabled() &&
        (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
    }

    /// Check if we need to request permission
    var needsPermission: Bool {
        authorizationStatus == .notDetermined
    }

    /// Check if permission was denied
    var isPermissionDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Request location permission (when in use)
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Get Current Location

    /// Get the current location for in-person verification
    /// - Returns: The current CLLocation with GPS coordinates
    /// - Throws: LocationServiceError if location cannot be obtained
    func getCurrentLocation() async throws -> CLLocation {
        // Check if location services are enabled
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.locationServicesDisabled
        }

        // Check authorization status
        switch authorizationStatus {
        case .notDetermined:
            // Request permission and wait for result
            requestPermission()
            try await waitForAuthorization()

        case .denied, .restricted:
            throw LocationServiceError.permissionDenied

        case .authorizedWhenInUse, .authorizedAlways:
            break // We're good to go

        @unknown default:
            throw LocationServiceError.unknownAuthorizationStatus
        }

        // Get location using async continuation
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.isUpdatingLocation = true
            self.lastError = nil
            self.locationManager.requestLocation()

            // Set timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(Self.locationTimeout * 1_000_000_000))
                if self.locationContinuation != nil {
                    self.locationContinuation?.resume(throwing: LocationServiceError.timeout)
                    self.locationContinuation = nil
                    self.isUpdatingLocation = false
                }
            }
        }
    }

    /// Wait for authorization status to change from notDetermined
    private func waitForAuthorization() async throws {
        // Wait up to 60 seconds for user to respond to permission dialog
        for _ in 0..<60 {
            if authorizationStatus != .notDetermined {
                if authorizationStatus == .denied || authorizationStatus == .restricted {
                    throw LocationServiceError.permissionDenied
                }
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        throw LocationServiceError.permissionTimeout
    }

    // MARK: - Validation

    /// Check if a location is accurate enough for in-person verification
    /// - Parameter location: The location to validate
    /// - Returns: True if accuracy is within acceptable range
    func isLocationAccurate(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy <= Self.minimumAccuracy && location.horizontalAccuracy >= 0
    }

    /// Create a VerificationLocation from a CLLocation
    /// - Parameter location: The CLLocation to convert
    /// - Returns: A VerificationLocation suitable for the Ping model
    func makeVerificationLocation(from location: CLLocation) -> VerificationLocation {
        VerificationLocation(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }

            self.isUpdatingLocation = false
            self.currentLocation = location

            // Check accuracy
            if self.isLocationAccurate(location) {
                self.locationContinuation?.resume(returning: location)
            } else {
                self.locationContinuation?.resume(throwing: LocationServiceError.insufficientAccuracy(location.horizontalAccuracy))
            }
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isUpdatingLocation = false

            let locationError: LocationServiceError
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    locationError = .permissionDenied
                case .locationUnknown:
                    locationError = .locationUnknown
                case .network:
                    locationError = .networkError
                default:
                    locationError = .systemError(clError)
                }
            } else {
                locationError = .systemError(error)
            }

            self.lastError = locationError
            self.locationContinuation?.resume(throwing: locationError)
            self.locationContinuation = nil
        }
    }
}

// MARK: - Location Service Errors

enum LocationServiceError: LocalizedError {
    case locationServicesDisabled
    case permissionDenied
    case permissionTimeout
    case unknownAuthorizationStatus
    case timeout
    case locationUnknown
    case networkError
    case insufficientAccuracy(CLLocationAccuracy)
    case systemError(Error)

    var errorDescription: String? {
        switch self {
        case .locationServicesDisabled:
            return "Location services are disabled. Please enable them in Settings."
        case .permissionDenied:
            return "Location permission was denied. Please enable location access in Settings."
        case .permissionTimeout:
            return "Location permission request timed out."
        case .unknownAuthorizationStatus:
            return "Unknown location authorization status."
        case .timeout:
            return "Location request timed out. Please try again."
        case .locationUnknown:
            return "Unable to determine your location. Please try again."
        case .networkError:
            return "Network error while getting location. Please check your connection."
        case .insufficientAccuracy(let accuracy):
            return "Location accuracy (\(Int(accuracy))m) is not sufficient for in-person verification."
        case .systemError(let error):
            return "Location error: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .locationServicesDisabled:
            return "Go to Settings > Privacy > Location Services and turn on location services."
        case .permissionDenied:
            return "Go to Settings > PRUUF and enable location access."
        case .timeout, .locationUnknown:
            return "Make sure you have a clear view of the sky and try again."
        case .networkError:
            return "Check your internet connection and try again."
        case .insufficientAccuracy:
            return "Move to an area with better GPS reception and try again."
        default:
            return nil
        }
    }
}
