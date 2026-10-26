import SwiftUI
import UIKit

final class AirCursorUIView: UIView {
    var onAction: ((CursorAction) -> Void)?
    var showsHints = true {
        didSet { hintLabel.isHidden = !showsHints || state == .dragging || state == .scrolling }
    }

    private enum TrackingState {
        case idle
        case pending
        case moving
        case dragArmed
        case dragging
        case scrolling
    }

    private var state: TrackingState = .idle
    private var singleTouch: UITouch?
    private var secondaryTouch: UITouch?
    private var startPoint: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var lastMoveTime: TimeInterval = 0
    private var movedDistance: CGFloat = 0
    private var lastTapTime: TimeInterval = -1
    private var lastTapPoint: CGPoint = .zero
    private var scrollStartCentroid: CGPoint = .zero
    private var scrollLastCentroid: CGPoint = .zero
    private var scrollDistance: CGFloat = 0
    private var longPressTimer: Timer?
    private var lastScrollFeedback: TimeInterval = 0
    private var scrollHideTask: Task<Void, Never>?

    private let tapSlop: CGFloat = 8
    private let dragArmDelay: TimeInterval = 0.32
    private let doubleTapInterval: TimeInterval = 0.34

    private let glowLayer = CALayer()
    private let hintLabel = UILabel()
    private let dragPill = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let dragLabel = UILabel()
    private let scrollIndicator = UIView()
    private let scrollIndicatorFill = UIView()
    private let rippleLayer = CAShapeLayer()
    private let centerDot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isAccessibilityElement = true
        accessibilityLabel = "Air Cursor touchpad"
        accessibilityHint = "Drag to move the pointer. Tap to click. Two-finger drag to scroll. Long press and drag to drag."
        accessibilityTraits = [.allowsDirectInteraction]

        glowLayer.cornerRadius = 30
        glowLayer.borderWidth = 1.4
        glowLayer.borderColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 0).cgColor
        glowLayer.shadowColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 1).cgColor
        glowLayer.shadowOpacity = 0
        glowLayer.shadowRadius = 28
        layer.addSublayer(glowLayer)

        hintLabel.text = "TAP  ·  DRAG  ·  SCROLL"
        hintLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.28)
        hintLabel.textAlignment = .center
        hintLabel.isUserInteractionEnabled = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        dragLabel.text = "DRAG"
        dragLabel.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        dragLabel.textColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 1)
        dragLabel.translatesAutoresizingMaskIntoConstraints = false
        dragPill.layer.cornerRadius = 12
        dragPill.clipsToBounds = true
        dragPill.alpha = 0
        dragPill.isUserInteractionEnabled = false
        dragPill.translatesAutoresizingMaskIntoConstraints = false
        dragPill.contentView.addSubview(dragLabel)
        addSubview(dragPill)

        centerDot.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        centerDot.layer.cornerRadius = 2
        centerDot.isUserInteractionEnabled = false
        centerDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerDot)

        scrollIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        scrollIndicator.layer.cornerRadius = 2.5
        scrollIndicator.alpha = 0
        scrollIndicator.isUserInteractionEnabled = false
        scrollIndicator.translatesAutoresizingMaskIntoConstraints = false
        scrollIndicatorFill.backgroundColor = UIColor.white.withAlphaComponent(0.52)
        scrollIndicatorFill.layer.cornerRadius = 1.5
        scrollIndicatorFill.translatesAutoresizingMaskIntoConstraints = false
        scrollIndicator.addSubview(scrollIndicatorFill)
        addSubview(scrollIndicator)

        rippleLayer.fillColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 0.13).cgColor
        rippleLayer.strokeColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 0.42).cgColor
        rippleLayer.lineWidth = 1
        rippleLayer.opacity = 0
        layer.addSublayer(rippleLayer)

        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            dragPill.centerXAnchor.constraint(equalTo: centerXAnchor),
            dragPill.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            dragPill.heightAnchor.constraint(equalToConstant: 24),
            dragLabel.leadingAnchor.constraint(equalTo: dragPill.contentView.leadingAnchor, constant: 11),
            dragLabel.trailingAnchor.constraint(equalTo: dragPill.contentView.trailingAnchor, constant: -11),
            dragLabel.centerYAnchor.constraint(equalTo: dragPill.contentView.centerYAnchor),
            centerDot.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerDot.widthAnchor.constraint(equalToConstant: 4),
            centerDot.heightAnchor.constraint(equalToConstant: 4),
            scrollIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scrollIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            scrollIndicator.widthAnchor.constraint(equalToConstant: 5),
            scrollIndicator.heightAnchor.constraint(equalToConstant: 120),
            scrollIndicatorFill.leadingAnchor.constraint(equalTo: scrollIndicator.leadingAnchor),
            scrollIndicatorFill.trailingAnchor.constraint(equalTo: scrollIndicator.trailingAnchor),
            scrollIndicatorFill.heightAnchor.constraint(equalToConstant: 34),
            scrollIndicatorFill.centerYAnchor.constraint(equalTo: scrollIndicator.centerYAnchor)
        ])
    }

    deinit {
        longPressTimer?.invalidate()
        scrollHideTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.frame = bounds
        rippleLayer.frame = bounds
        CATransaction.commit()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let all = event?.allTouches ?? touches
        let now = CACurrentMediaTime()

        if all.count >= 2 {
            beginScrolling(all: all, now: now)
            return
        }

        guard let touch = touches.first else { return }
        singleTouch = touch
        secondaryTouch = nil
        startPoint = touch.location(in: self)
        lastPoint = startPoint
        startTime = now
        lastMoveTime = now
        movedDistance = 0
        state = .pending
        setHintsHidden(true)
        scheduleDragArm()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        let all = event?.allTouches ?? touches
        let now = CACurrentMediaTime()

        if all.count >= 2 {
            if state != .scrolling {
                beginScrolling(all: all, now: now)
            }
            updateScrolling(all: all, now: now)
            return
        }

        guard let touch = singleTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        let step = hypot(dx, dy)
        movedDistance += step
        lastPoint = point
        lastMoveTime = now

        switch state {
        case .pending:
            if movedDistance > tapSlop {
                if now - startTime >= dragArmDelay {
                    beginDrag()
                } else {
                    state = .moving
                    cancelDragArm()
                }
                onAction?(.move(dx: dx, dy: dy))
            }
        case .dragArmed:
            if movedDistance > 2.5 {
                beginDrag()
                onAction?(.move(dx: dx, dy: dy))
            }
        case .moving, .dragging:
            onAction?(.move(dx: dx, dy: dy))
        case .scrolling, .idle:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let now = CACurrentMediaTime()
        let remaining = (event?.allTouches ?? []).subtracting(touches)

        if state == .scrolling {
            if remaining.isEmpty {
                endScrolling(now: now)
            }
            return
        }

        guard let touch = singleTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)

        switch state {
        case .pending, .moving:
            if movedDistance < tapSlop, now - startTime < 0.45 {
                handleTap(at: point, now: now)
            }
        case .dragging:
            endDrag()
        case .dragArmed, .idle:
            break
        case .scrolling:
            endScrolling(now: now)
        }

        resetTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if state == .dragging {
            endDrag()
        } else if state == .scrolling {
            endScrolling(now: CACurrentMediaTime())
        }
        onAction?(.cancel)
        resetTracking()
    }

    private func scheduleDragArm() {
        cancelDragArm()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: dragArmDelay, repeats: false) { [weak self] _ in
            guard let self, self.state == .pending, self.movedDistance < self.tapSlop else { return }
            self.state = .dragArmed
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
        }
    }

    private func cancelDragArm() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func beginDrag() {
        guard state != .dragging else { return }
        state = .dragging
        cancelDragArm()
        onAction?(.dragBegan)
        showDragPill()
        UIView.animate(withDuration: 0.18) {
            self.glowLayer.borderColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 0.60).cgColor
            self.glowLayer.shadowOpacity = 0.28
        }
    }

    private func endDrag() {
        guard state == .dragging else { return }
        onAction?(.dragEnded)
        hideDragPill()
        UIView.animate(withDuration: 0.22) {
            self.glowLayer.borderColor = UIColor(red: 0.373, green: 0.890, blue: 0.784, alpha: 0).cgColor
            self.glowLayer.shadowOpacity = 0
        }
    }

    private func beginScrolling(all: Set<UITouch>, now: TimeInterval) {
        let touches = Array(all)
        guard touches.count >= 2 else { return }
        cancelDragArm()
        if state == .dragging {
            onAction?(.dragEnded)
            hideDragPill()
        }
        state = .scrolling
        scrollStartCentroid = centroid(of: touches)
        scrollLastCentroid = scrollStartCentroid
        scrollDistance = 0
        startTime = now
        setHintsHidden(true)
        showScrollIndicator()
    }

    private func updateScrolling(all: Set<UITouch>, now: TimeInterval) {
        let touches = Array(all)
        guard touches.count >= 2 else { return }
        let current = centroid(of: touches)
        let dx = current.x - scrollLastCentroid.x
        let dy = current.y - scrollLastCentroid.y
        scrollDistance += hypot(dx, dy)
        scrollLastCentroid = current

        if abs(dx) > 0.25 || abs(dy) > 0.25 {
            onAction?(.scroll(dx: dx, dy: dy))
            if now - lastScrollFeedback > 0.05 {
                lastScrollFeedback = now
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }

        let offset = max(min(dy / 6, 40), -40)
        UIView.animate(withDuration: 0.12) {
            self.scrollIndicatorFill.transform = CGAffineTransform(translationX: 0, y: offset)
        }
    }

    private func endScrolling(now: TimeInterval) {
        let isTap = now - startTime < 0.34 && scrollDistance < 12
        if isTap {
            onAction?(.rightClick)
            showRipple(at: scrollLastCentroid, strong: true)
        }
        hideScrollIndicator()
        state = .idle
        setHintsHidden(false)
    }

    private func handleTap(at point: CGPoint, now: TimeInterval) {
        let isDouble = now - lastTapTime < doubleTapInterval && hypot(point.x - lastTapPoint.x, point.y - lastTapPoint.y) < 36
        if isDouble {
            onAction?(.click(count: 2))
            lastTapTime = -1
            showRipple(at: point, strong: true)
        } else {
            onAction?(.click(count: 1))
            lastTapTime = now
            lastTapPoint = point
            showRipple(at: point, strong: false)
        }
    }

    private func resetTracking() {
        state = .idle
        singleTouch = nil
        secondaryTouch = nil
        cancelDragArm()
        setHintsHidden(false)
        scrollHideTask?.cancel()
    }

    private func centroid(of touches: [UITouch]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        let points = touches.map { $0.location(in: self) }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func showRipple(at point: CGPoint, strong: Bool) {
        let radius: CGFloat = strong ? 34 : 24
        let path = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        rippleLayer.path = path.cgPath
        rippleLayer.opacity = 1
        rippleLayer.transform = CATransform3DMakeScale(0.5, 0.5, 1)
        rippleLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rippleLayer.bounds = bounds
        rippleLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.5
        animation.toValue = strong ? 1.5 : 1.2
        animation.duration = 0.42
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rippleLayer.add(animation, forKey: "rippleScale")

        UIView.animate(withDuration: 0.42, animations: {
            self.rippleLayer.opacity = 0
        })
    }

    private func showDragPill() {
        hintLabel.isHidden = true
        UIView.animate(withDuration: 0.16) {
            self.dragPill.alpha = 1
        }
    }

    private func hideDragPill() {
        UIView.animate(withDuration: 0.18) {
            self.dragPill.alpha = 0
        } completion: { _ in
            self.hintLabel.isHidden = !self.showsHints
        }
    }

    private func showScrollIndicator() {
        scrollHideTask?.cancel()
        UIView.animate(withDuration: 0.16) {
            self.scrollIndicator.alpha = 1
        }
    }

    private func hideScrollIndicator() {
        scrollHideTask?.cancel()
        scrollHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            UIView.animate(withDuration: 0.25) {
                self?.scrollIndicator.alpha = 0
            }
        }
    }

    private func setHintsHidden(_ hidden: Bool) {
        hintLabel.isHidden = hidden || !showsHints
        centerDot.isHidden = hidden
    }

    override func accessibilityActivate() -> Bool {
        onAction?(.click(count: 1))
        return true
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            [
                UIAccessibilityCustomAction(name: "Left click") { [weak self] _ in
                    self?.onAction?(.click(count: 1))
                    return true
                },
                UIAccessibilityCustomAction(name: "Right click") { [weak self] _ in
                    self?.onAction?(.rightClick)
                    return true
                },
                UIAccessibilityCustomAction(name: "Scroll up") { [weak self] _ in
                    self?.onAction?(.scroll(dx: 0, dy: 80))
                    return true
                },
                UIAccessibilityCustomAction(name: "Scroll down") { [weak self] _ in
                    self?.onAction?(.scroll(dx: 0, dy: -80))
                    return true
                },
                UIAccessibilityCustomAction(name: "Escape") { [weak self] _ in
                    self?.onAction?(.cancel)
                    return true
                }
            ]
        }
        set {}
    }
}

struct AirCursorView: UIViewRepresentable {
    let onAction: (CursorAction) -> Void
    var showsHints: Bool = true

    func makeUIView(context: Context) -> AirCursorUIView {
        let view = AirCursorUIView()
        view.onAction = onAction
        view.showsHints = showsHints
        return view
    }

    func updateUIView(_ uiView: AirCursorUIView, context: Context) {
        uiView.onAction = onAction
        uiView.showsHints = showsHints
    }
}
