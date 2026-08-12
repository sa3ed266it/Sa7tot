import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var rawNonce: String?
    @State private var didAppear = false
    @State private var taglineIndex = 0
    @State private var revealedWordCount = 0

    private let taglineKeys = [
        "auth.login.tagline",
        "auth.login.tagline.control",
        "auth.login.tagline.clarity",
        "auth.login.tagline.movements",
        "auth.login.tagline.focus",
        "auth.login.tagline.yours"
    ]

    let error: SupabaseAuthPresentationError?
    let isAuthenticating: Bool

    init(
        error: SupabaseAuthPresentationError? = nil,
        isAuthenticating: Bool = false
    ) {
        self.error = error
        self.isAuthenticating = isAuthenticating
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: max(20, proxy.size.height * 0.06))

                    Image("Sa7totLogo")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 124, height: 83)
                        .accessibilityHidden(true)

                    Text("Sa7tot")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.PrimaryText)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 4)

                    HStack(spacing: 4) {
                        ForEach(Array(currentTaglineWords.enumerated()), id: \.offset) { index, word in
                            Text(word)
                                .font(.body)
                                .foregroundStyle(Color.SubtitleText)
                                .opacity(index < revealedWordCount ? 1 : 0)
                                .blur(
                                    radius: accessibilityReduceMotion || index < revealedWordCount ? 0 : 6
                                )
                                .offset(
                                    y: accessibilityReduceMotion || index < revealedWordCount ? 0 : 3
                                )
                                .animation(taglineWordAnimation, value: revealedWordCount)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .padding(.top, 6)

                    Spacer(minLength: max(28, proxy.size.height * 0.08))

                    if let error {
                        Text(error.message)
                            .font(.callout)
                            .foregroundStyle(Color.SubtitleText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 14)
                    }

                    if isAuthenticating {
                        Sa7totLoader(size: .compact)
                            .frame(height: 50)
                            .accessibilityLabel(AppLocalization.key("auth.login.signIn"))
                            .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
                    } else if error != .configuration {
                        SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: complete)
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 50)
                            .clipShape(Capsule())
                            .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
                    }
                }
                .frame(minHeight: max(proxy.size.height, 560))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .offset(y: -24)
            }
        }
        .background(Color.AppPageBackground.ignoresSafeArea())
        .opacity(didAppear || accessibilityReduceMotion ? 1 : 0)
        .offset(y: didAppear || accessibilityReduceMotion ? 0 : 8)
        .scaleEffect(didAppear || accessibilityReduceMotion ? 1 : 0.985)
        .animation(.easeOut(duration: 0.32), value: didAppear)
        .onAppear {
            guard !accessibilityReduceMotion else {
                didAppear = true
                return
            }
            didAppear = true
        }
        .task {
            guard taglineKeys.count > 1 else { return }

            while !Task.isCancelled {
                let wordCount = currentTaglineWords.count
                guard wordCount > 0 else { return }

                for wordIndex in 1...wordCount {
                    if wordIndex > 1 {
                        try? await Task.sleep(nanoseconds: 360_000_000)
                        guard !Task.isCancelled else { return }
                    }

                    withAnimation(taglineWordAnimation) {
                        revealedWordCount = wordIndex
                    }
                }

                try? await Task.sleep(nanoseconds: 1_900_000_000)
                guard !Task.isCancelled else { return }

                withAnimation(taglineExitAnimation) {
                    revealedWordCount = 0
                }

                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }

                taglineIndex = (taglineIndex + 1) % taglineKeys.count
            }
        }
    }

    private var currentTaglineWords: [String] {
        AppLocalization.string(taglineKeys[taglineIndex])
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private var taglineWordAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.16)
            : .easeOut(duration: 0.28)
    }

    private var taglineExitAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.16)
            : .easeInOut(duration: 0.28)
    }

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try AppleNonce.random()
            rawNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleNonce.sha256(nonce)
        } catch {
            rawNonce = nil
        }
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        guard let rawNonce else { return }

        Task {
            switch result {
            case let .success(authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    authService.handle(error: .invalidAppleCredential)
                    return
                }
                do {
                    let credential = try AppleAuthorizationCredentialBuilder.build(
                        from: credential,
                        rawNonce: rawNonce
                    )
                    await authService.signIn(with: credential)
                } catch let error as SupabaseAuthError {
                    authService.handle(error: error)
                } catch {
                    authService.handle(error: .invalidAppleCredential)
                }
            case let .failure(error as ASAuthorizationError) where error.code == .canceled:
                authService.handle(error: .userCancelled)
            case .failure:
                authService.handle(error: .invalidAppleCredential)
            }
        }
    }
}
