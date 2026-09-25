import SwiftUI
import UIKit

struct PatchProjectsView: View {
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    @AppStorage("nta_selected_game") private var selectedGame = "Free Fire"
    @AppStorage("nta_aim_co") private var aimCoEnabled = false
    @StateObject private var modService = FFModService.shared
    @StateObject private var authService = AuthKeyService.shared
    @EnvironmentObject private var appState: AppState
    @State private var activeAlert: ActiveAlert? = nil

    enum ActiveAlert: Identifiable {
        case confirm
        case success(String)
        case notInstalled
        case logoutConfirm
        
        var id: String {
            switch self {
            case .confirm:
                return "confirm"
            case .success(let msg):
                return "success_\(msg)"
            case .notInstalled:
                return "notInstalled"
            case .logoutConfirm:
                return "logoutConfirm"
            }
        }
    }

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 10/255, blue: 12/255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerView
                        licenseCardView
                        if appState.isIOS18KernelSupported {
                            advancedPermissionCardView
                        }
                        gameSegmentView
                        if !selectedGame.contains("MAX") {
                            aimSectionView
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .alert(item: $activeAlert) { item in
            switch item {
            case .confirm:
                return Alert(
                    title: Text("Bạn có chắc chắn muốn bật?"),
                    message: nil,
                    primaryButton: .default(Text("Bật")) {
                        performTurnOn()
                    },
                    secondaryButton: .cancel(Text("Hủy"))
                )
            case .success(let message):
                return Alert(
                    title: Text(message),
                    message: nil,
                    dismissButton: .cancel(Text("Đóng"))
                )
            case .notInstalled:
                return Alert(
                    title: Text("Chưa tải game"),
                    message: nil,
                    dismissButton: .cancel(Text("Đóng"))
                )
            case .logoutConfirm:
                return Alert(
                    title: Text("Bạn có chắc chắn muốn đăng xuất key?"),
                    message: nil,
                    primaryButton: .destructive(Text("Đăng xuất")) {
                        authService.logout()
                    },
                    secondaryButton: .cancel(Text("Hủy"))
                )
            }
        }
        .onAppear {
            authService.updateCountdown()
            authService.startPeriodicValidation()
        }
    }

    private func handleUserToggle() {
        if aimCoEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                aimCoEnabled = false
            }
            _ = modService.restoreGoc(isMax: false)
            activeAlert = .success("Đã tắt aim cổ")
        } else {
            activeAlert = .confirm
        }
    }

    private func performTurnOn() {
        let ok = modService.applyMod(isMax: false)
        if ok {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                aimCoEnabled = true
            }
            activeAlert = .success("Đã bật aim cổ thành công")
        } else {
            activeAlert = .notInstalled
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.12))

                if let uiImage = UIImage(named: "nta_bear_avatar") ?? UIImage(named: "AppIcon60x60") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image("nta_bear_avatar")
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("NTA Mod")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)

                Text("FFXC / PRIVATE EDITION")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(white: 0.55))
                    .tracking(0.5)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 46/255, green: 204/255, blue: 113/255))
                        .frame(width: 7, height: 7)
                    Text(selectedGame)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.65))
                }
            }

            Spacer()

            Button {
                activeAlert = .logoutConfirm
            } label: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.12))
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(white: 0.8))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - License / Status Card
    private var licenseCardView: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                Text(authService.savedKey.isEmpty ? "NTAM-VIP-KEY" : authService.savedKey)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Expires In")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                    Text(authService.countdownText.isEmpty ? authService.formattedRemainingCountdown : authService.countdownText)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.5))
                    Text(AppInfo.displayMachineName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.6))
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.65))
                    Text(AppInfo.osVersion)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.65))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 19/255, green: 19/255, blue: 22/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - iOS 18 Advanced Permission Card
    private var advancedPermissionCardView: some View {
        VStack(spacing: 0) {
            // Row 1: Trạng thái (cho phần trong ngoặc xuống 1 dòng riêng)
            HStack(alignment: .center, spacing: 8) {
                Text("Trạng thái")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white)

                Spacer()

                if appState.kernelExploitRunning {
                    Text("Đang kích hoạt...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                } else if appState.exploitStatus.isSuccess {
                    Text("Đã kích hoạt")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Chưa kích hoạt")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 235/255, green: 65/255, blue: 65/255))

                        Text("(cần phải kích hoạt để mod hoạt động)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color(red: 235/255, green: 65/255, blue: 65/255).opacity(0.85))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .background(Color(white: 0.22))
                .padding(.horizontal, 16)

            // Row 2: Kích hoạt (Màu xanh lá cây, to hơn 1 chút, cái trong ngoặc xuống 1 dòng riêng)
            Button(action: {
                appState.runKernelExploitIfNeeded(force: true) { success in
                    if success {
                        activeAlert = .success("Kích hoạt quyền nâng cao thành công")
                    } else {
                        activeAlert = .success("Kích hoạt thất bại. Vui lòng thử lại!")
                    }
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: appState.exploitStatus.isSuccess ? "lock.fill" : "lock.open")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(red: 52/255, green: 199/255, blue: 89/255))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.exploitStatus.isSuccess ? "Đã kích hoạt" : "Kích hoạt")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(red: 52/255, green: 199/255, blue: 89/255))

                        Text("(Áp dụng cho iOS 18.0–18.7.1)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(white: 0.5))
                    }

                    Spacer()

                    if appState.kernelExploitRunning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 52/255, green: 199/255, blue: 89/255)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(appState.kernelExploitRunning || appState.exploitStatus.isSuccess)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 28/255, green: 28/255, blue: 30/255))
        )
    }

    // MARK: - Game Switcher
    private var gameSegmentView: some View {
        HStack(spacing: 0) {
            gameSegmentButton(title: "Free Fire")
            gameSegmentButton(title: "Free Fire MAX")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 19/255, green: 19/255, blue: 22/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func gameSegmentButton(title: String) -> some View {
        let isSelected = selectedGame == title
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedGame = title
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                .foregroundColor(isSelected ? .black : Color(white: 0.55))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    isSelected
                        ? RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.94))
                        : nil
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - AIM Section
    @ViewBuilder
    private var aimSectionView: some View {
        if !selectedGame.contains("MAX") {
            VStack(alignment: .leading, spacing: 10) {
                Text("AIM")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.0)
                    .padding(.leading, 4)
                    .padding(.top, 8)

                // Aim cổ
                featureToggleCard(
                    title: "Aim cổ",
                    subtitle: "Lưu ý khi vào game đến sảnh rồi bật",
                    isOn: aimCoEnabled,
                    onToggle: {
                        handleUserToggle()
                    }
                ) {
                    Image(systemName: "scope")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .transition(.opacity)
        }
    }

    private func featureToggleCard<Icon: View>(
        title: String,
        subtitle: String,
        isOn: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.13))
                icon()
            }
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.5))
            }

            Spacer()

            Button(action: onToggle) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color(red: 46/255, green: 204/255, blue: 113/255) : Color(white: 0.22))
                    .frame(width: 51, height: 31)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .padding(2)
                            .offset(x: isOn ? 10 : -10)
                            .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 19/255, green: 19/255, blue: 22/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Custom Switch Style
struct NTACustomSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(configuration.isOn ? Color(red: 46/255, green: 204/255, blue: 113/255) : Color(white: 0.22))
                .frame(width: 51, height: 31)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compatibility
struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    let request: PatchPasswordRequest
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in
                            store.clearUnlockError()
                        }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    if let origin = request.origin {
                        Text(language.text(
                            "patch.password_repo_contact",
                            origin.repositoryName
                        ))
                    } else {
                        Text(language.text("patch.password_once_message"))
                    }
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

private struct PatchStorePresentationModifier: ViewModifier {
    @ObservedObject var store: PatchProjectStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { request in
                PatchUnlockView(store: store, request: request)
            }
    }
}

extension View {
    func patchStorePresentation(_ store: PatchProjectStore) -> some View {
        modifier(PatchStorePresentationModifier(store: store))
    }
}
