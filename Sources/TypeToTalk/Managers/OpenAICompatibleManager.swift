import Foundation

@MainActor
class OpenAICompatibleManager: ObservableObject {
    func processText(
        _ text: String,
        endpoint: String,
        model: String,
        apiKey: String,
        prompt: String
    ) async -> String {
        guard !apiKey.isEmpty, !model.isEmpty else { return text }
        guard let url = URL(string: endpoint) else { return text }
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.5
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return text
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Formatter API error: \(error)")
        }
        
        return text
    }
}
