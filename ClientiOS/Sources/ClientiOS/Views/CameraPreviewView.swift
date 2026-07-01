#if canImport(UIKit)
import SwiftUI
import WebRTC

/// Renders the same shared `RTCVideoTrack` used for streaming — this is just another renderer
/// registered on the track (WebRTC supports multiple simultaneous renderers per track), NOT a
/// second `AVCaptureSession`, which iOS does not allow concurrently on one physical camera.
struct CameraPreviewView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        context.coordinator.attach(videoTrack: videoTrack, to: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }

    final class Coordinator {
        private var currentTrack: RTCVideoTrack?

        func attach(videoTrack: RTCVideoTrack?, to view: RTCMTLVideoView) {
            guard currentTrack !== videoTrack else { return }
            currentTrack?.remove(view)
            currentTrack = videoTrack
            videoTrack?.add(view)
        }

        func detach(from view: RTCMTLVideoView) {
            currentTrack?.remove(view)
            currentTrack = nil
        }
    }
}
#endif
