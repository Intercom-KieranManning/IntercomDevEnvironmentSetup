#if canImport(UIKit)
import WebRTC

// stasel/WebRTC's ObjC types predate Swift 6 strict concurrency and aren't marked Sendable.
// We only ever read from these across actor boundaries (delegate callback -> MainActor Task),
// never mutate concurrently, so @unchecked Sendable is the standard, accepted way to bridge a
// non-Sendable ObjC library into Swift 6 concurrency checking.
extension RTCSessionDescription: @unchecked @retroactive Sendable {}
extension RTCIceCandidate: @unchecked @retroactive Sendable {}
extension RTCPeerConnection: @unchecked @retroactive Sendable {}
#endif
