import Foundation

/// Connexion WebSocket au serveur, avec reconnexion automatique.
final class LiveSocket {
    private var task: URLSessionWebSocketTask?
    private var url: URL?
    private var stopped = true
    private var pingTimer: Timer?

    var onMessage: ((Data) -> Void)?
    var onState: ((Bool) -> Void)?

    func connect(to url: URL) {
        disconnect()
        self.url = url
        stopped = false
        open()
    }

    func disconnect() {
        stopped = true
        pingTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func open() {
        guard let url, !stopped else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive(on: task)
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                self?.task?.send(.string("ping")) { _ in }
            }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, task === self.task else { return }
            switch result {
            case .success(let message):
                self.onState?(true)
                switch message {
                case .string(let text): self.onMessage?(Data(text.utf8))
                case .data(let data): self.onMessage?(data)
                @unknown default: break
                }
                self.receive(on: task)
            case .failure:
                self.onState?(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.open() }
            }
        }
    }
}
