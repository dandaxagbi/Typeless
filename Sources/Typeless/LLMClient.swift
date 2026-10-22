import Foundation

public final class LLMClient {
    public static let shared = LLMClient()

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }

    public func cleanupTranscript(_ rawText: String, config: AppConfig) async -> String {
        guard let apiKey = ConfigManager.shared.getAPIKey(), !apiKey.isEmpty else {
            // No API key set: requirement specifies "If no key is set, this mode just does a plain paste"
            return rawText
        }

        // Determine endpoint and auth style
        if ConfigManager.shared.envVars["ANTHROPIC_API_KEY"] != nil && ConfigManager.shared.envVars["OPENAI_API_KEY"] == nil {
            if let result = await cleanupWithAnthropic(rawText: rawText, apiKey: apiKey, model: config.llmModel) {
                return result
            }
        } else {
            if let result = await cleanupWithOpenAICompatible(rawText: rawText, apiKey: apiKey, config: config) {
                return result
            }
        }

        // Fallback to raw text if LLM call fails
        return rawText
    }

    private func cleanupWithOpenAICompatible(rawText: String, apiKey: String, config: AppConfig) async -> String? {
        var baseURL = config.llmBaseURL
        var model = config.llmModel

        if ConfigManager.shared.envVars["OPENROUTER_API_KEY"] != nil {
            baseURL = "https://openrouter.ai/api/v1"
            if model == "gpt-4o-mini" { model = "openai/gpt-4o-mini" }
        } else if ConfigManager.shared.envVars["GROQ_API_KEY"] != nil {
            baseURL = "https://api.groq.com/openai/v1"
            if model == "gpt-4o-mini" { model = "llama-3.3-70b-versatile" }
        }

        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemInstruction = "You are an expert transcription editor. Clean up the following speech dictation:\n1. Fix punctuation and sentence capitalization.\n2. Remove stuttering, false starts, and filler words (e.g. um, uh, like, you know, ah, eh, o sea, este).\n3. Retain the exact original meaning, tone, and spoken language.\n4. Output ONLY the polished text. Do not wrap in quotes. Do not add explanations, preamble, or markdown formatting."

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": rawText]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  var content = message["content"] as? String else {
                return nil
            }

            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if (content.hasPrefix("\"") && content.hasSuffix("\"")) || (content.hasPrefix("“") && content.hasSuffix("”")) {
                content = String(content.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            }
            return content.isEmpty ? rawText : content
        } catch {
            return nil
        }
    }

    private func cleanupWithAnthropic(rawText: String, apiKey: String, model: String) async -> String? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let anthropicModel = model.contains("claude") ? model : "claude-3-5-haiku-latest"
        let systemPrompt = "You are an expert transcription editor. Clean up the following speech dictation:\n1. Fix punctuation and sentence capitalization.\n2. Remove stuttering, repetitions, and filler words (e.g. um, uh, like, you know, ah, eh, o sea).\n3. Retain the exact original meaning and language.\n4. Output ONLY the polished text without quotes or explanations."

        let body: [String: Any] = [
            "model": anthropicModel,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": rawText]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let contentArray = json["content"] as? [[String: Any]],
                  let firstBlock = contentArray.first,
                  var text = firstBlock["text"] as? String else {
                return nil
            }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("“") && text.hasSuffix("”")) {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            }
            return text.isEmpty ? rawText : text
        } catch {
            return nil
        }
    }
}
