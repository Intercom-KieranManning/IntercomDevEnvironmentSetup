#if canImport(UIKit)
import Foundation
import AVFoundation
import CoreMedia
import WebRTC

enum CameraError: Error {
    case noCameraAvailable
    case noSupportedFormat
}

/// Owns exactly one `RTCCameraVideoCapturer` + `RTCVideoSource` + `RTCVideoTrack`. Native WebRTC
/// lets a single `RTCVideoTrack` be added directly to multiple `RTCPeerConnection`s, so — unlike
/// ClientPython's `SharedCameraSource` (a manual per-viewer frame-queue fan-out, needed there
/// because aiortc's track model is one-track-per-connection) — one capture session here can feed
/// every viewer's peer connection directly, plus a local preview renderer.
@MainActor
final class CameraController {
    private let factory: RTCPeerConnectionFactory
    private var capturer: RTCCameraVideoCapturer?
    private var source: RTCVideoSource?
    private(set) var videoTrack: RTCVideoTrack?

    /// Matches ClientPython's Config defaults (320x240 @ 5fps).
    private let targetWidth = 320
    private let targetHeight = 240
    private let targetFPS = 5

    init(factory: RTCPeerConnectionFactory) {
        self.factory = factory
    }

    var isRunning: Bool { videoTrack != nil }

    /// Idempotent: returns the existing track if already running.
    func start() async throws -> RTCVideoTrack {
        if let videoTrack { return videoTrack }

        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == .back }) ?? devices.first else {
            throw CameraError.noCameraAvailable
        }
        guard let format = Self.bestFormat(for: device, targetWidth: targetWidth, targetHeight: targetHeight) else {
            throw CameraError.noSupportedFormat
        }
        let fps = Self.bestFrameRate(for: format, target: targetFPS)

        let source = factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: source)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: device, format: format, fps: fps) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        let track = factory.videoTrack(with: source, trackId: "video0")
        self.source = source
        self.capturer = capturer
        self.videoTrack = track
        return track
    }

    func stop() async {
        guard let capturer else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            capturer.stopCapture {
                continuation.resume()
            }
        }
        self.capturer = nil
        self.source = nil
        self.videoTrack = nil
    }

    private static func bestFormat(
        for device: AVCaptureDevice, targetWidth: Int, targetHeight: Int
    ) -> AVCaptureDevice.Format? {
        let targetArea = targetWidth * targetHeight
        return RTCCameraVideoCapturer.supportedFormats(for: device).min { lhs, rhs in
            let lhsDims = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rhsDims = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let lhsArea = Int(lhsDims.width) * Int(lhsDims.height)
            let rhsArea = Int(rhsDims.width) * Int(rhsDims.height)
            return abs(lhsArea - targetArea) < abs(rhsArea - targetArea)
        }
    }

    private static func bestFrameRate(for format: AVCaptureDevice.Format, target: Int) -> Int {
        let maxSupported = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? Double(target)
        return Int(min(Double(target), maxSupported))
    }
}
#endif
