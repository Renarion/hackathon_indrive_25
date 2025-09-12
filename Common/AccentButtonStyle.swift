//
//  AccentButtonStyle.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import SwiftUI

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.accent)
            .foregroundColor(.black)
            .fontWeight(.medium)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
