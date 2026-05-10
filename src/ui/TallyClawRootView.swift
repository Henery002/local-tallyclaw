import SwiftUI
import TallyClawCore

public struct TallyClawRootView: View {
  private static let hoverBubbleWidth: CGFloat = 132

  private let snapshot: UsageSnapshot
  @ObservedObject private var preferences: FloatingWindowPreferences
  @StateObject private var windowState = FloatingWindowState()
  @State private var petStageFrame: CGRect = .zero
  @State private var isHovered = false
  @State private var isExpanded = false
  @State private var isPressed = false
  @State private var particles: [TokenParticle] = []
  @State private var lastLifetimeTokens: Int64?
  @State private var activityMonitor = UsageActivityMonitor()

  public init(
    snapshot: UsageSnapshot = .preview,
    preferences: FloatingWindowPreferences = FloatingWindowPreferences()
  ) {
    self.snapshot = snapshot
    _preferences = ObservedObject(wrappedValue: preferences)
  }

  public var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let visualState = petState(at: timeline.date)
      let palette = PetPalette(state: visualState)
      let motion = PetMotion(date: timeline.date, state: visualState, isPressed: isPressed)

      ZStack(alignment: .top) {
        petStage(motion: motion, state: visualState)

        ExpandedDataStrip(snapshot: snapshot, color: palette.main)
          .offset(y: 96)
          .opacity(isExpanded ? 1 : 0)
          .allowsHitTesting(isExpanded)
          .accessibilityHidden(!isExpanded)
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
          emitTokenPulse(count: min(5, max(2, Int((newValue - previous) / 10_000) + 1)))
        }
        lastLifetimeTokens = newValue
      }
      .onChange(of: snapshot) { _, newSnapshot in
        _ = activityMonitor.ingest(newSnapshot, at: Date())
      }
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
  private func petStage(motion: PetMotion, state: PetVisualState) -> some View {
    let palette = PetPalette(state: state)
    let hoverSide = hoverSide()

    ZStack {
      petShadow(motion: motion)

      ForEach(particles) { particle in
        TokenParticleView(particle: particle, color: palette.main)
      }

      TallyClawPetBody(
        state: state,
        palette: palette,
        motion: motion,
        isHovered: isHovered,
        pulseActive: !particles.isEmpty
      )
      .offset(x: motion.x, y: motion.y)

      if isHovered && !isExpanded {
        HoverDataLeaf(snapshot: snapshot, color: palette.main)
          .offset(x: hoverSide == .right ? 68 : -68, y: -7)
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
    }
    .onTapGesture {
      withAnimation(.easeInOut(duration: 0.24)) {
        isExpanded.toggle()
      }
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 1)
        .onChanged { _ in
          windowState.beginDragIfNeeded()
          windowState.updateDrag(petFrameInWindow: petDragFrameInWindow())
        }
        .onEnded { _ in
          windowState.endDrag(saveFrame: preferences.saveFrame)
        }
    )
  }

  private var windowSize: CGSize {
    isExpanded
      ? FloatingWindowDragGeometry.expandedWindowSize
      : FloatingWindowDragGeometry.collapsedWindowSize
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

  private func petShadow(motion: PetMotion) -> some View {
    Ellipse()
      .fill(.black.opacity(isPressed ? 0.18 : 0.34))
      .frame(width: isPressed ? 26 : 34, height: isPressed ? 5 : 7)
      .blur(radius: 2.2)
      .offset(y: 35 - motion.y * 0.2)
  }
}

private enum PetVisualState {
  case idle
  case highActivity
  case warning
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

  init(date: Date, state: PetVisualState, isPressed: Bool) {
    let time = date.timeIntervalSinceReferenceDate
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
      nextX = sin(time * .pi * 0.5) * 0.45
      nextY = sin(time * .pi * 0.52) * 1.6
      nextScale = 1 + sin(time * .pi * 0.48) * 0.01
      nextCoreScale = 1 + sin(time * .pi * 0.9) * 0.08
      nextEnergyPhase = CGFloat(time.truncatingRemainder(dividingBy: 2.8) / 2.8)
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
  let isHovered: Bool
  let pulseActive: Bool

  var body: some View {
    ZStack {
      shell
      ears
      face
      eyes
      core
      feet
      energyTicks
    }
    .frame(width: 64, height: 64)
    .scaleEffect(motion.scale * 1.3125)
    .shadow(color: palette.glow, radius: pulseActive ? 7 : 4)
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
      EyeView(state: state, isHovered: isHovered, motion: motion, side: .left, color: palette.main)
      EyeView(state: state, isHovered: isHovered, motion: motion, side: .right, color: palette.main)
    }
    .offset(y: -3)
    .shadow(color: palette.glow, radius: 3)
  }

  private var core: some View {
    ZStack {
      if state == .highActivity {
        Capsule()
          .fill(palette.main)
          .frame(width: 11 + sin(motion.energyPhase * .pi * 2) * 5, height: 3 + cos(motion.energyPhase * .pi * 4) * 1.5)
          .shadow(color: palette.glow, radius: 5)
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

  var body: some View {
    switch state {
    case .warning:
      WarningEye(side: side)
        .stroke(color, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        .frame(width: 5, height: 4)
    case .highActivity:
      ActiveEye()
        .stroke(color, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        .frame(width: 6, height: 4)
    case .idle:
      if isHovered {
        Circle()
          .fill(color)
          .frame(width: 3, height: 3)
          .offset(y: -1)
      } else {
        Capsule()
          .fill(color)
          .frame(width: 4.5, height: 1.5)
          .scaleEffect(y: motion.eyeBlinkScale)
      }
    }
  }
}

private struct HoverDataLeaf: View {
  let snapshot: UsageSnapshot
  let color: Color

  var body: some View {
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
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(Color(red: 0.06, green: 0.09, blue: 0.15).opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color(red: 0.25, green: 0.32, blue: 0.43).opacity(0.8), lineWidth: 1)
    }
  }
}

private struct ExpandedDataStrip: View {
  let snapshot: UsageSnapshot
  let color: Color

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Label("本地来源", systemImage: "externaldrive.connected.to.line.below")
          .font(.system(size: 10, weight: .regular))
          .foregroundStyle(Color(red: 0.8, green: 0.84, blue: 0.9))

        Spacer(minLength: 8)

        StatusDot(color: color)
      }

      LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
        MiniMetric(title: "今日", value: snapshot.today.tokens.total.formattedCompact.lowercased())
        MiniMetric(title: "7 天", value: snapshot.week.tokens.total.formattedCompact.lowercased())
        MiniMetric(title: "30 天", value: snapshot.month.tokens.total.formattedCompact.lowercased())
        MiniMetric(title: "总计", value: snapshot.lifetime.tokens.total.formattedCompact.lowercased())
      }

      HStack(spacing: 7) {
        Label("成功率", systemImage: "waveform.path.ecg")
          .font(.system(size: 10, weight: .regular))
          .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
        Spacer()
        Text("\(snapshot.week.requests.successRatePercent)%")
          .font(.system(size: 10, weight: .regular, design: .monospaced))
          .foregroundStyle(Color(red: 0.21, green: 0.86, blue: 0.56))
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(12)
    .frame(width: 236)
    .background(Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color(red: 0.26, green: 0.32, blue: 0.42).opacity(0.42), lineWidth: 0.8)
    }
    .shadow(color: .black.opacity(0.26), radius: 8, y: 6)
  }
}

private struct MiniMetric: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 8.5, weight: .regular))
        .foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.56))
      Text(value)
        .font(.system(size: 12, weight: .regular, design: .monospaced))
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

private struct ActiveEye: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    return path
  }
}
