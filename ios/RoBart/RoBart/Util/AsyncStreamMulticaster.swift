//
//  AsyncStreamMulticaster.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/23/24.
//

import Foundation

extension Util {
    class AsyncStreamMulticaster<T> {
        private var _continuations: [UUID: AsyncStream<T>.Continuation] = [:]
        private let _lock = NSLock()    // thread safe!

        /// - Returns: A new stream to read from and a handle to use to unsubscribe.
        func subscribe() -> (AsyncStream<T>, UUID) {
            let id = UUID()
            let stream = AsyncStream { continuation in
                self._lock.lock()
                self._continuations[id] = continuation
                self._lock.unlock()

                // Handle termination. Subscriber does not need to explicitly unsubscribe when the
                // producer terminates the stream.
                continuation.onTermination = { [weak self] _ in
                    guard let self = self else { return }
                    _lock.lock()
                    _continuations.removeValue(forKey: id)
                    _lock.unlock()
                }
            }
            return (stream, id)
        }

        /// Unsubscribe (removes the resources held by the subscriber's continuation). No need
        /// to unsubscribe if the stream was terminated (read to completion).
        /// - Parameter handle: Subscription handle.
        func unsubscribe(_ handle: UUID) {
            // Get continuation, if it exists, and then release lock before calling finish() to
            // avoid a deadlock with onTermination above.
            var continuation: AsyncStream<T>.Continuation?
            _lock.lock()
            continuation = _continuations[handle]
            _continuations.removeValue(forKey: handle)
            _lock.unlock()
            continuation?.finish()
        }

        /// Send item to all current subscribers.
        func broadcast(_ element: T) {
            _lock.lock()
            for continuation in _continuations.values {
                continuation.yield(element)
            }
            _lock.unlock()
        }

        /// Finish all streams.
        func finish() {
            _lock.lock()
            for continuation in _continuations.values {
                continuation.finish()
            }
            _continuations.removeAll()
            _lock.unlock()
        }
    }
}
