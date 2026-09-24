import SwiftUI

struct AuthKeyView: View {
    @StateObject private var authService = AuthKeyService.shared
    @State private var inputKey: String = ""
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
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
                Text("Enter a valid key.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                
                // Input TextField
                HStack {
                    TextField("", text: $inputKey)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .tint(Color(red: 0/255, green: 206/255, blue: 232/255))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isFieldFocused)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 16/255, green: 16/255, blue: 18/255))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 28)
                
                // Log In Button
                Button {
                    isFieldFocused = false
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
                .padding(.horizontal, 28)
                .padding(.top, 16)
                
                // Footer / Error Text
                Text(authService.errorMessage ?? "Enter your license key to unlock the app.")
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
            // Auto focus if no key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if inputKey.isEmpty {
                    isFieldFocused = true
                }
            }
        }
    }
}
