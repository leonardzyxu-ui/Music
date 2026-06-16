import Foundation
import Network

final class LocalControlServer: @unchecked Sendable {
    typealias Handler = @MainActor (BridgeRequest) async -> BridgeReply

    private let port: UInt16
    private let handler: Handler
    private var listener: NWListener?

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(AppConfiguration.bridgeHost), port: endpointPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequestData(on: connection, accumulated: Data())
    }

    private func receiveRequestData(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, _ in
            guard let self else {
                connection.cancel()
                return
            }
            var next = accumulated
            if let data {
                next.append(data)
            }

            if !Self.hasCompleteRequest(next), !isComplete {
                self.receiveRequestData(on: connection, accumulated: next)
                return
            }

            guard let request = Self.parse(data: next) else {
                Self.send(BridgeReply.error("Malformed HTTP request.", status: 400), on: connection)
                return
            }
            Task { @MainActor in
                let reply: BridgeReply
                if request.method == "OPTIONS" {
                    reply = BridgeReply.ok(["message": "CORS preflight accepted"])
                } else {
                    reply = await self.handler(request)
                }
                Self.send(reply, on: connection)
            }
        }
    }

    private static func hasCompleteRequest(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              let headerRange = text.range(of: "\r\n\r\n") else {
            return false
        }

        let headerText = String(text[..<headerRange.lowerBound])
        let bodyStart = text.distance(from: text.startIndex, to: headerRange.upperBound)
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line -> Int? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                return Int(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            } ?? 0

        return data.count >= bodyStart + contentLength
    }

    private static func parse(data: Data) -> BridgeRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.components(separatedBy: "\r\n\r\n")
        guard let headerText = parts.first else { return nil }
        let bodyText = parts.dropFirst().joined(separator: "\r\n\r\n")
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestPieces = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestPieces.count >= 2 else { return nil }

        let method = requestPieces[0].uppercased()
        let target = requestPieces[1]
        let components = URLComponents(string: "http://\(AppConfiguration.bridgeHost)\(target)")
        let path = components?.path ?? target
        let query = decodeQuery(components?.percentEncodedQuery)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[String(key)] = value
        }

        var body: [String: Any] = [:]
        if !bodyText.isEmpty, let bodyData = bodyText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            body = object
        }

        return BridgeRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    private static func decodeQuery(_ percentEncodedQuery: String?) -> [String: String] {
        guard let percentEncodedQuery, !percentEncodedQuery.isEmpty else { return [:] }
        var values: [String: String] = [:]
        for pair in percentEncodedQuery.split(separator: "&", omittingEmptySubsequences: true) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = pieces.first else { continue }
            let name = formDecode(rawName)
            let value = pieces.count > 1 ? formDecode(pieces[1]) : ""
            values[name] = value
        }
        return values
    }

    private static func formDecode(_ value: Substring) -> String {
        let plusAsSpace = value.replacingOccurrences(of: "+", with: " ")
        return plusAsSpace.removingPercentEncoding ?? plusAsSpace
    }

    private static func send(_ reply: BridgeReply, on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: reply.payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let reason = HTTPReason.reason(for: reply.status)
        var header = "HTTP/1.1 \(reply.status) \(reason)\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Headers: Authorization, Content-Type\r\n"
        header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private enum HTTPReason {
    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Bad Request"
        }
    }
}
