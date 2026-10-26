import UIKit

@MainActor
final class Haptics {
    static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private var lastScrollTick: TimeInterval = 0

    func prepare() {
        light.prepare()
        medium.prepare()
        rigid.prepare()
        selection.prepare()
    }

    func tap() {
        light.impactOccurred(intensity: 0.7)
    }

    func click() {
        rigid.impactOccurred(intensity: 0.8)
    }

    func dragStart() {
        medium.impactOccurred(intensity: 0.7)
    }

    func scrollTick() {
        let now = CACurrentMediaTime()
        guard now - lastScrollTick > 0.06 else { return }
        lastScrollTick = now
        selection.selectionChanged()
    }

    func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}
