import SwiftUI
import AVFoundation
import Combine

struct CameraView: UIViewControllerRepresentable {
    let imageHandler: (UIImage) -> Void
    @Binding var isRunning: Bool
    let viewModel: DocumentScannerViewModel

    func makeUIViewController(context: Context) -> CameraPreviewController {
        let vc = CameraPreviewController()
        vc.delegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.viewModel = viewModel
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.viewModel = viewModel

        // Share the controller instance with the view model once available
        if let controller = uiViewController.controller {
            viewModel.attachCamera(controller)
        }
        
        // Remove the automatic start/stop based on isRunning
        // Let the camera run continuously once started
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(parent: self)
        c.viewModel = viewModel
        return c
    }

    final class Coordinator: NSObject, CameraPreviewControllerDelegate {
        var parent: CameraView
        var viewModel: DocumentScannerViewModel?

        init(parent: CameraView) {
            self.parent = parent
        }

        func cameraPreviewController(_ controller: CameraPreviewController, didCapture image: UIImage) {
            parent.imageHandler(image)
        }
    }
}

// MARK: - UIKit host + camera controller

protocol CameraPreviewControllerDelegate: AnyObject {
    func cameraPreviewController(_ controller: CameraPreviewController, didCapture image: UIImage)
}

final class CameraPreviewController: UIViewController {
    weak var delegate: CameraPreviewControllerDelegate?
    var controller: CameraController?

    private let previewLayer = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        Task {
            do {
                let c = try await CameraController()
                controller = c
                try await c.configurePreview(on: previewLayer)
                try await c.start()
            } catch {
                print("CameraPreviewController setup error: \(error)")
            }
        }

        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(capture))
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    @objc private func capture() {
        Task {
            guard let controller else { return }
            do {
                let image = try await controller.capturePhoto()
                await MainActor.run {
                    delegate?.cameraPreviewController(self, didCapture: image)
                }
            } catch {
                print("Capture error: \(error)")
            }
        }
    }
}

// MARK: - CameraController

enum CameraError: Error, LocalizedError {
    case noVideoDeviceAvailable
    case failedToCreateInput

    var errorDescription: String? {
        switch self {
        case .noVideoDeviceAvailable:
            return "No video capture device is available on this device."
        case .failedToCreateInput:
            return "Failed to create camera input."
        }
    }
}

actor CameraController {
    private let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isCapturing = false

    // Retain in-flight photo delegates until completion
    private var inFlightDelegates: Set<PhotoCaptureDelegate> = []

    init() async throws {}

    func configurePreview(on layer: AVCaptureVideoPreviewLayer) async throws {
        try await configureSessionIfNeeded()
        await MainActor.run {
            layer.session = session
        }
    }

    func start() async throws {
        try await configureSessionIfNeeded()
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() async throws {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func setTorch(on: Bool) async throws {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        try device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func flipCamera() async throws {
        // Don't flip if currently capturing
        guard !isCapturing else { return }
        
        currentPosition = (currentPosition == .back) ? .front : .back
        try await reconfigureForCurrentPosition()
    }

    func capturePhoto() async throws -> UIImage {
        // Prevent multiple simultaneous captures
        guard !isCapturing else {
            throw NSError(domain: "Camera", code: -3, userInfo: [NSLocalizedDescriptionKey: "Capture already in progress"])
        }
        
        isCapturing = true
        defer { isCapturing = false }
        
        try await configureSessionIfNeeded()

        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        
        // Enable flash for back camera in low light (optional)
        if let device = videoDeviceInput?.device, device.hasFlash, currentPosition == .back {
            settings.flashMode = .auto
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: NSError(domain: "Camera", code: -99, userInfo: [NSLocalizedDescriptionKey: "Camera deallocated"]))
                return
            }

            var delegateRef: PhotoCaptureDelegate?

            delegateRef = PhotoCaptureDelegate { [weak self] image, error in
                guard let self else { return }
                
                Task {
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let image = image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "No image"]))
                    }

                    if let delegateRef {
                        await self.removeInFlight(delegateRef)
                    }
                }
            }

            guard let delegateRef else { return }

            Task {
                await self.addInFlight(delegateRef)
                // Ensure we're on the session queue for capture
                self.photoOutput.capturePhoto(with: settings, delegate: delegateRef)
            }
        }
    }

    private func addInFlight(_ delegate: PhotoCaptureDelegate) {
        inFlightDelegates.insert(delegate)
    }

    private func removeInFlight(_ delegate: PhotoCaptureDelegate) {
        inFlightDelegates.remove(delegate)
    }

    private func configureSessionIfNeeded() async throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        let device = try bestDevice(position: currentPosition)
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        } else {
            session.commitConfiguration()
            throw CameraError.failedToCreateInput
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            
            // Configure connection for proper orientation
            if let connection = photoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }

    private func reconfigureForCurrentPosition() async throws {
        // Don't reconfigure while capturing
        guard !isCapturing else { return }
        
        session.beginConfiguration()
        
        if let input = videoDeviceInput {
            session.removeInput(input)
        }
        
        let device = try bestDevice(position: currentPosition)
        let input = try AVCaptureDeviceInput(device: device)
        
        if session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
            
            // Reconfigure connection orientation
            if let connection = photoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        } else {
            session.commitConfiguration()
            throw CameraError.failedToCreateInput
        }
        
        session.commitConfiguration()
    }

    private func bestDevice(position: AVCaptureDevice.Position) throws -> AVCaptureDevice {
        // Try dual camera first for back camera (better quality)
        if position == .back {
            if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
                return device
            }
        }
        
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        
        if let any = AVCaptureDevice.default(for: .video) {
            return any
        }
        
        throw CameraError.noVideoDeviceAvailable
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?, Error?) -> Void

    init(completion: @escaping (UIImage?, Error?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(nil, error)
            return
        }
        
        guard let data = photo.fileDataRepresentation() else {
            completion(nil, NSError(domain: "Camera", code: -2, userInfo: [NSLocalizedDescriptionKey: "No photo data"]))
            return
        }
        
        guard let image = UIImage(data: data) else {
            completion(nil, NSError(domain: "Camera", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"]))
            return
        }
        
        completion(image, nil)
    }
}
