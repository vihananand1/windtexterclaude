import Foundation

/// Provides static functions to send SMS and Email via backend API endpoints.
struct DeliveryManager {
    

    /// Sends an SMS message using the backend API. Calls completion with success/failure.
    static func sendSMS(to: String, message: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/send_sms") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["to": to, "message": message]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "sent" {
                completion(true)
            } else {
                print("SMS send error:", error?.localizedDescription ?? "Unknown")
                completion(false)
            }
        }.resume()
    }

    /// Sends an email using the backend API. Always sets delivery_path to 'send_email'.
    static func sendEmail(to: String, subject: String = "WindTexter", message: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/send_email") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Explicitly set the "delivery_path" to snake_case
        let body = [
            "to": to,
            "subject": subject,
            "message": message,
            "delivery_path": "send_email" // Always use snake_case
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "sent" {
                completion(true)
            } else {
                print("Email send error:", error?.localizedDescription ?? "Unknown")
                completion(false)
            }
        }.resume()
    }
}

extension DeliveryManager {
    static func sendEmailWithImage(to email: String, message: String, imageData: Data?, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/send_email_with_image") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: Any] = [
            "to": email,
            "message": message,
            "subject": "WindTexter"
        ]
        
        // Add image data as base64 if present
        if let imageData = imageData {
            let imageBase64 = imageData.base64EncodedString()
            payload["image_data"] = imageBase64
            payload["image_filename"] = "image.jpg"
            print("📧 Sending email with image (\(imageData.count) bytes)")
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to send email: \(error.localizedDescription)")
                    completion(false)
                } else if let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 {
                    print("Email with image sent successfully")
                    completion(true)
                } else {
                    print("Email sending failed with status code")
                    completion(false)
                }
            }
        }.resume()
    }
}
