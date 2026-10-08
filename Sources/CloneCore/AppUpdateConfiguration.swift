import Foundation

public struct AppUpdateConfiguration {
    public let publicKey: String
    public let feedURL: URL

    public init?(publicKey: String?, architecture: String) {
        guard let publicKey, let bytes = Data(base64Encoded: publicKey), bytes.count == 32,
              ["arm64", "x86_64"].contains(architecture) else { return nil }
        self.publicKey = publicKey
        feedURL = URL(string: "https://github.com/tamia6/AppDuo/releases/latest/download/appcast-\(architecture).xml")!
    }
}

/// Called on the application's main thread. Never interrupt an active clone operation.
public final class UpdateInstallationGate {
    private var pending: (() -> Void)?
    public init() {}
    public func postponeIfBusy(_ isBusy: Bool, installation: @escaping () -> Void) -> Bool {
        guard isBusy else { return false }
        pending = installation
        return true
    }
    public func resumeIfIdle(isBusy: Bool) {
        guard !isBusy else { return }
        let installation = pending
        pending = nil
        installation?()
    }
}
