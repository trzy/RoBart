//
//  Task+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/12/24.
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
