import Foundation

struct BridgeRequest: @unchecked Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: [String: Any]

    var bearerToken: String? {
        guard let authorization = headers["authorization"] else { return nil }
        let prefix = "bearer "
        guard authorization.lowercased().hasPrefix(prefix) else { return nil }
        return String(authorization.dropFirst(prefix.count))
    }

    func string(_ key: String) -> String? {
        if let value = body[key] as? String { return value }
        if let value = body[key] as? NSNumber { return value.stringValue }
        if let value = body[key] { return String(describing: value) }
        return query[key]
    }
}

struct BridgeReply: @unchecked Sendable {
    var status: Int
    var payload: [String: Any]

    static func ok(_ payload: [String: Any]) -> BridgeReply {
        BridgeReply(status: 200, payload: ["ok": true].merging(payload) { _, new in new })
    }

    static func error(
        _ message: String,
        status: Int = 400,
        code: String = "bad_request",
        details: [String: Any] = [:]
    ) -> BridgeReply {
        var errorPayload: [String: Any] = [
            "code": code,
            "message": message
        ]
        for (key, value) in details where key != "code" && key != "message" {
            errorPayload[key] = value
        }
        return BridgeReply(status: status, payload: [
            "ok": false,
            "error": errorPayload
        ])
    }
}
