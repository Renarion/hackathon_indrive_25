//
//  MonitoringStatus.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 12/09/2025.
//

import SwiftUI

enum MonitoringStatus: String, Sendable {
    case preparing
    case monitoring
    case accedent
    
    var name: String {
        switch self {
        case .preparing: "Preparing"
        case .monitoring: "Monitoring"
        case .accedent: "Accedent detected"
        }
    }
    
    var color: Color {
        switch self {
        case .preparing: .blue.opacity(0.5)
        case .monitoring: .accent
        case .accedent: .red
        }
    }
}
