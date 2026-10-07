import AppKit
import Combine
import CloneCore
import Sparkle

@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = true
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private var started = false
    private var isBusy: () -> Bool = { false }
    private let gate = UpdateInstallationGate()
    private var startupError: String?

    func start(isBusy: @escaping () -> Bool) {
        guard !started else { return }
        started = true
        self.isBusy = isBusy
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard AppUpdateConfiguration(publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, architecture: architecture) != nil else {
            startupError = "此构建尚未配置更新签名。请从官网安装最新版本。"
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
        controller.startUpdater()
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        if let controller {
            controller.checkForUpdates(nil)
        } else {
            let alert = NSAlert()
            alert.messageText = "暂时无法检查更新"
            alert.informativeText = startupError ?? "更新器尚未启动，请稍后重试。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // A slow launch-time check may miss Sparkle's three-second presentation
        // window. Bring its existing prompt forward while this app is active;
        // otherwise Sparkle presents it when the user returns to the app.
        guard handleShowingUpdate, !state.userInitiated, NSApp.isActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard NSApp.isActive else { return }
            self?.controller?.checkForUpdates(nil)
        }
    }

    func cloneOperationChanged(isBusy: Bool) {
        gate.resumeIfIdle(isBusy: isBusy)
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        gate.postponeIfBusy(isBusy(), installation: installHandler)
    }
}
