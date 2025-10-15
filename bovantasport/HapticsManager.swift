//
//  HapticsManager.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine
import UIKit

/// Centralized, app-wide haptics controller (dark-first app, minimal latency).
/// No stubs — ready for production use.
///
/// Usage:
/// HapticsManager.shared.soft()
/// HapticsManager.shared.success()
final class HapticsManager: ObservableObject {
    // MARK: - Singleton
    static let shared = HapticsManager()

    // MARK: - Public (observable) state
    @Published private(set) var isEnabled: Bool

    // MARK: - Storage
    private let keyEnabled = "settings.haptics.enabled"
    private let defaults: UserDefaults = .standard

    // MARK: - Cached generators (to avoid allocation on every tap)
    private lazy var impactSoft   = UIImpactFeedbackGenerator(style: .soft)
    private lazy var impactLight  = UIImpactFeedbackGenerator(style: .light)
    private lazy var impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private lazy var impactHeavy  = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var impactRigid  = UIImpactFeedbackGenerator(style: .rigid)

    private lazy var selection    = UISelectionFeedbackGenerator()
    private lazy var notify       = UINotificationFeedbackGenerator()

    // MARK: - Throttle (avoid haptic spam)
    private var lastHapticAt: TimeInterval = 0
    private let minInterval: TimeInterval = 0.018 // ~18ms feels instant; prevents bursts

    // MARK: - Init
    private init() {
        if defaults.object(forKey: keyEnabled) == nil {
            defaults.set(true, forKey: keyEnabled) // default ON
        }
        self.isEnabled = defaults.bool(forKey: keyEnabled)

        // Pre-warm generators for lower latency on first use
        prepareAll()
        // Listen for app foreground to re-prepare (prevents "cold start" feel)
        NotificationCenter.default.addObserver(
            forName: UIScene.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.prepareAll() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Enable/disable haptics globally (persisted).
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: keyEnabled)
        if enabled { prepareAll() }
    }

    /// Short, gentle tap.
    func soft() { impact(style: .soft) }

    /// Light but noticeable.
    func light() { impact(style: .light) }

    /// Default impact.
    func medium() { impact(style: .medium) }

    /// Strong feedback (e.g., major events).
    func heavy() { impact(style: .heavy) }

    /// Crisp, rigid snap.
    func rigid() { impact(style: .rigid) }

    /// For picker/segment changes.
    func select() {
        guard gate() else { return }
        guard isEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    /// Success notification (e.g., match saved).
    func success() {
        notify(.success)
    }

    /// Warning notification (e.g., near limit).
    func warning() {
        notify(.warning)
    }

    /// Error notification (e.g., invalid action).
    func error() {
        notify(.error)
    }

    /// Custom intensity (0…1) with base style.
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        guard gate() else { return }
        guard isEnabled else { return }
        let generator = generator(for: style)
        // Use new API when available, fallback otherwise
        if #available(iOS 13.0, *) {
            generator.impactOccurred(intensity: max(0, min(1, intensity)))
        } else {
            generator.impactOccurred()
        }
        generator.prepare()
    }

    // MARK: - Private helpers

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard gate() else { return }
        guard isEnabled else { return }
        notify.notificationOccurred(type)
        notify.prepare()
    }

    private func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard gate() else { return }
        guard isEnabled else { return }
        let g = generator(for: style)
        g.impactOccurred()
        g.prepare()
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .soft:   return impactSoft
        case .light:  return impactLight
        case .medium: return impactMedium
        case .heavy:  return impactHeavy
        case .rigid:  return impactRigid
        @unknown default: return impactMedium
        }
    }

    private func prepareAll() {
        impactSoft.prepare()
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        impactRigid.prepare()
        selection.prepare()
        notify.prepare()
    }

    @discardableResult
    private func gate() -> Bool {
        // Ensure calls are on main (UIKit generators expect main thread)
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in _ = self?.gate() }
            return false
        }
        let now = CACurrentMediaTime()
        guard now - lastHapticAt >= minInterval else { return false }
        lastHapticAt = now
        return true
    }
}
