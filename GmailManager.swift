import Foundation
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

/// Manages Gmail integration: fetching, decoding, and storing messages from Gmail.
class GmailManager {
    /// Fetches all Gmail messages for a chat, decodes them, and stores new messages locally.
    static func fetchAndStoreMessages(for chat: Chat) {
        guard let email = chat.email,
              !email.isEmpty,
              let accessToken = UserDefaults.standard.string(forKey: "gmailAccessToken") else {
            return
        }

        print("Checking messages for chat: \(chat.name) (\(email))")

        GmailService.fetchEmailIDs(accessToken: accessToken) { ids in
            print("Found \(ids.count) email IDs")

            for id in ids {

                GmailService.fetchEmailBody(id: id, token: accessToken) { body, timestampString, sender in
                    guard let body = body, !body.isEmpty else {
                        return
                    }

                    // Accept only messages from windtexter@gmail.com and not sent by this user
                    guard let sender = sender?.lowercased(),
                          sender.contains("windtexter@gmail.com"),
                          !sender.contains(chat.email?.lowercased() ?? "") else {
                        return
                    }


                    let key = "savedMessages-\(chat.id.uuidString)"
                    var messages: [Message] = []

                    if let data = UserDefaults.standard.data(forKey: key),
                       let decoded = try? JSONDecoder().decode([Message].self, from: data) {
                        messages = decoded

                        if messages.contains(where: { $0.coverText == body || $0.realText == body }) {
                            return
                        }
                    }

                    decodeCoverChunks([body]) { decodedText in
                        let realText = decodedText ?? body

                        let timestamp = timestampString ?? ISO8601DateFormatter().string(from: Date())

                        let newMessage = Message(
                            realText: realText,
                            coverText: body,
                            isSentByCurrentUser: false,
                            timestamp: timestamp,
                            deliveryPath: "email",
                        )

                        messages.append(newMessage)

                        if let encoded = try? JSONEncoder().encode(messages) {
                            UserDefaults.standard.set(encoded, forKey: key)
                        }
                    }
                }
            }
        }
    }

    /// Calls backend API to decode cover text chunks to real message text.
    static func decodeCoverChunks(_ covers: [String], completion: @escaping (String?) -> Void) {
        guard let bitString = covers.first else {
            completion(nil)
            return
        }

        // convert bitstring (e.g., "01001000...") to [Int]
        let bits: [Int] = bitString.compactMap { char in
            if char == "0" { return 0 }
            else if char == "1" { return 1 }
            else { return nil }  // skip anything unexpected
        }

        guard !bits.isEmpty else {
            print("Empty or invalid bit sequence.")
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "bit_sequence": bits,
            "compression_method": "utf8" // Match backend expectation
        ]

        guard let url = URL(string: "\(API.baseURL)/decode_cover_chunks") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let decoded = json["decoded_text"] as? String {
                completion(decoded)
            } else {
                print("❌ Failed to parse decoded text from response")
                completion(nil)
            }
        }.resume()
    }
}
