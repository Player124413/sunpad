//! Simulates a mouse drag on the macOS screen at absolute coordinates, which
//! the iOS Simulator turns into a touch drag on the device. Used to verify the
//! SunPad touch controls end-to-end.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 5,
      let x0 = Double(args[1]), let y0 = Double(args[2]),
      let x1 = Double(args[3]), let y1 = Double(args[4]) else {
    print("usage: simdrag <x0> <y0> <x1> <y1>")
    exit(2)
}

let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: type,
            mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

post(.leftMouseDown, CGPoint(x: x0, y: y0))
usleep(120_000)
let steps = 24
for i in 1...steps {
    let t = Double(i) / Double(steps)
    let p = CGPoint(x: x0 + (x1 - x0) * t, y: y0 + (y1 - y0) * t)
    post(.leftMouseDragged, p)
    usleep(25_000)
}
usleep(120_000)
post(.leftMouseUp, CGPoint(x: x1, y: y1))
