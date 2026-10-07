import SwiftUI

@main
struct DepthLabApp: App {
    @State private var samples = SampleStore()
    @State private var captures = CaptureStore()
    @State private var protocolStore = ProtocolStore()

    init() { AppSettings.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(samples)
                .environment(captures)
                .environment(protocolStore)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            MeasureView()
                .tabItem { Label("Đo", systemImage: "ruler") }
            SamplesView()
                .tabItem { Label("Mẫu", systemImage: "tablecells") }
            CaptureLibraryView()
                .tabItem { Label("Thư viện", systemImage: "photo.stack") }
            ProtocolView()
                .tabItem { Label("Quy trình", systemImage: "checklist") }
            MoreView()
                .tabItem { Label("Thêm", systemImage: "ellipsis.circle") }
        }
    }
}
