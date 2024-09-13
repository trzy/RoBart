//
//  NavigationController.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/12/24.
//

import Foundation

enum NavigationCommand {
    case navigate(to: Vector3)
}

class NavigationController {
    static let shared = NavigationController()

    private var _nextCommand: NavigationCommand?
    private var _currentTask: Task<Void, Never>?

    fileprivate init() {
    }

    func runTask() async {
        while true {
            // Await next navigation command
            guard let command = _nextCommand else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            _nextCommand = nil

            // Execute command
            _currentTask = Task {
                do {
                    switch command {
                    case .navigate(to: let position):
                        log("Navigating to \(position)")
                        try await navigateToGoal(position: position)
                    }
                } catch {
                    log("Command interrupted: \(error.localizedDescription)")
                }
            }
            _ = await _currentTask!.result
        }
    }

    /// Attempts to stop the currently-running navigation task. Because tasks are cooperative,
    /// there is no guarantee when or whether this will stop the task.
    func stopNavigation() {
        _currentTask?.cancel()
    }

    func run(_ command: NavigationCommand) {
        stopNavigation()
        _nextCommand = command
    }
}

fileprivate func log(_ message: String) {
    print("[NavigationController] \(message)")
}
