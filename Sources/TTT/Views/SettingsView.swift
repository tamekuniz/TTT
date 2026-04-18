import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var accessibility: AccessibilityManager
    
    @State private var newWord = ""
    @State private var newReading = ""
    
    var body: some View {
        TabView {
            // タブ1: 一般設定
            generalSettings
                .tabItem {
                    Label("一般", systemImage: "gearshape")
                }
            
            // タブ2: スマート辞書
            dictionarySettings
                .tabItem {
                    Label("スマート辞書", systemImage: "text.book.closed")
                }
        }
        .padding()
        .frame(width: 500, height: 450)
    }
    
    // 一般設定のビュー
    private var generalSettings: some View {
        Form {
            Section("AI 設定") {
                SecureField("Groq API キー", text: $settings.groqApiKey)
                    .textFieldStyle(.roundedBorder)
                
                TextEditor(text: $settings.systemPrompt)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                
                Text("AI への整形指示（プロンプト）")
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
    }
    
    // 辞書設定のビュー
    private var dictionarySettings: some View {
        VStack {
            Text("よく使う専門用語や人名を登録すると、聞き取り精度が向上し、自動的に置換されます。コンテキスト（文脈）を汚さず高速に動作します。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            
            List {
                ForEach(settings.dictionary) { entry in
                    HStack {
                        Text(entry.word)
                            .fontWeight(.bold)
                        Spacer()
                        Text(entry.reading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: settings.removeEntry)
            }
            .listStyle(.bordered)
            
            HStack {
                TextField("単語 (例: TTT)", text: $newWord)
                TextField("よみ (例: てぃーてぃーてぃー)", text: $newReading)
                Button("追加") {
                    if !newWord.isEmpty {
                        settings.addEntry(word: newWord, reading: newReading)
                        newWord = ""
                        newReading = ""
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
    }
}
