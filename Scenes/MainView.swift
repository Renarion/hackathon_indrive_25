//
//  ContentView.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import SwiftUI
import MapKit

struct MainView: View {
    private let worker = MainWorker()
    
    @State
    private var isConfigured: Bool = false
    @State
    private var isDrivingModeEnabled: Bool = false
    @State
    private var isConfirmationDialogPresented: Bool = false
    @State
    private var isReportResultPresented: Bool = false
    @State
    private var status: MonitoringStatus = .preparing
    @State
    private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    @State
    private var host: String = ""
    @State
    private var trackingMode: MapUserTrackingMode = .follow
    @State
    private var countdown: Int = 5
    @State
    private var countdownTimer: Timer?
    @State
    private var isAnimated: Bool = false
    
    @State
    private var monitoringTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 8) {
            if !isConfigured {
                VStack(spacing: 16) {
                    Text("Technical Screen")
                        .font(.title)
                    TextField("API Host", text: $host)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Configure") {
                        isConfigured = true
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(host.isEmpty)
                }
            } else {
                if isDrivingModeEnabled {
                    monitoringView()
                } else {
                    welcomeView()
                }
            }
        }
        .padding()
        .onChange(of: isDrivingModeEnabled) { _, isEnabled in
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
        .sheet(isPresented: $isConfirmationDialogPresented) {
            confirmationView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isReportResultPresented) {
            reportSendView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private extension MainView {
    @ViewBuilder
    func welcomeView() -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "shield.righthalf.filled")
                .font(.title)
                .foregroundStyle(.black)
                .padding(12)
                .background(.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(spacing: 8) {
                Text("Safety Assist")
                    .font(.title)
                Text("We're here for you, just in case.\nEnable ride monitoring so we can send help quickly if an accident occurs.")
                    .font(.headline)
                    .fontWeight(.regular)
                    .opacity(0.8)
            }
            .multilineTextAlignment(.center)
            
            Spacer()
            
            Button("Enable Monitoring", systemImage: "car.fill") {
                isDrivingModeEnabled.toggle()
            }
            .buttonStyle(AccentButtonStyle())
        }
    }
    
    @ViewBuilder
    func monitoringView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title)
                .foregroundStyle(.black)
                .padding(12)
                .background(.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(spacing: 8) {
                Text("You are on a ride")
                    .font(.title)
                Text("Ride monitoring system is active. Have a safe ride!")
                    .font(.headline)
                    .fontWeight(.regular)
                    .opacity(0.8)
            }
            .multilineTextAlignment(.center)
            
            VStack {
                Text("Current status: \(status.name)")
                    .font(.body)
                    .foregroundStyle(.black)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(status.color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Map(
                coordinateRegion: $mapRegion,
                showsUserLocation: true,
                userTrackingMode: $trackingMode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    trackingMode = .follow
                } label: {
                    Image(systemName: "location.fill")
                        .font(.body)
                        .foregroundStyle(.accent)
                        .padding(12)
                        .background(Color.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
            }
            
            Button("Disable Monitoring", systemImage: "car.fill") {
                isDrivingModeEnabled = false
            }
            .buttonStyle(AccentButtonStyle())
        }
    }
    
    @ViewBuilder
    func confirmationView() -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "light.beacon.min.fill")
                .font(.title)
                .foregroundStyle(.black)
                .padding(12)
                .background(.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .scaleEffect(isAnimated ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8),
                    value: isAnimated
                )
            
            VStack(spacing: 8) {
                Text("Detected a possible accident")
                    .font(.title)
                Text("We will contact the InDrive Response Team if you don't respond.")
                    .font(.headline)
                    .fontWeight(.regular)
                    .opacity(0.8)
            }
            .multilineTextAlignment(.center)
            
            Spacer()
            
            VStack(spacing: 8) {
                Button(action: {
                    confirmAction()
                }) {
                    Text("Send SOS (\(countdown))")
                }
                .buttonStyle(DangerButtonStyle())
                .frame(maxWidth: .infinity)

                Button("I'm Safe") {
                    stopCountdown()
                    isConfirmationDialogPresented = false
                }
                .buttonStyle(AccentButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .onAppear {
            isAnimated = true
            startCountdown {
                confirmAction()
            }
        }
        .onDisappear {
            isAnimated = false
            stopCountdown()
        }
    }
    
    @ViewBuilder
    func reportSendView() -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "light.beacon.min.fill")
                .font(.title)
                .foregroundStyle(.black)
                .padding(12)
                .background(.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(spacing: 8) {
                Text("Report Sent")
                    .font(.title)
                Text("Our team has been notified and is now reviewing your report. Help is on the way.")
                    .font(.headline)
                    .fontWeight(.regular)
                    .opacity(0.8)
            }
            .multilineTextAlignment(.center)
            
            Spacer()
            
            Button("OK") {
                isReportResultPresented = false
            }
            .buttonStyle(AccentButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

private extension MainView {
    func startMonitoring() {
        monitoringTask = Task {
            for await updatedStatus in await worker.performMonitoring(with: host) {
                if Task.isCancelled { break }
                status = updatedStatus
                
                if status == .accedent {
                    isConfirmationDialogPresented = true
                }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        
        Task {
            await worker.stopMonitoring()
        }
    }
    
    func startCountdown(_ completion: @escaping () -> Void) {
        countdown = 10
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
                completion()
            }
        }
    }
    
    func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    func confirmAction() {
        stopCountdown()
        isConfirmationDialogPresented = false
        isReportResultPresented = true
        
        Task {
            await worker.pushAccedentReport()
        }
    }
}
