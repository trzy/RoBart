//
//  Stopwatch.swift
//  ChatARKit
//
//  Created by Bart Trzynadlowski on 9/20/22.
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

extension Util
{
    public struct Stopwatch {
        private var _info = mach_timebase_info()
        private var _startTime: UInt64 = 0

        init() {
            if mach_timebase_info(&_info) != KERN_SUCCESS {
                //TODO: set a flag so we always return -1?
            }
        }

        public mutating func start() {
            _startTime = mach_absolute_time()
        }

        public func elapsedSeconds() -> TimeInterval {
            let end = mach_absolute_time()
            let elapsed = end - _startTime
            let nanos = elapsed * UInt64(_info.numer) / UInt64(_info.denom)
            return TimeInterval(nanos) / TimeInterval(NSEC_PER_SEC)
        }

        public func elapsedMicroseconds() -> Double {
            let end = mach_absolute_time()
            let elapsed = end - _startTime
            let nanos = elapsed * UInt64(_info.numer) / UInt64(_info.denom)
            return Double(nanos) / Double(NSEC_PER_USEC)
        }

        public func elapsedMilliseconds() -> Double {
            let end = mach_absolute_time()
            let elapsed = end - _startTime
            let nanos = elapsed * UInt64(_info.numer) / UInt64(_info.denom)
            return Double(nanos) / Double(NSEC_PER_MSEC)
        }

        public static func measure(_ block: () -> Void) -> TimeInterval {
            var info = mach_timebase_info()
            guard mach_timebase_info(&info) == KERN_SUCCESS else { return -1 }
            let start = mach_absolute_time()
            block()
            let end = mach_absolute_time()
            let elapsed = end - start
            let nanos = elapsed * UInt64(info.numer) / UInt64(info.denom)
            return TimeInterval(nanos) / TimeInterval(NSEC_PER_SEC)
        }
    }
}
