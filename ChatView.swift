// ChatView.Swift - COMPLETE FIXED VERSION WITH CONTACT MANAGEMENT

import SwiftUI
import CoreLocation
import Contacts
import GoogleSignIn
import GoogleSignInSwift

// Add this helper class for consistent device ID
class DeviceIDManager {
    static let shared = DeviceIDManager()
    private let deviceIDKey = "WindTexterDeviceID"
    
    private init() {}
    
    var deviceID: String {
        if let existingID = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existingID
        } else {
            // Create a new persistent device ID
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: deviceIDKey)
            return newID
        }
    }
}

struct OffsetOpacityModifier: ViewModifier {
    let xOffset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: xOffset)
            .opacity(opacity)
    }
}

struct IMessageSendTransition: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.85)
            .opacity(isVisible ? 1 : 0)
            .offset(x: isVisible ? 0 : 20, y: isVisible ? 0 : -8)
            .animation(.interpolatingSpring(stiffness: 220, damping: 22), value: isVisible)
    }
}

class ChatMessagesStore: ObservableObject {
    @Published var loadedMessageIDs: [UUID: Set<UUID>] = [:]
    @Published var messagesPerChat: [UUID: [Message]] = [:]
    @Published var latestChange = UUID()
    
    func isDuplicate(_ newMessage: Message, in chat: Chat) -> Bool {
        let existingMessages = messagesPerChat[chat.id] ?? []

        return existingMessages.contains(where: { existing in
            existing.id == newMessage.id ||
            (existing.realText == newMessage.realText &&
             existing.senderID == newMessage.senderID &&
             existing.coverText == newMessage.coverText &&
             existing.timestamp == newMessage.timestamp &&
             existing.isSentByCurrentUser == newMessage.isSentByCurrentUser)
        })
    }

    func load(for chat: Chat) {
        let key = "savedMessages-\(chat.id.uuidString)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Message].self, from: data) {
            
            // Remove duplicates when loading from UserDefaults
            let uniqueMessages = removeDuplicates(from: decoded)
            
            // FIXED: Set isSentByCurrentUser based on consistent device ID
            let currentDeviceID = DeviceIDManager.shared.deviceID
            for message in uniqueMessages {
                // Only update if senderID exists and doesn't match current logic
                if let senderID = message.senderID {
                    message.isSentByCurrentUser = (senderID == currentDeviceID)
                }
                // If no senderID, keep the existing isSentByCurrentUser value
            }
            
            messagesPerChat[chat.id] = uniqueMessages
            loadedMessageIDs[chat.id] = Set(uniqueMessages.map { $0.id })
            
            // Save back the deduplicated messages
            if let encoded = try? JSONEncoder().encode(uniqueMessages) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    func addMessage(_ message: Message, to chat: Chat) {
        //  Use centralized duplicate detection
        guard !isDuplicate(message, in: chat) else {
            print("🔄 ChatMessagesStore: Skipping duplicate message")
            return
        }

        //   FIXED: Ensure senderID is set consistently
        if message.senderID == nil {
            message.senderID = DeviceIDManager.shared.deviceID
        }

        //   Add message
        var updatedMessages = messagesPerChat[chat.id, default: []]
        updatedMessages.append(message)
        messagesPerChat[chat.id] = updatedMessages

        //   Track ID after successfully adding
        loadedMessageIDs[chat.id, default: []].insert(message.id)

        latestChange = UUID()
        save(chat: chat)

        print("  ChatMessagesStore: Added message. Total count: \(updatedMessages.count)")
    }

    //   Helper function to remove duplicates
    private func removeDuplicates(from messages: [Message]) -> [Message] {
        var uniqueMessages: [Message] = []
        
        for message in messages {
            let isDuplicate = uniqueMessages.contains { existing in
                // Same logic as addMessage
                if existing.id == message.id {
                    return true
                }
                
                let sameContent = existing.realText == message.realText &&
                                 existing.coverText == message.coverText
                let sameTimestamp = existing.timestamp == message.timestamp
                let sameSender = existing.isSentByCurrentUser == message.isSentByCurrentUser
                
                return sameContent && sameTimestamp && sameSender
            }
            
            if !isDuplicate {
                uniqueMessages.append(message)
            }
        }
        
        return uniqueMessages
    }

    func save(chat: Chat) {
        if let liveMessages = messagesPerChat[chat.id],
           let encoded = try? JSONEncoder().encode(liveMessages) {
            UserDefaults.standard.set(encoded, forKey: "savedMessages-\(chat.id.uuidString)")
        }
    }
}

final class Message: Identifiable, Codable, ObservableObject, Equatable {
    var senderID: String? = nil
    var deliveryPath: String?  // e.g., "WhatsApp", "Telegram", "Twitter"
    let id: UUID
    var realText: String?
    var coverText: String?
    var isSentByCurrentUser: Bool
    let timestamp: String // Keep timestamp as String
    let imageData: Data?
    var bitCount: Int? = nil
    var isAutoReply: Bool = false

    init(
        id: UUID = UUID(),
        realText: String?,
        coverText: String?,
        isSentByCurrentUser: Bool,
        timestamp: String,
        imageData: Data? = nil,
        bitCount: Int? = nil,
        deliveryPath: String? = nil,
        isAutoReply: Bool = false,
        senderID: String? = nil
    ) {
        print("🔍 MESSAGE INIT DEBUG:")
        print("   Received senderID parameter: '\(senderID ?? "NIL")'")
        
        self.id = id
        self.realText = realText
        self.coverText = coverText
        self.isSentByCurrentUser = isSentByCurrentUser
        self.timestamp = timestamp
        self.imageData = imageData
        self.bitCount = bitCount
        self.deliveryPath = deliveryPath
        self.isAutoReply = isAutoReply
        
        //   FIXED: Only set senderID if not provided
        self.senderID = senderID ?? DeviceIDManager.shared.deviceID
        
        print("   Final self.senderID: '\(self.senderID ?? "NIL")'")
        print("---")
    }

    func displayText(showRealMessage: Bool) -> String {
        if showRealMessage {
            return realText ?? ""
        } else {
            return coverText ?? realText ?? ""
        }
    }
    
    static func ==(lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
               lhs.realText == rhs.realText &&
               lhs.coverText == rhs.coverText &&
               lhs.timestamp == rhs.timestamp
    }

    func formattedTimestamp() -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            return displayFormatter.string(from: date)
        } else {
            //   IMPROVED: Try parsing without fractional seconds as fallback
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: timestamp) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "h:mm a"
                return displayFormatter.string(from: date)
            }
            
            //   LAST RESORT: If timestamp is already in display format, return as-is
            if timestamp.contains(":") && (timestamp.contains("AM") || timestamp.contains("PM") || timestamp.count <= 8) {
                return timestamp
            }
            
            // If all else fails, create current time
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            return displayFormatter.string(from: Date())
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, senderID, realText, coverText, isSentByCurrentUser, timestamp, imageData, deliveryPath, bitCount, isAutoReply
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        deliveryPath = try container.decodeIfPresent(String.self, forKey: .deliveryPath)
        id = try container.decode(UUID.self, forKey: .id)
        realText = try container.decodeIfPresent(String.self, forKey: .realText)
        coverText = try container.decodeIfPresent(String.self, forKey: .coverText)
        senderID = try container.decodeIfPresent(String.self, forKey: .senderID)
        
        // Use String for timestamp
        timestamp = try container.decode(String.self, forKey: .timestamp)
        
        // Decode isSentByCurrentUser with a default value
        isSentByCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .isSentByCurrentUser) ?? false
        
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        bitCount = try container.decodeIfPresent(Int.self, forKey: .bitCount)
        isAutoReply = try container.decodeIfPresent(Bool.self, forKey: .isAutoReply) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(realText, forKey: .realText)
        try container.encodeIfPresent(coverText, forKey: .coverText)
        try container.encode(isSentByCurrentUser, forKey: .isSentByCurrentUser)
        try container.encode(timestamp, forKey: .timestamp) // Keep timestamp as String
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(senderID, forKey: .senderID)
        try container.encodeIfPresent(deliveryPath, forKey: .deliveryPath)
        try container.encodeIfPresent(bitCount, forKey: .bitCount)
        try container.encode(isAutoReply, forKey: .isAutoReply)
    }
}

struct ChatView: View {
    var scrollContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if messagesGroupedByPath.isEmpty {
                // Show a message when no messages match the selected path
                VStack {
                    Spacer()
                    if let selectedPath = selectedPathToReveal {
                        Text("No cover messages found for \(selectedPath.capitalized)")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .padding()
                    } else {
                        Text("")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .padding()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(messagesGroupedByPath.keys.sorted(), id: \.self) { path in
                    if let messages = messagesGroupedByPath[path] {
                        VStack(alignment: .leading, spacing: 8) {
                            // 🏷️ Path header label - only show if multiple paths or in cover mode
                            if messagesGroupedByPath.keys.count > 1 || selectedPathToReveal != nil {
                                Text(path.uppercased())
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.15))
                                    .cornerRadius(10)
                                    .padding(.bottom, 5)
                            }

                            // 💬 Messages for that path
                            ForEach(messages) { message in
                                MessageBubble(message: message, showRealMessage: selectedPathToReveal == nil)
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7,
                                           alignment: message.isSentByCurrentUser ? .trailing : .leading)
                                    .padding(message.isSentByCurrentUser ? .leading : .trailing, 40)
                                    .frame(maxWidth: .infinity,
                                           alignment: message.isSentByCurrentUser ? .trailing : .leading)
                                    .id(message.id)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    var deliveryPaths: [String] {
        (try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData))?.sorted() ?? []
    }

    @Binding var chat: Chat
    var liveMessages: [Message] {
        let messages = messageStore.messagesPerChat[chat.id] ?? []
        print("📋 ChatView liveMessages count: \(messages.count) for chat \(chat.name)")
        return messages
    }

    @EnvironmentObject var messageStore: ChatMessagesStore
    @State private var lastSentBitstream: [Int] = []
    @AppStorage("isSignedInToGmail") private var isSignedInToGmail: Bool = false
    @State private var emailPollingTimer: Timer?
    @State private var backendPollingTimer: Timer?
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var isUnlocked = false
    @State private var selectedPathToReveal: String? = nil
    @Binding var isInChat: Bool
    @Binding var chats: [Chat]
    @State private var lastSentMessageID: UUID?
    @AppStorage("selectedPathForChat") private var selectedPathForChatRaw: String = ""
    @State private var inputHeight: CGFloat = 40
    @State private var messageText: String = ""
    @State private var refreshToggle = false
    @State private var selectedImage: UIImage?
    @State private var showImagePicker: Bool = false
    @StateObject var locationManager = LocationManager()
    @State private var hasLoadedMessages = false
    
    // NEW: Contact management state
    @State private var showingContactDetail = false
    
    let deviceID = DeviceIDManager.shared.deviceID
    
    @AppStorage("selectedPaths") private var selectedPathsData: Data = Data()

    var selectedPaths: [String] {
        (try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData))?.sorted() ?? deliveryPaths
    }
    
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var allDeliveryPaths: [String] {
        Array(Set(liveMessages.compactMap { $0.deliveryPath })).sorted()
    }

    var messagesGroupedByPath: [String: [Message]] {
        let filteredMessages: [Message]
        
        if let selectedPath = selectedPathToReveal {
            // Only show messages from the selected path when in cover message mode
            filteredMessages = liveMessages.filter { message in
                let normalizedMessagePath = normalizeDeliveryPath(message.deliveryPath ?? "")
                let normalizedSelectedPath = normalizeDeliveryPath(selectedPath)
                return normalizedMessagePath == normalizedSelectedPath
            }
        } else {
            // Show all messages when in real message mode
            filteredMessages = liveMessages
        }
        
        let groups = Dictionary(grouping: filteredMessages, by: { $0.deliveryPath ?? "" })
        return groups.filter { !$0.value.isEmpty }
    }
    
    var body: some View {
        VStack {
            ZStack {
                // Centered chat name - MADE CLICKABLE FOR CONTACT MANAGEMENT
                HStack {
                    Spacer()
                    
                    // Make this entire section clickable
                    Button(action: {
                        showingContactDetail = true
                    }) {
                        HStack(spacing: 6.7) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 45, height: 45)
                                .overlay(
                                    Text(String(chat.name.prefix(1)))
                                        .font(.title)
                                        .foregroundColor(.white)
                                )
                            
                            Text(chat.name)
                                .font(.title3)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                    .buttonStyle(PlainButtonStyle()) // Removes default button styling
                    
                    Spacer()
                }
                
                // Top-left toggle
                HStack {
                    Menu {
                        Button("Show All Real Messages", action: {
                            selectedPathToReveal = nil
                            saveSelectedPath(nil)
                        })
                        ForEach(getAvailablePathsForContact(chat), id: \.self) { path in
                            Button("Show Cover Messages from \(path)", action: {
                                selectedPathToReveal = path
                                saveSelectedPath(path)
                            })
                        }
                    } label: {
                        Label(
                            selectedPathToReveal.map { "(\($0))" } ?? "Real Messages",
                            systemImage: selectedPathToReveal == nil ? "eye.slash.fill" : "eye.fill"
                        )
                        .foregroundColor(.blue)
                        .padding(10)
                    }

                    Spacer()
                }
                
                // Top-right star button
                HStack {
                    Spacer()
                    Button(action: {
                        toggleFavorite()
                    }) {
                        Image(systemName: chat.isFavorite ? "star.fill" : "star")
                            .resizable()
                            .frame(width: 26, height: 26)
                            .foregroundColor(chat.isFavorite ? .yellow : .gray)
                            .padding()
                    }
                }
            }
            .padding(.top, 6)
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.2) : Color.gray.opacity(0.6))
                .padding(.horizontal, 10)
            
            ScrollViewReader { proxy in
                ScrollView {
                    scrollContent
                }
                .id(refreshToggle)
                .onAppear {
                    self.scrollProxy = proxy
                }
                .onTapGesture {
                    isTextFieldFocused = false
                }
                .onChange(of: lastSentMessageID) { newID in
                    guard let id = newID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                .onReceive(messageStore.$latestChange) { _ in
                    DispatchQueue.main.async {
                        print("🎯 ChatView received messageStore update for chat \(chat.name)")
                        print("📊 Current message count: \(self.liveMessages.count)")
                        refreshToggle.toggle()
                        scrollToBottom()
                    }
                }
            }
                
            VStack(spacing: 6) {
                if let image = selectedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()
                            .padding(.leading, 8)
                        
                        Spacer()
                        
                        Button(action: {
                            selectedImage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 20))
                        }
                        .padding(.trailing, 10)
                    }
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
                    .padding(.horizontal, 10)
                }
                
                HStack(alignment: .bottom) {
                    ZStack(alignment: .leading) {
                        if messageText.isEmpty {
                            Text("Type a message...")
                                .foregroundColor(Color.gray)
                                .padding(.leading, 20)
                        }
                        
                        GrowingTextEditor(
                            text: $messageText,
                            dynamicHeight: $inputHeight,
                            minHeight: 40,
                            maxHeight: 120
                        )
                        .frame(height: inputHeight)
                        .frame(maxWidth: .infinity)
                        .padding(.leading, 10)
                        .focused($isTextFieldFocused)
                    }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20))
                            .padding(8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        showImagePicker = true
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .padding(8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 10)
                }
                .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showingContactDetail) {
            ContactDetailViewForChat(chat: chat, chats: $chats)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onAppear {
            loadMessages()
            
            guard !hasLoadedMessages else { return }
            hasLoadedMessages = true

            cleanupDuplicateMessages(for: chat)
            
            //   FIX: Mark chat as read when entering
            markChatAsRead()
            
            if let restoredPath = try? JSONDecoder().decode([UUID: String].self, from: selectedPathForChatRaw.data(using: .utf8) ?? Data())[chat.id] {
                selectedPathToReveal = restoredPath
            }
            
            // Initial Backend fetch
            let activePaths = ["send_email", "send_sms"]
            for path in activePaths {
                BackendAPI.fetchMessages(for: path) { backendMessages in
                    DispatchQueue.main.async {
                        for message in backendMessages {
                            addMessageIfNew(message, to: chat)
                        }
                        scrollToBottom()
                    }
                }
            }

            //   IMPROVED: Start polling timer with better message handling
            backendPollingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                print("🎯 ChatView polling for \(chat.name)")
                
                let activePaths = ["email", "send_email", "send_sms"]
                for path in activePaths {
                    BackendAPI.fetchMessages(for: path) { backendMessages in
                        let key = "savedMessages-\(chat.id.uuidString)"
                        var storedMessages: [Message] = []
                        
                        if let data = UserDefaults.standard.data(forKey: key),
                           let decoded = try? JSONDecoder().decode([Message].self, from: data) {
                            storedMessages = decoded
                        }
                        
                        let storedIDs = Set(storedMessages.map { $0.id })
                        let newMessages = backendMessages.filter { !storedIDs.contains($0.id) }
                        
                        if !newMessages.isEmpty {
                            print("🎯 ChatView found \(newMessages.count) new messages!")
                            
                            DispatchQueue.main.async {
                                for message in newMessages {
                                    addMessageIfNew(message, to: chat)
                                    
                                    //   FIX: Since user is IN the chat, don't increment unread counter
                                    // Messages received while in chat are considered "read"
                                }
                                self.scrollToBottom()
                            }
                        }
                    }
                }
            }
            
            if isSignedInToGmail {
                fetchIncomingEmailsFromGmail()
                emailPollingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                    fetchIncomingEmailsFromGmail()
                }
            }
        }
    
        .onReceive(messageStore.$latestChange) { _ in
            DispatchQueue.main.async {
                print("🎯 ChatView received messageStore update for chat \(chat.name)")
                print("📊 Current message count: \(self.liveMessages.count)")
                refreshToggle.toggle()
                scrollToBottom()
            }
        }

        .onDisappear {
            isInChat = false
            updateChatPreviewToLatestMessage()
            emailPollingTimer?.invalidate()
            emailPollingTimer = nil
            backendPollingTimer?.invalidate()
            backendPollingTimer = nil
            
            //   FIX: Ensure chat remains marked as read when leaving
            markChatAsRead()
        }
        .onChange(of: selectedPathToReveal != nil) { _ in
            refreshToggle.toggle()
        }
    }
    
    private func handleNewReceivedMessage(_ message: Message) {
        addMessageIfNew(message, to: chat)
        
        // Since user is actively in the chat, don't increment unread counter
        // The message is considered "read" immediately
        print("📨 Received new message in active chat - not incrementing unread count")
        
        scrollToBottom()
    }

    func addMessageIfNew(_ message: Message, to chat: Chat) {
        let currentDeviceID = DeviceIDManager.shared.deviceID
        
        if message.senderID != nil {
            message.isSentByCurrentUser = (message.senderID == currentDeviceID)
            print("  Message has senderID '\(message.senderID!)', isSentByCurrentUser: \(message.isSentByCurrentUser)")
        } else {
            print("⚠️ Message missing senderID - keeping as received message")
            message.isSentByCurrentUser = false
        }
        
        message.deliveryPath = normalizeDeliveryPath(message.deliveryPath ?? "")

        let existing = messageStore.messagesPerChat[chat.id] ?? []
        let newHash = message.contentHash

        print("🔍 DEBUG: Checking message for duplicates:")
        print("   New message ID: \(message.id.uuidString.prefix(8))")
        print("   New message realText: '\(message.realText ?? "nil")'")
        print("   New message coverText: '\(message.coverText ?? "nil")'")
        print("   Has image: \(message.imageData != nil)")
        if let imageData = message.imageData {
            print("   Image size: \(imageData.count) bytes")
        }

        if existing.contains(where: { $0.contentHash == newHash }) {
            print("🔄 DUPLICATE DETECTED via contentHash. Message not added.")
            return
        }

        messageStore.addMessage(message, to: chat)
    }

    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImage != nil else { return }

        //   Convert image to data if present
        var imageData: Data? = nil
        if let image = selectedImage {
            // Compress image to reasonable size for email
            imageData = image.jpegData(compressionQuality: 0.7)
            print("📸 Image converted to data: \(imageData?.count ?? 0) bytes")
        }

        DispatchQueue.main.async {
            messageText = ""
            selectedImage = nil
        }

        let availablePaths = getAvailablePathsForContact(chat).map { $0.lowercased() }

        let pathsToSend: [String] = {
            var paths: [String] = []
            if availablePaths.contains("sms"), chat.phoneNumber != nil {
                paths.append("send_sms")
            }
            if availablePaths.contains("email"), chat.email != nil {
                paths.append("send_email")
            }
            return paths
        }()
        

        //   FIX: Handle image messages differently - EXIT EARLY to avoid bitstream processing
        if let imageData = imageData {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            for path in pathsToSend {
                let normalized = normalizeDeliveryPath(path)

                let msg = Message(
                    realText: trimmed.isEmpty ? nil : trimmed,
                    coverText: trimmed.isEmpty ? nil : trimmed,
                    isSentByCurrentUser: true,
                    timestamp: timestamp,
                    imageData: imageData
                )

                msg.senderID = DeviceIDManager.shared.deviceID
                msg.deliveryPath = normalized

                //   Add message to chat
                messageStore.addMessage(msg, to: chat)
                lastSentMessageID = msg.id
                scrollToBottom()

                //   Send actual message
                if path == "send_sms", let phone = chat.phoneNumber {
                    let textToSend = (trimmed.isEmpty ? "📸 Image" : trimmed) + " [Image attached]"
                    DeliveryManager.sendSMS(to: phone, message: textToSend) { success in
                        print(success ? "  SMS with image note sent" : "❌ SMS failed")
                    }
                } else if path == "send_email", let email = chat.email {
                    DeliveryManager.sendEmailWithImage(
                        to: email,
                        message: trimmed.isEmpty ? "📸 Image" : trimmed,
                        imageData: imageData
                    ) { success in
                        print(success ? "  Email with image sent" : "❌ Email failed")
                    }
                }

                //   Store message in backend
                if let timestampDate = ISO8601DateFormatter().date(from: timestamp) {
                    APIStorageManager.shared.storeMessageWithImage(
                        id: msg.id,
                        senderID: msg.senderID,
                        chatID: chat.id,
                        realText: trimmed.isEmpty ? nil : trimmed,
                        coverText: trimmed.isEmpty ? nil : trimmed,
                        bitCount: nil,
                        isAutoReply: false,
                        deliveryPath: normalized,
                        timestamp: timestampDate,
                        imageData: imageData
                    )
                }
            }

            print("🚪 EARLY RETURN: Image message processed for all paths")
            return //   CRITICAL: Exit early after processing image message for all paths
        }

        //   Continue with existing text message logic
        generateBitstream(for: trimmed) { bits, bitCount in
            DispatchQueue.main.async {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let bitstream = bits.map { String($0) }.joined()

                print("💥 Sending message with:")
                print("   realText: '\(trimmed)'")
                print("   bitstream: '\(bitstream)'")

                for path in pathsToSend {
                    let normalized = normalizeDeliveryPath(path)

                    let msg = Message(
                        realText: trimmed,
                        coverText: bitstream,
                        isSentByCurrentUser: true,
                        timestamp: timestamp,
                        imageData: nil
                    )

                    msg.senderID = DeviceIDManager.shared.deviceID
                    msg.deliveryPath = normalized
                    msg.bitCount = bitCount

                    //   Add to message store
                    messageStore.addMessage(msg, to: chat)
                    lastSentMessageID = msg.id
                    scrollToBottom()

                    //   Send via actual path
                    if path == "send_sms", let phone = chat.phoneNumber {
                        DeliveryManager.sendSMS(to: phone, message: bitstream) { success in
                            print(success ? "  SMS sent to \(phone)" : "❌ SMS failed")
                        }
                    } else if path == "send_email", let email = chat.email {
                        DeliveryManager.sendEmail(to: email, message: bitstream) { success in
                            print(success ? "  Email sent to \(email)" : "❌ Email failed")
                        }
                    }

                    //   Store in backend
                    if let timestampDate = ISO8601DateFormatter().date(from: timestamp) {
                        APIStorageManager.shared.storeMessage(
                            id: msg.id,
                            senderID: msg.senderID,
                            chatID: chat.id,
                            realText: trimmed,
                            coverText: bitstream,
                            bitCount: bitCount,
                            isAutoReply: false,
                            deliveryPath: normalized,
                            timestamp: timestampDate
                        )
                    }
                }
            }
        }
    }

    func fetchAutoReply(to userMessage: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/generate_reply") else {
            completion(nil)
            return
        }
        
        let history = liveMessages.suffix(10).map { $0.displayText(showRealMessage: selectedPathToReveal != nil) }
        let payload: [String: Any] = [
            "chat_history": history,
            "last_message": userMessage
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reply = json["reply"] as? String {
                completion(reply)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    func saveSelectedPath(_ path: String?) {
        var allSelections = (try? JSONDecoder().decode([UUID: String].self, from: selectedPathForChatRaw.data(using: .utf8) ?? Data())) ?? [:]
        allSelections[chat.id] = path
        if let data = try? JSONEncoder().encode(allSelections),
           let jsonString = String(data: data, encoding: .utf8) {
            selectedPathForChatRaw = jsonString
        }
    }
    
    private func updateChatTimeConsistently(with message: Message) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].time = message.formattedTimestamp() // Always use formatted timestamp
        }
    }
        
    func updateChatPreviewToLatestMessage() {
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }
        
        print("🏃‍♂️ updateChatPreviewToLatestMessage called for \(chat.name)")
        
        //   FIX: Use the same logic as HomePage's updateChatPreview
        // Find the most recent valid message, regardless of current view mode
        let allMessages = liveMessages
        let validMessages = allMessages.filter { message in
            let hasRealText = !(message.realText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasCoverText = !(message.coverText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasImage = message.imageData != nil
            
            return hasRealText || hasCoverText || hasImage
        }
        
        let sortedMessages = validMessages.sorted { $0.timestamp > $1.timestamp }
        
        guard let latestMessage = sortedMessages.first else {
            print("   No valid messages found for preview update")
            return
        }
        
        print("   Latest message has imageData: \(latestMessage.imageData != nil)")
        print("   Latest message realText: '\(latestMessage.realText ?? "nil")'")
        print("   Latest message timestamp: \(latestMessage.timestamp)")
        
        //   FIX: Update both realMessage and coverMessage properly
        if latestMessage.imageData != nil {
            // Image message - always show image placeholder
            chats[index].realMessage = latestMessage.realText?.isEmpty == false ? latestMessage.realText! : "📸 Image"
            chats[index].coverMessage = "📸 Image"
            print("     Set preview to IMAGE on exit")
        } else if latestMessage.isSentByCurrentUser {
            // Sent message - we have both real and cover text
            chats[index].realMessage = latestMessage.realText ?? ""
            chats[index].coverMessage = latestMessage.coverText ?? ""
            print("     Set preview to SENT TEXT on exit")
        } else {
            // Received message
            if let realText = latestMessage.realText, !realText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chats[index].realMessage = realText
                chats[index].coverMessage = latestMessage.coverText ?? realText
                print("     Set preview to RECEIVED TEXT (decoded) on exit")
            } else {
                chats[index].realMessage = latestMessage.coverText ?? ""
                chats[index].coverMessage = latestMessage.coverText ?? ""
                print("     Set preview to RECEIVED TEXT (bitstream only) on exit")
            }
        }
        
        //   ALWAYS use formattedTimestamp() instead of raw timestamp
        chats[index].time = latestMessage.formattedTimestamp()
        
        print("   Final on exit - realMessage: '\(chats[index].realMessage)'")
        print("   Final on exit - coverMessage: '\(chats[index].coverMessage.prefix(30))...'")
    }
    
    func scheduleAutoReply() {
        let delay = Double.random(in: 1.5...3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let replies = [
                "Okay", "Sure", "Let me know.", "Interesting...", "Sounds good.",
                "I'll check.", "Alright.", "Got it.", "Thanks!", "Cool."
            ]
            let reply = replies.randomElement() ?? "Okay"
            
            //   FIX: Create ISO8601 timestamp instead of formatted timestamp
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestampString = isoFormatter.string(from: Date())
            
            let message = Message(
                realText: nil,
                coverText: reply,
                isSentByCurrentUser: false,
                timestamp: timestampString,  // Use ISO8601 format
                imageData: nil
            )
            
            withAnimation(.easeOut(duration: 0.35)) {
                messageStore.addMessage(message, to: chat)
                lastSentMessageID = message.id
            }
            
            scrollToBottom()
        }
    }
    
    func normalizeDeliveryPath(_ path: String) -> String {
        switch path.lowercased() {
            case "send_email": return "email"
            case "send_sms": return "sms"
            case "whatsapp": return "whatsapp"
            default: return path.lowercased()
        }
    }
        
    func sendCoverChunks(for chunks: [(String, Int)], originalText: String, path: String) {
        let chatID = chat.id
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for (chunkText, chunkBitCount) in chunks {
            let timestamp = isoFormatter.string(from: Date())
            let userMessage = Message(
                realText: originalText,
                coverText: chunkText,
                isSentByCurrentUser: true,
                timestamp: timestamp,
                imageData: nil
            )

            // Normalize the path to "email"
            userMessage.deliveryPath = "email"
            userMessage.bitCount = chunkBitCount
            userMessage.isAutoReply = false

            messageStore.addMessage(userMessage, to: chat)
            lastSentMessageID = userMessage.id

            if let timestampDate = isoFormatter.date(from: userMessage.timestamp) {
                APIStorageManager.shared.storeMessage(
                    id: userMessage.id,
                    chatID: chatID,
                    realText: userMessage.realText,
                    coverText: userMessage.coverText,
                    bitCount: userMessage.bitCount,
                    isAutoReply: false,
                    deliveryPath: "email", // Use the normalized "email"
                    timestamp: timestampDate
                )
            }

            if path == "SMS", let phoneNumber = chat.phoneNumber {
                DeliveryManager.sendSMS(to: phoneNumber, message: chunkText) { success in
                }
            } else if path == "send_email", let email = chat.email {
                // Use "email" for both sending and receiving
                DeliveryManager.sendEmail(to: email, message: chunkText) { success in
                }
            }

            fetchAutoReply(to: chunkText) { reply in
                guard let reply = reply else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.6...1.2)) {
                    let replyTimestamp = isoFormatter.string(from: Date())
                    let autoReply = Message(
                        realText: nil,
                        coverText: reply,
                        isSentByCurrentUser: false,
                        timestamp: replyTimestamp,
                        imageData: nil
                    )
                    autoReply.deliveryPath = "email" // Normalize the auto-reply path
                    autoReply.isAutoReply = true

                    messageStore.addMessage(autoReply, to: chat)
                    lastSentMessageID = autoReply.id
                    scrollToBottom()

                    if let replyDate = isoFormatter.date(from: autoReply.timestamp) {
                        APIStorageManager.shared.storeMessage(
                            id: autoReply.id,
                            chatID: chatID,
                            realText: nil,
                            coverText: reply,
                            bitCount: nil,
                            isAutoReply: true,
                            deliveryPath: "email", // Normalize the path for auto-reply
                            timestamp: replyDate
                        )
                    }
                }
            }
        }
    }

    let regionToPaths: [String: [String]] = [
        "US": ["SMS", "Email"],
        "GB": ["SMS", "Email"],
        "IN": ["Email"],
        "BR": ["Email"],
        "DE": ["Email"],
        "CN": ["SMS", "Email"], // UPDATED: Both should work
        "default": ["Email"]
    ]
        
    func scrollToBottom(animated: Bool = true) {
        guard let proxy = scrollProxy, let last = liveMessages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    func getAvailablePathsForContact(_ chat: Chat) -> [String] {
        let key = "availablePaths-\(chat.phoneNumber ?? chat.email ?? "unknown")"
        let raw = (UserDefaults.standard.array(forKey: key) as? [String])
            ?? (regionToPaths[locationManager.countryCode ?? "default"]
                ?? regionToPaths["default"]!)

        return raw.filter { $0.lowercased() != "windtexter" }
    }

    func fetchIncomingEmailsFromGmail() {
        let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString ??
                    UserDefaults.standard.string(forKey: "gmailAccessToken")

        guard let accessToken = token else {
            return
        }

        GmailService.fetchEmailIDs(accessToken: accessToken) { ids in
            for id in ids {
                GmailService.fetchEmailBody(id: id, token: accessToken) { body, timestampString, sender in
                    guard let decodedBody = body else { return }
                }
            }
        }
    }
    
    func normalize(_ string: String?) -> String {
        guard let string = string else { return "" }
        return string.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
        
    func toggleFavorite() {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].isFavorite.toggle()
        }
    }
        
    func generateBitstream(for message: String, completion: @escaping ([Int], Int) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/split_cover_chunks") else {
            completion([], 0)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "message": message,
            "path": "send_email"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion([], 0)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let bitStrings = json["bitstream"] as? [String],
                  let count = json["bit_count"] as? Int else {
                completion([], 0)
                return
            }

            let bits = bitStrings.compactMap { Int($0) }
            completion(bits, count)
            lastSentBitstream = bits
            
            if !lastSentBitstream.isEmpty {
                decodeBitstream(bits: lastSentBitstream) { decoded in
                    DispatchQueue.main.async {
                        guard let decoded = decoded else { return }

                        let bitstreamString = lastSentBitstream.map { String($0) }.joined()
                        var existingMessages = messageStore.messagesPerChat[chat.id] ?? []

                        //   Try to find existing message and update it
                        if let index = existingMessages.lastIndex(where: {
                            ($0.coverText?.trimmingCharacters(in: .whitespacesAndNewlines) == bitstreamString)
                        }) {
                            existingMessages[index].realText = decoded
                            messageStore.messagesPerChat[chat.id] = existingMessages
                            messageStore.save(chat: chat)
                            messageStore.latestChange = UUID()
                            print("  Updated realText for message \(existingMessages[index].id)")
                        } else {
                            //   FIXED: Use addMessageIfNew instead of direct manipulation
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            let newMessage = Message(
                                realText: decoded,
                                coverText: bitstreamString,
                                isSentByCurrentUser: false,
                                timestamp: timestamp
                            )
                            newMessage.deliveryPath = normalizeDeliveryPath("send_email")
                            newMessage.isAutoReply = false

                            //   Use consistent duplicate prevention
                            addMessageIfNew(newMessage, to: chat)
                            lastSentMessageID = newMessage.id
                            scrollToBottom()
                        }
                    }
                }
            }
        }.resume()
    }

    func cleanupDuplicateMessages(for chat: Chat) {
        let key = "savedMessages-\(chat.id.uuidString)"
        
        guard let data = UserDefaults.standard.data(forKey: key),
              let messages = try? JSONDecoder().decode([Message].self, from: data) else {
            print("🧹 No messages to clean up for \(chat.name)")
            return
        }
        
        print("🧹 Cleaning up \(messages.count) messages for \(chat.name)")
        
        // Sort by timestamp to keep the earliest version of duplicates
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        var uniqueMessages: [Message] = []
        
        for message in sortedMessages {
            let isDuplicate = uniqueMessages.contains { existing in
                // Check for exact ID match
                if existing.id == message.id {
                    print("🗑️ Removing duplicate by ID: \(message.id.uuidString.prefix(8))")
                    return true
                }
                
                //   ENHANCED: Check for content duplicates (same content + timestamp, ignore ID)
                let sameContent = existing.realText == message.realText &&
                                 existing.coverText == message.coverText
                let sameTimestamp = existing.timestamp == message.timestamp
                let sameSender = existing.isSentByCurrentUser == message.isSentByCurrentUser
                
                if sameContent && sameTimestamp && sameSender {
                    print("🗑️ Removing content duplicate:")
                    print("   Keeping: ID=\(existing.id.uuidString.prefix(8)), content=\(existing.displayText(showRealMessage: false).prefix(20))...")
                    print("   Removing: ID=\(message.id.uuidString.prefix(8)), content=\(message.displayText(showRealMessage: false).prefix(20))...")
                    return true
                }
                
                return false
            }
            
            if !isDuplicate {
                uniqueMessages.append(message)
            }
        }
        
        print("🧹 Cleaned up: \(messages.count) -> \(uniqueMessages.count) messages")
        
        // Save the cleaned messages back to UserDefaults
        if let encoded = try? JSONEncoder().encode(uniqueMessages) {
            UserDefaults.standard.set(encoded, forKey: key)
            print("  Saved cleaned messages to UserDefaults")
        }
        
        //   FORCE RESET: Clear messageStore to ensure clean reload
        messageStore.messagesPerChat[chat.id] = []
        print("🧹 Reset messageStore for clean reload")
    }
    
    func decodeBitstream(bits: [Int], completion: @escaping (String?) -> Void) {
        
        guard let url = URL(string: "\(API.baseURL)/decode_cover_chunks") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "bit_sequence": bits,
            "compression_method": "utf8"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let decoded = json["decoded_text"] as? String
            else {
                print("❌ Failed to decode bitstream: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }

            completion(decoded)
        }.resume()
    }
        
    func updateChatContent(realText: String?, coverText: String?, imageData: Data? = nil) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            //   FIX: Create ISO8601 timestamp and then format it for display
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = isoFormatter.string(from: Date())
            
            // Create a temporary message to get formatted timestamp
            let tempMessage = Message(
                realText: realText,
                coverText: coverText,
                isSentByCurrentUser: true,
                timestamp: timestamp,
                imageData: imageData
            )
            
            //   NEW: Handle image messages properly in preview
            if imageData != nil {
                // For image messages, show image placeholder
                chats[index].realMessage = realText?.isEmpty == false ? realText! : "📸 Image"
                chats[index].coverMessage = "📸 Image"
            } else {
                // For text messages, set both real and cover text
                let fallback = "New message"
                
                if let realText = realText, !realText.isEmpty {
                    chats[index].realMessage = realText
                } else {
                    chats[index].realMessage = fallback
                }
                
                if let coverText = coverText, !coverText.isEmpty {
                    chats[index].coverMessage = coverText
                } else {
                    chats[index].coverMessage = fallback
                }
            }
            
            //   FIX: Use formatted timestamp
            chats[index].time = tempMessage.formattedTimestamp()
        }
    }
        
    func loadMessages() {
        messageStore.load(for: chat)
    }
    
    func markChatAsRead() {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            let previousCount = chats[index].unreadCount
            chats[index].unreadCount = 0
            print("  ChatView: Marked chat '\(chat.name)' as read (was: \(previousCount), now: 0)")
        }
    }
}

// MARK: - Contact Management Integration for ChatView

struct ContactDetailViewForChat: View {
    let chat: Chat
    @Binding var chats: [Chat]
    @State private var showingEditSheet = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var messageStore: ChatMessagesStore
    
    // Convert Chat to Contact for the management system
    private var contact: Contact {
        Contact(
            name: chat.name,
            phoneNumber: chat.phoneNumber,
            email: chat.email
        )
    }
    
    var availablePaths: [String] {
        getAvailablePathsForContact(contact)
    }
    
    var savedPaths: [String] {
        getSavedPathsForContact(contact)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(String(chat.name.prefix(1).uppercased()))
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        
                        Text(chat.name)
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .padding(.top)
                    
                    // Contact Information
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Contact Information")
                        
                        VStack(spacing: 12) {
                            if let email = chat.email {
                                ContactInfoRow(
                                    icon: "envelope.fill",
                                    title: "Email",
                                    value: email,
                                    color: .blue
                                )
                            }
                            
                            if let phone = chat.phoneNumber {
                                ContactInfoRow(
                                    icon: "phone.fill",
                                    title: "Phone",
                                    value: phone,
                                    color: .green
                                )
                            }
                            
                            if chat.email == nil && chat.phoneNumber == nil {
                                VStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.questionmark")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    
                                    Text("No contact information available")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Add phone or email to enable more delivery paths")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    
                    // Delivery Paths Configuration
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Delivery Paths Configuration")
                        
                        if !savedPaths.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Currently Active Paths")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                }
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    ForEach(savedPaths, id: \.self) { path in
                                        ActivePathCard(path: path, contact: contact)
                                    }
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: savedPaths.isEmpty ? "info.circle" : "plus.circle")
                                    .foregroundColor(.blue)
                                Text(savedPaths.isEmpty ? "Available Paths" : "Other Available Paths")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                let pathsToShow = savedPaths.isEmpty ? availablePaths : availablePaths.filter { !savedPaths.contains($0) }
                                ForEach(pathsToShow, id: \.self) { path in
                                    PathCard(path: path, contact: contact)
                                }
                            }
                        }
                    }
                    
                    // Chat-specific stats
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Chat Statistics")
                        
                        HStack(spacing: 20) {
                            StatCard(
                                icon: "bubble.left.and.bubble.right",
                                title: "Messages",
                                value: "\(getMessageCount())",
                                color: .blue
                            )
                            
                            StatCard(
                                icon: "star.fill",
                                title: "Favorite",
                                value: chat.isFavorite ? "Yes" : "No",
                                color: chat.isFavorite ? .yellow : .gray
                            )
                        }
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            showingEditSheet = true
                        }) {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Edit Contact")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            toggleFavorite()
                        }) {
                            HStack {
                                Image(systemName: chat.isFavorite ? "star.slash" : "star.fill")
                                Text(chat.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .foregroundColor(.orange)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationTitle("Contact Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ModifiedAddContactView(existingContact: contact) { updatedContact in
                // Update the chat with new contact information
                updateChatWithContact(updatedContact)
            }
        }
    }
    
    private func getAvailablePathsForContact(_ contact: Contact) -> [String] {
        var paths: [String] = []
        
        if contact.phoneNumber != nil {
            paths.append("SMS")
        }
        if contact.email != nil {
            paths.append("Email")
        }
        
        // REMOVED: paths.append("WindTexter")
        return paths
    }
    
    private func getSavedPathsForContact(_ contact: Contact) -> [String] {
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        return (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    
    private func getMessageCount() -> Int {
        let messages = messageStore.messagesPerChat[chat.id] ?? []
        return messages.count
    }
    
    private func toggleFavorite() {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].isFavorite.toggle()
        }
    }
    
    private func updateChatWithContact(_ updatedContact: Contact) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].phoneNumber = updatedContact.phoneNumber
            chats[index].email = updatedContact.email
            // Note: Name changes might require more complex handling
            // depending on how you want to manage chat identity
        }
    }
}

// Supporting view for chat statistics
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct MessageBubble: View {
    let message: Message
    let showRealMessage: Bool

    //   Add the debug init here
    init(message: Message, showRealMessage: Bool) {
        self.message = message
        self.showRealMessage = showRealMessage
        
        // Debug print
        print("🔍 MessageBubble for message \(message.id.uuidString.prefix(8)):")
        print("   Has imageData: \(message.imageData != nil)")
        if let imageData = message.imageData {
            print("   Image size: \(imageData.count) bytes")
            print("   Can create UIImage: \(UIImage(data: imageData) != nil)")
        }
        print("   realText: '\(message.realText ?? "nil")'")
        print("   coverText: '\(message.coverText ?? "nil")'")
        print("   showRealMessage: \(showRealMessage)")
    }

    var body: some View {
        let text = message.displayText(showRealMessage: showRealMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        
        //   Move debug prints to computed properties that execute before the view builds
        let _ = debugPrint("🎨 MessageBubble rendering - text: '\(text)', hasImage: \(message.imageData != nil)")

        return Group {
            if let imageData = message.imageData,
               let uiImage = UIImage(data: imageData) {
                let _ = debugPrint("  Rendering image bubble")
                VStack(alignment: .leading, spacing: 5) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 250)
                        .cornerRadius(12)

                    //   FIX: Show text only if it exists and is meaningful
                    if !text.isEmpty && text != "📸 Image" && (showRealMessage || !isBitstream(text)) {
                        let _ = debugPrint("📝 Also showing text: '\(text)'")
                        Text(text)
                            .padding(8)
                            .background(message.isSentByCurrentUser ? Color.blue : Color.gray.opacity(0.45))
                            .foregroundColor(message.isSentByCurrentUser ? .white : .primary)
                            .cornerRadius(12)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    } else {
                        let _ = debugPrint("🚫 Not showing text - isEmpty: \(text.isEmpty), isImagePlaceholder: \(text == "📸 Image"), showReal: \(showRealMessage), isBitstream: \(isBitstream(text))")
                    }
                }
            } else {
                let _ = debugPrint("❌ Not rendering image - hasImageData: \(message.imageData != nil), canCreateUIImage: \(message.imageData != nil ? UIImage(data: message.imageData!) != nil : false)")
                //   FIX: Handle empty text messages better
                if !text.isEmpty {
                    let _ = debugPrint("📝 Rendering text-only bubble: '\(text)'")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text.isEmpty ? "[Empty Message]" : text)
                            .padding(12)
                            .background(message.isSentByCurrentUser ? Color.blue : Color.gray.opacity(0.45))
                            .foregroundColor(message.isSentByCurrentUser ? .white : .primary)
                            .cornerRadius(16)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    let _ = debugPrint("🚫 Not rendering anything - no text and no valid image")
                    EmptyView()
                }
            }
        }
    }
    
    //   Helper function for debug printing
    private func debugPrint(_ message: String) -> Void {
        print(message)
        return ()
    }
    
    private func isBitstream(_ text: String) -> Bool {
        // Check if the text consists only of 0s and 1s (with possible spaces)
        let cleanedText = text.replacingOccurrences(of: " ", with: "")
        return !cleanedText.isEmpty && cleanedText.allSatisfy { $0 == "0" || $0 == "1" }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return self.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

extension Message {
    var contentHash: String {
        let combined = """
        \(realText ?? "")
        \(coverText ?? "")
        \(timestamp)
        \(isSentByCurrentUser)
        \(senderID ?? "")
        \(deliveryPath ?? "")
        \(imageData?.count ?? 0)
        """
        return combined.hash.description
    }
}
