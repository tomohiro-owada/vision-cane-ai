import SwiftUI

/// アプリのルートビュー。起動時にガイドパイプラインを立ち上げ、画面自体は
/// シンプルな状況表示に徹する（視覚的な情報より音声・触覚を優先する設計）。
struct ContentView: View {
    @EnvironmentObject private var viewModel: GuideViewModel

    var body: some View {
        GuideView()
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.stop() }
    }
}

#Preview {
    ContentView()
        .environmentObject(GuideViewModel())
}
