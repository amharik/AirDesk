import UIKit

enum DeviceContext {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var name: String {
        isPad ? "iPad" : "iPhone"
    }

    static var symbolName: String {
        isPad ? "ipad" : "iphone.gen3"
    }
}
