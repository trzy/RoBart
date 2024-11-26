//
//  Task+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/12/24.
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

extension Task where Success == Never, Failure == Never {
    /// Sleeps until a condition is satisfied.
    /// - Parameter timeout: Optional timeout after which the function returns if the conditon is still `false`.
    /// - Parameter pollEvery: How often to poll the condition function.
    /// - Parameter until: A function that will be polled until it returns `true`.
    static func sleep(timeout: Duration? = nil, pollEvery pollInterval: Duration = .milliseconds(32), until conditionSatisfied: () -> Bool) async throws {
        let startTime = Date.timeIntervalSinceReferenceDate
        while !conditionSatisfied() {
            if let timeout = timeout {
                let elapsed = Duration.seconds(Date.timeIntervalSinceReferenceDate - startTime)
                if elapsed >= timeout {
                    break
                }
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    /// Sleeps while a condition is `true`.
    /// - Parameter timeout: Optional timeout after which the function returns if the condition is still `true`.
    /// - Parameter pollEvery: How often to poll the condition function.
    /// - Parameter while: A function that will be polled until it returns `false`.
    static func sleep(timeout: Duration? = nil, pollEvery pollInterval: Duration = .milliseconds(32), while conditionNotSatisfied: () -> Bool) async throws {
        let startTime = Date.timeIntervalSinceReferenceDate
        while conditionNotSatisfied() {
            if let timeout = timeout {
                let elapsed = Duration.seconds(Date.timeIntervalSinceReferenceDate - startTime)
                if elapsed >= timeout {
                    break
                }
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    /// Sleeps until a condition is `false` up to a specific time in the future.
    /// - Parameter withDeadline: Timepoint in the future to return if the condition is still `false`.
    /// - Parameter pollEvery: How often to poll the condition function.
    /// - Parameter until: A function that will be polled until it returns `true`.
    static func sleep(withDeadline deadline: Date, pollEvery pollInterval: Duration = .milliseconds(32), until conditionSatisfied: () -> Bool) async throws {
        let timeout = deadline.timeIntervalSince(Date.now)
        if timeout > 0 {
            try await Task.sleep(timeout: .seconds(timeout), pollEvery: pollInterval, until: conditionSatisfied)
        }
    }

    /// Sleeps while a condition is `true` up to a specific time in the future.
    /// - Parameter withDeadline: Timepoint in the future to return if the condition is still `true`.
    /// - Parameter pollEvery: How often to poll the condition function.
    /// - Parameter while: A function that will be polled until it returns `true`.
    static func sleep(withDeadline deadline: Date, pollEvery pollInterval: Duration = .milliseconds(32), while conditionNotSatisfied: () -> Bool) async throws {
        let timeout = deadline.timeIntervalSince(Date.now)
        if timeout > 0 {
            try await Task.sleep(timeout: .seconds(timeout), pollEvery: pollInterval, while: conditionNotSatisfied)
        }
    }
}
