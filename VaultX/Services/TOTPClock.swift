import Combine
import Foundation

@MainActor
final class TOTPClock: ObservableObject {
    static let shared = TOTPClock()

    @Published private(set) var currentTime = Date()
    private var timer: AnyCancellable?

    private init() {}

    func start() {
        currentTime = Date()
        guard timer == nil else { return }

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.currentTime = date
            }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func updateNow() {
        currentTime = Date()
    }
}
