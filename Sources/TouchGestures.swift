import CoreGraphics
import Foundation

/// Recognizes 13K gestures and reports them. Binding to actions happens in TouchEngine.
/// Unrecognized finger counts (e.g. three) emit nothing.
final class TouchGestures {
    var onGesture: ((TouchGestureKind, GesturePhase, GesturePayload) -> Void)?
    var onOverlay: (([CGPoint]) -> Void)?
    var onHide: (() -> Void)?

    private enum Mode {
        case idle
        case onePending
        case oneSwipe
        case dragArmed
        case dragging
        case twoFinger
        case pinching
        case fourFinger
        case fiveFinger
        case ignore
    }

    private var mode: Mode = .idle
    private var downAt: TimeInterval = 0
    private var origin: CGPoint = .zero
    private var last: CGPoint = .zero
    private var lastFingers: [CGPoint] = []
    private var lastDist: CGFloat = 0
    private var lastRadius: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var vel: CGPoint = .zero
    private var firedDiscrete = false
    private var longPress: DispatchWorkItem?
    private var momentumGen = 0
    private var lastSwipeKind: TouchGestureKind = .oneFingerSwipe

    func reset() {
        cancelLongPress()
        stopMomentum()
        if mode == .dragging {
            emit(.oneFingerLongPressDrag, .ended, point: last)
        }
        mode = .idle
        lastFingers = []
        firedDiscrete = false
        onHide?()
    }

    func ingest(fingers quartz: [CGPoint], now: TimeInterval) {
        if quartz.isEmpty {
            ended(now: now)
            return
        }
        stopMomentum()
        onOverlay?(quartz)
        let c = centroid(quartz)
        let dt = max(0.001, now - lastTime)

        switch quartz.count {
        case 1:
            oneFinger(quartz[0], now: now, dt: dt)
        case 2:
            cancelLongPress()
            twoFinger(quartz, now: now, dt: dt)
        case 4:
            cancelLongPress()
            fourFinger(quartz, now: now, dt: dt)
        case 5, 6, 7, 8, 9, 10:
            cancelLongPress()
            fiveFinger(quartz, now: now)
        default:
            cancelLongPress()
            mode = .ignore
        }

        last = c
        lastFingers = quartz
        lastTime = now
    }

    // MARK: - 1 finger

    private func oneFinger(_ p: CGPoint, now: TimeInterval, dt: TimeInterval) {
        switch mode {
        case .idle, .ignore:
            mode = .onePending
            downAt = now
            origin = p
            last = p
            vel = .zero
            firedDiscrete = false
            scheduleLongPress()

        case .onePending:
            vel = CGPoint(x: (p.x - last.x) / dt, y: (p.y - last.y) / dt)
            if hypot(p.x - origin.x, p.y - origin.y) > 16 {
                cancelLongPress()
                mode = .oneSwipe
                lastSwipeKind = .oneFingerSwipe
                emit(.oneFingerSwipe, .began, point: origin)
                emit(.oneFingerSwipe, .changed, point: p, delta: CGPoint(x: p.x - last.x, y: p.y - last.y))
            }

        case .oneSwipe:
            vel = CGPoint(x: (p.x - last.x) / dt, y: (p.y - last.y) / dt)
            emit(.oneFingerSwipe, .changed, point: p, delta: CGPoint(x: p.x - last.x, y: p.y - last.y))

        case .dragArmed:
            vel = CGPoint(x: (p.x - last.x) / dt, y: (p.y - last.y) / dt)
            if hypot(p.x - origin.x, p.y - origin.y) > 10 {
                mode = .dragging
                emit(.oneFingerLongPressDrag, .began, point: origin)
                emit(.oneFingerLongPressDrag, .changed, point: p, delta: CGPoint(x: p.x - last.x, y: p.y - last.y))
            }

        case .dragging:
            vel = CGPoint(x: (p.x - last.x) / dt, y: (p.y - last.y) / dt)
            emit(.oneFingerLongPressDrag, .changed, point: p, delta: CGPoint(x: p.x - last.x, y: p.y - last.y))

        case .twoFinger, .pinching, .fourFinger, .fiveFinger:
            mode = .oneSwipe
            lastSwipeKind = .oneFingerSwipe
            origin = p
            emit(.oneFingerSwipe, .began, point: p)
        }
    }

    // MARK: - 2 fingers

    private func twoFinger(_ fingers: [CGPoint], now: TimeInterval, dt: TimeInterval) {
        let c = centroid(fingers)
        let d = hypot(fingers[0].x - fingers[1].x, fingers[0].y - fingers[1].y)

        if mode != .twoFinger && mode != .pinching {
            if mode == .dragging { emit(.oneFingerLongPressDrag, .ended, point: last) }
            mode = .twoFinger
            downAt = now
            origin = c
            last = c
            lastDist = d
            vel = .zero
            firedDiscrete = false
            return
        }

        let trans = hypot(c.x - last.x, c.y - last.y)
        let distDelta = d - lastDist
        vel = CGPoint(x: (c.x - last.x) / dt, y: (c.y - last.y) / dt)

        if mode == .twoFinger {
            if abs(distDelta) > 10, abs(distDelta) > trans {
                mode = .pinching
                emit(.pinch, .began, point: c, scale: zoomDelta(distDelta, distance: d))
            } else if trans > 2 {
                lastSwipeKind = .twoFingerSwipe
                emit(.twoFingerSwipe, .changed, point: c, delta: CGPoint(x: c.x - last.x, y: c.y - last.y))
            }
        } else if mode == .pinching {
            if abs(distDelta) > 1 {
                emit(.pinch, .changed, point: c, scale: zoomDelta(distDelta, distance: d))
            } else if trans > 8 {
                mode = .twoFinger
                lastSwipeKind = .twoFingerSwipe
                emit(.twoFingerSwipe, .changed, point: c, delta: CGPoint(x: c.x - last.x, y: c.y - last.y))
            }
        }

        lastDist = d
    }

    // MARK: - 4 fingers

    private func fourFinger(_ fingers: [CGPoint], now: TimeInterval, dt: TimeInterval) {
        let c = centroid(fingers)
        if mode != .fourFinger {
            if mode == .dragging { emit(.oneFingerLongPressDrag, .ended, point: last) }
            mode = .fourFinger
            downAt = now
            origin = c
            last = c
            vel = .zero
            firedDiscrete = false
            return
        }
        vel = CGPoint(x: (c.x - last.x) / dt, y: (c.y - last.y) / dt)
        let dy = c.y - origin.y
        let dx = c.x - origin.x
        if !firedDiscrete, abs(dy) > 40, abs(dy) > abs(dx) * 1.15 {
            firedDiscrete = true
            if dy < 0 {
                emit(.fourFingerSwipeUp, .ended, point: c)
            } else {
                emit(.fourFingerSwipeDown, .ended, point: c)
            }
        }
    }

    // MARK: - 5 fingers pinch-in

    private func fiveFinger(_ fingers: [CGPoint], now: TimeInterval) {
        let c = centroid(fingers)
        let r = radius(fingers, around: c)
        if mode != .fiveFinger {
            if mode == .dragging { emit(.oneFingerLongPressDrag, .ended, point: last) }
            mode = .fiveFinger
            downAt = now
            origin = c
            last = c
            lastRadius = r
            firedDiscrete = false
            return
        }
        if !firedDiscrete, lastRadius > 8, (r < lastRadius * 0.62 || lastRadius - r > 36) {
            firedDiscrete = true
            emit(.fiveFingerPinch, .ended, point: c)
        }
    }

    // MARK: - lift

    private func ended(now: TimeInterval) {
        cancelLongPress()
        let duration = now - downAt
        let dist = hypot(last.x - origin.x, last.y - origin.y)
        let n = lastFingers.count

        switch mode {
        case .onePending:
            if duration < 0.5, dist < 16 {
                emit(.oneFingerTap, .ended, point: origin)
            } else if duration >= 0.45, dist < 16 {
                emit(.oneFingerLongPress, .ended, point: origin)
            }
        case .oneSwipe:
            emit(.oneFingerSwipe, .ended, point: last, delta: vel)
            startMomentum(kind: .oneFingerSwipe)
        case .dragArmed:
            emit(.oneFingerLongPress, .ended, point: origin)
        case .dragging:
            emit(.oneFingerLongPressDrag, .ended, point: last)
        case .twoFinger:
            if duration < 0.4, dist < 22, n >= 2 {
                emit(.twoFingerTap, .ended, point: origin)
            } else {
                emit(.twoFingerSwipe, .ended, point: last, delta: vel)
                startMomentum(kind: .twoFingerSwipe)
            }
        case .pinching:
            emit(.pinch, .ended, point: last)
        case .fourFinger, .fiveFinger, .idle, .ignore:
            break
        }

        mode = .idle
        lastFingers = []
        firedDiscrete = false
        onHide?()
    }

    private func scheduleLongPress() {
        cancelLongPress()
        let origin = self.origin
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .onePending else { return }
            let dist = hypot(self.last.x - origin.x, self.last.y - origin.y)
            guard dist < 16 else { return }
            self.mode = .dragArmed
        }
        longPress = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48, execute: work)
    }

    private func cancelLongPress() {
        longPress?.cancel()
        longPress = nil
    }

    private func startMomentum(kind: TouchGestureKind) {
        var v = vel
        guard hypot(v.x, v.y) > 80 else { return }
        momentumGen += 1
        let gen = momentumGen
        func tick() {
            guard gen == self.momentumGen, self.mode == .idle, hypot(v.x, v.y) > 40 else { return }
            let step: CGFloat = 1.0 / 60.0
            self.emit(kind, .changed, point: self.last, delta: CGPoint(x: v.x * step, y: v.y * step))
            v.x *= 0.92
            v.y *= 0.92
            DispatchQueue.main.asyncAfter(deadline: .now() + step, execute: tick)
        }
        DispatchQueue.main.async(execute: tick)
    }

    private func stopMomentum() {
        momentumGen += 1
    }

    private func emit(
        _ kind: TouchGestureKind,
        _ phase: GesturePhase,
        point: CGPoint,
        delta: CGPoint = .zero,
        scale: CGFloat = 0
    ) {
        onGesture?(kind, phase, GesturePayload(point: point, delta: delta, scaleDelta: scale))
    }

    private func zoomDelta(_ distDelta: CGFloat, distance: CGFloat) -> CGFloat {
        guard distance > 1 else { return 0 }
        return distDelta * 1.2
    }

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        var x: CGFloat = 0, y: CGFloat = 0
        for p in pts { x += p.x; y += p.y }
        let n = CGFloat(max(pts.count, 1))
        return CGPoint(x: x / n, y: y / n)
    }

    private func radius(_ pts: [CGPoint], around c: CGPoint) -> CGFloat {
        guard !pts.isEmpty else { return 0 }
        var s: CGFloat = 0
        for p in pts { s += hypot(p.x - c.x, p.y - c.y) }
        return s / CGFloat(pts.count)
    }
}
