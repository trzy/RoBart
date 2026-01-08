//
//  AsyncStreamMulticaster.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/23/24.
//
//  This file is part of RoBart.
//
//  RoBart is free software: you can redistribute it and/or modify it under the
//  terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later
//  version.
//
//  RoBart is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with RoBart. If not, see <http://www.gnu.org/licenses/>.
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
