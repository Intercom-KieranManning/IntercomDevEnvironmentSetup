import Foundation

/// Matches APIServer/api/turn.py's `generate_turn_credentials()` shape.
public struct TurnCredentials: Codable, Equatable, Sendable {
    public let url: String
    public let username: String
    public let credential: String
}

struct TurnCredentialsResponse: Decodable {
    let turnCredentials: TurnCredentials?

    enum CodingKeys: String, CodingKey {
        case turnCredentials = "turn_credentials"
    }
}
