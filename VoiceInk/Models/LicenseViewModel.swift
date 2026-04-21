import Foundation
import AppKit

/// Stub ViewModel — the trial/license system has been removed in the ValVoice fork.
/// The app is always considered licensed. No network calls, no trial tracking, no activation flow.
/// The original observable shape is preserved so existing `@StateObject` / `@ObservedObject`
/// call sites continue to compile unchanged.
@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published private(set) var activationsLimit: Int = 0

    init() {}

    func startTrial() {}

    var canUseApp: Bool { true }

    func openPurchaseLink() {}

    func validateLicense() async {
        licenseState = .licensed
    }

    func removeLicense() {}
}
