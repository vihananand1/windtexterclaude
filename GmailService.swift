import Foundation
import SwiftUI

/// Provides static functions to fetch message IDs and bodies from the Gmail API.
class GmailService {
    /// Fetches the IDs of recent inbox messages using the Gmail API.
    static func fetchEmailIDs(accessToken: String, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=10&q=is:inbox") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion([])
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
            }

            guard let data = data else {
                completion([])
                return
            }

            if let rawJSON = String(data: data, encoding: .utf8) {
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["messages"] as? [[String: Any]] else {
                completion([])
                return
            }

            let ids = messages.compactMap { $0["id"] as? String }
            completion(ids)
        }.resume()
    }

    /// Fetches the body, timestamp, and sender of a Gmail message by ID.
    static func fetchEmailBody(id: String, token: String, completion: @escaping (String?, String?, String?) -> Void) {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data else {
                completion(nil, nil, nil)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else {
                completion(nil, nil, nil)
                return
            }

            // Extract timestamp
            var timestampString: String?
            if let internalDateStr = json["internalDate"] as? String,
               let ms = Double(internalDateStr) {
                let date = Date(timeIntervalSince1970: ms / 1000)
                timestampString = ISO8601DateFormatter().string(from: date)
            }

            // Extract sender email
            var senderAddress: String?
            if let headers = payload["headers"] as? [[String: Any]] {
                for header in headers {
                    if let name = header["name"] as? String, name == "From",
                       let value = header["value"] as? String {
                        senderAddress = value
                        break
                    }
                }
            }

            // Try to decode from parts
            if let parts = payload["parts"] as? [[String: Any]] {
                for part in parts {
                    if let mimeType = part["mimeType"] as? String,
                       mimeType == "text/plain",
                       let body = part["body"] as? [String: Any],
                       let data64 = body["data"] as? String {
                        let clean = data64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                        if let decodedData = Data(base64Encoded: clean),
                           let decodedString = String(data: decodedData, encoding: .utf8) {
                            completion(decodedString, timestampString, senderAddress)
                            return
                        }
                    }
                }
            }

            // Try fallback body
            if let body = payload["body"] as? [String: Any],
               let data64 = body["data"] as? String {
                let clean = data64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                if let decodedData = Data(base64Encoded: clean),
                   let decodedString = String(data: decodedData, encoding: .utf8) {
                    completion(decodedString, timestampString, senderAddress)
                    return
                }
            }

            completion(nil, timestampString, senderAddress)
        }.resume()
    }
}
