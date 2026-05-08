import SwiftUI
import TallyClawCore

public struct TallyClawRootView: View {
  private let snapshot: UsageSnapshot
  @State private var isHovered = false
  @State private var isExpanded = false
  @State private var isPressed = false
  @State private var particles: [TokenParticle] = []
  @State private var lastTodayTokens: Int64?

  public init(snapshot: UsageSnapshot = .preview) {
    self.snapshot = snapshot
  }

  public var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let motion = PetMotion(date: timeline.date, state: petState, isPressed: isPressed)

      ZStack {
        petShadow(motion: motion)

        ForEach(particles) { particle in
          TokenParticleView(particle: particle, color: palette.main)
        }

        VStack(spacing: 8) {
          ZStack {
            if isHovered && !isExpanded {
              HoverDataLeaf(snapshot: snapshot, color: palette.main)
                .offset(x: 78, y: -24)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))
            }

            TallyClawPetBody(
              state: petState,
              palette: palette,
              motion: motion,
              isHovered: isHovered,
              pulseActive: !particles.isEmpty
            )
            .scaleEffect(isPressed ? 1.06 : 1)
            .offset(x: motion.x, y: motion.y)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
          }
          .frame(width: 156, height: 122)
          .contentShape(Rectangle())
          .onHover { hovering in
            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
              isHovered = hovering
            }
          }
          .onTapGesture {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.66)) {
              isPressed = true
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
              isExpanded.toggle()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
              withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                isPressed = false
              }
            }
          }

          if isExpanded {
            ExpandedDataStrip(snapshot: snapshot, color: palette.main)
              .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
          }
        }
      }
      .frame(width: 268, height: isExpanded ? 218 : 148)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(FloatingWindowConfigurator())
      .onAppear {
        lastTodayTokens = snapshot.today.tokens.total
        emitTokenPulse(count: 2)
      }
      .onChange(of: snapshot.today.tokens.total) { _, newValue in
        guard let previous = lastTodayTokens else {
          lastTodayTokens = newValue
          return
        }
        if newValue > previous {
          emitTokenPulse(count: min(5, max(2, Int((newValue - previous) / 10_000) + 1)))
        }
        lastTodayTokens = newValue
      }
    }
  }

  private var petState: PetVisualState {
    switch snapshot.syncHealth {
    case .idle:
      .idle
    case .syncing:
      snapshot.today.tokens.total > 0 ? .highActivity : .idle
    case .warning:
      .warning
    }
  }

  private var palette: PetPalette {
    PetPalette(state: petState)
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
      .frame(width: isPressed ? 44 : 58, height: isPressed ? 9 : 12)
      .blur(radius: 4)
      .offset(y: 49 - motion.y * 0.3)
  }
}

private enum PetVisualState {
  case idle
  case highActivity
  case warning
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
      nextY = sin(time * .pi / 2) * 7
      nextScale = 1 + sin(time * .pi / 2) * 0.018
      nextCoreScale = 1 + sin(time * .pi) * 0.12
      nextEnergyPhase = CGFloat(time.truncatingRemainder(dividingBy: 4) / 4)
    case .highActivity:
      nextX = sin(time * .pi * 1.8) * 1.2
      nextY = sin(time * .pi * 1.35) * 4
      nextScale = 1 + sin(time * .pi * 1.6) * 0.026
      nextCoreScale = 1 + sin(time * .pi * 3.6) * 0.18
      nextEnergyPhase = CGFloat(time.truncatingRemainder(dividingBy: 1.2) / 1.2)
    case .warning:
      nextX = sin(time * .pi * 8) * 1.2
      nextY = sin(time * .pi * 2.2) * 2
      nextScale = 0.99
      nextCoreScale = 1 + sin(time * .pi * 1.8) * 0.08
      nextEnergyPhase = CGFloat(time.truncatingRemainder(dividingBy: 2.2) / 2.2)
    }

    if isPressed {
      nextY -= 12
      nextScale *= 1.04
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
      Circle()
        .stroke(palette.main.opacity(0.18), lineWidth: 2)
        .frame(width: 92, height: 92)
        .scaleEffect(1 + motion.coreScale * 0.08)
        .opacity(state == .highActivity ? 0.9 : 0.45)

      shell
      ears
      face
      eyes
      core
      feet
      energyTicks
    }
    .frame(width: 96, height: 96)
    .scaleEffect(motion.scale)
    .shadow(color: palette.glow, radius: pulseActive ? 20 : 12)
  }

  private var shell: some View {
    RoundedRectangle(cornerRadius: 22, style: .continuous)
      .fill(
        LinearGradient(
          colors: [palette.bodyTop, palette.bodyBottom],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(palette.stroke, lineWidth: 2)
      }
      .frame(width: 74, height: 64)
      .offset(y: 5)
  }

  private var ears: some View {
    ZStack {
      Triangle()
        .fill(palette.stroke)
        .frame(width: 15, height: 14)
        .rotationEffect(.degrees(-8))
        .offset(x: -21, y: -33)
      Triangle()
        .fill(palette.stroke)
        .frame(width: 15, height: 14)
        .rotationEffect(.degrees(8))
        .offset(x: 21, y: -33)
    }
  }

  private var face: some View {
    RoundedRectangle(cornerRadius: 9, style: .continuous)
      .fill(Color(red: 0.01, green: 0.02, blue: 0.06))
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(palette.glow.opacity(0.22))
      }
      .frame(width: 56, height: 30)
      .offset(y: -5)
  }

  private var eyes: some View {
    HStack(spacing: 20) {
      EyeView(state: state, isHovered: isHovered, side: .left, color: palette.main)
      EyeView(state: state, isHovered: isHovered, side: .right, color: palette.main)
    }
    .offset(y: -6)
    .shadow(color: palette.glow, radius: 6)
  }

  private var core: some View {
    ZStack {
      Circle()
        .stroke(palette.main.opacity(state == .highActivity ? 0.58 : 0.25), lineWidth: 1.2)
        .frame(width: 18, height: 18)
        .scaleEffect(state == .highActivity || pulseActive ? motion.coreScale : 0.82)

      Circle()
        .fill(palette.main)
        .frame(width: 7, height: 7)
        .scaleEffect(pulseActive ? 1.35 : motion.coreScale)
    }
    .offset(y: 25)
    .shadow(color: palette.glow, radius: 8)
  }

  private var feet: some View {
    HStack(spacing: 28) {
      Capsule()
        .fill(palette.stroke)
        .frame(width: 11, height: 7)
      Capsule()
        .fill(palette.stroke)
        .frame(width: 11, height: 7)
    }
    .offset(y: 42)
  }

  private var energyTicks: some View {
    HStack(spacing: 5) {
      ForEach(0..<5, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(palette.main.opacity(index == activeTick ? 0.9 : 0.22))
          .frame(width: 4, height: CGFloat(5 + index % 2 * 3))
      }
    }
    .offset(y: 45)
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
  let side: EyeSide
  let color: Color

  var body: some View {
    switch state {
    case .warning:
      WarningEye(side: side)
        .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 10, height: 8)
    case .highActivity:
      ActiveEye()
        .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 12, height: 8)
    case .idle:
      if isHovered {
        Circle()
          .fill(color)
          .frame(width: 6, height: 6)
          .offset(y: -2)
      } else {
        Capsule()
          .fill(color)
          .frame(width: 9, height: 3)
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
        .frame(width: 6, height: 6)
        .shadow(color: color.opacity(0.8), radius: 6)
      Text("\(snapshot.today.tokens.total.formattedCompact.lowercased()) tk")
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(color)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(red: 0.06, green: 0.09, blue: 0.15).opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color(red: 0.25, green: 0.32, blue: 0.43).opacity(0.8), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.24), radius: 12, y: 8)
  }
}

private struct ExpandedDataStrip: View {
  let snapshot: UsageSnapshot
  let color: Color

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Label("Local Sources", systemImage: "externaldrive.connected.to.line.below")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color(red: 0.8, green: 0.84, blue: 0.9))

        Spacer(minLength: 8)

        StatusDot(color: color)
      }

      HStack(spacing: 8) {
        MiniMetric(title: "Today", value: snapshot.today.tokens.total.formattedCompact.lowercased())
        MiniMetric(title: "Week", value: snapshot.week.tokens.total.formattedCompact.lowercased())
      }

      HStack(spacing: 8) {
        Label("Success", systemImage: "waveform.path.ecg")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color(red: 0.58, green: 0.64, blue: 0.72))
        Spacer()
        Text("\(snapshot.week.requests.successRatePercent)%")
          .font(.system(size: 11, weight: .bold, design: .monospaced))
          .foregroundStyle(Color(red: 0.21, green: 0.86, blue: 0.56))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .padding(12)
    .frame(width: 198)
    .background(Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color(red: 0.26, green: 0.32, blue: 0.42).opacity(0.55), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.34), radius: 20, y: 14)
  }
}

private struct MiniMetric: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title.uppercased())
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.56))
      Text(value)
        .font(.system(size: 14, weight: .bold, design: .monospaced))
        .foregroundStyle(Color(red: 0.86, green: 0.9, blue: 0.96))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct StatusDot: View {
  let color: Color
  @State private var pulse = false

  var body: some View {
    ZStack {
      Circle()
        .fill(color.opacity(0.28))
        .frame(width: 18, height: 18)
        .scaleEffect(pulse ? 1.25 : 0.8)
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
    }
    .onAppear {
      withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
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
    Text("+tk")
      .font(.system(size: 10, weight: .black, design: .monospaced))
      .foregroundStyle(color)
      .shadow(color: color.opacity(0.8), radius: 6)
      .offset(x: particle.xOffset, y: isFloating ? -68 : 18)
      .scaleEffect(isFloating ? 1.05 : 0.58)
      .opacity(isFloating ? 0 : 1)
      .onAppear {
        withAnimation(.easeOut(duration: 1.0)) {
          isFloating = true
        }
      }
  }
}

private struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
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
