import SwiftUI
import UIKit

@MainActor
final class MacTrackpadUIView: UIView {
    var onAction: ((CursorAction, CGSize) -> Void)?
    var dragMode = false {
        didSet {
            guard dragMode != oldValue else { return }
            if !dragMode, state == .dragging {
                endDrag()
                resetTracking()
            }
        }
    }
    var showsHints = true {
        didSet {
            guard showsHints != oldValue else { return }
            hintLabel.isHidden = !showsHints || state == .dragging
        }
    }

    private enum TrackingState {
        case idle
        case pending
        case moving
        case scrolling
        case dragging
    }

    private var state: TrackingState = .idle
    private var primaryTouch: UITouch?
    private var startPoint: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var dragLastPoint: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var movedDistance: CGFloat = 0
    private var tapAndHalf = false
    private var lastTapTime: TimeInterval = -1
    private var lastTapPoint: CGPoint = .zero
    private var scrollStartTime: TimeInterval = 0
    private var scrollLastCentroid: CGPoint = .zero
    private var scrollDistance: CGFloat = 0
    private var lastScrollFeedback: TimeInterval = 0

    private let tapSlop: CGFloat = 8
    private let dragThreshold: CGFloat = 4
    private let doubleTapInterval: TimeInterval = 0.34
    private let scrollTapInterval: TimeInterval = 0.34

    private let hintLabel = UILabel()
    private let dragLabel = UILabel()
    private let highlightLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.24)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isAccessibilityElement = true
        accessibilityIdentifier = "MacTrackpad"
        accessibilityLabel = "MacBook trackpad"
        accessibilityHint = "Move one finger to move the pointer. Tap to click. Two fingers scroll or tap to right-click. Three fingers drag. Double-tap and drag to drag."
        accessibilityTraits = [.allowsDirectInteraction]

        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.masksToBounds = true

        highlightLayer.colors = [
            UIColor.white.withAlphaComponent(0.09).cgColor,
            UIColor.white.withAlphaComponent(0.01).cgColor
        ]
        highlightLayer.startPoint = CGPoint(x: 0.5, y: 0)
        highlightLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.insertSublayer(highlightLayer, at: 0)

        hintLabel.text = "1 FINGER MOVE · TAP CLICK · HOLD OR DOUBLE-TAP + DRAG · 2 FINGER SCROLL · 3 FINGER DRAG"
        hintLabel.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.28)
        hintLabel.textAlignment = .center
        hintLabel.isUserInteractionEnabled = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        dragLabel.text = "DRAG"
        dragLabel.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        dragLabel.textColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 1)
        dragLabel.textAlignment = .center
        dragLabel.alpha = 0
        dragLabel.isUserInteractionEnabled = false
        dragLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dragLabel)

        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            dragLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            dragLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.frame = bounds
        CATransaction.commit()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let all = event?.allTouches ?? touches
        let now = CACurrentMediaTime()

        if all.count >= 3 {
            let point = centroid(of: Array(all))
            beginDrag(at: point)
            return
        }

        if all.count == 2 {
            if state == .dragging { return }
            beginScrolling(all: all, now: now)
            return
        }

        guard state != .dragging, state != .scrolling, let touch = touches.first else { return }
        primaryTouch = touch
        startPoint = touch.location(in: self)
        lastPoint = startPoint
        startTime = now
        movedDistance = 0
        if dragMode {
            beginDrag(at: startPoint)
            return
        }
        tapAndHalf = now - lastTapTime < doubleTapInterval
            && hypot(startPoint.x - lastTapPoint.x, startPoint.y - lastTapPoint.y) < 36
        state = .pending
        hintLabel.isHidden = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        let all = event?.allTouches ?? touches
        let now = CACurrentMediaTime()

        if all.count >= 3 {
            if state != .dragging {
                beginDrag(at: centroid(of: Array(all)))
            }
            updateDrag(to: centroid(of: Array(all)))
            return
        }

        if state == .dragging {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            updateDrag(to: touch.location(in: self))
            return
        }

        if all.count == 2 {
            if state != .scrolling {
                beginScrolling(all: all, now: now)
            }
            updateScrolling(all: all, now: now)
            return
        }

        guard let touch = primaryTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)
        let delta = CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y)
        let step = hypot(delta.x, delta.y)
        movedDistance += step
        lastPoint = point

        switch state {
        case .pending:
            if (tapAndHalf || now - startTime > 0.42), movedDistance > dragThreshold {
                beginDrag(at: startPoint)
                onAction?(.move(dx: point.x - startPoint.x, dy: point.y - startPoint.y), bounds.size)
                dragLastPoint = point
            } else if movedDistance > tapSlop {
                state = .moving
                onAction?(.move(dx: delta.x, dy: delta.y), bounds.size)
            }
        case .moving:
            onAction?(.move(dx: delta.x, dy: delta.y), bounds.size)
        case .dragging:
            updateDrag(to: point)
        case .idle, .scrolling:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let now = CACurrentMediaTime()
        let remaining = (event?.allTouches ?? []).subtracting(touches)
        if !remaining.isEmpty {
            if state == .dragging {
                return
            }
            if state == .scrolling {
                return
            }
        }

        switch state {
        case .dragging:
            endDrag()
        case .scrolling:
            endScrolling(now: now)
        case .pending, .moving:
            guard let touch = primaryTouch, touches.contains(touch) else {
                resetTracking()
                return
            }
            let point = touch.location(in: self)
            if movedDistance < tapSlop, now - startTime < 0.45 {
                if tapAndHalf {
                    onAction?(.click(count: 2), bounds.size)
                    lastTapTime = -1
                } else {
                    onAction?(.click(count: 1), bounds.size)
                    lastTapTime = now
                    lastTapPoint = point
                }
            } else {
                lastTapTime = -1
            }
        case .idle:
            break
        }
        resetTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        let remaining = (event?.allTouches ?? []).subtracting(touches)
        if !remaining.isEmpty, state == .dragging || state == .scrolling {
            return
        }
        if state == .dragging {
            endDrag()
        }
        onAction?(.cancel, bounds.size)
        resetTracking()
    }

    private func beginDrag(at point: CGPoint) {
        guard state != .dragging else { return }
        state = .dragging
        dragLastPoint = point
        hintLabel.isHidden = true
        onAction?(.dragBegan, bounds.size)
        if showsHints {
            UIView.animate(withDuration: 0.14) {
                self.dragLabel.alpha = 1
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.55)
    }

    private func updateDrag(to point: CGPoint) {
        let dx = point.x - dragLastPoint.x
        let dy = point.y - dragLastPoint.y
        guard abs(dx) > 0.01 || abs(dy) > 0.01 else { return }
        dragLastPoint = point
        onAction?(.move(dx: dx, dy: dy), bounds.size)
    }

    private func endDrag() {
        guard state == .dragging else { return }
        state = .idle
        onAction?(.dragEnded, bounds.size)
        UIView.animate(withDuration: 0.16) {
            self.dragLabel.alpha = 0
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35)
    }

    private func beginScrolling(all: Set<UITouch>, now: TimeInterval) {
        guard all.count >= 2 else { return }
        state = .scrolling
        scrollStartTime = now
        scrollLastCentroid = centroid(of: Array(all))
        scrollDistance = 0
        hintLabel.isHidden = true
    }

    private func updateScrolling(all: Set<UITouch>, now: TimeInterval) {
        guard all.count >= 2 else { return }
        let current = centroid(of: Array(all))
        let dx = current.x - scrollLastCentroid.x
        let dy = current.y - scrollLastCentroid.y
        scrollDistance += hypot(dx, dy)
        scrollLastCentroid = current
        guard abs(dx) > 0.25 || abs(dy) > 0.25 else { return }
        onAction?(.scroll(dx: dx, dy: dy), bounds.size)
        if now - lastScrollFeedback > 0.06 {
            lastScrollFeedback = now
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func endScrolling(now: TimeInterval) {
        if now - scrollStartTime < scrollTapInterval, scrollDistance < 12 {
            onAction?(.rightClick, bounds.size)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
        }
    }

    private func resetTracking() {
        state = .idle
        primaryTouch = nil
        tapAndHalf = false
        hintLabel.isHidden = !showsHints
        dragLabel.alpha = 0
    }

    private func centroid(of touches: [UITouch]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        let points = touches.map { $0.location(in: self) }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    override func accessibilityActivate() -> Bool {
        onAction?(.click(count: 1), bounds.size)
        return true
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            [
                UIAccessibilityCustomAction(name: "Left click") { [weak self] _ in
                    guard let self else { return false }
                    self.onAction?(.click(count: 1), self.bounds.size)
                    return true
                },
                UIAccessibilityCustomAction(name: "Right click") { [weak self] _ in
                    guard let self else { return false }
                    self.onAction?(.rightClick, self.bounds.size)
                    return true
                },
                UIAccessibilityCustomAction(name: "Scroll up") { [weak self] _ in
                    guard let self else { return false }
                    self.onAction?(.scroll(dx: 0, dy: 80), self.bounds.size)
                    return true
                },
                UIAccessibilityCustomAction(name: "Scroll down") { [weak self] _ in
                    guard let self else { return false }
                    self.onAction?(.scroll(dx: 0, dy: -80), self.bounds.size)
                    return true
                }
            ]
        }
        set {}
    }
}

struct MacTrackpadView: UIViewRepresentable {
    let onAction: (CursorAction, CGSize) -> Void
    var showsHints: Bool = true
    var dragMode: Bool = false

    func makeUIView(context: Context) -> MacTrackpadUIView {
        let view = MacTrackpadUIView()
        view.onAction = onAction
        view.showsHints = showsHints
        view.dragMode = dragMode
        return view
    }

    func updateUIView(_ uiView: MacTrackpadUIView, context: Context) {
        uiView.onAction = onAction
        if uiView.showsHints != showsHints { uiView.showsHints = showsHints }
        if uiView.dragMode != dragMode { uiView.dragMode = dragMode }
    }
}
