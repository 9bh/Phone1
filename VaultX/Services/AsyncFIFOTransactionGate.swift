import Foundation

actor AsyncFIFOTransactionGate {
    enum WaiterState {
        case registered
        case queued(CheckedContinuation<Void, Error>)
        case owner
    }
    
    private var waiters: [(id: UUID, state: WaiterState)] = []
    
    private func register(id: UUID) {
        let ownerExists = waiters.contains { 
            if case .owner = $0.state { return true }
            if case .queued = $0.state { return true }
            return false
        }
        
        if !ownerExists && waiters.isEmpty {
            waiters.append((id: id, state: .owner))
        } else {
            waiters.append((id: id, state: .registered))
        }
    }
    
    private func acquire(id: UUID) async throws {
        if let idx = waiters.firstIndex(where: { $0.id == id }) {
            if case .owner = waiters[idx].state {
                return
            }
        } else {
            throw CancellationError()
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let idx = waiters.firstIndex(where: { $0.id == id }) {
                waiters[idx].state = .queued(continuation)
            } else {
                continuation.resume(throwing: CancellationError())
            }
        }
    }
    
    private func release(id: UUID) {
        guard let idx = waiters.firstIndex(where: { $0.id == id }), case .owner = waiters[idx].state else { return }
        waiters.remove(at: idx)
        
        while !waiters.isEmpty {
            let next = waiters[0]
            switch next.state {
            case .queued(let continuation):
                waiters[0].state = .owner
                continuation.resume()
                return
            case .registered:
                waiters[0].state = .owner
                return
            case .owner:
                fatalError("Gate state corruption: Multiple owners")
            }
        }
    }
    
    private func cancel(id: UUID) {
        guard let idx = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters[idx]
        
        switch waiter.state {
        case .registered:
            waiters.remove(at: idx)
        case .queued(let continuation):
            waiters.remove(at: idx)
            continuation.resume(throwing: CancellationError())
        case .owner:
            break
        }
    }
    
    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        let id = UUID()
        await register(id: id)
        
        return try await withTaskCancellationHandler {
            try await acquire(id: id)
            do {
                try Task.checkCancellation()
                let result = try await operation()
                try Task.checkCancellation()
                await release(id: id)
                return result
            } catch {
                await release(id: id)
                throw error
            }
        } onCancel: {
            Task {
                await self.cancel(id: id)
            }
        }
    }
    
    func snapshot() -> (ownerPresent: Bool, queuedCount: Int, registeredCount: Int) {
        let owner = waiters.contains(where: { if case .owner = $0.state { return true } else { return false } })
        let queued = waiters.filter { if case .queued = $0.state { return true } else { return false } }.count
        let reg = waiters.filter { if case .registered = $0.state { return true } else { return false } }.count
        return (owner, queued, reg)
    }

    func testHook_cancelUnknown() async {
        await cancel(id: UUID())
    }
}
