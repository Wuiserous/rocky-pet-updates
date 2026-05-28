import AppKit
import SwiftUI

struct PetDragSurface: NSViewRepresentable {
    let onClick: () -> Void
    let onSelectState: (PetState) -> Void
    let onSelectPet: (PetCharacter) -> Void
    let onOpenControlCenter: () -> Void
    let onDragBegan: () -> Void
    let onDragStateChanged: (PetState) -> Void
    let onDragEnded: () -> Void
    var petCharacter: PetCharacter = .golemMale
    var currentState: PetState = .idle

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onClick = onClick
        view.onSelectState = onSelectState
        view.onSelectPet = onSelectPet
        view.onOpenControlCenter = onOpenControlCenter
        view.onDragBegan = onDragBegan
        view.onDragStateChanged = onDragStateChanged
        view.onDragEnded = onDragEnded
        view.petCharacter = petCharacter
        view.currentState = currentState
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onClick = onClick
        nsView.onSelectState = onSelectState
        nsView.onSelectPet = onSelectPet
        nsView.onOpenControlCenter = onOpenControlCenter
        nsView.onDragBegan = onDragBegan
        nsView.onDragStateChanged = onDragStateChanged
        nsView.onDragEnded = onDragEnded
        nsView.petCharacter = petCharacter
        nsView.currentState = currentState
    }
}

final class DragView: NSView {
    var onClick: (() -> Void)?
    var onSelectState: ((PetState) -> Void)?
    var onSelectPet: ((PetCharacter) -> Void)?
    var onOpenControlCenter: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragStateChanged: ((PetState) -> Void)?
    var onDragEnded: (() -> Void)?
    var petCharacter: PetCharacter = .golemMale
    var currentState: PetState = .idle

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
            if !didDrag {
                onDragBegan?()
            }
            didDrag = true
        }

        if abs(deltaX) > 4 {
            let dragState: PetState = deltaX > 0 ? .walkingRight : .walkingLeft
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

        let petMenu = NSMenu()
        for pet in PetCharacter.allCases {
            let item = NSMenuItem(
                title: pet.title,
                action: #selector(selectPet(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = pet.rawValue
            item.state = pet == petCharacter ? .on : .off
            petMenu.addItem(item)
        }

        let petItem = NSMenuItem(title: "Pets", action: nil, keyEquivalent: "")
        menu.setSubmenu(petMenu, for: petItem)
        menu.addItem(petItem)

        let expressionMenu = NSMenu()

        for state in petCharacter.availableStates {
            let item = NSMenuItem(
                title: state.title,
                action: #selector(selectState(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = state.rawValue
            item.state = state == currentState ? .on : .off
            expressionMenu.addItem(item)
        }

        let expressionItem = NSMenuItem(title: "Expressions", action: nil, keyEquivalent: "")
        menu.setSubmenu(expressionMenu, for: expressionItem)
        menu.addItem(expressionItem)

        menu.addItem(.separator())

        let controlCenterItem = NSMenuItem(
            title: "Open Control Center",
            action: #selector(openControlCenter),
            keyEquivalent: ""
        )
        controlCenterItem.target = self
        menu.addItem(controlCenterItem)

        let quitItem = NSMenuItem(
            title: "Quit Rocky",
            action: #selector(quitRocky),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

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

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let pet = PetCharacter(rawValue: rawValue)
        else {
            return
        }

        petCharacter = pet
        onSelectPet?(pet)
    }

    @objc private func openControlCenter() {
        onOpenControlCenter?()
    }

    @objc private func quitRocky() {
        NSApp.terminate(nil)
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
    static let rockyOpenControlCenter = Notification.Name("rockyOpenControlCenter")
}
