//
//  LocationManager.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import Foundation
import CoreLocation
import MapKit

enum LocationError: Error, LocalizedError {
    case permissionDenied
    case locationUnavailable
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied"
        case .locationUnavailable:
            return "Location unavailable"
        case .timeout:
            return "Location request timeout"
        }
    }
}

final class LocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    
    var location: CLLocation?
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        authorizationStatus = manager.authorizationStatus
    }
    
    // MARK: - Public Methods
    
    /// Запрашивает разрешение на использование геолокации
    func requestLocationPermission() async -> CLAuthorizationStatus {
        if authorizationStatus != .notDetermined {
            return authorizationStatus
        }
        
        return await withCheckedContinuation { continuation in
            self.authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }
    
    /// Получает текущую геолокацию
    func getCurrentLocation() async throws -> CLLocation {
        guard isLocationServicesEnabled else {
            throw LocationError.locationUnavailable
        }

        let status = await requestLocationPermission()
        
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationError.permissionDenied
        }
        
        manager.requestLocation()
        
        return manager.location ?? CLLocation(latitude: 0, longitude: 0)
    }
    
    /// Начинает непрерывное отслеживание геолокации
    func startLocationUpdates() async throws {
        let status = await requestLocationPermission()
        
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationError.permissionDenied
        }
        
        manager.startUpdatingLocation()
    }
    
    /// Останавливает отслеживание геолокации
    func stopLocationUpdates() {
        manager.stopUpdatingLocation()
    }
    
    // MARK: - Legacy Methods
    
    func requestLocation() {
        Task {
            do {
                _ = try await getCurrentLocation()
            } catch {
                print("Failed to get location: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let newStatus = manager.authorizationStatus
            authorizationStatus = newStatus
            
            if let continuation = authorizationContinuation {
                authorizationContinuation = nil
                continuation.resume(returning: newStatus)
            }
            
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                // Можем начать обновления локации если нужно
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let newLocation = locations.last else { return }
            
            location = newLocation
            region = MKCoordinateRegion(
                center: newLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            
            // Завершаем continuation если ожидается одноразовый запрос локации
            if let continuation = locationContinuation {
                locationContinuation = nil
                continuation.resume(returning: newLocation)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("Location manager failed with error: \(error.localizedDescription)")
            
            if let continuation = locationContinuation {
                locationContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
