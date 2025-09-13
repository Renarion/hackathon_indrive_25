//
//  Inter.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import SwiftUI

actor MainWorker: Sendable {
    private let locationManager = LocationManager()
    private let motionManager = MotionManager()
    private let audioRecordingManager = AudioRecordingManager()
    private let cameraManager = CameraManager(devicePosition: .front)
    private var networkManager = NetworkManager(serverURL: URL(string: "http://10.70.10.12:5000/uploading_to_gemini")!)
    
    private var accelerometerData: [Double] = []
    private var accedentData: [AccedentResultData] = []
    
    func performMonitoring(with host: String) -> AsyncStream<MonitoringStatus> {
        networkManager = NetworkManager(serverURL: URL(string: "http://\(host):5000/uploading_to_gemini")!)
        
        return AsyncStream<MonitoringStatus> { continuation in
            Task {
                continuation.yield(.preparing)
                
                try await locationManager.startLocationUpdates()
                try await audioRecordingManager.requestRecordPermission()

                do {
                    try await cameraManager.setupSession()
                    
                    for try await data in motionManager.startStreamAccelerometerData() {
                        let magnitude = calculateSingleMagnitude(x: data.x, y: data.y, z: data.z)
                        
                        if accelerometerData.count >= 100 {
                            continuation.yield(.monitoring)
                            
                            let new = accelerometerData[accelerometerData.count - 100..<accelerometerData.count]
                            let average = new.reduce(0, +) / Double(new.count)
                            let standartDeviation = calculateStandardDeviation(values: Array(new))
                            let deviation = average + 5 + standartDeviation
                            
                            if magnitude > deviation {
                                continuation.yield(.accedent)
                                try await collectAccedentReport()
                                accelerometerData = []
                                continuation.yield(.preparing)
                            }
                            
                            print(magnitude, average, deviation)
                        }
                        
                        accelerometerData.append(magnitude)
                    }
                } catch {
                    print(error)
                }
            }
        }
    }
    
    func stopMonitoring() async {
        motionManager.stopAccelerometer()
        locationManager.stopLocationUpdates()
    }
    
    func pushAccedentReport() {
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            
            if await accedentData.isEmpty {
                try await Task.sleep(for: .seconds(6))
            }
            
            do {
                let timestamp = Date().timeIntervalSince1970
                let location = try await locationManager.getCurrentLocation()
                
                var photos: [Data] = []
                var audio: Data = Data()
                
                for data in await accedentData {
                    switch data {
                    case .photos(let pho):
                        photos = pho
                    case .audio(let aud):
                        audio = aud
                    }
                }
                
                try await networkManager.sendData(
                    timestamp: timestamp,
                    location: location,
                    photos: photos,
                    audio: audio
                )
            } catch {
                print(error)
            }
        }
    }
}

private extension MainWorker {
    func resetAccedentReport() {
        accedentData = []
    }
    
    func collectAccedentReport() async throws {
        resetAccedentReport()
        
        let processedData = try await withThrowingTaskGroup(of: AccedentResultData.self, returning: [AccedentResultData].self) { group in
            group.addTask {
                .photos(try await self.cameraManager.takePhotos(count: 5, timeout: 0.3))
            }
            
            group.addTask {
                self.audioRecordingManager.record()
                try await Task.sleep(for: .seconds(5))
                self.audioRecordingManager.stop()
                return .audio(try self.audioRecordingManager.takeRecordedAudio())
            }
            
            return try await group.reduce(into: [AccedentResultData]()) { result, accedentResult in
                result.append(accedentResult)
            }
        }
        
        print(processedData)
        print("Data was collected")
        
        accedentData = processedData
    }
    
    func calculateSingleMagnitude(x: Double, y: Double, z: Double) -> Double {
        return sqrt(x * x + y * y + z * z)
    }
    
    func calculateStandardDeviation(values: [Double]) -> Double {
        guard values.count > 1 else { return 0.0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(values.count - 1)
        
        return sqrt(variance)
    }
}
