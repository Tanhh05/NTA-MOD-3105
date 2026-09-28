import SwiftUI
import UIKit

struct PatchProjectsView: View {
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    @AppStorage("nta_selected_game") private var selectedGame = "Free Fire"
    private var isCurrentGameMax: Bool { selectedGame.contains("MAX") }
    @AppStorage("nta_aim_co") private var aimCoEnabled = false
    @AppStorage("nta_aim_body") private var aimBodyEnabled = false
    @AppStorage("nta_tam_len_dau") private var tamLenDauEnabled = false
    @AppStorage("nta_magic") private var magicEnabled = false
    @AppStorage("nta_dinh_vi_sung") private var dinhViSungEnabled = false
    @AppStorage("nta_dinh_vi_sung_blue") private var dinhViSungBlueEnabled = false
    @AppStorage("nta_menu_csharp") private var menuCSharpEnabled = false

    @StateObject private var modService = FFModService.shared
    @StateObject private var authService = AuthKeyService.shared
    @EnvironmentObject private var appState: AppState
    @State private var activeAlert: ActiveAlert? = nil

    enum ActiveAlert: Identifiable {
        case confirm(title: String, message: String? = nil, action: () -> Void)
        case success(String)
        case notInstalled
        case logoutConfirm
        
        var id: String {
            switch self {
            case .confirm(let title, _, _):
                return "confirm_\(title)"
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
            case .confirm(let title, let message, let action):
                return Alert(
                    title: Text(title),
                    message: message != nil ? Text(message!) : nil,
                    primaryButton: .default(Text("Bật")) {
                        action()
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
            let keyToUse = authService.savedKey.isEmpty ? "ROX-VIP-IOS" : authService.savedKey
            modService.fetchModsFromAPI(key: keyToUse)
        }
    }

    // MARK: - Handlers: 1. Aim Cổ (Aim Neck)
    private func handleAimNeckToggle() {
        if aimCoEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                aimCoEnabled = false
            }
            DispatchQueue.global(qos: .utility).async {
                _ = self.modService.restoreAimGoc(isMax: self.isCurrentGameMax)
            }
            activeAlert = .success("Đã tắt aim cổ thành công")
        } else {
            if appState.isIOS18 && !appState.exploitStatus.isSuccess {
                activeAlert = .success("Vui lòng ấn Kích hoạt trước khi bật tính năng!")
                return
            }
            activeAlert = .confirm(title: "Bạn có chắc chắn muốn bật Aim cổ?") {
                performTurnOnAimNeck()
            }
        }
    }

    private func performTurnOnAimNeck() {
        let filesToApply: [ServerModFile] = {
            if let f = modService.getFile(byId: 2) { return [f] }
            if let f = modService.getFiles(byDisplayName: "neck").first { return [f] }
            return []
        }()
        
        if filesToApply.isEmpty {
            modService.applyModOnline(isMax: isCurrentGameMax, key: authService.savedKey) { ok, message in
                if ok {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        aimCoEnabled = true
                        aimBodyEnabled = false
                        tamLenDauEnabled = false
                        magicEnabled = false
                    }
                    activeAlert = .success("Đã bật aim cổ thành công")
                } else {
                    activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
                }
            }
        } else {
            modService.applyModFiles(filesToApply, isMax: isCurrentGameMax) { ok, message in
                if ok {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        aimCoEnabled = true
                        aimBodyEnabled = false
                        tamLenDauEnabled = false
                        magicEnabled = false
                    }
                    activeAlert = .success("Đã bật aim cổ thành công")
                } else {
                    activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
                }
            }
        }
    }

    // MARK: - Handlers: 2. Aim Body 80%
    private func handleAimBodyToggle() {
        if aimBodyEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                aimBodyEnabled = false
            }
            DispatchQueue.global(qos: .utility).async {
                _ = self.modService.restoreAimGoc(isMax: self.isCurrentGameMax)
            }
            activeAlert = .success("Đã tắt aim body 80% & dán lại file gốc")
        } else {
            if appState.isIOS18 && !appState.exploitStatus.isSuccess {
                activeAlert = .success("Vui lòng ấn Kích hoạt trước khi bật tính năng!")
                return
            }
            activeAlert = .confirm(title: "Bạn có chắc chắn muốn bật Aim Body 80%?") {
                performTurnOnAimBody()
            }
        }
    }

    private func performTurnOnAimBody() {
        guard let file = modService.getFile(byId: 3) ?? modService.getFiles(byDisplayName: "body").first else {
            activeAlert = .success("Chưa tải được thông tin mod từ server")
            return
        }
        
        modService.applyModFiles([file], isMax: isCurrentGameMax) { ok, message in
            if ok {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    aimBodyEnabled = true
                    aimCoEnabled = false
                    tamLenDauEnabled = false
                    magicEnabled = false
                }
                activeAlert = .success("Đã bật aim body 80% thành công")
            } else {
                activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
            }
        }
    }

    // MARK: - Handlers: 3. Tâm tự lên đầu
    private func handleTamLenDauToggle() {
        if tamLenDauEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                tamLenDauEnabled = false
            }
            DispatchQueue.global(qos: .utility).async {
                _ = self.modService.restoreAimGoc(isMax: self.isCurrentGameMax)
            }
            activeAlert = .success("Đã tắt tâm tự lên đầu & dán lại file gốc")
        } else {
            if appState.isIOS18 && !appState.exploitStatus.isSuccess {
                activeAlert = .success("Vui lòng ấn Kích hoạt trước khi bật tính năng!")
                return
            }
            activeAlert = .confirm(title: "Bạn có chắc chắn muốn bật Tâm tự lên đầu?") {
                performTurnOnTamLenDau()
            }
        }
    }

    private func performTurnOnTamLenDau() {
        guard let file = modService.getFile(byId: 5) ?? modService.getFiles(byDisplayName: "tam").first else {
            activeAlert = .success("Chưa tải được thông tin mod từ server")
            return
        }
        
        modService.applyModFiles([file], isMax: isCurrentGameMax) { ok, message in
            if ok {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    tamLenDauEnabled = true
                    aimCoEnabled = false
                    aimBodyEnabled = false
                    magicEnabled = false
                }
                activeAlert = .success("Đã bật tâm tự lên đầu thành công")
            } else {
                activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
            }
        }
    }

    // MARK: - Handlers: 4. Magic
    private func handleMagicToggle() {
        if magicEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                magicEnabled = false
            }
            DispatchQueue.global(qos: .utility).async {
                _ = self.modService.restoreAimGoc(isMax: self.isCurrentGameMax)
            }
            activeAlert = .success("Đã tắt Magic & dán lại file gốc")
        } else {
            if appState.isIOS18 && !appState.exploitStatus.isSuccess {
                activeAlert = .success("Vui lòng ấn Kích hoạt trước khi bật tính năng!")
                return
            }
            activeAlert = .confirm(title: "Bạn có chắc chắn muốn bật Magic?") {
                performTurnOnMagic()
            }
        }
    }

    private func performTurnOnMagic() {
        guard let file = modService.getFile(byId: 11) ?? modService.getFiles(byDisplayName: "magic").first else {
            activeAlert = .success("Chưa tải được thông tin mod từ server")
            return
        }
        
        modService.applyModFiles([file], isMax: isCurrentGameMax) { ok, message in
            if ok {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    magicEnabled = true
                    aimCoEnabled = false
                    aimBodyEnabled = false
                    tamLenDauEnabled = false
                }
                activeAlert = .success("Đã bật Magic thành công")
            } else {
                activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
            }
        }
    }

    // MARK: - Handlers: 5. Định vị súng 7 màu
    private func handleDinhViSungToggle() {
        if dinhViSungEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                dinhViSungEnabled = false
            }
            DispatchQueue.global(qos: .utility).async {
                _ = self.modService.restoreDinhViGoc(isMax: self.isCurrentGameMax)
            }
            activeAlert = .success("Đã tắt định vị súng 7 màu & dán lại file gốc")
        } else {
            if appState.isIOS18 && !appState.exploitStatus.isSuccess {
                activeAlert = .success("Vui lòng ấn Kích hoạt trước khi bật tính năng!")
                return
            }
            activeAlert = .confirm(
                title: "Bạn có chắc chắn muốn bật Định vị súng 7 màu?",
                message: "Lưu ý bật trước khi vào game"
            ) {
                performTurnOnDinhViSung()
            }
        }
    }

    private func performTurnOnDinhViSung() {
        guard let file = modService.getFile(byId: 4) ?? modService.getFiles(byDisplayName: "7 mau").first ?? modService.getFiles(byCategory: "dinhvi").first else {
            activeAlert = .success("Chưa tải được thông tin mod từ server")
            return
        }
        
        modService.applyModFiles([file], isMax: isCurrentGameMax) { ok, message in
            if ok {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    dinhViSungEnabled = true
                    dinhViSungBlueEnabled = false
                }
                activeAlert = .success("Đã bật định vị súng 7 màu thành công")
            } else {
                activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
            }
        }
    }

    // MARK: - Handlers: 6. Định vị súng Blue
    private func handleDinhViSungBlueToggle() {
        if dinhViSungBlueEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                dinhViSungBlueEnabled = false
            }
            DispatchQueue.global(qos: .utility).async {
                _ = self.modService.restoreDinhViGoc(isMax: self.isCurrentGameMax)
            }
            activeAlert = .success("Đã tắt định vị súng Blue & dán lại file gốc")
        } else {
            if appState.isIOS18 && !appState.exploitStatus.isSuccess {
                activeAlert = .success("Vui lòng ấn Kích hoạt trước khi bật tính năng!")
                return
            }
            activeAlert = .confirm(
                title: "Bạn có chắc chắn muốn bật Định vị súng Blue?",
                message: "Lưu ý bật trước khi vào game"
            ) {
                performTurnOnDinhViSungBlue()
            }
        }
    }

    private func performTurnOnDinhViSungBlue() {
        guard let file = modService.getFile(byId: 12) ?? modService.getFiles(byDisplayName: "blue").first else {
            activeAlert = .success("Chưa tải được thông tin mod từ server")
            return
        }
        
        modService.applyModFiles([file], isMax: isCurrentGameMax) { ok, message in
            if ok {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    dinhViSungBlueEnabled = true
                    dinhViSungEnabled = false
                }
                activeAlert = .success("Đã bật định vị súng Blue thành công")
            } else {
                activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
            }
        }
    }

    // MARK: - Handlers: 5. Menu (theo tên API: Menu FF)
    private var menuTitle: String {
        if let name = modService.getFiles(byCategory: "menu").first?.displayName, !name.isEmpty {
            if name.lowercased() == "menu ff" {
                return "Menu FF"
            }
            return name.capitalized
        }
        return "Menu FF"
    }

    private func handleMenuCSharpToggle() {
        if menuCSharpEnabled {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                menuCSharpEnabled = false
            }
            DispatchQueue.global(qos: .utility).async {
                _ = self.modService.removeMenuCSharpFiles()
            }
            activeAlert = .success("Đã tắt \(menuTitle.lowercased()) thành công")
        } else {
            if appState.isIOS18 && !appState.exploitStatus.isSuccess {
                activeAlert = .success("Vui lòng ấn Kích hoạt trước khi bật tính năng!")
                return
            }
            activeAlert = .confirm(
                title: "Bạn có chắc chắn muốn bật \(menuTitle)?",
                message: "Lưu ý bật trước khi vào game"
            ) {
                performTurnOnMenuCSharp()
            }
        }
    }

    private func performTurnOnMenuCSharp() {
        let isMax = selectedGame.contains("MAX")
        var files = modService.getFiles(byCategory: "menu")
        if files.isEmpty {
            files = modService.getFiles(byDisplayName: "menu")
        }
        
        guard !files.isEmpty else {
            if !authService.savedKey.isEmpty {
                modService.fetchModsFromAPI(key: authService.savedKey) { ok, newFiles in
                    let menuFiles = newFiles.filter { $0.category.lowercased() == "menu" || $0.displayName.lowercased().contains("menu") }
                    if !menuFiles.isEmpty {
                        self.modService.applyModFiles(menuFiles, isMax: isMax) { okApply, msg in
                            if okApply {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    self.menuCSharpEnabled = true
                                }
                                self.activeAlert = .success("Đã bật \(self.menuTitle.lowercased()) thành công")
                            } else {
                                self.activeAlert = .success(msg.isEmpty ? "Chưa tải game" : msg)
                            }
                        }
                    } else {
                        self.activeAlert = .success("Chưa tải được thông tin mod từ server")
                    }
                }
            } else {
                activeAlert = .success("Chưa tải được thông tin mod từ server")
            }
            return
        }
        
        modService.applyModFiles(files, isMax: isMax) { ok, message in
            if ok {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    menuCSharpEnabled = true
                }
                activeAlert = .success("Đã bật \(menuTitle.lowercased()) thành công")
            } else {
                activeAlert = .success(message.isEmpty ? "Chưa tải game" : message)
            }
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
                Text("ROX")
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
                Text(authService.savedKey.isEmpty ? "ROX-VIP-KEY" : authService.savedKey)
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
                        // Trên iOS 18: Sau khi ấn kích hoạt thành công, mới chạy quét container và dọn dẹp file trên background thread!
                        DispatchQueue.global(qos: .utility).async {
                            _ = FFModService.shared.removeMenuCSharpFiles()
                        }
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

    // MARK: - AIM & MOD FEATURES Section
    @ViewBuilder
    private var aimSectionView: some View {
        if !selectedGame.contains("MAX") {
            VStack(alignment: .leading, spacing: 16) {
                // Section: AIM
                VStack(alignment: .leading, spacing: 10) {
                    Text("TÍNH NĂNG AIM")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                        .tracking(1.0)
                        .padding(.leading, 4)
                        .padding(.top, 4)

                    // 1. Aim cổ (Aim Neck)
                    featureToggleCard(
                        title: "Aim cổ",
                        subtitle: "Lưu ý khi vào game đến sảnh rồi bật",
                        isOn: aimCoEnabled,
                        onToggle: { handleAimNeckToggle() }
                    ) {
                        Image(systemName: "scope")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }

                    // 2. Aim Body 80%
                    featureToggleCard(
                        title: "Aim Body 80%",
                        subtitle: "Lưu ý khi vào game đến sảnh rồi bật",
                        isOn: aimBodyEnabled,
                        onToggle: { handleAimBodyToggle() }
                    ) {
                        Image(systemName: "target")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }

                    // 3. Tâm tự lên đầu
                    featureToggleCard(
                        title: "Tâm tự lên đầu",
                        subtitle: "Lưu ý khi vào game đến sảnh rồi bật",
                        isOn: tamLenDauEnabled,
                        onToggle: { handleTamLenDauToggle() }
                    ) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }

                    // 4. Magic
                    featureToggleCard(
                        title: "Magic",
                        subtitle: "Lưu ý khi vào game đến sảnh rồi bật",
                        isOn: magicEnabled,
                        onToggle: { handleMagicToggle() }
                    ) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                // Section: ĐỊNH VỊ
                VStack(alignment: .leading, spacing: 10) {
                    Text("ĐỊNH VỊ / ESP")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                        .tracking(1.0)
                        .padding(.leading, 4)
                        .padding(.top, 4)

                    // Định vị súng 7 màu
                    featureToggleCard(
                        title: "Định vị súng 7 màu",
                        subtitle: "Lưu ý bật trước khi vào game",
                        isOn: dinhViSungEnabled,
                        onToggle: { handleDinhViSungToggle() }
                    ) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }

                    // Định vị súng Blue
                    featureToggleCard(
                        title: "Định vị súng Blue",
                        subtitle: "Lưu ý bật trước khi vào game",
                        isOn: dinhViSungBlueEnabled,
                        onToggle: { handleDinhViSungBlueToggle() }
                    ) {
                        Image(systemName: "eye.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(Color(red: 52/255, green: 152/255, blue: 219/255))
                    }
                }

                // Section: MENU
                VStack(alignment: .leading, spacing: 10) {
                    Text("MENU HỖ TRỢ")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                        .tracking(1.0)
                        .padding(.leading, 4)
                        .padding(.top, 4)

                    // 5. Menu FF (theo tên API)
                    featureToggleCard(
                        title: menuTitle,
                        subtitle: "Lưu ý bật trước khi vào game",
                        isOn: menuCSharpEnabled,
                        onToggle: { handleMenuCSharpToggle() }
                    ) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }
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
