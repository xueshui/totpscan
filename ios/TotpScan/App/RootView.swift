import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            AccountsView()
                .tabItem { Label("账户", systemImage: "person.crop.rectangle.stack") }

            LoginFlowView()
                .tabItem { Label("扫码登录", systemImage: "qrcode.viewfinder") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .appAlert()
        .appToast()
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.reload()
            }
        }
    }
}
