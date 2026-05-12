import SwiftUI
import TallyClawCore

public struct TallyClawRootView: View {
  private static let hoverBubbleWidth: CGFloat = 132
  private static let hoverBubbleOffsetX: CGFloat = 88

  private let snapshot: UsageSnapshot
  @ObservedObject private var preferences: FloatingWindowPreferences
  @StateObject private var windowState = FloatingWindowState()
  @State private var petStageFrame: CGRect = .zero
  @State private var isHovered = false
  @State private var hoverLocation: CGPoint?
  @State private var isExpanded = false
  @State private var isPanelVisible = false
  @State private var expansionTransitionID = UUID()
  @State private var isPressed = false
  @State private var particles: [TokenParticle] = []
  @State private var lastLifetimeTokens: Int64?
  @State private var activityMonitor = UsageActivityMonitor()
  @State private var animationDate = Date()

  public init(
    snapshot: UsageSnapshot = .preview,
    preferences: FloatingWindowPreferences = FloatingWindowPreferences()
  ) {
    self.snapshot = snapshot
    _preferences = ObservedObject(wrappedValue: preferences)
  }

  public var body: some View {
    let visualState = petState(at: animationDate)
    let cadence = PetAnimationCadence.resolve(
      state: visualState,
      isExpanded: isExpanded,
      isHovered: isHovered,
      isPressed: isPressed,
      hasParticles: !particles.isEmpty
    )
    let activityIntensity = activityMonitor.intensity(for: snapshot, at: animationDate)
    let activitySource = activityMonitor.activeSource(for: snapshot, at: animationDate)
    let palette = PetPalette(state: visualState)
    let motion = PetMotion(date: animationDate, state: visualState, intensity: activityIntensity, isPressed: isPressed)

    ZStack(alignment: .top) {
      petStage(motion: motion, state: visualState, intensity: activityIntensity, source: activitySource)
        .transaction { transaction in
          transaction.animation = nil
        }

      if isExpanded {
        ExpandedDataStrip(snapshot: snapshot, color: palette.main)
          .offset(y: 96)
          .opacity(isPanelVisible ? 1 : 0)
          .allowsHitTesting(isPanelVisible)
      }
    }
    .frame(width: FloatingWindowDragGeometry.rootContentWidth, height: windowSize.height, alignment: .top)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .coordinateSpace(name: "floatingRoot")
    .background(
      FloatingWindowConfigurator(
        windowState: windowState,
        preferences: preferences,
        desiredSize: windowSize
      )
    )
    .onChange(of: snapshot.lifetime.tokens.total) { _, newValue in
      guard let previous = lastLifetimeTokens else {
        lastLifetimeTokens = newValue
        return
      }
      if newValue > previous {
        emitTokenPulse(count: UsageActivityIntensity(tokenDelta: newValue - previous).particleCount)
      }
      lastLifetimeTokens = newValue
    }
    .onChange(of: snapshot) { _, newSnapshot in
      _ = activityMonitor.ingest(newSnapshot, at: Date())
    }
    .task(id: cadence.minimumInterval) {
      await runAnimationClock(interval: cadence.minimumInterval)
    }
  }

  @MainActor
  private func runAnimationClock(interval: TimeInterval) async {
    guard interval > 0 else { return }
    let nanoseconds = UInt64(max(interval, 1.0 / 30.0) * 1_000_000_000)
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled else { return }
      animationDate = Date()
    }
  }

  private func petState(at date: Date) -> PetVisualState {
    switch activityMonitor.state(for: snapshot, at: date) {
    case .idle:
      .idle
    case .active:
      .highActivity
    case .warning:
      .warning
    }
  }

  @ViewBuilder
  private func petStage(
    motion: PetMotion,
    state: PetVisualState,
    intensity: UsageActivityIntensity,
    source: UsageActivitySource
  ) -> some View {
    let palette = PetPalette(state: state)
    let hoverSide = hoverSide()
    let petOffset = CGSize(width: motion.x, height: motion.y)

    ZStack {
      petShadow(motionY: petOffset.height)

      ForEach(particles) { particle in
        TokenParticleView(particle: particle, color: palette.main)
      }

      TallyClawPetBody(
        state: state,
        palette: palette,
        motion: motion,
        intensity: intensity,
        activitySource: source,
        isHovered: isHovered,
        hoverLocation: hoverLocation,
        pulseActive: !particles.isEmpty
      )
      .offset(x: petOffset.width, y: petOffset.height)

      if isHovered && !isExpanded {
        HoverDataLeaf(snapshot: snapshot, color: palette.main)
          .offset(x: hoverSide == .right ? Self.hoverBubbleOffsetX : -Self.hoverBubbleOffsetX, y: -7)
          .transition(.opacity)
      }
    }
    .frame(width: 170, height: 94)
    .background(
      GeometryReader { proxy in
        Color.clear.preference(key: PetStageFramePreferenceKey.self, value: proxy.frame(in: .named("floatingRoot")))
      }
    )
    .contentShape(Rectangle())
    .onPreferenceChange(PetStageFramePreferenceKey.self) { frame in
      petStageFrame = frame
    }
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.18)) {
        isHovered = hovering
      }
      if hovering && !isExpanded {
        windowState.revealEdgeAttachment(petFrameInWindow: petDragFrameInWindow())
      } else if !isExpanded {
        hoverLocation = nil
        windowState.concealEdgeAttachment(petFrameInWindow: petDragFrameInWindow())
      }
    }
    .onContinuousHover { phase in
      switch phase {
      case let .active(location):
        hoverLocation = location
      case .ended:
        hoverLocation = nil
      }
    }
    .onTapGesture {
      toggleExpansion()
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 1)
        .onChanged { _ in
          windowState.beginDragIfNeeded()
          windowState.updateDrag(petFrameInWindow: petDragFrameInWindow())
        }
        .onEnded { _ in
          windowState.endDrag(petFrameInWindow: petDragFrameInWindow(), saveFrame: preferences.saveFrame)
        }
    )
  }

  private var windowSize: CGSize {
    isExpanded
      ? FloatingWindowDragGeometry.expandedWindowSize
      : FloatingWindowDragGeometry.collapsedWindowSize
  }

  private func toggleExpansion() {
    let willExpand = !isExpanded
    let transitionID = UUID()
    expansionTransitionID = transitionID

    if willExpand {
      windowState.revealForExpansion(
        petFrameInWindow: petDragFrameInWindow(),
        targetWindowSize: FloatingWindowDragGeometry.expandedWindowSize
      )
      withoutAnimation {
        isPanelVisible = false
        isExpanded = true
      }
      DispatchQueue.main.async {
        guard expansionTransitionID == transitionID, isExpanded else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
          isPanelVisible = true
        }
      }
    } else {
      withAnimation(.easeInOut(duration: 0.18)) {
        isPanelVisible = false
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        guard expansionTransitionID == transitionID, !isPanelVisible else { return }
        withoutAnimation {
          isExpanded = false
        }
        windowState.restoreAfterExpansionCollapse(petFrameInWindow: petDragFrameInWindow())
      }
    }
  }

  private func withoutAnimation(_ updates: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, updates)
  }

  private func hoverSide() -> HoverSide {
    let gap: CGFloat = 18
    let petCenterX = windowState.frame.minX + petAnchorInWindow().x
    let rightSpace = windowState.visibleFrame.maxX - petCenterX
    let leftSpace = petCenterX - windowState.visibleFrame.minX

    if rightSpace < Self.hoverBubbleWidth + gap, leftSpace > Self.hoverBubbleWidth + gap {
      return .left
    }
    return .right
  }

  private func petAnchorInWindow() -> CGPoint {
    let petFrame = petFrameInWindow()
    if petFrame != .zero {
      return CGPoint(x: petFrame.midX, y: petFrame.midY)
    }
    return CGPoint(x: windowState.frame.width / 2, y: windowState.frame.height / 2)
  }

  private func petFrameInWindow() -> CGRect {
    if petStageFrame != .zero {
      return petStageFrame
    }
    return FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: windowState.frame.size)
  }

  private func petDragFrameInWindow() -> CGRect {
    FloatingWindowDragGeometry.petDragFrame(stageFrame: petFrameInWindow())
  }

  private func emitTokenPulse(count: Int = 3) {
    let next = (0..<count).map { TokenParticle(index: $0) }
    particles.append(contentsOf: next)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
      withAnimation(.easeOut(duration: 0.2)) {
        particles.removeAll { particle in
          next.contains(where: { $0.id == particle.id })
        }
      }
    }
  }

  private func petShadow(motionY: CGFloat) -> some View {
    Ellipse()
      .fill(.black.opacity(isPressed ? 0.18 : 0.34))
      .frame(width: isPressed ? 26 : 34, height: isPressed ? 5 : 7)
      .blur(radius: 2.2)
      .offset(y: 35 - motionY * 0.2)
  }
}

enum PetVisualState {
  case idle
  case highActivity
  case warning
}

struct PetAnimationCadence: Equatable, Sendable {
  let minimumInterval: TimeInterval

  static func resolve(
    state: PetVisualState,
    isExpanded: Bool,
    isHovered: Bool,
    isPressed: Bool,
    hasParticles: Bool
  ) -> PetAnimationCadence {
    if isPressed || hasParticles {
      return PetAnimationCadence(minimumInterval: 1.0 / 30.0)
    }

    if isHovered {
      return PetAnimationCadence(minimumInterval: 1.0 / 12.0)
    }

    if state == .highActivity {
      return PetAnimationCadence(minimumInterval: 1.0 / 2.0)
    }

    return PetAnimationCadence(minimumInterval: 0)
  }
}

private enum HoverSide {
  case left
  case right
}

private struct PetStageFramePreferenceKey: PreferenceKey {
  static let defaultValue: CGRect = .zero

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

private struct PetPalette {
  let main: Color
  let glow: Color
  let bodyTop: Color
  let bodyBottom: Color
  let stroke: Color

  init(state: PetVisualState) {
    switch state {
    case .idle:
      main = Color(red: 0.02, green: 0.71, blue: 0.83)
      glow = Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.42)
    case .highActivity:
      main = Color(red: 0.66, green: 0.33, blue: 0.97)
      glow = Color(red: 0.66, green: 0.33, blue: 0.97).opacity(0.44)
    case .warning:
      main = Color(red: 0.98, green: 0.75, blue: 0.14)
      glow = Color(red: 0.98, green: 0.75, blue: 0.14).opacity(0.44)
    }

    bodyTop = Color(red: 0.12, green: 0.16, blue: 0.24)
    bodyBottom = Color(red: 0.05, green: 0.08, blue: 0.14)
    stroke = Color(red: 0.2, green: 0.25, blue: 0.33)
  }
}

private struct PetMotion {
  let x: CGFloat
  let y: CGFloat
  let scale: CGFloat
  let coreScale: CGFloat
  let energyPhase: CGFloat
  let eyeBlinkScale: CGFloat
  let earRotationLeft: CGFloat
  let earRotationRight: CGFloat

  init(date: Date, state: PetVisualState, intensity: UsageActivityIntensity, isPressed: Bool) {
    let time = date.timeIntervalSinceReferenceDate
    let boost = intensity.visualBoost
    let nextX: CGFloat
    var nextY: CGFloat
    var nextScale: CGFloat
    let nextCoreScale: CGFloat
    let nextEnergyPhase: CGFloat

    switch state {
    case .idle:
      nextX = 0
      nextY = sin(time * .pi * 0.26) * 1.1
      nextScale = 1 + sin(time * .pi * 0.26) * 0.006
      nextCoreScale = 1 + sin(time * .pi * 0.35) * 0.04
      nextEnergyPhase = CGFloat(time.truncatingRemainder(dividingBy: 6.0) / 6.0)
    case .highActivity:
      nextX = sin(time * .pi * 0.5) * (0.32 + boost * 0.18)
      nextY = sin(time * .pi * 0.52) * (1.15 + boost * 0.55)
      nextScale = 1 + sin(time * .pi * 0.48) * (0.006 + boost * 0.006)
      nextCoreScale = 1 + sin(time * .pi * 0.9) * (0.045 + boost * 0.055)
      let period = 3.4 - boost * 1.0
      nextEnergyPhase = CGFloat(time.truncatingRemainder(dividingBy: period) / period)
    case .warning:
      nextX = sin(time * .pi * 1.1) * 0.35
      nextY = sin(time * .pi * 0.6) * 0.9
      nextScale = 0.996
      nextCoreScale = 1 + sin(time * .pi * 0.7) * 0.05
      nextEnergyPhase = CGFloat(time.truncatingRemainder(dividingBy: 3.2) / 3.2)
    }

    if isPressed {
      nextScale *= 1.01
    }

    // Eye Blink Logic (smooth and reliable)
    let blinkPhase = time.truncatingRemainder(dividingBy: 3.8)
    if state == .idle && blinkPhase < 0.12 {
      let progress = blinkPhase / 0.12
      // sin(progress * pi) goes 0 -> 1 -> 0
      let intensity = sin(progress * .pi)
      eyeBlinkScale = CGFloat(max(0.1, 1.0 - intensity * 1.5))
    } else {
      eyeBlinkScale = 1.0
    }

    // Ear Twitch Logic (rapid, smooth flicking)
    // Left Ear: 3 rapid outward flicks every 4.7s
    let leftPhase = time.truncatingRemainder(dividingBy: 4.7)
    if leftPhase < 0.15 {
      let progress = leftPhase / 0.15
      // abs(sin) guarantees outward only; 3*pi means 3 flicks
      earRotationLeft = CGFloat(-abs(sin(progress * .pi * 3)) * 22)
    } else {
      earRotationLeft = 0
    }

    // Right Ear: 2 slightly slower outward flicks every 5.3s
    let rightPhase = time.truncatingRemainder(dividingBy: 5.3)
    if rightPhase < 0.2 {
      let progress = rightPhase / 0.2
      // right ear outward is positive rotation
      earRotationRight = CGFloat(abs(sin(progress * .pi * 2)) * 22)
    } else {
      earRotationRight = 0
    }

    x = nextX
    y = nextY
    scale = nextScale
    coreScale = nextCoreScale
    energyPhase = nextEnergyPhase
  }
}

private struct TallyClawPetBody: View {
  let state: PetVisualState
  let palette: PetPalette
  let motion: PetMotion
  let intensity: UsageActivityIntensity
  let activitySource: UsageActivitySource
  let isHovered: Bool
  let hoverLocation: CGPoint?
  let pulseActive: Bool

  var body: some View {
    ZStack {
      shell
      ears
      face
      if state == .highActivity && activitySource == .cockpit {
        CodexFocusSweep(phase: motion.energyPhase, color: palette.main)
          .frame(width: 28, height: 15)
          .offset(y: -2.5)
      }
      eyes
      core
      feet
      energyTicks
    }
    .frame(width: 64, height: 64)
    .scaleEffect(motion.scale * 1.3125)
    .shadow(color: palette.glow, radius: pulseActive ? 7 + intensity.visualBoost * 2 : 4)
  }

  private var shell: some View {
    RoundedRectangle(cornerRadius: 11, style: .continuous)
      .fill(
        LinearGradient(
          colors: [palette.bodyTop, palette.bodyBottom],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(palette.stroke, lineWidth: 1)
      }
      .frame(width: 37, height: 32)
      .offset(y: 2.5)
  }

  private var ears: some View {
    ZStack {
      PetEar()
        .fill(palette.stroke)
        .frame(width: 9, height: 9)
        .rotationEffect(.degrees(-10 + motion.earRotationLeft), anchor: .bottomTrailing)
        .offset(x: -12, y: -16)
      PetEar()
        .fill(palette.stroke)
        .frame(width: 9, height: 9)
        .rotationEffect(.degrees(10 + motion.earRotationRight), anchor: .bottomLeading)
        .offset(x: 12, y: -16)
    }
  }

  private var face: some View {
    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
      .fill(Color(red: 0.01, green: 0.02, blue: 0.06))
      .overlay {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
          .fill(palette.glow.opacity(0.22))
      }
      .frame(width: 28, height: 15)
      .offset(y: -2.5)
  }

  private var eyes: some View {
    HStack(spacing: 10) {
      EyeView(state: state, isHovered: isHovered, motion: motion, side: .left, color: palette.main, gazeOffset: gazeOffset)
      EyeView(state: state, isHovered: isHovered, motion: motion, side: .right, color: palette.main, gazeOffset: gazeOffset)
    }
    .offset(y: -3)
    .shadow(color: palette.glow, radius: 3)
  }

  private var gazeOffset: CGSize {
    guard isHovered, state == .idle, let hoverLocation else {
      return .zero
    }

    let normalizedX = Self.clamp((hoverLocation.x - 85) / 85, min: -1, max: 1)
    let normalizedY = Self.clamp((hoverLocation.y - 47) / 47, min: -1, max: 1)
    return CGSize(width: normalizedX * 1.15, height: normalizedY * 0.75 - 0.35)
  }

  private var core: some View {
    ZStack {
      if state == .highActivity {
        ActivityCoreSignal(
          color: palette.main,
          glow: palette.glow,
          phase: motion.energyPhase,
          intensity: intensity
        )
      } else {
        Circle()
          .stroke(palette.main.opacity(0.25), lineWidth: 0.8)
          .frame(width: 9, height: 9)
          .scaleEffect(pulseActive ? motion.coreScale : 0.82)

        Circle()
          .fill(palette.main)
          .frame(width: 3.5, height: 3.5)
          .scaleEffect(pulseActive ? 1.35 : motion.coreScale)
      }
    }
    .offset(y: 12.5)
    .shadow(color: palette.glow, radius: 3.5)
  }

  private var feet: some View {
    HStack(spacing: 14) {
      Capsule()
        .fill(palette.stroke)
        .frame(width: 5.5, height: 3.5)
      Capsule()
        .fill(palette.stroke)
        .frame(width: 5.5, height: 3.5)
    }
    .offset(y: 21)
  }

  private var energyTicks: some View {
    HStack(spacing: 2.5) {
      ForEach(0..<5, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(palette.main.opacity(index == activeTick ? 0.9 : 0.22))
          .frame(width: 2, height: index.isMultiple(of: 2) ? 2.5 : 4.0)
      }
    }
    .offset(y: 22.5)
  }

  private var activeTick: Int {
    Int((motion.energyPhase * 5).rounded(.down)) % 5
  }

  private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, minimum), maximum)
  }
}

private struct CodexFocusSweep: View {
  let phase: CGFloat
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let x = proxy.size.width * phase

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
          .stroke(color.opacity(0.18), lineWidth: 0.7)

        Capsule()
          .fill(
            LinearGradient(
              colors: [.clear, color.opacity(0.68), .clear],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: 2.2, height: proxy.size.height - 2)
          .offset(x: min(max(x, 0), proxy.size.width - 2.2), y: 1)
          .shadow(color: color.opacity(0.55), radius: 2.5)
      }
    }
  }
}

private enum EyeSide {
  case left
  case right
}

private struct EyeView: View {
  let state: PetVisualState
  let isHovered: Bool
  let motion: PetMotion
  let side: EyeSide
  let color: Color
  let gazeOffset: CGSize

  var body: some View {
    switch state {
    case .warning:
      WarningEye(side: side)
        .stroke(color, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        .frame(width: 5, height: 4)
    case .highActivity:
      ActiveEyeView(side: side, color: color, phase: motion.energyPhase)
    case .idle:
      if isHovered {
        Circle()
          .fill(color)
          .frame(width: 3, height: 3)
          .offset(x: gazeOffset.width, y: gazeOffset.height)
      } else {
        Capsule()
          .fill(color)
          .frame(width: 4.5, height: 1.5)
          .scaleEffect(y: motion.eyeBlinkScale)
      }
    }
  }
}

private struct ActivityCoreSignal: View {
  let color: Color
  let glow: Color
  let phase: CGFloat
  let intensity: UsageActivityIntensity

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      ForEach(0..<3, id: \.self) { index in
        Capsule()
          .fill(color.opacity(index == 1 ? 0.95 : 0.68))
          .frame(width: 1.7, height: barHeight(at: index))
          .shadow(color: glow.opacity(0.35 + intensity.visualBoost * 0.22), radius: 1.6 + intensity.visualBoost * 1.1)
      }
    }
    .frame(width: 14, height: 6)
    .animation(.easeInOut(duration: 0.12), value: phase)
  }

  private func barHeight(at index: Int) -> CGFloat {
    let offset = CGFloat(index) * 0.23
    let wave = (sin((phase + offset) * .pi * 2) + 1) / 2
    return 1.7 + wave * (1.8 + intensity.visualBoost * 1.2)
  }
}

private struct ActiveEyeView: View {
  let side: EyeSide
  let color: Color
  let phase: CGFloat

  var body: some View {
    ZStack {
      ActiveFocusEye(side: side)
        .stroke(color, style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round))

      Circle()
        .fill(color.opacity(0.9))
        .frame(width: 1.6, height: 1.6)
        .offset(x: side == .left ? -0.45 : 0.45, y: -0.05 + scanOffset)
        .shadow(color: color.opacity(0.55), radius: 1.8)
    }
    .frame(width: 6.5, height: 4.5)
    .rotationEffect(.degrees(side == .left ? -3 : 3))
  }

  private var scanOffset: CGFloat {
    sin(phase * .pi * 2) * 0.18
  }
}

private struct HoverDataLeaf: View {
  let snapshot: UsageSnapshot
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 7) {
        Circle()
          .fill(color)
          .frame(width: 5, height: 5)
          .shadow(color: color.opacity(0.8), radius: 5)

        Text("\(snapshot.today.tokens.total.formattedCompact.lowercased()) tokens")
          .font(.system(size: 10.5, weight: .regular, design: .monospaced))
          .foregroundStyle(color)
          .fixedSize(horizontal: true, vertical: false)
      }

      if let sourceText = hoverSourceText {
        Text(sourceText)
          .font(.system(size: 8.6, weight: .regular))
          .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(Color(red: 0.06, green: 0.09, blue: 0.15).opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color(red: 0.25, green: 0.32, blue: 0.43).opacity(0.8), lineWidth: 1)
    }
  }

  private var hoverSourceText: String? {
    guard let source = snapshot.topSources.first else { return nil }
    return "\(displayName(for: source.name)) \(source.percent)%"
  }

  private func displayName(for sourceName: String) -> String {
    switch sourceName {
    case "cockpit-codex-stats":
      return "cockpit"
    case "local-ai-gateway":
      return "gateway"
    default:
      return sourceName
    }
  }
}

private struct ExpandedDataStrip: View {
  let snapshot: UsageSnapshot
  let color: Color

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 8) {
        HStack {
          Label("本地来源", systemImage: "externaldrive.connected.to.line.below")
            .font(PanelText.sectionTitle)
            .foregroundStyle(Color(red: 0.8, green: 0.84, blue: 0.9))

          Spacer(minLength: 8)

          StatusDot(color: color)
        }

        TodayDigestStrip(digest: snapshot.todayDigest, color: color)

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
          MiniMetric(title: "今日", value: snapshot.today.tokens.total.formattedCompact.lowercased())
          MiniMetric(title: "7 天", value: snapshot.week.tokens.total.formattedCompact.lowercased())
          MiniMetric(title: "30 天", value: snapshot.month.tokens.total.formattedCompact.lowercased())
          MiniMetric(title: "总计", value: snapshot.lifetime.tokens.total.formattedCompact.lowercased())
        }

        LifetimeScopeStrip(text: snapshot.lifetimeScopeText)

        WindowTrendStrip(snapshot: snapshot, color: color)

        SuccessRateStrip(requests: snapshot.week.requests, color: color)

        SourceHealthStrip(snapshot: snapshot, color: color)

        if snapshot.observationFacets.hasLeaders {
          ObservationFacetStrip(facets: snapshot.observationFacets, explanation: snapshot.traceExplanation, color: color)
        } else if !snapshot.topSources.isEmpty {
          TopSourcesStrip(sources: Array(snapshot.topSources.prefix(3)), color: color)
        }
      }
      .padding(12)
    }
    .frame(width: 236)
    .frame(maxHeight: 438)
    .scrollClipDisabled(false)
    .background(Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color(red: 0.26, green: 0.32, blue: 0.42).opacity(0.42), lineWidth: 0.8)
    }
    .shadow(color: .black.opacity(0.26), radius: 8, y: 6)
  }
}

private enum PanelText {
  static let sectionTitle = Font.system(size: 10, weight: .regular)
  static let body = Font.system(size: 9.5, weight: .regular)
  static let bodyMono = Font.system(size: 9.5, weight: .regular, design: .monospaced)
  static let caption = Font.system(size: 8.6, weight: .regular)
  static let valueMono = Font.system(size: 12, weight: .regular, design: .monospaced)
}

private struct TodayDigestStrip: View {
  let digest: UsageDailyDigest
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Circle()
          .fill(color)
          .frame(width: 4.5, height: 4.5)
          .shadow(color: color.opacity(0.75), radius: 4)

        Text(digest.title)
          .font(.system(size: 10.5, weight: .regular, design: .monospaced))
          .foregroundStyle(Color(red: 0.86, green: 0.9, blue: 0.96))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }

      Text(digest.detail)
        .font(PanelText.body)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SuccessRateStrip: View {
  let requests: RequestStats
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 7) {
        Label("7 天成功率", systemImage: "waveform.path.ecg")
          .font(PanelText.sectionTitle)
          .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))

        Spacer()

        Text("\(requests.successRatePercent)%")
          .font(PanelText.bodyMono)
          .foregroundStyle(Color(red: 0.21, green: 0.86, blue: 0.56))
      }

      Text(requests.successSummaryText)
        .font(PanelText.caption)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct LifetimeScopeStrip: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: "lock.circle")
        .font(PanelText.sectionTitle)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
        .frame(width: 12)

      Text(text)
        .font(PanelText.caption)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct WindowTrendStrip: View {
  let snapshot: UsageSnapshot
  let color: Color

  private var windows: [(String, Int64)] {
    [
      ("今日", snapshot.today.tokens.total),
      ("7天", snapshot.week.tokens.total),
      ("30天", snapshot.month.tokens.total)
    ]
  }

  private var maxValue: Int64 {
    max(windows.map(\.1).max() ?? 0, 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Label("窗口趋势", systemImage: "chart.line.uptrend.xyaxis")
          .font(PanelText.sectionTitle)
          .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))

        Spacer()

        Text("最近 6h · 30m")
          .font(PanelText.caption)
          .foregroundStyle(Color(red: 0.48, green: 0.54, blue: 0.63))
      }

      if !snapshot.hourlyTokenTrend.isEmpty {
        HourlyTokenLineChart(buckets: snapshot.hourlyTokenTrend, color: color)
      }

      if !snapshot.dailyTokenTrend.isEmpty {
        DailyTokenChart(days: snapshot.dailyTokenTrend, color: color)
      }

      HStack(alignment: .bottom, spacing: 8) {
        ForEach(windows, id: \.0) { item in
          TrendBar(
            title: item.0,
            value: item.1.formattedCompact.lowercased(),
            fraction: CGFloat(item.1) / CGFloat(maxValue),
            color: color
          )
        }
      }

      Text(UsageSnapshot.windowSemanticsText)
        .font(PanelText.caption)
        .foregroundStyle(Color(red: 0.48, green: 0.54, blue: 0.63))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct HourlyTokenLineChart: View {
  let buckets: [HourlyTokenUsage]
  let color: Color
  @State private var hoveredBucketID: HourlyTokenUsage.ID?
  @State private var livePulseDate = Date()

  private var maxTokens: Int64 {
    max(buckets.map(\.tokens).max() ?? 0, 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      GeometryReader { proxy in
        ZStack {
          line(in: proxy.size, opacity: 0.92, lineWidth: 1.25)
            .shadow(color: color.opacity(0.26), radius: 2)

          line(in: proxy.size, opacity: 0.16, lineWidth: 4.5)
            .blur(radius: 1.8)

          ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
            let point = chartPoint(at: index, in: proxy.size)
            Circle()
              .fill(hoveredBucketID == bucket.id ? color : Color(red: 0.08, green: 0.11, blue: 0.17))
              .overlay {
                Circle()
                  .stroke(color.opacity(hoveredBucketID == bucket.id ? 0.95 : 0.48), lineWidth: hoveredBucketID == bucket.id ? 1.2 : 0.8)
              }
              .frame(width: hoveredBucketID == bucket.id ? 5.6 : 4.2, height: hoveredBucketID == bucket.id ? 5.6 : 4.2)
              .position(point)
              .animation(.easeInOut(duration: 0.12), value: hoveredBucketID)
          }

          if let lastIndex = buckets.indices.last {
            let point = chartPoint(at: lastIndex, in: proxy.size)
            let pulse = livePulse(at: livePulseDate)
            Circle()
              .stroke(color.opacity(0.2 + pulse * 0.34), lineWidth: 0.9)
              .frame(width: 8 + pulse * 7, height: 8 + pulse * 7)
              .position(point)
              .allowsHitTesting(false)
          }

          Rectangle()
            .fill(Color.white.opacity(0.001))
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
              switch phase {
              case .active(let location):
                hoveredBucketID = nearestBucketID(forX: location.x, width: proxy.size.width)
              case .ended:
                hoveredBucketID = nil
              }
            }
            .help(hoverHelpText)
          .frame(width: proxy.size.width, height: proxy.size.height)
        }
      }
      .frame(height: 42)
      .overlay(alignment: .bottom) {
        HStack {
          Text(buckets.first?.label ?? "")
          Spacer()
          Text(middleLabel)
          Spacer()
          Text(buckets.last?.label ?? "")
        }
        .font(.system(size: 7.2, weight: .regular, design: .monospaced))
        .foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.56))
        .allowsHitTesting(false)
      }

      Text(statusText)
        .font(PanelText.caption)
        .foregroundStyle(hoveredBucketID == nil ? Color(red: 0.48, green: 0.54, blue: 0.63) : color)
        .lineLimit(1)
        .animation(.easeInOut(duration: 0.12), value: hoveredBucketID)
    }
    .padding(.top, 2)
    .task {
      await runLivePulseClock()
    }
  }

  @MainActor
  private func runLivePulseClock() async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard !Task.isCancelled else { return }
      livePulseDate = Date()
    }
  }

  private func line(in size: CGSize, opacity: Double, lineWidth: CGFloat) -> some View {
    Path { path in
      let points = chartPoints(in: size)
      guard let first = points.first else { return }

      path.move(to: first)
      for point in points.dropFirst() {
        path.addLine(to: point)
      }
    }
    .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
  }

  private func chartPoints(in size: CGSize) -> [CGPoint] {
    buckets.indices.map { chartPoint(at: $0, in: size) }
  }

  private func chartPoint(at index: Int, in size: CGSize) -> CGPoint {
    guard !buckets.isEmpty else { return CGPoint(x: size.width / 2, y: size.height / 2) }

    let safeIndex = min(max(index, 0), buckets.count - 1)
    let xPadding: CGFloat = 3
    let topPadding: CGFloat = 3
    let bottomPadding: CGFloat = 11
    let usableWidth = max(size.width - xPadding * 2, 1)
    let usableHeight = max(size.height - topPadding - bottomPadding, 1)
    let fraction = min(max(CGFloat(buckets[safeIndex].tokens) / CGFloat(maxTokens), 0), 1)
    let x = buckets.count == 1
      ? size.width / 2
      : xPadding + usableWidth * CGFloat(safeIndex) / CGFloat(buckets.count - 1)
    let y = topPadding + usableHeight * (1 - fraction)

    return CGPoint(x: x, y: y)
  }

  private var statusText: String {
    if let hoveredBucket = buckets.first(where: { $0.id == hoveredBucketID }) {
      return "\(hoveredBucket.label) · \(hoveredBucket.tokens.formattedCompact.lowercased()) tokens"
    }

    guard let latestBucket = buckets.last else {
      return "当前半小时滚动累计"
    }
    return "当前半小时 · \(latestBucket.tokens.formattedCompact.lowercased()) tokens"
  }

  private var hoverHelpText: String {
    guard let hoveredBucket = buckets.first(where: { $0.id == hoveredBucketID }) else {
      return "移动查看最近 6h / 30m token"
    }
    return "\(hoveredBucket.label) · \(hoveredBucket.tokens.formattedCompact.lowercased()) tokens"
  }

  private var middleLabel: String {
    guard !buckets.isEmpty else { return "" }
    return buckets[buckets.count / 2].label
  }

  private func nearestBucketID(forX x: CGFloat, width: CGFloat) -> HourlyTokenUsage.ID? {
    guard !buckets.isEmpty else { return nil }
    guard buckets.count > 1 else { return buckets.first?.id }

    let xPadding: CGFloat = 3
    let usableWidth = max(width - xPadding * 2, 1)
    let clamped = min(max(x - xPadding, 0), usableWidth)
    let rawIndex = (clamped / usableWidth) * CGFloat(buckets.count - 1)
    let index = min(max(Int(rawIndex.rounded()), 0), buckets.count - 1)
    return buckets[index].id
  }

  private func livePulse(at date: Date) -> CGFloat {
    let wave = (sin(date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
    return CGFloat(wave)
  }
}

private struct DailyTokenChart: View {
  let days: [DailyTokenUsage]
  let color: Color
  @State private var hoveredDayID: DailyTokenUsage.ID?

  private var maxTokens: Int64 {
    max(days.map(\.tokens).max() ?? 0, 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .bottom, spacing: 5) {
        ForEach(days) { day in
          VStack(spacing: 4) {
            GeometryReader { proxy in
              let fraction = CGFloat(day.tokens) / CGFloat(maxTokens)
              VStack {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                  .fill(
                    LinearGradient(
                      colors: [
                        color.opacity(hoveredDayID == day.id ? 1 : 0.92),
                        color.opacity(hoveredDayID == day.id ? 0.52 : 0.38)
                      ],
                      startPoint: .top,
                      endPoint: .bottom
                    )
                  )
                  .frame(height: max(3, proxy.size.height * min(max(fraction, 0), 1)))
                  .shadow(color: color.opacity(hoveredDayID == day.id ? 0.45 : 0), radius: 3)
              }
            }
            .frame(height: 34)

            Text(day.label)
              .font(.system(size: 7.4, weight: .regular, design: .monospaced))
              .foregroundStyle(hoveredDayID == day.id ? color : Color(red: 0.42, green: 0.48, blue: 0.56))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .onHover { hovering in
            hoveredDayID = hovering ? day.id : (hoveredDayID == day.id ? nil : hoveredDayID)
          }
          .help("\(day.label) · \(day.tokens.formattedCompact.lowercased()) tokens")
        }
      }

      Text(hoverText)
        .font(PanelText.caption)
        .foregroundStyle(color)
        .lineLimit(1)
        .opacity(hoveredDayID == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.12), value: hoveredDayID)
    }
    .padding(.top, 2)
  }

  private var hoverText: String {
    guard let hoveredDay = days.first(where: { $0.id == hoveredDayID }) else {
      return " "
    }
    return "\(hoveredDay.label) · \(hoveredDay.tokens.formattedCompact.lowercased()) tokens"
  }
}

private struct TrendBar: View {
  let title: String
  let value: String
  let fraction: CGFloat
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.white.opacity(0.055))
          Capsule()
            .fill(color.opacity(0.72))
            .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
        }
      }
      .frame(height: 5)

      Text(title)
        .font(PanelText.caption)
        .foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.56))

      Text(value)
        .font(PanelText.bodyMono)
        .foregroundStyle(Color(red: 0.86, green: 0.9, blue: 0.96))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SourceHealthStrip: View {
  let snapshot: UsageSnapshot
  let color: Color

  private var available: Int { snapshot.sourceStatuses.availableCount }
  private var failed: Int { snapshot.sourceStatuses.failedCount }
  private var total: Int { snapshot.sourceStatuses.count }

  private var healthText: String {
    let suffix = slowestReadMilliseconds.map { " · \($0)ms" } ?? ""
    if total == 0 {
      return "同步中"
    }
    if failed > 0 {
      return "\(available)/\(total) 可用\(suffix)"
    }
    return "\(available)/\(total) 正常\(suffix)"
  }

  private var healthColor: Color {
    failed > 0 ? Color(red: 0.98, green: 0.75, blue: 0.14) : color
  }

  private var slowestReadMilliseconds: Int? {
    let value = snapshot.sourceStatuses.compactMap(\.readDurationMilliseconds).max()
    guard let value, value > 0 else { return nil }
    return value
  }

  var body: some View {
    HStack(spacing: 7) {
      Label("来源健康", systemImage: "checkmark.seal")
        .font(PanelText.sectionTitle)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))

      Spacer()

      Text(healthText)
        .font(PanelText.bodyMono)
        .foregroundStyle(healthColor)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct ObservationFacetStrip: View {
  let facets: UsageObservationFacets
  let explanation: String?
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("近 7 天事件追溯", systemImage: "list.bullet.rectangle")
        .font(PanelText.sectionTitle)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))

      Text(explanation ?? "近 7 天 exact 逐请求事件；不含 cockpit 聚合快照")
        .font(PanelText.caption)
        .foregroundStyle(Color(red: 0.48, green: 0.54, blue: 0.63))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      if let model = facets.modelLeaders.first {
        ObservationFacetRow(title: "模型", facet: model, color: color)
      }
      if let provider = facets.providerLeaders.first {
        ObservationFacetRow(title: "Provider", facet: provider, color: color)
      }
      if let source = facets.sourceNameLeaders.first {
        ObservationFacetRow(title: "来源", facet: source, color: color)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct ObservationFacetRow: View {
  let title: String
  let facet: UsageObservationFacet
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(PanelText.caption)
        .foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.56))
        .frame(width: 42, alignment: .leading)

      Text(facet.name)
        .font(PanelText.body)
        .foregroundStyle(Color(red: 0.8, green: 0.84, blue: 0.9))
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 4)

      Text(facet.tokens.formattedCompact.lowercased())
        .font(PanelText.bodyMono)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: 48, alignment: .trailing)
    }
  }
}

private struct TopSourcesStrip: View {
  let sources: [SourceShare]
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("主要来源", systemImage: "square.stack.3d.up")
        .font(PanelText.sectionTitle)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))

      ForEach(sources) { source in
        SourceShareRow(source: source, color: color)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SourceShareRow: View {
  let source: SourceShare
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      Text(source.name)
        .font(PanelText.body)
        .foregroundStyle(Color(red: 0.8, green: 0.84, blue: 0.9))
        .lineLimit(1)
        .truncationMode(.tail)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.white.opacity(0.055))
          Capsule()
            .fill(color.opacity(0.68))
            .frame(width: proxy.size.width * CGFloat(min(max(source.percent, 0), 100)) / 100)
        }
      }
      .frame(height: 4)

      Text("\(source.percent)%")
        .font(PanelText.bodyMono)
        .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
        .frame(width: 34, alignment: .trailing)
    }
  }
}

private struct MiniMetric: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(PanelText.caption)
        .foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.56))
      Text(value)
        .font(PanelText.valueMono)
        .foregroundStyle(Color(red: 0.86, green: 0.9, blue: 0.96))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct StatusDot: View {
  let color: Color
  @State private var pulse = false

  var body: some View {
    ZStack {
      Circle()
        .fill(color.opacity(0.28))
        .frame(width: 9, height: 9)
        .scaleEffect(pulse ? 1.1 : 0.92)
      Circle()
        .fill(color)
        .frame(width: 3.5, height: 3.5)
    }
    .onAppear {
      withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
  }
}

private struct TokenParticle: Identifiable, Equatable {
  let id = UUID()
  let index: Int
  let xOffset: CGFloat

  init(index: Int) {
    self.index = index
    xOffset = CGFloat([-18, -6, 8, 20, 2][index % 5])
  }
}

private struct TokenParticleView: View {
  let particle: TokenParticle
  let color: Color
  @State private var isFloating = false

  var body: some View {
    Text("+tokens")
      .font(.system(size: 8, weight: .regular, design: .monospaced))
      .foregroundStyle(color)
      .shadow(color: color.opacity(0.8), radius: 3)
      .offset(x: particle.xOffset * 0.5, y: isFloating ? -34 : 9)
      .scaleEffect(isFloating ? 1.02 : 0.72)
      .opacity(isFloating ? 0 : 1)
      .onAppear {
        withAnimation(.easeOut(duration: 0.85)) {
          isFloating = true
        }
      }
  }
}

private extension UsageActivityIntensity {
  var visualBoost: CGFloat {
    switch self {
    case .none, .low:
      return 0.35
    case .medium:
      return 0.68
    case .high:
      return 1.0
    }
  }

  var particleCount: Int {
    switch self {
    case .none:
      return 0
    case .low:
      return 1
    case .medium:
      return 3
    case .high:
      return 5
    }
  }
}

private struct PetEar: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.midX, y: rect.minY),
      control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.4)
    )
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.maxY),
      control: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY + rect.height * 0.4)
    )
    path.closeSubpath()
    return path
  }
}

private struct WarningEye: Shape {
  let side: EyeSide

  func path(in rect: CGRect) -> Path {
    var path = Path()
    if side == .left {
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    } else {
      path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    }
    return path
  }
}

private struct ActiveFocusEye: Shape {
  let side: EyeSide

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let horizontalInset = rect.width * 0.04
    let left = CGPoint(x: rect.minX + horizontalInset, y: rect.midY + rect.height * 0.08)
    let right = CGPoint(x: rect.maxX - horizontalInset, y: rect.midY + rect.height * 0.08)
    let upper = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.12)
    let lowerBias: CGFloat = side == .left ? -0.12 : 0.12
    let lower = CGPoint(x: rect.midX + rect.width * lowerBias, y: rect.maxY - rect.height * 0.18)

    path.move(to: left)
    path.addQuadCurve(to: right, control: upper)
    path.addQuadCurve(to: left, control: lower)
    return path
  }
}
