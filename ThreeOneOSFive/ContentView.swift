import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var appState: AppState
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @State private var tabNavigation: AppTabNavigationState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showLogs = false
    @StateObject private var authService = AuthKeyService.shared

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-files-tab") {
            initialTab = AppSection.files.rawValue
        } else {
            initialTab = AppSection.installed.rawValue
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: AppSection.installed.rawValue))
#endif
    }

    var body: some View {
        Group {
            if authService.isAuthenticated {
                if horizontalSizeClass == .regular {
                    regularLayout
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    compactLayout
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            } else {
                AuthKeyView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authService.isAuthenticated)
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .imageScale(.small)
        .onAppear {
            authService.autoCheck()
        }
        .onChange(of: authService.isAuthenticated) { authenticated in
            if authenticated {
                appState.detectSupport()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, authService.isAuthenticated {
                authService.revalidateCurrentKey()
                appState.detectSupport()
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .patchStorePresentation(patchStore)
    }

    @ViewBuilder
    private var compactLayout: some View {
        if featureVisibility.visibleSections.count > 1 {
            TabView(selection: tabSelection) {
                ForEach(featureVisibility.visibleSections) { section in
                    sectionContent(section)
                        .tabItem {
                            CompactTabLabel(
                                title: language.text(section.titleKey),
                                systemImage: section.systemImage
                            )
                        }
                        .tag(section.rawValue)
                }
            }
        } else {
            sectionContent(.installed)
        }
    }

    @ViewBuilder
    private var regularLayout: some View {
        if featureVisibility.visibleSections.count > 1 {
            NavigationSplitView {
                List {
                    ForEach(featureVisibility.visibleSections) { section in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                tabNavigation.select(section.rawValue)
                            }
                        } label: {
                            Label(language.text(section.titleKey), systemImage: section.systemImage)
                                .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            section.rawValue == tabNavigation.selectedTab
                                ? AppTheme.accent.opacity(0.14)
                                : Color.clear
                        )
                        .accessibilityAddTraits(
                            section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                        )
                    }
                }
                .navigationTitle("NTA MOD")
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
            } detail: {
                sectionContent(selectedVisibleSection)
                    .id(selectedVisibleSection.rawValue)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            sectionContent(.installed)
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(developerModeEnabled: developerModeActive)
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .installed
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .installed: return "tab.installed"
        case .files: return "tab.files"
        }
    }

    var systemImage: String {
        switch self {
        case .installed: return "tray.full.fill"
        case .files: return "folder.fill"
        }
    }
}
