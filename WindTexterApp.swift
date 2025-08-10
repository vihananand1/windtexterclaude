import SwiftUI

@main
struct WindTexterApp: App {
    @State private var isInChat: Bool = false
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @StateObject var messageStore = ChatMessagesStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .environmentObject(messageStore) // Inject into environment
        }
    }
}
