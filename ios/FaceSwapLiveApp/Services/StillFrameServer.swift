import Foundation
import Network

/// Serves the warped still to the page on this phone only.
///
/// The page already draws a picture. This stream replaces that picture's
/// pixels. It never leaves the phone, and it never carries face numbers.
@MainActor
final class StillFrameServer {
    private(set) var port: UInt16?
    private(set) var hasClient = false
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var latest: Data?
    private var busy: Set<ObjectIdentifier> = []

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            let listener = try NWListener(using: parameters, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    if case .ready = state {
                        self?.port = listener.port?.rawValue
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            port = nil
        }
    }

    func publish(_ jpeg: Data) {
        latest = jpeg
        for connection in connections {
            let id = ObjectIdentifier(connection)
            guard !busy.contains(id) else { continue }
            sendFrame(jpeg, on: connection)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        hasClient = false
        port = nil
        latest = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    guard self.isLoopback(connection) else {
                        connection.cancel()
                        return
                    }
                    self.connections.append(connection)
                    self.hasClient = true
                    self.readRequest(connection)
                case .failed, .cancelled:
                    self.connections.removeAll { $0 === connection }
                    self.busy.remove(ObjectIdentifier(connection))
                    self.hasClient = !self.connections.isEmpty
                default:
                    break
                }
            }
        }
    }

    private func readRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, let data, let text = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }
                guard text.hasPrefix("GET ") else {
                    connection.cancel()
                    return
                }
                self.send(self.headers(), on: connection) {
                    if let latest = self.latest {
                        self.sendFrame(latest, on: connection)
                    }
                }
            }
        }
    }

    private func sendFrame(_ jpeg: Data, on connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        busy.insert(id)
        send(framePart(jpeg), on: connection) { [weak self] in
            self?.busy.remove(id)
        }
    }

    private func send(_ data: Data, on connection: NWConnection, done: @escaping @MainActor () -> Void) {
        connection.send(content: data, completion: .contentProcessed { _ in
            MainActor.assumeIsolated {
                done()
            }
        })
    }

    private func headers() -> Data {
        let lines = [
            "HTTP/1.1 200 OK",
            "Content-Type: multipart/x-mixed-replace; boundary=frame",
            "Cache-Control: no-cache, no-store",
            "Access-Control-Allow-Origin: *",
            "Connection: keep-alive",
            "",
            ""
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private func framePart(_ jpeg: Data) -> Data {
        var data = Data([
            "--frame",
            "Content-Type: image/jpeg",
            "Content-Length: \(jpeg.count)",
            "",
            ""
        ].joined(separator: "\r\n").utf8)
        data.append(jpeg)
        data.append(Data("\r\n".utf8))
        return data
    }

    /// The listener is already bound to loopback. This rejects a peer that is
    /// clearly somewhere else, and allows one we cannot name.
    private func isLoopback(_ connection: NWConnection) -> Bool {
        guard case .hostPort(let host, _) = connection.endpoint else { return true }
        switch host {
        case .ipv4(let address):
            return address == .loopback
        case .ipv6(let address):
            return address == .loopback
        case .name(let name, _):
            return name == "localhost" || name == "127.0.0.1"
        @unknown default:
            return false
        }
    }
}
