//
//  CameraManager.swift
//  SafetyMonitoring
//
//  Created by Aleksei Pleshkov on 11/09/2025.
//

import AVFoundation
import UIKit

enum CameraManagerError: Error {
    case deviceNotFound
    case takePhotoFailed
}

final class CameraManager: NSObject, @unchecked Sendable {
    // MARK: - Properties

    private let deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    private var devicePosition: AVCaptureDevice.Position
    private var flashMode: AVCaptureDevice.FlashMode = .off

    private var checkedContinuation: CheckedContinuation<UIImage?, Never>?
    private lazy var output = AVCapturePhotoOutput()

    private lazy var videoDevice = AVCaptureDevice.default(deviceType, for: .video, position: devicePosition)
    private lazy var session = AVCaptureSession()

    // MARK: - Init

    init(devicePosition: AVCaptureDevice.Position) {
        self.devicePosition = devicePosition
    }
}

// MARK: - CameraManagerLogic

extension CameraManager {
    var isFrontPosition: Bool {
        devicePosition == .front
    }

    var isFlashEnabled: Bool {
        flashMode == .on
    }

    var deviceAspectRatio: CGFloat {
        guard let videoDevice else {
            return 1
        }

        let activeFormat = videoDevice.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let width = CGFloat(dimensions.width)
        let height = CGFloat(dimensions.height)

        guard height > 0 else {
            return 1
        }

        let aspectRatio = width / height
        let normalizedAspectRatio = aspectRatio > 1 ? aspectRatio : 1

        return normalizedAspectRatio
    }

    @MainActor
    func setupSession() throws {
        guard let videoDevice else {
            throw CameraManagerError.deviceNotFound
        }

        session.beginConfiguration()

        defer {
            session.commitConfiguration()
        }

        if let deviceInput = try? AVCaptureDeviceInput(device: videoDevice), session.canAddInput(deviceInput) {
            session.addInput(deviceInput)
        }

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.sessionPreset = .photo
    }

    func startCapturing() async {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    func stopCapturing() async {
        guard session.isRunning else { return }
        session.stopRunning()
    }
    
    func takePhotos(count: Int, timeout: Double) async throws -> [Data] {
        var result: [Data] = []
        result.reserveCapacity(count)
        
        await startCapturing()
        
        for _ in 0..<count {
            let photo = await capturePhoto()
            
            guard let data = photo?.jpegData(compressionQuality: 0.8) else {
                throw CameraManagerError.takePhotoFailed
            }
            
            result.append(data)
            
            try await Task.sleep(for: .seconds(timeout))
        }
        
        await stopCapturing()

        return result
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let imageData = photo.fileDataRepresentation(), var image = UIImage(data: imageData) else {
            checkedContinuation?.resume(returning: nil)
            return
        }
        if isFrontPosition {
            image = UIImage(cgImage: image.cgImage!, scale: 1.0, orientation: .leftMirrored)
        }
        checkedContinuation?.resume(returning: image)
        checkedContinuation = nil
    }
}

// MARK: - Private Methods

private extension CameraManager {
    func capturePhoto() async -> UIImage? {
        guard
            session.isRunning,
            let videoConnection = output.connection(with: .video),
            videoConnection.isEnabled,
            videoConnection.isActive
        else {
            return nil
        }

        return await withCheckedContinuation { checkedContinuation in
            self.checkedContinuation = checkedContinuation
            
            let photoSettings = AVCapturePhotoSettings()

            if let photoPreviewType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.flashMode = .off
                if #available(iOS 18.0, *) {
                    photoSettings.isShutterSoundSuppressionEnabled = true
                }
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoPreviewType]
                output.capturePhoto(with: photoSettings, delegate: self)
            }
        }
    }

    func reloadSession() throws {
        session.beginConfiguration()

        defer {
            session.commitConfiguration()
        }

        session.inputs.forEach {
            session.removeInput($0)
        }

        session.outputs.forEach {
            session.removeOutput($0)
        }

        videoDevice = AVCaptureDevice.default(deviceType, for: .video, position: devicePosition)

        guard let videoDevice else {
            throw CameraManagerError.deviceNotFound
        }

        if let deviceInput = try? AVCaptureDeviceInput(device: videoDevice), session.canAddInput(deviceInput) {
            session.addInput(deviceInput)
        }

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.sessionPreset = .photo
    }
}
