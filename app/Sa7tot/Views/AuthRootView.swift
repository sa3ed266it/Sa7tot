import SwiftUI

enum AppBootstrapState: Equatable {
    case resolvingSession
    case loadingRequiredData
    case ready
    case signedOut
    case failed
}

struct AuthRootView: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @EnvironmentObject private var remoteFinancialStore: FinancialRemoteStore
    @EnvironmentObject private var pushTokenCoordinator: PushTokenCoordinator

    @State private var hasResolvedInitialAuth = false
    @State private var isSigningIn = false
    @State private var bootstrapState: AppBootstrapState = .resolvingSession
    @State private var initialSplashCanExit = false
    @State private var hasCompletedInitialSplash = false
    @State private var splashDestinationOpacity = 0.0
    @State private var isDestinationAboveSplash = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                postSplashContent
                    .opacity(splashDestinationOpacity)
                    .zIndex(isDestinationAboveSplash ? 1 : 0)

                if !hasCompletedInitialSplash {
                    BootstrapSplashView(
                        canExit: $initialSplashCanExit,
                        containerSize: proxy.size,
                        onDestinationReveal: revealInitialDestination,
                        onFinished: completeInitialSplash
                    )
                    .zIndex(isDestinationAboveSplash ? 0 : 1)
                }
            }
            .coordinateSpace(name: SplashCoordinateSpace.root)
        }
        .task {
            pushTokenCoordinator.start()
            await restoreAuthSession()
        }
        .onChange(of: authService.state) { state in
            pushTokenCoordinator.reconcile(authState: state)
            switch state {
            case .restoring:
                initialSplashCanExit = false
                if hasResolvedInitialAuth {
                    isSigningIn = true
                } else {
                    bootstrapState = .resolvingSession
                }
            case .signedOut:
                hasResolvedInitialAuth = true
                isSigningIn = false
                bootstrapState = .signedOut
                initialSplashCanExit = true
            case .signedIn:
                hasResolvedInitialAuth = true
                isSigningIn = false
                initialSplashCanExit = true
                beginBootstrap()
            case .error:
                hasResolvedInitialAuth = true
                isSigningIn = false
                bootstrapState = .signedOut
                initialSplashCanExit = true
            }

            switch state {
            case .signedOut, .error:
                remoteFinancialStore.resetRemoteState()
            default:
                break
            }
        }
    }

    private func completeInitialSplash() {
        hasCompletedInitialSplash = true
    }

    private func revealInitialDestination() {
        isDestinationAboveSplash = true
        withAnimation(SplashZoomTiming.destinationFadeAnimation) {
            splashDestinationOpacity = 1
        }
    }

    private func retryBootstrap() {
        guard case .signedIn = authService.state else { return }
        beginBootstrap()
    }

    private func restoreAuthSession() async {
        let race = StartupRace()
        let restoreTask = Task {
            await authService.restoreSession()
            await race.finish(true)
        }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await race.finish(false)
        }

        let didResolve = await race.wait()
        timeoutTask.cancel()
        restoreTask.cancel()
        guard !didResolve, authService.state == .restoring else { return }
        authService.handle(error: .network("Session restoration timed out."))
    }

    @ViewBuilder
    private var postSplashContent: some View {
        switch authService.state {
        case .restoring:
            if isSigningIn {
                LoginView(isAuthenticating: true)
            } else {
                BootstrapSplashView(animate: false)
            }
        case .signedIn:
            GeometryReader { proxy in
                let topSafeAreaOffset = max(
                    proxy.safeAreaInsets.top - proxy.frame(in: .global).minY,
                    0
                )

                ZStack(alignment: .top) {
                    ContentView()
                        .ignoresSafeArea()

                    if bootstrapState == .failed,
                       let error = remoteFinancialStore.bootstrapError,
                       error != .unauthorized,
                       remoteFinancialStore.hasUsableContent {
                        BootstrapInlineErrorBanner(
                            error: error,
                            retry: retryBootstrap
                        )
                        .padding(.top, topSafeAreaOffset + 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2000)
                    }

                    AppToastView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, topSafeAreaOffset + 7)
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                        .zIndex(1000)
                }
            }
        case .signedOut:
            LoginView()
        case let .error(error):
            LoginView(error: error)
        }
    }

    private func beginBootstrap() {
        guard bootstrapState != .loadingRequiredData, bootstrapState != .ready else { return }
        bootstrapState = .loadingRequiredData

        let race = StartupRace()
        let bootstrapTask = Task {
            let didBecomeReady = await remoteFinancialStore.bootstrapIfNeeded()
            await race.finish(didBecomeReady)
        }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            await race.finish(false)
        }

        Task {
            let didBecomeReady = await race.wait()
            timeoutTask.cancel()
            bootstrapTask.cancel()
            guard !Task.isCancelled else { return }
            if remoteFinancialStore.bootstrapError == .unauthorized {
                await authService.signOut()
                return
            }
            bootstrapState = didBecomeReady ? .ready : .failed
        }
    }
}

private enum SplashCoordinateSpace {
    static let root = "sa7tot-splash-root"
}

private struct SplashMarkFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let nextValue = nextValue() {
            value = nextValue
        }
    }
}

private actor StartupRace {
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(_ result: Bool) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private enum SplashZoomTiming {
    static let breathingScale: CGFloat = 1.018
    static let breathingInhaleDuration: UInt64 = 800_000_000
    static let breathingExhaleDuration: UInt64 = 800_000_000
    static let breathingInhaleAnimation = Animation.easeInOut(duration: 0.8)
    static let breathingExhaleAnimation = Animation.easeInOut(duration: 0.8)
    static let minimumBreathingWindow: UInt64 = 900_000_000
    static let breathingSettleAnimation = Animation.easeOut(duration: 0.12)
    static let breathingSettleDuration: UInt64 = 120_000_000
    static let takeoffScale: CGFloat = 1.10
    static let takeoffDuration: UInt64 = 180_000_000
    static let takeoffAnimation = Animation.timingCurve(0.35, 0.0, 0.20, 1.0, duration: 0.18)
    static let mainPushDuration: UInt64 = 560_000_000
    static let mainPushAnimation = Animation.timingCurve(0.35, 0.0, 0.20, 1.0, duration: 0.56)
    static let wordmarkExitAnimation = Animation.easeOut(duration: 0.20)
    static let logoClearedBeat: UInt64 = 80_000_000
    static let destinationFadeDuration: UInt64 = 360_000_000
    static let destinationFadeAnimation = Animation.easeOut(duration: 0.36)
    static let completionCushion: UInt64 = 60_000_000
    static let reduceMotionZoomAnimation = Animation.easeOut(duration: 0.22)
    static let reduceMotionCompletionDelay: UInt64 = 260_000_000
}

private enum SplashZoomFocalPoint {
    // Empty space between the primary S and 7 strokes in Sa7totLogo.
    static let normalized = CGPoint(x: 0.60, y: 0.48)
    static let anchor = UnitPoint(x: normalized.x, y: normalized.y)
}

private struct BootstrapSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var canExit: Bool
    let containerSize: CGSize
    let onDestinationReveal: () -> Void
    let onFinished: () -> Void
    let animate: Bool

    @State private var phase: SplashBrandPhase
    @State private var wordmarkWidth: CGFloat = 0
    @State private var hasCompletedMinimumHold = false
    @State private var exitStarted = false
    @State private var markFrame: CGRect?
    @State private var breathingScale: CGFloat = 1
    @State private var breathingActive = false
    @State private var exitZoomScale: CGFloat = 1
    @State private var exitZoomOffset: CGSize = .zero
    @State private var wordmarkExitOpacity = 1.0

    init(
        canExit: Binding<Bool> = .constant(false),
        containerSize: CGSize = .zero,
        onDestinationReveal: @escaping () -> Void = {},
        animate: Bool = true,
        onFinished: @escaping () -> Void = {}
    ) {
        self._canExit = canExit
        self.containerSize = containerSize
        self.onDestinationReveal = onDestinationReveal
        self.animate = animate
        self.onFinished = onFinished
        _phase = State(initialValue: animate ? .hidden : .complete)
    }

    var body: some View {
        ZStack {
            Color.AppPageBackground
                .ignoresSafeArea()

            SplashBrandLockup(
                phase: phase,
                reduceMotion: reduceMotion,
                reportsMarkFrame: animate,
                wordmarkWidth: $wordmarkWidth,
                breathingScale: breathingScale,
                exitZoomScale: exitZoomScale,
                exitZoomOffset: exitZoomOffset,
                wordmarkExitOpacity: wordmarkExitOpacity
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sa7tot")
        }
        .onPreferenceChange(SplashMarkFramePreferenceKey.self) { frame in
            markFrame = frame
        }
        .task {
            await runAnimation()
        }
        .task(id: breathingActive) {
            await runBreathingIfNeeded()
        }
        .task(id: exitStarted) {
            guard exitStarted else { return }
            await runExitSequence()
        }
        .onChange(of: canExit) { _ in
            attemptExitIfReady()
        }
        .onChange(of: phase) { _ in
            attemptExitIfReady()
        }
    }

    private var appearanceAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.24) : .easeOut(duration: 0.42)
    }

    private var revealAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.22) : .easeInOut(duration: 0.42)
    }

    private func runAnimation() async {
        guard animate else { return }

        for _ in 0..<60 where wordmarkWidth == 0 {
            guard await pause(for: 16_000_000) else { return }
        }

        guard !Task.isCancelled else { return }
        if wordmarkWidth == 0 {
            wordmarkWidth = 120
        }
        withAnimation(appearanceAnimation) {
            phase = .markAppearing
        }

        guard await pause(for: 420_000_000) else { return }
        withAnimation(appearanceAnimation) {
            phase = .markSettled
        }

        guard await pause(for: 160_000_000) else { return }
        withAnimation(revealAnimation) {
            phase = .revealingWordmark
        }

        guard await pause(for: reduceMotion ? 360_000_000 : 760_000_000) else { return }
        withAnimation(revealAnimation) {
            phase = .complete
        }

        breathingActive = !reduceMotion

        guard await pause(for: reduceMotion ? 220_000_000 : SplashZoomTiming.minimumBreathingWindow) else { return }
        hasCompletedMinimumHold = true
        attemptExitIfReady()
    }

    private func runBreathingIfNeeded() async {
        guard breathingActive, !reduceMotion, !exitStarted else { return }

        while !Task.isCancelled {
            withAnimation(SplashZoomTiming.breathingInhaleAnimation) {
                breathingScale = SplashZoomTiming.breathingScale
            }
            guard await pause(for: SplashZoomTiming.breathingInhaleDuration) else { return }

            withAnimation(SplashZoomTiming.breathingExhaleAnimation) {
                breathingScale = 1
            }
            guard await pause(for: SplashZoomTiming.breathingExhaleDuration) else { return }
        }
    }

    private func attemptExitIfReady() {
        guard animate,
              canExit,
              hasCompletedMinimumHold,
              phase == .complete,
              !exitStarted else { return }

        guard let markFrame else { return }

        exitStarted = true
        breathingActive = false
        withAnimation(SplashZoomTiming.breathingSettleAnimation) {
            breathingScale = 1
        }
    }

    private func runExitSequence() async {
        guard let markFrame else { return }

        if reduceMotion {
            withAnimation(SplashZoomTiming.wordmarkExitAnimation) {
                wordmarkExitOpacity = 0
            }
            withAnimation(SplashZoomTiming.reduceMotionZoomAnimation) {
                exitZoomScale = 1.12
                phase = .exiting
            }
            guard await pause(for: SplashZoomTiming.reduceMotionCompletionDelay) else { return }
            onDestinationReveal()
            guard await pause(for: SplashZoomTiming.destinationFadeDuration + SplashZoomTiming.completionCushion) else {
                return
            }
            onFinished()
            return
        }

        guard await pause(for: SplashZoomTiming.breathingSettleDuration) else { return }
        withAnimation(SplashZoomTiming.wordmarkExitAnimation) {
            wordmarkExitOpacity = 0
        }
        withAnimation(SplashZoomTiming.takeoffAnimation) {
            exitZoomScale = SplashZoomTiming.takeoffScale
            exitZoomOffset = focalOffset(for: markFrame)
            phase = .exiting
        }

        guard await pause(for: SplashZoomTiming.takeoffDuration) else { return }
        withAnimation(SplashZoomTiming.mainPushAnimation) {
            exitZoomScale = zoomScale(for: markFrame)
        }

        guard await pause(for: SplashZoomTiming.mainPushDuration) else { return }
        phase = .logoFullyCleared
        guard await pause(for: SplashZoomTiming.logoClearedBeat) else { return }
        onDestinationReveal()

        guard await pause(for: SplashZoomTiming.destinationFadeDuration + SplashZoomTiming.completionCushion) else {
            return
        }
        onFinished()
    }

    private func zoomScale(for frame: CGRect) -> CGFloat {
        guard frame.width > 0, frame.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return 128
        }

        let scaleNeededToCoverViewport = max(
            containerSize.width / frame.width,
            containerSize.height / frame.height
        )
        // The focal point is an empty region, so visible-stroke clearance—not
        // the image rectangle—determines how far the camera must continue.
        let visibleStrokeClearanceFactor: CGFloat = 8.0
        return scaleNeededToCoverViewport * visibleStrokeClearanceFactor
    }

    private func focalOffset(for frame: CGRect) -> CGSize {
        let focalPoint = CGPoint(
            x: frame.minX + frame.width * SplashZoomFocalPoint.normalized.x,
            y: frame.minY + frame.height * SplashZoomFocalPoint.normalized.y
        )
        return CGSize(
            width: containerSize.width / 2 - focalPoint.x,
            height: containerSize.height / 2 - focalPoint.y
        )
    }

    private func pause(for nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private enum SplashBrandPhase: Equatable {
    case hidden
    case markAppearing
    case markSettled
    case revealingWordmark
    case complete
    case exiting
    case logoFullyCleared
}

private struct SplashBrandLockup: View {
    let phase: SplashBrandPhase
    let reduceMotion: Bool
    let reportsMarkFrame: Bool
    @Binding var wordmarkWidth: CGFloat
    let breathingScale: CGFloat
    let exitZoomScale: CGFloat
    let exitZoomOffset: CGSize
    let wordmarkExitOpacity: Double

    private let markWidth: CGFloat = 92
    private let markHeight: CGFloat = 62
    private let spacing: CGFloat = 12

    var body: some View {
        HStack(spacing: spacing) {
            Image("Sa7totLogo")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: markWidth, height: markHeight)
                .opacity(markOpacity)
                .blur(radius: markBlur)
                .scaleEffect(markScale)
                .scaleEffect(exitZoomScale, anchor: SplashZoomFocalPoint.anchor)
                .offset(x: exitZoomOffset.width, y: exitZoomOffset.height)
                .offset(x: markOffset)
                .overlay {
                    if reportsMarkFrame {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: SplashMarkFramePreferenceKey.self,
                                    value: proxy.frame(in: .named(SplashCoordinateSpace.root))
                                )
                        }
                    }
                }

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array("Sa7tot".enumerated()), id: \.offset) { index, character in
                        SplashLetterView(
                            character: character,
                            index: index,
                            isVisible: isWordmarkVisible,
                            reduceMotion: reduceMotion
                        )
                    }
                }
                .offset(x: wordmarkOffset)
                .opacity(isWordmarkVisible ? wordmarkExitOpacity : 0)

                Text("Sa7tot")
                    .font(ClashDisplayFont.font(size: 32))
                    .foregroundStyle(.clear)
                    .fixedSize()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .overlay {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: SplashWordmarkWidthKey.self, value: proxy.size.width)
                        }
                    }
            }
        }
        .fixedSize()
        .scaleEffect(breathingScale)
        .onPreferenceChange(SplashWordmarkWidthKey.self) { width in
            wordmarkWidth = width
        }
    }

    private var markOpacity: Double {
        switch phase {
        case .hidden: 0
        case .exiting: 1
        case .logoFullyCleared: 1
        default: 1
        }
    }

    private var markBlur: CGFloat {
        reduceMotion || phase != .hidden ? 0 : 10
    }

    private var markScale: CGFloat {
        reduceMotion || phase != .hidden ? 1 : 0.92
    }

    private var markOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        switch phase {
        case .hidden, .markAppearing, .markSettled:
            return (wordmarkWidth + spacing) / 2
        default:
            return 0
        }
    }

    private var wordmarkOffset: CGFloat {
        reduceMotion || phase == .revealingWordmark || phase == .complete || phase == .exiting ? 0 : -6
    }

    private var isWordmarkVisible: Bool {
        switch phase {
        case .revealingWordmark, .complete, .exiting:
            return true
        default:
            return false
        }
    }
}

private struct SplashLetterView: View {
    let character: Character
    let index: Int
    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        Text(String(character))
            .font(ClashDisplayFont.font(size: 32))
            .foregroundStyle(Color.PrimaryText)
            .fixedSize()
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible || reduceMotion ? 0 : 4)
            .offset(y: isVisible || reduceMotion ? 0 : startingOffset)
            .rotationEffect(.degrees(isVisible || reduceMotion ? 0 : startingRotation))
            .animation(letterAnimation.delay(letterDelay), value: isVisible)
    }

    private var letterAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .interactiveSpring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.04)
    }

    private var letterDelay: Double {
        reduceMotion ? Double(index) * 0.04 : Double(index) * 0.075
    }

    private var startingOffset: CGFloat {
        index.isMultiple(of: 2) ? 10 : -8
    }

    private var startingRotation: Double {
        index.isMultiple(of: 2) ? -1.2 : 1.2
    }
}

private struct SplashWordmarkWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
