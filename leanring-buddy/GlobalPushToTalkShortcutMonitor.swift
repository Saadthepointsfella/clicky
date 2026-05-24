//
//  GlobalPushToTalkShortcutMonitor.swift
//  leanring-buddy
//
//  Captures push-to-talk keyboard shortcuts while makesomething is running in the
//  background. Uses a listen-only CGEvent tap so modifier-only shortcuts like
//  ctrl + option behave more like a real system-wide voice tool.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class GlobalPushToTalkShortcutMonitor: ObservableObject {
    let shortcutTransitionPublisher = PassthroughSubject<BuddyPushToTalkShortcut.ShortcutTransition, Never>()

    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?
    /// Mutated exclusively from the CGEvent tap callback, which runs on
    /// `CFRunLoopGetMain()` and therefore always executes on the main thread.
    /// Published so the overlay can hide immediately on key release without
    /// waiting for the async dictation state pipeline to catch up.
    @Published private(set) var isShortcutCurrentlyPressed = false

    deinit {
        stop()
    }

    func start() {
        // If the event tap is already running, don't restart it.
        // Restarting resets isShortcutCurrentlyPressed, which would kill
        // the waveform overlay mid-press when the permission poller calls
        // refreshAllPermissions → start() every few seconds.
        guard globalEventTap == nil else { return }

        let monitoredEventTypes: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let eventMask = monitoredEventTypes.reduce(CGEventMask(0)) { currentMask, eventType in
            currentMask | (CGEventMask(1) << eventType.rawValue)
        }

        let eventTapCallback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let globalPushToTalkShortcutMonitor = Unmanaged<GlobalPushToTalkShortcutMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            return globalPushToTalkShortcutMonitor.handleGlobalEventTap(
                eventType: eventType,
                event: event
            )
        }

        guard let globalEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ Global push-to-talk: couldn't create CGEvent tap")
            return
        }

        guard let globalEventTapRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            globalEventTap,
            0
        ) else {
            CFMachPortInvalidate(globalEventTap)
            print("⚠️ Global push-to-talk: couldn't create event tap run loop source")
            return
        }

        self.globalEventTap = globalEventTap
        self.globalEventTapRunLoopSource = globalEventTapRunLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: globalEventTap, enable: true)
    }

    func stop() {
        isShortcutCurrentlyPressed = false

        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
            self.globalEventTapRunLoopSource = nil
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    func refreshEventTap() {
        isShortcutCurrentlyPressed = false

        guard let globalEventTap else {
            start()
            return
        }

        CGEvent.tapEnable(tap: globalEventTap, enable: true)
    }

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        print("⌨️ Push-to-talk raw event: type=\(eventType.rawValue); modifiersRaw=\(event.flags.rawValue); storedPressed=\(isShortcutCurrentlyPressed)")

        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            print("⌨️ Push-to-talk event tap disabled; re-enabling")
            refreshEventTap()
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if let shortcutIsCurrentlyPressed = shortcutPressedStateFromCurrentEvent(
            eventType: eventType,
            eventKeyCode: eventKeyCode,
            modifierFlagsRawValue: event.flags.rawValue
        ) {
            publishShortcutTransitionIfNeeded(
                shortcutIsCurrentlyPressed: shortcutIsCurrentlyPressed,
                modifierFlagsRawValue: event.flags.rawValue
            )
            return Unmanaged.passUnretained(event)
        }

        let shortcutTransition = BuddyPushToTalkShortcut.shortcutTransition(
            for: eventType,
            keyCode: eventKeyCode,
            modifierFlagsRawValue: event.flags.rawValue,
            wasShortcutPreviouslyPressed: isShortcutCurrentlyPressed
        )

        switch shortcutTransition {
        case .none:
            break
        case .pressed:
            isShortcutCurrentlyPressed = true
            print("⌨️ Push-to-talk monitor emitted pressed; modifiersRaw=\(event.flags.rawValue)")
            shortcutTransitionPublisher.send(.pressed)
        case .released:
            isShortcutCurrentlyPressed = false
            print("⌨️ Push-to-talk monitor emitted released; modifiersRaw=\(event.flags.rawValue)")
            shortcutTransitionPublisher.send(.released)
        }

        return Unmanaged.passUnretained(event)
    }

    private func shortcutPressedStateFromCurrentEvent(
        eventType: CGEventType,
        eventKeyCode: UInt16,
        modifierFlagsRawValue: UInt64
    ) -> Bool? {
        let transitionAssumingShortcutWasReleased = BuddyPushToTalkShortcut.shortcutTransition(
            for: eventType,
            keyCode: eventKeyCode,
            modifierFlagsRawValue: modifierFlagsRawValue,
            wasShortcutPreviouslyPressed: false
        )

        if case .pressed = transitionAssumingShortcutWasReleased {
            return true
        }

        let transitionAssumingShortcutWasPressed = BuddyPushToTalkShortcut.shortcutTransition(
            for: eventType,
            keyCode: eventKeyCode,
            modifierFlagsRawValue: modifierFlagsRawValue,
            wasShortcutPreviouslyPressed: true
        )

        if case .released = transitionAssumingShortcutWasPressed {
            return false
        }

        return nil
    }

    private func publishShortcutTransitionIfNeeded(
        shortcutIsCurrentlyPressed: Bool,
        modifierFlagsRawValue: UInt64
    ) {
        if shortcutIsCurrentlyPressed && !isShortcutCurrentlyPressed {
            isShortcutCurrentlyPressed = true
            print("⌨️ Push-to-talk monitor emitted pressed; modifiersRaw=\(modifierFlagsRawValue)")
            shortcutTransitionPublisher.send(.pressed)
            return
        }

        if !shortcutIsCurrentlyPressed && isShortcutCurrentlyPressed {
            isShortcutCurrentlyPressed = false
            print("⌨️ Push-to-talk monitor emitted released; modifiersRaw=\(modifierFlagsRawValue)")
            shortcutTransitionPublisher.send(.released)
            return
        }

        isShortcutCurrentlyPressed = shortcutIsCurrentlyPressed
    }
}
