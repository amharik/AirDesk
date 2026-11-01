import Foundation

enum RemoteTerminalEvent: Sendable {
    case ready
    case data(Data)
    case exit(String?)
}

@MainActor
final class RemoteTerminalController {
    private(set) var isRunning = false
    var onEvent: ((RemoteTerminalEvent) -> Void)?

    private var session: SSHPTYSession?
    private var readerTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var pending = Data()
    private var generation = 0
    private var connectingToken: Int?

    func start(configuration: SSHPTYConfiguration) async throws {
        stop()

        generation += 1
        let token = generation
        let session = SSHPTYSession(configuration: configuration)
        self.session = session
        pending.removeAll(keepingCapacity: true)

        readerTask = Task { [weak self] in
            do {
                for try await data in session.output {
                    guard !Task.isCancelled else { return }
                    self?.receive(data, token: token)
                }
                self?.finish(token: token, error: nil)
            } catch is CancellationError {
                return
            } catch {
                self?.finish(token: token, error: error)
            }
        }

        connectingToken = token
        do {
            try await session.connect()
        } catch {
            connectingToken = nil
            if token == generation {
                readerTask?.cancel()
                readerTask = nil
                self.session = nil
                generation += 1
            }
            throw error
        }

        guard token == generation else {
            connectingToken = nil
            await session.close()
            throw CancellationError()
        }

        connectingToken = nil
        isRunning = true
        onEvent?(.ready)
    }

    func write(_ data: Data) {
        guard let session, isRunning, !data.isEmpty else { return }
        let token = generation
        Task { [weak self] in
            do {
                try await session.write(data)
            } catch {
                self?.finish(token: token, error: error)
            }
        }
    }

    func resize(columns: Int, rows: Int) {
        guard let session, isRunning else { return }
        let token = generation
        Task { [weak self] in
            do {
                try await session.resize(columns: columns, rows: rows)
            } catch {
                self?.finish(token: token, error: error)
            }
        }
    }

    func stop() {
        generation += 1
        connectingToken = nil
        let session = self.session
        self.session = nil
        isRunning = false
        readerTask?.cancel()
        readerTask = nil
        flushTask?.cancel()
        flushTask = nil
        pending.removeAll(keepingCapacity: true)

        if let session {
            Task { await session.close() }
        }
    }

    private func receive(_ data: Data, token: Int) {
        guard token == generation else { return }
        pending.append(data)
        scheduleFlush(token: token)
    }

    private func scheduleFlush(token: Int) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            self?.flush(token: token)
        }
    }

    private func flush(token: Int) {
        flushTask = nil
        guard token == generation, !pending.isEmpty else { return }
        let data = pending
        pending.removeAll(keepingCapacity: true)
        onEvent?(.data(data))
    }

    private func finish(token: Int, error: Error?) {
        guard token == generation else { return }
        flush(token: token)

        let wasConnecting = connectingToken == token
        connectingToken = nil
        let session = self.session
        self.session = nil
        isRunning = false
        readerTask = nil
        flushTask?.cancel()
        flushTask = nil
        generation += 1

        if let session {
            Task { await session.close() }
        }
        if !wasConnecting {
            onEvent?(.exit(error?.localizedDescription))
        }
    }
}
