import AppKit
import SwiftUI

struct PetDragSurface: NSViewRepresentable {
    let onClick: () -> Void
    let onSelectState: (PetState) -> Void
    let onDragStateChanged: (PetState) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onClick = onClick
        view.onSelectState = onSelectState
        view.onDragStateChanged = onDragStateChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onClick = onClick
        nsView.onSelectState = onSelectState
        nsView.onDragStateChanged = onDragStateChanged
        nsView.onDragEnded = onDragEnded
    }
}

final class DragView: NSView {
    var onClick: (() -> Void)?
    var onSelectState: ((PetState) -> Void)?
    var onDragStateChanged: ((PetState) -> Void)?
    var onDragEnded: (() -> Void)?

    private var dragStartWindowOrigin: CGPoint?
    private var dragStartMouseLocation: CGPoint?
    private var didDrag = false
    private var activeDragState: PetState?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }

        dragStartWindowOrigin = window.frame.origin
        dragStartMouseLocation = NSEvent.mouseLocation
        didDrag = false
        activeDragState = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let startOrigin = dragStartWindowOrigin,
            let startMouseLocation = dragStartMouseLocation
        else {
            return
        }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - startMouseLocation.x
        let deltaY = currentLocation.y - startMouseLocation.y

        if abs(deltaX) > 2 || abs(deltaY) > 2 {
            didDrag = true
        }

        if abs(deltaX) > 4 {
            let dragState: PetState = deltaX > 0 ? .movingRight : .movingLeft
            if activeDragState != dragState {
                activeDragState = dragState
                onDragStateChanged?(dragState)
            }
        }

        let origin = clampedOrigin(
            for: window,
            proposedOrigin: CGPoint(
                x: startOrigin.x + deltaX,
                y: startOrigin.y + deltaY
            )
        )

        window.setFrame(
            NSRect(origin: origin, size: window.frame.size),
            display: true
        )
        NotificationCenter.default.post(name: .rockyPetWindowMoved, object: window)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?()
        } else {
            onDragEnded?()
        }

        dragStartWindowOrigin = nil
        dragStartMouseLocation = nil
        didDrag = false
        activeDragState = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        for state in PetState.allCases {
            let item = NSMenuItem(
                title: state.title,
                action: #selector(selectState(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = state.rawValue
            menu.addItem(item)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func selectState(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let state = PetState(rawValue: rawValue)
        else {
            return
        }

        onSelectState?(state)
    }

    private func clampedOrigin(for window: NSWindow, proposedOrigin: CGPoint) -> CGPoint {
        guard let screen = window.screen ?? NSScreen.main else {
            return proposedOrigin
        }

        let petRectInWindow = convert(bounds, to: nil)
        let visibleFrame = screen.visibleFrame

        var origin = proposedOrigin

        let petMinX = origin.x + petRectInWindow.minX
        let petMaxX = origin.x + petRectInWindow.maxX
        let petMinY = origin.y + petRectInWindow.minY
        let petMaxY = origin.y + petRectInWindow.maxY

        if petMinX < visibleFrame.minX {
            origin.x += visibleFrame.minX - petMinX
        } else if petMaxX > visibleFrame.maxX {
            origin.x -= petMaxX - visibleFrame.maxX
        }

        if petMinY < visibleFrame.minY {
            origin.y += visibleFrame.minY - petMinY
        } else if petMaxY > visibleFrame.maxY {
            origin.y -= petMaxY - visibleFrame.maxY
        }

        return origin
    }
}

extension Notification.Name {
    static let rockyPetWindowMoved = Notification.Name("rockyPetWindowMoved")
}
