//
//  NetworkManager.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import Foundation
import CoreLocation

enum NetworkError: Error {
    case invalidResponse
    case serverError(Int)
}

actor NetworkManager: Sendable {
    private let session: URLSession
    private let serverURL: URL

    init(serverURL: URL, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.session = session
    }
    
    // MARK: - Public Methods
    
    func sendData<T: Codable & Sendable>(_ payload: T) async throws {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData

        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }
    }
    
    func sendData(timestamp: Double, location: CLLocation, photos: [Data], audio: Data) async throws {
        var multipart = MultipartRequest()
        for field in [
            "timestamp": String(timestamp),
            "latitude": String(location.coordinate.latitude),
            "longitude": String(location.coordinate.longitude)
        ] {
            multipart.add(key: field.key, value: field.value)
        }

        for (index, photo) in photos.enumerated() {
            multipart.add(
                key: "photos",
                fileName: "photo-\(index).jpg",
                fileMimeType: "image/jpg",
                fileData: photo
            )
        }

        multipart.add(
            key: "audio",
            fileName: "audio.wav",
            fileMimeType: "audio/wav",
            fileData: audio
        )

        var request = URLRequest(url: serverURL)
        
        request.httpMethod = "POST"
        request.setValue(multipart.httpContentTypeHeadeValue, forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.httpBody

        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }
    }
}
