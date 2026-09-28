import SwiftUI
import UIKit

// MARK: - Native UIKit UITextField for 100% reliable touch & typing on iOS 18
struct NativeKeyInputField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onCommit: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField(frame: .zero)
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(white: 0.45, alpha: 1.0)]
        )
        tf.text = text
        tf.textColor = .white
        tf.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.returnKeyType = .done
        tf.tintColor = UIColor(red: 0/255, green: 206/255, blue: 232/255, alpha: 1.0)
        tf.delegate = context.coordinator
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onCommit: (() -> Void)?

        init(text: Binding<String>, onCommit: (() -> Void)?) {
            self._text = text
            self.onCommit = onCommit
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.text = textField.text ?? ""
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            onCommit?()
            return true
        }
    }
}

struct AuthKeyView: View {
    @StateObject private var authService = AuthKeyService.shared
    @State private var inputKey: String = ""
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    dismissKeyboard()
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                // Centered App Icon
                ZStack {
                    if let uiImage = UIImage(named: "nta_bear_avatar") ?? UIImage(named: "AppIcon60x60") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image("nta_bear_avatar")
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
                
                // Title
                Text("Authentication Required")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                // Subtitle
                Text("Nhập mã key bản quyền để mở khóa app.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                
                // Input TextField Box with Paste & Clear Buttons
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.45))
                    
                    NativeKeyInputField(
                        placeholder: "Nhập mã key tại đây...",
                        text: $inputKey,
                        onCommit: {
                            dismissKeyboard()
                            authService.verifyKey(inputKey)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if !inputKey.isEmpty {
                        Button {
                            inputKey = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(white: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        if let paste = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !paste.isEmpty {
                            inputKey = paste
                            dismissKeyboard()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Dán")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0/255, green: 206/255, blue: 232/255))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0/255, green: 206/255, blue: 232/255).opacity(0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 16/255, green: 16/255, blue: 18/255))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                
                // Log In Button
                Button {
                    dismissKeyboard()
                    authService.verifyKey(inputKey)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0/255, green: 206/255, blue: 232/255))
                            .frame(height: 50)
                        
                        if authService.isChecking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Log In")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(authService.isChecking)
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Footer / Error Text
                Text(authService.errorMessage ?? "Vui lòng nhập mã bản quyền để sử dụng các tính năng.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 235/255, green: 65/255, blue: 65/255))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)
                
                Spacer()
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !authService.savedKey.isEmpty {
                inputKey = authService.savedKey
            }
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
