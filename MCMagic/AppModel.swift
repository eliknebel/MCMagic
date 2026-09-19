import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

enum SwipeDirectionPreference: String, CaseIterable, Identifiable {
    case up
    case down
    case both

    var id: Self { self }

    var title: String {
        switch self {
        case .up: "Two Fingers Up"
        case .down: "Two Fingers Down"
        case .both: "Two Fingers Up or Down"
        }
    }

    var monitorValue: MCMagicDirectionPreference {
        switch self {
        case .up: .up
        case .down: .down
        case .both: .both
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private enum DefaultsKey {
        static let isEnabled = "isEnabled"
        static let activateSwipeDirection = "activateSwipeDirection"
        static let dismissSwipeDirection = "dismissSwipeDirection"
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
            guard hasStarted else { return }
            applyEnabledState(requestPermission: isEnabled)
        }
    }

    @Published var activateSwipeDirection: SwipeDirectionPreference {
        didSet {
            UserDefaults.standard.set(
                activateSwipeDirection.rawValue,
                forKey: DefaultsKey.activateSwipeDirection
            )
            GestureMonitor.shared.activationDirection = activateSwipeDirection.monitorValue
        }
    }

    @Published var dismissSwipeDirection: SwipeDirectionPreference {
        didSet {
            UserDefaults.standard.set(
                dismissSwipeDirection.rawValue,
                forKey: DefaultsKey.dismissSwipeDirection
            )
            GestureMonitor.shared.dismissalDirection = dismissSwipeDirection.monitorValue
        }
    }

    private var hasStarted = false
    private var retryTimer: Timer?
    private var recoveryWorkItem: DispatchWorkItem?
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var magicMouseObserver: MagicMouseObserver?
    private var systemSleeping = false

    private init() {
        activateSwipeDirection = SwipeDirectionPreference(
            rawValue: UserDefaults.standard.string(forKey: DefaultsKey.activateSwipeDirection) ?? ""
        ) ?? .up

        dismissSwipeDirection = SwipeDirectionPreference(
            rawValue: UserDefaults.standard.string(forKey: DefaultsKey.dismissSwipeDirection) ?? ""
        ) ?? .down

        if UserDefaults.standard.object(forKey: DefaultsKey.isEnabled) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.isEnabled)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        startLifecycleMonitoring()
        GestureMonitor.shared.activationDirection = activateSwipeDirection.monitorValue
        GestureMonitor.shared.dismissalDirection = dismissSwipeDirection.monitorValue
        applyEnabledState(requestPermission: isEnabled)
    }

    func stop() {
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        retryTimer?.invalidate()
        retryTimer = nil
        GestureMonitor.shared.stop()
        stopLifecycleMonitoring()
    }

    private func applyEnabledState(requestPermission: Bool) {
        guard isEnabled else {
            recoveryWorkItem?.cancel()
            recoveryWorkItem = nil
            retryTimer?.invalidate()
            retryTimer = nil
            GestureMonitor.shared.stop()
            return
        }

        if requestPermission {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            _ = CGRequestListenEventAccess()
        }

        attemptStart()
    }

    private func attemptStart() {
        magicMouseObserver?.start()
        do {
            try GestureMonitor.shared.start()
            retryTimer?.invalidate()
            retryTimer = nil
        } catch {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retryTimer == nil, isEnabled, !systemSleeping else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled, !self.systemSleeping else { return }
                self.attemptStart()
            }
        }
    }

    private func startLifecycleMonitoring() {
        guard magicMouseObserver == nil else { return }

        let mouseObserver = MagicMouseObserver { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handleLifecycleEvent(.magicMouseChanged)
                }
            }
        }
        magicMouseObserver = mouseObserver
        mouseObserver.start()

        let center = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleLifecycleEvent(.willSleep)
                }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleLifecycleEvent(.didWake)
                }
            },
            center.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleLifecycleEvent(.screenDidWake)
                }
            },
            center.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleLifecycleEvent(.sessionDidBecomeActive)
                }
            },
        ]
    }

    private func stopLifecycleMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens.forEach(center.removeObserver)
        workspaceObserverTokens.removeAll()
        magicMouseObserver?.stop()
        magicMouseObserver = nil
    }

    private func handleLifecycleEvent(_ event: MCMagicLifecycleEvent) {
        if event == .willSleep {
            systemSleeping = true
        } else if event == .didWake {
            systemSleeping = false
            magicMouseObserver?.stop()
            magicMouseObserver?.start()
        }

        let action = MCMagicLifecycleActionForEvent(
            event,
            isEnabled && hasStarted,
            systemSleeping
        )
        switch action {
        case .stopMonitor:
            recoveryWorkItem?.cancel()
            recoveryWorkItem = nil
            retryTimer?.invalidate()
            retryTimer = nil
            GestureMonitor.shared.stop()
        case .restartMonitor:
            let delay = event == .didWake ? 2.0 : 1.0
            scheduleMonitorRecovery(after: delay)
        case .none:
            break
        @unknown default:
            break
        }
    }

    private func scheduleMonitorRecovery(after delay: TimeInterval) {
        recoveryWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled, !self.systemSleeping else { return }
                self.recoveryWorkItem = nil
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                GestureMonitor.shared.stop()
                self.attemptStart()
            }
        }
        recoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
