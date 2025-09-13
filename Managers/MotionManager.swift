//
//  MotionManager.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import Foundation
import CoreMotion

enum MotionManagerError: Error {
    case accelerometerNotAvailable
    case noData
}

struct MotionManager {
    private let motionManager = CMMotionManager()
    
    func startStreamAccelerometerData() -> AsyncThrowingStream<CMAcceleration, Error> {
        return AsyncThrowingStream<CMAcceleration, Error> { continuation in
            guard motionManager.isAccelerometerAvailable else {
                continuation.finish(throwing: MotionManagerError.accelerometerNotAvailable)
                return
            }
            
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: .main) { data, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                
                guard let data = data else {
                    continuation.finish(throwing: MotionManagerError.noData)
                    return
                }
                
                continuation.yield(data.acceleration)
            }
            
            continuation.onTermination = { _ in
                self.motionManager.stopAccelerometerUpdates()
            }
        }
    }
    
    func stopAccelerometer() {
        motionManager.stopAccelerometerUpdates()
    }
}
