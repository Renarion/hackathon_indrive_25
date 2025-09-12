//
//  Data+Append.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import Foundation

public extension Data {
    mutating func append(_ string: String, encoding: String.Encoding = .utf8) {
        guard let data = string.data(using: encoding) else {
            return
        }
        append(data)
    }
}
