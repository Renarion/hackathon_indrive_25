//
//  SendSummaryDataRequest.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import Foundation

struct SendSummaryDataRequest: Codable, Sendable {
    let timestamp: Int
    let photos: [String]
}
