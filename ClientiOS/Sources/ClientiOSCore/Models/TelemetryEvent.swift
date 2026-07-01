import Foundation

/// Matches the server's accepted `event` enum (APIServer/client_devices/views.py `device_telemetry`).
public enum TelemetryEvent: String, Sendable {
    case connected
    case disconnected
    case streaming
    case heartbeat
    case error
}

/// Matches DeviceTelemetryLog.Level (APIServer/client_devices/models.py).
public enum TelemetryLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}
