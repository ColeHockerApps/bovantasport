import SwiftUI
import StoreKit
import UIKit
import Combine


@MainActor
public final class ReviewNudge: ObservableObject {
    public static let shared = ReviewNudge()
    private var scheduled = false
    private var task: Task<Void, Never>?
    private let onceKey = "review.prompted.once"

    public func schedule(after seconds: TimeInterval = 180) {
        guard !scheduled else { return }
        guard !UserDefaults.standard.bool(forKey: onceKey) else { return }
        scheduled = true
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.request()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        scheduled = false
    }

    private func request() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        SKStoreReviewController.requestReview(in: scene)
        UserDefaults.standard.set(true, forKey: onceKey)
    }
}
