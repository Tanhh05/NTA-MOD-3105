import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.preferredLanguageCode
    @State private var showAttribution = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(patchDraftCoordinator)
                .environmentObject(fileOperationCoordinator)
                .environmentObject(patchStore)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .preferredColorScheme(.dark)
                .onAppear {
                    setupTerminationHandler()
                }
                .onOpenURL { url in
                    patchDraftCoordinator.presentImport(url)
                }
        }
    }

    private func setupTerminationHandler() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            log("app: will terminate — auto-restoring original cache")
            _ = FFModService.shared.restoreGoc(isMax: false)
            UserDefaults.standard.set(false, forKey: "nta_aim_co")
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var isIOS18: Bool {
        AppInfo.versionTuple.major == 18
    }

    var isIOS18KernelSupported: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        let v = AppInfo.versionTuple
        return v.major == 18 && (v.minor < 7 || (v.minor == 7 && v.patch <= 1))
        #endif
    }

    var exploitStatusDisplayVN: String {
        if kernelExploitRunning {
            return "Đang kích hoạt..."
        }
        switch exploitStatus {
        case .notStarted:
            return "Chưa kích hoạt (cần phải kích hoạt để mod hoạt động)"
        case .success:
            return "Đã kích hoạt"
        case .failed:
            return "Thất bại"
        case .unsupported:
            return "Không hỗ trợ"
        }
    }

    var exploitStatusColor: Color {
        if kernelExploitRunning {
            return Color.orange
        }
        switch exploitStatus {
        case .notStarted:
            return Color(red: 235/255, green: 65/255, blue: 65/255)
        case .success:
            return Color.green
        case .failed:
            return Color.red
        case .unsupported:
            return Color(white: 0.5)
        }
    }

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        guard AuthKeyService.shared.isAuthenticated else { return }
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        // Trên iOS 18: KHÔNG tự động chạy luồng sandbox khi mở app/nhập key
        if isIOS18 {
            log("app: iOS 18 detected — sandbox exploit skipped on launch, manual activation button enabled on home screen")
            return
        }
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        if exploitStatus.isSuccess {
            KernelExploit.isActivated = true
        }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning else {
            completion?(exploitStatus.isSuccess)
            return
        }
        if !force {
            guard !exploitStatus.isSuccess,
                  !exploitStatus.isFailed else {
                completion?(exploitStatus.isSuccess)
                return
            }
        } else {
            guard !exploitStatus.isSuccess else {
                completion?(true)
                return
            }
        }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    KernelExploit.isActivated = true
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
                completion?(ok)
            }
        }
    }
}
