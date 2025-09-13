//
//  AudioRecordingManager.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import Foundation
import AVFoundation

enum AudioRecordingError: Error, LocalizedError {
    case configurationFailed
    case missingBuiltInMicrophone
    case unableToSetBuiltInMicrophone
    case unableToCreateAudioRecorder
    case permissionDenied
    case recordingFailed
}

enum AudioRecordingState: String, Sendable {
    case recording
    case stopped
}

final class AudioRecordingManager: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var recorder: AVAudioRecorder!
    private var state: AudioRecordingState = .stopped
    
    private let recordingFileName = "recording.wav"
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        do {
            try configureAudioSession()
            try enableBuiltInMicrophone()
            try setupAudioRecorder()
        } catch {
            // If any errors occur during initialization,
            // terminate the app with a fatalError.
            fatalError("Error: \(error)")
        }
    }
    
    // MARK: - Recorder Control
    
    func requestRecordPermission() async throws {
        await AVAudioApplication.requestRecordPermission()
    }
    
    func record() {
        guard state != .recording else { return }
        
        recorder.record()
        state = .recording
    }
    
    func takeRecordedAudio() throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appending(path: recordingFileName)
        
        return try Data(contentsOf: fileURL)
    }
    
    func stop() {
        recorder.stop()
        state = .stopped
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let destURL = FileManager.default.temporaryDirectory.appending(path: recordingFileName)
        
        try? FileManager.default.removeItem(at: destURL)
        try? FileManager.default.moveItem(at: recorder.url, to: destURL)

        recorder.prepareToRecord()
        state = .stopped
    }
}

private extension AudioRecordingManager {
    func setupAudioRecorder() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(recordingFileName)
        
        do {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
            recorder = try AVAudioRecorder(url: fileURL, settings: audioSettings)
        } catch {
            throw AudioRecordingError.unableToCreateAudioRecorder
        }
        
        recorder.delegate = self
        recorder.prepareToRecord()
    }
    
    func configureAudioSession() throws {
        do {
            // Get the instance of audio session.
            let audioSession = AVAudioSession.sharedInstance()
            
            // Set the audio session category to record, allowing default to speaker and Bluetooth.
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker])
            
            // Activate the audio session.
            try audioSession.setActive(true)
        } catch {
            // If an error occurs during configuration, throw an appropriate error.
            throw AudioRecordingError.configurationFailed
        }
    }
    
    func enableBuiltInMicrophone() throws {
        // Get the instance of audio session.
        let audioSession = AVAudioSession.sharedInstance()

        // Get the audio inputs.
        let availableInputs = audioSession.availableInputs
        
        // Find the available input that corresponds to the built-in microphone.
        guard let builtInMicInput = availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            // If no built-in microphone is found, throw an error.
            throw AudioRecordingError.missingBuiltInMicrophone
        }
        
        do {
            // Set the built-in microphone as the preferred input.
            try audioSession.setPreferredInput(builtInMicInput)
        } catch {
            // If an error occurs while setting the preferred input, throw an appropriate error.
            throw AudioRecordingError.unableToSetBuiltInMicrophone
        }
    }
}
