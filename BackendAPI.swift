import Foundation
import UIKit

/// Provides functions for communicating with the backend API (fetching messages, etc.).
class BackendAPI {
    /// Fetches messages for a given delivery path from the backend.
    /// Normalizes the path and sends a POST request to /fetch_messages.
    static func fetchMessages(for path: String, completion: @escaping ([Message]) -> Void) {
        let normalizedPath = path.replacingOccurrences(of: "send_", with: "").lowercased()
        guard let url = URL(string: "\(API.baseURL)/fetch_messages") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let currentDeviceID = DeviceIDManager.shared.deviceID
        let body: [String: Any] = [
            "delivery_path": normalizedPath,
            "device_id": currentDeviceID
        ]
        
        print("🔍 FETCH REQUEST DEBUG:")
        print("   delivery_path: '\(normalizedPath)'")
        print("   device_id: '\(currentDeviceID)'")
        print("   Full body: \(body)")
        print("---")
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                if let rawMessages = json?["messages"] as? [[String: Any]] {
                    
                    //     ENHANCED: Parse messages manually to handle image data
                    let currentUserID = DeviceIDManager.shared.deviceID
                    let messages = rawMessages.compactMap { messageDict -> Message? in
                        return parseBackendMessage(messageDict, currentUserID: currentUserID)
                    }
                    
                    print("🔄 Parsed \(rawMessages.count) raw messages to \(messages.count) Message objects")
                    
                    DispatchQueue.main.async {
                        completion(messages)
                    }
                } else {
                    print("❌ No 'messages' key found in response")
                    DispatchQueue.main.async { completion([]) }
                }
            } catch {
                print("❌ JSON decode error: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    //     NEW: Helper function to parse individual backend messages with image support
    private static func parseBackendMessage(_ messageDict: [String: Any], currentUserID: String) -> Message? {
        guard let idString = messageDict["id"] as? String,
              let uuid = UUID(uuidString: idString),
              let timestamp = messageDict["timestamp"] as? String else {
            print("❌ Missing required fields in backend message")
            return nil
        }
        
        // Parse text fields (handle both camelCase and snake_case)
        let realText = messageDict["realText"] as? String ?? messageDict["real_text"] as? String
        let coverText = messageDict["coverText"] as? String ?? messageDict["cover_text"] as? String
        let rawPath = messageDict["delivery_path"] as? String ?? "email"
        let deliveryPath = normalizeDeliveryPath(rawPath)
        let senderID = messageDict["sender_id"] as? String
        let bitCount = messageDict["bit_count"] as? Int
        let isAutoReply = messageDict["is_auto_reply"] as? Bool ?? false
        
        //     CRITICAL: Parse image data from backend
        var imageData: Data? = nil
        if let imageBase64String = messageDict["imageData"] as? String ?? messageDict["image_data"] as? String,
           !imageBase64String.isEmpty {
            imageData = Data(base64Encoded: imageBase64String)
            if let imageData = imageData {
                print("📸 Parsed image data from backend: \(imageData.count) bytes")
            } else {
                print("⚠️ Failed to decode base64 image data")
            }
        }
        
        // Determine ownership based on sender_id
        let isSentByCurrentUser = (senderID == currentUserID)
        
        print("🔍 PARSING MESSAGE DEBUG:")
        print("   ID: \(idString.prefix(8))")
        print("   realText: '\(realText ?? "nil")'")
        print("   coverText: '\(coverText?.prefix(20) ?? "nil")...'")
        print("   senderID: '\(senderID ?? "nil")'")
        print("   currentUserID: '\(currentUserID)'")
        print("   isSentByCurrentUser: \(isSentByCurrentUser)")
        print("   hasImageData: \(imageData != nil)")
        if let imageData = imageData {
            print("   imageData size: \(imageData.count) bytes")
        }
        print("---")
        
        //     Create Message with all fields including image data
        let message = Message(
            id: uuid,
            realText: realText,
            coverText: coverText,
            isSentByCurrentUser: isSentByCurrentUser,
            timestamp: timestamp,
            imageData: imageData,  //     Include parsed image data
            bitCount: bitCount,
            deliveryPath: deliveryPath,
            isAutoReply: isAutoReply,
            senderID: senderID
        )
        
        return message
    }
    
    private static func normalizeDeliveryPath(_ path: String) -> String {
        switch path.lowercased() {
            case "send_email": return "email"
            case "send_sms": return "sms"
            case "windtexter": return "windtexter"
            default: return path.lowercased()
        }
    }
}
