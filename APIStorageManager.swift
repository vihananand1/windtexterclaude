// Handles encoding and sending of message data to the backend for storage by delivery path.

import Foundation

/// Codable struct representing the payload sent to the backend for message storage.
struct StoreMessageRequest: Codable {
    let id: String
    let chat_id: String
    let real_text: String?
    let cover_text: String?
    let bitCount: Int?
    let isAutoReply: Bool
    let delivery_path: String
    let timestamp: String
    let sender_id: String?     //     Add this line
}
    


/// Singleton for sending messages to the backend API for persistent storage.
class APIStorageManager {
    static let shared = APIStorageManager()
    
    private let backendURL = "\(API.baseURL)/store_message"
    
    /// Sends a message to the backend API for storage. Encodes all message fields and sends as JSON.
    func storeMessage(
        id: UUID,
        senderID: String? = nil,
        chatID: UUID,
        realText: String?,
        coverText: String?,
        bitCount: Int?,
        isAutoReply: Bool,
        deliveryPath: String,
        timestamp: Date
    ) {
        let formatter = ISO8601DateFormatter()
        let timestampStr = formatter.string(from: timestamp)
        
        // 🔍 Debug print values
        print("📤 Sending to /store_message:")
        print("   realText: \(realText ?? "nil")")
        print("   coverText: \(coverText ?? "nil")")
        print("   chatID: \(chatID)")
        print("   deliveryPath: \(deliveryPath)")
        print("   timestamp: \(timestampStr)")
        
        let payload = StoreMessageRequest(
            id: id.uuidString,
            chat_id: chatID.uuidString,
            real_text: realText,
            cover_text: coverText,
            bitCount: bitCount,
            isAutoReply: isAutoReply,
            delivery_path: deliveryPath,
            timestamp: timestampStr,
            sender_id: senderID
        )
        
        // 🔍 Log the full JSON payload
        if let jsonData = try? JSONEncoder().encode(payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📦 JSON payload:")
            print(jsonString)
        }
        
        guard let url = URL(string: backendURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data, let raw = String(data: data, encoding: .utf8) {
                print("📬 Response: \(raw)")
            }
            if let error = error {
                print("❌ Error: \(error.localizedDescription)")
            } else {
                print("    Message stored successfully")
            }
        }.resume()
    }
}

extension APIStorageManager {
    func storeMessageWithImage(
        id: UUID,
        senderID: String?,
        chatID: UUID,
        realText: String?,
        coverText: String?,
        bitCount: Int?,
        isAutoReply: Bool,
        deliveryPath: String,
        timestamp: Date,
        imageData: Data?
    ) {
        guard let url = URL(string: "\(API.baseURL)/store_message") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: Any] = [
            "id": id.uuidString,
            "sender_id": senderID ?? "",
            "chat_id": chatID.uuidString,
            "real_text": realText ?? "",
            "cover_text": coverText ?? "",
            "bit_count": bitCount ?? 0,           //     Changed from "bitCount"
            "is_auto_reply": isAutoReply,         //     Changed from "isAutoReply"
            "delivery_path": deliveryPath,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        
        //     Include image data if present
        if let imageData = imageData {
            let imageBase64 = imageData.base64EncodedString()
            payload["image_data"] = imageBase64
            print("💾 Storing message with image data (\(imageData.count) bytes)")
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Failed to store message: \(error)")
            } else {
                print("    Message stored successfully")
            }
        }.resume()
    }
}
