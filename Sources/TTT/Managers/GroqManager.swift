import Foundation

@MainActor
class GroqManager: ObservableObject {
    private let apiEndpoint = "https://api.groq.com/openai/v1/chat/completions"
    
    func processText(_ text: String, apiKey: String, prompt: String) async -> String {
        guard !apiKey.isEmpty else { return text }
        
        let requestBody: [String: Any] = [
            "model": "llama3-8b-8192",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.5
        ]
        
        guard let url = URL(string: apiEndpoint),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else { return text }
        
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
            print("Groq API error: \(error)")
        }
        
        return text
    }
}
