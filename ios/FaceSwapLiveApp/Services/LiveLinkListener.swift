import Foundation
import Network

/// Listens for Live Link Face packets from a second iPhone and turns each
/// valid one into a pose. Purely receiving — nothing is ever sent back, so
/// no local-network permission is asked for on this phone.
///
/// Every Network-framework call runs on this actor's own serial queue, which
/// is also the queue the listener and its flows call back on.
actor LiveLinkListener {
    private let queue = DispatchSerialQueue(label: "com.app.facetracking.livelink", qos: .userInteractive)

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    nonisolated let events: AsyncStream<FaceSourceEvent>
    private let sink: AsyncStream<FaceSourceEvent>.Continuation

    private var listener: NWListener?
    private var flows: [ObjectIdentifier: NWConnection] = [:]
    private var port: UInt16 = LiveLinkFacePacket.defaultPort

    init() {
        let (stream, continuation) = AsyncStream<FaceSourceEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = stream
        sink = continuation
    }

    /// Binds `port` for UDP. A port that cannot be bound is reported through
    /// `events` as `portUnavailable`.
    func start(port: UInt16) {
        stop()
        self.port = port

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            sink.yield(.portUnavailable(port: port))
            return
        }

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            sink.yield(.portUnavailable(port: port))
            return
        }

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.assumeIsolated { $0.listenerChanged(state) }
        }
        newListener.newConnectionHandler = { [weak self] flow in
            guard let self else { return }
            self.assumeIsolated { $0.accept(flow) }
        }

        listener = newListener
        newListener.start(queue: queue)
    }

    /// Closes the port and every sender flow.
    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for flow in flows.values {
            flow.stateUpdateHandler = nil
            flow.cancel()
        }
        flows.removeAll()
    }

    // MARK: - Listener

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            sink.yield(.listening(port: port))
        case .failed(let error):
            if case .posix(let code) = error, code == .EADDRINUSE {
                sink.yield(.portUnavailable(port: port))
            } else {
                sink.yield(.failed(error.localizedDescription))
            }
            listener = nil
        case .setup, .waiting, .cancelled:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Sender flows

    /// UDP hands each distinct sender to us as its own flow; every one is
    /// read until it fails or the listener stops.
    private func accept(_ flow: NWConnection) {
        let id = ObjectIdentifier(flow)
        flows[id] = flow
        flow.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.assumeIsolated { $0.flowChanged(id, state: state) }
        }
        flow.start(queue: queue)
        receive(on: id)
    }

    private func flowChanged(_ id: ObjectIdentifier, state: NWConnection.State) {
        switch state {
        case .failed, .cancelled:
            drop(id)
        default:
            break
        }
    }

    private func receive(on id: ObjectIdentifier) {
        guard let flow = flows[id] else { return }
        flow.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            self.assumeIsolated { $0.received(data, error: error, on: id) }
        }
    }

    private func received(_ data: Data?, error: NWError?, on id: ObjectIdentifier) {
        if let data, let packet = try? LiveLinkFacePacket.decode(data) {
            sink.yield(.pose(packet.pose(timestamp: FaceClock.now()), sender: packet.subjectName))
        }
        if error != nil {
            drop(id)
        } else if flows[id] != nil {
            receive(on: id)
        }
    }

    private func drop(_ id: ObjectIdentifier) {
        guard let flow = flows.removeValue(forKey: id) else { return }
        flow.stateUpdateHandler = nil
        flow.cancel()
    }
}
