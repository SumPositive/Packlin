import SwiftUI

struct PacklinMemoEditor: View {
    let placeholder: LocalizedStringKey?
    @Binding var text: String
    @Binding var isFocused: Bool
    var minHeight: CGFloat = 36
    var maxLength: Int?
    var backgroundColor: Color?
    var cornerRadius: CGFloat = 12

    @FocusState private var editorIsFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text.isEmpty ? " " : text)
                .font(FONT_EDIT)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0)
                .allowsHitTesting(false)

            if text.isEmpty, let placeholder {
                Text(placeholder)
                    .font(FONT_EDIT)
                    .foregroundStyle(Color(.placeholderText))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(FONT_EDIT)
                .focused($editorIsFocused)
                .scrollDisabled(true)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(editorBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            editorIsFocused = isFocused
        }
        .onChange(of: editorIsFocused) { _, newValue in
            isFocused = newValue
            if !newValue {
                normalizeText()
            }
        }
        .onChange(of: isFocused) { _, newValue in
            editorIsFocused = newValue
            if !newValue {
                normalizeText()
            }
        }
        .onChange(of: text) { _, newValue in
            guard let maxLength, maxLength < newValue.count else { return }
            text = String(newValue.prefix(maxLength))
        }
    }

    @ViewBuilder
    private var editorBackground: some View {
        if let backgroundColor {
            backgroundColor
        } else {
            Color.clear
        }
    }

    private func normalizeText() {
        // フォーカスが外れたタイミングで、入力前後の余分な空白と改行を揃える
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized != text {
            text = normalized
        }
    }
}
