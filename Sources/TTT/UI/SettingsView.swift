import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var accessibility: AccessibilityManager
    
    var body: some View {
        Form {
            Section("AI 設定") {
                SecureField("Groq API キー", text: $settings.groqApiKey)
                    .textFieldStyle(.roundedBorder)
                    .help("Groq API キーをセットしてください。")
                
                TextEditor(text: $settings.systemPrompt)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    .padding(.top, 4)
                
                Text("AI への整形指示（プロンプト）を自由に編集できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("システム権限") {
                HStack {
                    Image(systemName: accessibility.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibility.hasPermission ? .green : .orange)
                    Text("アクセシビリティ権限")
                    Spacer()
                    Button(accessibility.hasPermission ? "許可済み" : "設定を開く") {
                        if !accessibility.hasPermission {
                            accessibility.checkPermission()
                        }
                    }
                    .disabled(accessibility.hasPermission)
                }
            }
        }
        .padding()
        .frame(width: 450)
    }
}
