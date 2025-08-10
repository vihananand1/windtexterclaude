import SwiftUI
import GoogleSignIn
import GoogleSignInSwift


import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var countryCode: String? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            self.countryCode = placemarks?.first?.isoCountryCode
        }
        manager.stopUpdatingLocation()
    }
}


extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}



struct HomeView: View {
    @EnvironmentObject var messageStore: ChatMessagesStore // 👈 Required
    @State private var activePaths: [String] = []
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedFilter: String = "All"
    @AppStorage("isSignedInToGmail") private var isSignedInToGmail: Bool = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @StateObject var locationManager = LocationManager()
    @State private var searchQuery: String = ""
    @State private var chats: [Chat] = []

    let regionToPaths: [String: [String]] = [
        "US": ["SMS", "Email"],
        "GB": ["SMS", "Email"],
        "IN": ["Email"],
        "BR": ["Email"],
        "DE": ["Email"],
        "CN": ["SMS", "Email"], // UPDATED: Both should work
        "default": ["Email"]
    ]

    @Environment(\.colorScheme) var colorScheme
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("showRealMessage") private var showRealMessage: Bool = true
    @State private var isInChat: Bool = false
    @State private var backendPollingTimer: Timer?
    @State private var showingAddContact = false
    @State private var contacts: [Contact] = []
    @AppStorage("hasImportedContacts") private var hasImportedContacts = false

    var body: some View {
        TabView {
            mainChatTab
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("Chats")
                }

            SettingsView(isDarkMode: $isDarkMode)
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
        }
        .background(backgroundColor)
        .onChange(of: isInChat) { inChat in
            UIApplication.shared.windows.first?.rootViewController?.tabBarController?.tabBar.isHidden = inChat
        }
    }

    private var mainChatTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: UIScreen.main.bounds.height * 0.015)
                        searchBar
                        filterButtons
                        chatList
                    }
                    .padding(.top, 10)
                    .background(backgroundColor)
                }

                footerView // ⬅️ Moved outside the ScrollView, now closer to the bottom
            }
            .background(backgroundColor)
            .padding(.bottom, 40)
            .navigationTitle("WindTexter")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddContact = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .background(backgroundColor)
            .background(backgroundColor)

            .onAppear {
                backendPollingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                    print("🏠 HomePage polling at \(Date())")
                    print("🔍 Checking \(chats.count) chats")
                    
                    for chat in chats {
                        guard !isInChat else {
                            print("📱 User is in chat, skipping polling for \(chat.name)")
                            continue
                        }
                        
                        let activePaths = ["send_email", "send_sms"]
                        
                        for path in activePaths {
                            BackendAPI.fetchMessages(for: path) { backendMessages in
                                print("📡 HomePage: Got \(backendMessages.count) messages for chat \(chat.name) from path \(path)")
                                
                                DispatchQueue.main.async {
                                    messageStore.load(for: chat)
                                    let existingMessages = messageStore.messagesPerChat[chat.id] ?? []
                                    let existingIDs = Set(existingMessages.map { $0.id })
                                    
                                    // Filter out messages we already have
                                    let newMessages = backendMessages.filter { !existingIDs.contains($0.id) }
                                    
                                    if !newMessages.isEmpty {
                                        print("📥 HomePage: Found \(newMessages.count) new messages for \(chat.name)")
                                        
                                        for message in newMessages {
                                            messageStore.addMessage(message, to: chat)
                                            
                                            //    FIX: Only increment unread count for RECEIVED messages and only when NOT in chat
                                            if !message.isSentByCurrentUser && !self.isInChat {
                                                if let index = self.chats.firstIndex(where: { $0.id == chat.id }) {
                                                    self.chats[index].unreadCount += 1
                                                    print("📈 Incremented unread count for \(chat.name): \(self.chats[index].unreadCount)")
                                                }
                                            }
                                        }
                                        
                                        //    FIX: Update chat preview using the new logic that respects cover mode
                                        if let latestMessage = newMessages.last {
                                            self.updateChatPreview(for: chat, with: latestMessage)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                //    Force AppStorage sync with stored value
                if UserDefaults.standard.bool(forKey: "isSignedInToGmail") {
                    isSignedInToGmail = true
                }
                print("🧪 Synced isSignedInToGmail: \(isSignedInToGmail)")

                if !hasImportedContacts {
                    ContactManager.shared.requestAccess { granted in
                        guard granted else {
                            print("❌ Access to contacts denied.")
                            return
                        }

                        let imported = ContactManager.shared.fetchContacts()
                        self.contacts = imported
                        self.saveContacts()
                        hasImportedContacts = true
                    }
                }

                for chat in chats {
                    saveInitialMessageForChatIfNeeded(chat)
                }
            }
            .onDisappear {
                backendPollingTimer?.invalidate()
                backendPollingTimer = nil
            }
            
            .sheet(isPresented: $showingAddContact) {
                AddContactView { newContact in
                    let currentTime = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)

                    let newChat = Chat(
                        name: newContact.name,
                        realMessage: "",
                        coverMessage: "",
                        time: currentTime,
                        unreadCount: 0,
                        isFavorite: false,
                        isNew: true,
                        phoneNumber: newContact.phoneNumber,
                        email: newContact.email
                    )

                    chats.append(newChat)
                    saveInitialMessageForChatIfNeeded(newChat)

                    let availablePaths = getAvailablePathsForContact(newChat)
                    UserDefaults.standard.set(availablePaths, forKey: "availablePaths-\(newChat.id.uuidString)")

                    ContactManager.shared.requestAccess { granted in
                        guard granted else {
                            print("❌ Access to contacts denied.")
                            return
                        }

                        let imported = ContactManager.shared.fetchContacts()
                        self.contacts.append(contentsOf: imported)
                        self.saveContacts()
                    }
                }
            }
            
            .onReceive(messageStore.$latestChange) { _ in
                updateChatsWithLatestMessages()
            }

            .onReceive(timer) { _ in
                guard let signedInEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email else {
                    print("⚠️ No signed-in Gmail user.")
                    return
                }

                for chat in chats {
                    print("📬 Checking messages for chat: \(chat.name) (\(chat.email ?? ""))")
                    GmailManager.fetchAndStoreMessages(for: chat)
                }
            }
        }
    }
    

    private var searchBar: some View {
        TextField("Search Chats", text: $searchQuery)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
            .padding(.horizontal, 15)
            .padding(.bottom, 10)
    }

    private var filterButtons: some View {
        HStack {
            FilterButton(title: "All", selectedFilter: $selectedFilter)
            FilterButton(title: "Unread", selectedFilter: $selectedFilter)
            FilterButton(title: "Favorites", selectedFilter: $selectedFilter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 5)
        .padding(.leading, 15)
        .padding(.bottom, 5)
    }

    private var chatList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredChats.enumerated()), id: \.element.id) { index, chat in
                NavigationLink(destination: ChatView(chat: $chats[index], isInChat: $isInChat, chats: $chats)) {
                    VStack(spacing: 0) {
                        ChatRow(chat: chat, searchQuery: searchQuery, showRealMessage: showRealMessage)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(backgroundColor)

                        if index < filteredChats.count - 1 {
                            Divider()
                                .padding(.leading, 74)
                                .background(Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.6))
                        }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    //    FIX: Mark chat as read immediately when tapped
                    print("👆 User tapped on chat: \(chat.name)")
                    markChatAsRead(chat.id)
                    
                    //    NEW: Preload messages immediately when tapping
                    print("📂 Preloading messages for \(chat.name)")
                    messageStore.load(for: chat)
                    
                    isInChat = true
                })
            }
        }
        .transition(.opacity)
        .id(selectedFilter + searchQuery)
        .animation(.easeInOut(duration: 0.3), value: selectedFilter + searchQuery)
        .padding(.top, 5)
    }

    private var footerView: some View {
        Group {
            if selectedFilter == "All" && searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Text("WindTexter offers secure, encrypted messaging")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            }
        }
    }

    private var filteredChats: [Chat] {
        var results = chats

        switch selectedFilter {
        case "Unread":
            results = results.filter { $0.unreadCount > 0 }
        case "Favorites":
            results = results.filter { $0.isFavorite }
        default:
            break
        }

        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let rawQuery = searchQuery.lowercased()
            let query = rawQuery.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)

            results = results.filter { chat in
                let nameMatch = chat.name.lowercased().contains(query)

                if let savedData = UserDefaults.standard.data(forKey: "savedMessages-\(chat.id.uuidString)"),
                   let decodedMessages = try? JSONDecoder().decode([Message].self, from: savedData) {

                    let messageMatch = decodedMessages.contains { message in
                        let rawText = message.displayText(showRealMessage: showRealMessage).lowercased()
                        let normalizedText = rawText.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
                        return normalizedText.contains(query)
                    }

                    return nameMatch || messageMatch
                }

                return nameMatch
            }
        }

        return results
    }
    
    private func shouldIncrementUnreadCount(for message: Message, in chat: Chat) -> Bool {
        // Don't increment if:
        // 1. Message was sent by current user
        // 2. User is currently in this chat
        // 3. Chat is already marked as read recently
        
        if message.isSentByCurrentUser {
            print("🚫 Not incrementing unread: message sent by current user")
            return false
        }
        
        if isInChat {
            print("🚫 Not incrementing unread: user is in chat")
            return false
        }
        
        return true
    }
    
    private func getChatDisplayMode(for chatId: UUID) -> Bool {
        // Check if this specific chat has a path selected (real mode) or is in cover mode
        let chatModeSettings = (try? JSONDecoder().decode([UUID: String].self, from: selectedPathForChatRaw.data(using: .utf8) ?? Data())) ?? [:]
        return chatModeSettings[chatId] != nil // If there's a path set, it's in real mode; if nil, it's in cover mode
    }

    private func updateChatPreview(for chat: Chat, with message: Message) {
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }
        
        print("🔄 Updating chat preview for \(chat.name)")
        print("   New message timestamp: \(message.timestamp)")
        print("   New message isSentByCurrentUser: \(message.isSentByCurrentUser)")
        print("   New message has imageData: \(message.imageData != nil)")
        print("   New message realText: '\(message.realText ?? "nil")'")
        print("   New message coverText: '\(message.coverText?.prefix(50) ?? "nil")...'")
        
        //    CRITICAL FIX: Always find the MOST RECENT message for preview, don't just use the passed message
        let allMessages = messageStore.messagesPerChat[chat.id] ?? []
        let validMessages = allMessages.filter { !isEmptyMessage($0) } // Filter out empty messages
        let sortedMessages = validMessages.sorted(by: { $0.timestamp > $1.timestamp }) // Sort by timestamp (most recent first)
        
        guard let mostRecentMessage = sortedMessages.first else {
            print("   No valid messages found for preview")
            return
        }
        
        print("   Most recent message timestamp: \(mostRecentMessage.timestamp)")
        print("   Most recent message has imageData: \(mostRecentMessage.imageData != nil)")
        print("   Using most recent message for preview")
        
        //    Use the most recent message for preview, not the passed message
        updateChatPreviewWithMessage(chatIndex: index, message: mostRecentMessage)
    }

    //    Helper function to check if a message is empty/invalid
    private func isEmptyMessage(_ message: Message) -> Bool {
        let hasNoRealText = message.realText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let hasNoCoverText = message.coverText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let hasNoImage = message.imageData == nil
        
        return hasNoRealText && hasNoCoverText && hasNoImage
    }

    //    Separate the actual preview update logic
    private func updateChatPreviewWithMessage(chatIndex: Int, message: Message) {
        print("🎯 Setting preview for message:")
        print("   Has imageData: \(message.imageData != nil)")
        print("   realText: '\(message.realText ?? "nil")'")
        print("   coverText: '\(message.coverText?.prefix(30) ?? "nil")...'")
        
        //    Always update both fields so the preview can switch between modes
        if message.imageData != nil {
            // Image message - always show image placeholder with highest priority
            chats[chatIndex].realMessage = message.realText?.isEmpty == false ? message.realText! : "📸 Image"
            chats[chatIndex].coverMessage = "📸 Image"
            print("      Set preview to IMAGE")
        } else if message.isSentByCurrentUser {
            // Sent message - we have both real and cover text
            chats[chatIndex].realMessage = message.realText ?? ""
            chats[chatIndex].coverMessage = message.coverText ?? ""
            print("      Set preview to SENT TEXT")
        } else {
            // Received message - determine what to show based on message content
            if let realText = message.realText, !realText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Message has real text - this means it was decoded successfully
                chats[chatIndex].realMessage = realText
                chats[chatIndex].coverMessage = message.coverText ?? realText // Fallback to real text if no cover text
                print("      Set preview to RECEIVED TEXT (decoded)")
            } else {
                // Message only has cover text (bitstream) - couldn't be decoded or is pure cover
                chats[chatIndex].realMessage = message.coverText ?? "" // Show bitstream as "real" since that's all we have
                chats[chatIndex].coverMessage = message.coverText ?? ""
                print("      Set preview to RECEIVED TEXT (bitstream only)")
            }
        }
        
        // Update timestamp
        chats[chatIndex].time = message.formattedTimestamp()
        
        print("   Final preview - realMessage: '\(chats[chatIndex].realMessage)'")
        print("   Final preview - coverMessage: '\(chats[chatIndex].coverMessage.prefix(30))...'")
    }

    //    NEW: Add this property to HomeView to get the selected path for chat setting
    @AppStorage("selectedPathForChat") private var selectedPathForChatRaw: String = ""
    

    private func saveInitialMessageForChatIfNeeded(_ chat: Chat) {
        let key = "savedMessages-\(chat.id.uuidString)"
        guard UserDefaults.standard.data(forKey: key) == nil else { return }

        //    FIX: Create ISO8601 timestamp instead of formatted timestamp
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampString = isoFormatter.string(from: Date())

        let message = Message(
            realText: chat.realMessage,
            coverText: chat.coverMessage,
            isSentByCurrentUser: false,
            timestamp: timestampString  // Now uses ISO8601 format consistently
        )

        if let encoded = try? JSONEncoder().encode([message]) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    private func getAvailablePathsForContact(_ chat: Chat) -> [String] {
        let key = "availablePaths-\(chat.id.uuidString)"
        if let data = UserDefaults.standard.array(forKey: key) as? [String] {
            return data
        }

        let region = Locale.current.regionCode ?? "default"
        return regionToPaths[region] ?? regionToPaths["default"]!
    }

    private func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }
    
    private func updateChatsWithLatestMessages() {
        for index in chats.indices {
            let chatId = chats[index].id
            if let latestMessage = messageStore.messagesPerChat[chatId]?.last {
                updateChatPreview(for: chats[index], with: latestMessage)
            }
        }
    }
    
    private func markChatAsRead(_ chatId: UUID) {
        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            let previousCount = chats[index].unreadCount
            chats[index].unreadCount = 0
            print("   Marked chat '\(chats[index].name)' as read (was: \(previousCount), now: 0)")
        }
    }


    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
}


import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

struct SettingsView: View {
    @Binding var isDarkMode: Bool
    @AppStorage("showRealMessage") private var showRealMessage: Bool = true
    @AppStorage("selectedPaths") private var selectedPathsData: Data = Data()
    @AppStorage("gmailAccessToken") private var gmailAccessToken: String = ""

    @State private var selectedPathsInternal: Set<String> = []
    @AppStorage("isSignedInToGmail") var isSignedInToGmail = false

    private let allPaths = getAvailablePathsForCurrentRegion().filter { $0 != "WindTexter" }

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)

            Toggle("Dark Mode", isOn: $isDarkMode)
                .padding(.horizontal, 20)

            gmailSection

            HStack {
                Text("Enabled Paths")
                    .font(.title2)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ForEach(allPaths, id: \.self) { path in
                Toggle(path, isOn: Binding<Bool>(
                    get: { selectedPathsInternal.contains(path) },
                    set: { isOn in
                        if isOn {
                            selectedPathsInternal.insert(path)
                        } else {
                            selectedPathsInternal.remove(path)
                        }
                        if let encoded = try? JSONEncoder().encode(selectedPathsInternal) {
                            selectedPathsData = encoded
                        }
                    }
                ))
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .onAppear {
            if let decoded = try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData) {
                selectedPathsInternal = decoded
            } else {
                selectedPathsInternal = Set(allPaths)
            }

            isSignedInToGmail = !gmailAccessToken.isEmpty
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(UIColor.systemBackground))
    }

    var gmailSection: some View {
        VStack(spacing: 12) {
            Divider().padding(.horizontal)

            Text("Gmail Integration")
                .font(.headline)

            if isSignedInToGmail {
                Text("   Connected to Gmail")
                    .font(.subheadline)
                    .foregroundColor(.green)

                Button("Sign Out") {
                    AuthManager.shared.signOut()
                    isSignedInToGmail = false
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            } else {
                Button("Connect Gmail") {
                    signInWithGoogle()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(.bottom)
    }

    func signInWithGoogle() {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            print("❌ No root view controller found")
            return
        }

        GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: ["https://www.googleapis.com/auth/gmail.readonly"]
        ) { result, error in
            if let error = error {
                print("❌ Google Sign-In failed:", error.localizedDescription)
                return
            }

            guard let user = result?.user else {
                print("❌ No user object")
                return
            }

            let token = user.accessToken.tokenString
            gmailAccessToken = token
            isSignedInToGmail = true
            UserDefaults.standard.set(true, forKey: "isSignedInToGmail")
            UserDefaults.standard.set(token, forKey: "gmailAccessToken")
            UserDefaults.standard.synchronize()
            print("   Google Sign-In successful. Token saved.")
        }
    }
}




struct ChatRow: View {
    let chat: Chat
    let searchQuery: String
    let showRealMessage: Bool // This is the global setting, but we need to override it per chat
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("selectedPathForChat") private var selectedPathForChatRaw: String = ""

    //    NEW: Function to determine if THIS specific chat should show real messages
    private func shouldShowRealMessageForThisChat() -> Bool {
        let chatModeSettings = (try? JSONDecoder().decode([UUID: String].self, from: selectedPathForChatRaw.data(using: .utf8) ?? Data())) ?? [:]
        
        // If this chat has a specific path selected, it's in "real mode"
        // If no path is set (nil), it's in "cover mode"
        let chatIsInRealMode = chatModeSettings[chat.id] != nil
        
        print("📱 ChatRow for \(chat.name) - shouldShowReal: \(chatIsInRealMode)")
        return chatIsInRealMode
    }

    var body: some View {
        HStack {
            Circle()
                .fill(Color.gray)
                .frame(width: 50, height: 50)
                .overlay(Text(String(chat.name.prefix(1))).foregroundColor(.white))

            VStack(alignment: .leading) {
                Text(chat.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                //    CRITICAL FIX: Use the individual chat's mode setting
                Text(chat.displayMessage(showRealMessage: shouldShowRealMessageForThisChat()))
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack {
                Text(chat.time)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.caption2)
                        .padding(6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 8)
    }
}





struct Chat: Identifiable {
    let id = UUID()
    let name: String
    var realMessage: String
    var coverMessage: String
    var time: String
    var unreadCount: Int
    var isFavorite: Bool // <--- now mutable
    let isNew: Bool
    var phoneNumber: String?  // for SMS
    var email: String?

    func displayMessage(showRealMessage: Bool) -> String {
        showRealMessage ? realMessage : coverMessage
    }
}

struct Contact: Identifiable, Codable {
    let id: UUID
    var name: String
    var phoneNumber: String?
    var email: String?
    
    init(name: String, phoneNumber: String? = nil, email: String? = nil) {
        self.id = UUID()
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
    }
}

struct ContactsListView: View {
    @State private var contacts: [Contact] = []
    @State private var showAddContact = false

    var body: some View {
        NavigationView {
            List(contacts) { contact in
                VStack(alignment: .leading) {
                    Text(contact.name).font(.headline)
                    if let phone = contact.phoneNumber {
                        Text("📞 \(phone)").font(.subheadline)
                    }
                    if let email = contact.email {
                        Text("✉️ \(email)").font(.subheadline)
                    }
                }
            }
            .navigationTitle("Contacts")
            .toolbar {
                Button(action: { showAddContact = true }) {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showAddContact) {
                AddContactView { newContact in
                    contacts.append(newContact)
                    saveContacts()
                }
            }
            .onAppear {
                loadContacts()
            }
        }
    }

    func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }

    func loadContacts() {
        if let data = UserDefaults.standard.data(forKey: "savedContacts"),
           let decoded = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = decoded
        }
    }
}

// MARK: - Example FilterButton
struct FilterButton: View {
    let title: String
    @Binding var selectedFilter: String
    @Environment(\.colorScheme) var colorScheme // Get the current color scheme
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedFilter = title
            }
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(selectedFilter == title ? .bold : .regular)
                .foregroundColor(selectedFilter == title ? .blue : textColor)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 1))
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Text Color for Filters
    private var textColor: Color {
        colorScheme == .dark ? .white : .black // Light text for dark mode, dark text for light mode
    }
}

func getAvailablePathsForCurrentRegion() -> [String] {
    let regionToPaths: [String: [String]] = [
        "US": ["SMS", "send_email"],
        "GB": ["SMS", "send_email"],
        "IN": ["send_email"],
        "BR": ["send_email"],
        "DE": ["send_email"],
        "CN": ["SMS", "send_email"],
        "default": ["send_email"]
    ]
    
    let region = Locale.current.regionCode ?? "default"
    return regionToPaths[region] ?? regionToPaths["default"]!
}
