import Network
import Foundation

@MainActor
class NetworkManager: ObservableObject {
    private let monitor = NWPathMonitor()
    @Published var isOnline = true
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
}
