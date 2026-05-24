//
//  GlobalPushToTalkShortcutMonitor.swift
//  leanring-buddy
//
//  Captures push-to-talk keyboard shortcuts while makesomething is running in the
//  background. Uses a listen-only CGEvent tap so modifier-only shortcuts like
//  ctrl + option behave more like a real system-wide voice tool.
//

import AppKit
import Carbon
import Combine
import CoreGraphics
import Foundation

final class GlobalPushToTalkShortcutMonitor: ObservableObject {
    let shortcutTransitionPublisher = PassthroughSubject<BuddyPushToTalkShortcut.ShortcutTransition, Never>()

    private enum ActiveShortcutSource {
        case eventTap
        case carbonHotKey
    }

    private let eventTapStateLock = NSLock()
    private var eventTapThread: Thread?
    private var eventTapThreadIdentifier: UUID?
    private var eventTapRunLoop: CFRunLoop?
    private var shouldStopEventTapThread = false
    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?
    private var consecutiveDisabledEventCount = 0
    /// Mutated exclusively from the CGEvent tap callback on the event tap
    /// thread. The published mirror below is updated on the main queue.
    private var eventTapThreadIsShortcutCurrentlyPressed = false
    private var activeShortcutSource: ActiveShortcutSource?
    private var carbonFallbackHotKeyRef: EventHotKeyRef?
    private var carbonFallbackEventHandlerRef: EventHandlerRef?
    private let carbonFallbackHotKeySignature: OSType = 0x436C_4B79 // "ClKy"
    private let carbonFallbackHotKeyIdentifier: UInt32 = 1
    /// Published so the overlay can hide immediately on key release without
    /// waiting for the async dictation state pipeline to catch up.
    @Published private(set) var isShortcutCurrentlyPressed = false

    deinit {
        stop()
    }

    func start() {
        registerCarbonFallbackHotKeyIfNeeded()

        eventTapStateLock.lock()
        guard eventTapThread == nil else {
            eventTapStateLock.unlock()
            return
        }
        let newEventTapThreadIdentifier = UUID()
        let newEventTapThread = Thread { [weak self] in
            self?.runEventTapThread(identifier: newEventTapThreadIdentifier)
        }
        newEventTapThread.name = "ClickyPushToTalkEventTap"
        eventTapThread = newEventTapThread
        eventTapThreadIdentifier = newEventTapThreadIdentifier
        shouldStopEventTapThread = false
        eventTapStateLock.unlock()

        newEventTapThread.start()
    }

    func stop() {
        unregisterCarbonFallbackHotKey()
        updatePublishedShortcutPressedState(false)

        eventTapStateLock.lock()
        let runLoopToStop = eventTapRunLoop
        let runLoopSourceToRemove = globalEventTapRunLoopSource
        let eventTapToInvalidate = globalEventTap
        shouldStopEventTapThread = true
        globalEventTapRunLoopSource = nil
        globalEventTap = nil
        eventTapRunLoop = nil
        eventTapThreadIsShortcutCurrentlyPressed = false
        activeShortcutSource = nil
        consecutiveDisabledEventCount = 0
        eventTapStateLock.unlock()

        if let runLoopToStop, let runLoopSourceToRemove {
            CFRunLoopRemoveSource(runLoopToStop, runLoopSourceToRemove, .commonModes)
        }

        if let eventTapToInvalidate {
            CGEvent.tapEnable(tap: eventTapToInvalidate, enable: false)
            CFMachPortInvalidate(eventTapToInvalidate)
        }

        if let runLoopToStop {
            CFRunLoopStop(runLoopToStop)
        }
    }

    func refreshEventTap() {
        updatePublishedShortcutPressedState(false)

        eventTapStateLock.lock()
        eventTapThreadIsShortcutCurrentlyPressed = false
        activeShortcutSource = nil
        consecutiveDisabledEventCount = 0
        let existingEventTap = globalEventTap
        eventTapStateLock.unlock()

        guard let existingEventTap else {
            start()
            return
        }

        guard CFMachPortIsValid(existingEventTap) else {
            stop()
            start()
            return
        }

        CGEvent.tapEnable(tap: existingEventTap, enable: true)
    }

    private func runEventTapThread(identifier: UUID) {
        autoreleasepool {
            let currentRunLoop = CFRunLoopGetCurrent()

            eventTapStateLock.lock()
            eventTapRunLoop = currentRunLoop
            let shouldStopBeforeStarting = shouldStopEventTapThread
            eventTapStateLock.unlock()

            if shouldStopBeforeStarting {
                eventTapStateLock.lock()
                if eventTapThreadIdentifier == identifier {
                    eventTapRunLoop = nil
                    eventTapThread = nil
                    eventTapThreadIdentifier = nil
                    shouldStopEventTapThread = false
                }
                eventTapStateLock.unlock()
                return
            }

            print("🔬 EventTap: dedicated thread started")
            createEventTapOnCurrentRunLoop()
            CFRunLoopRun()
            tearDownEventTapOnCurrentRunLoop()
            updatePublishedShortcutPressedState(false)

            eventTapStateLock.lock()
            if eventTapThreadIdentifier == identifier {
                eventTapRunLoop = nil
                eventTapThread = nil
                eventTapThreadIdentifier = nil
                shouldStopEventTapThread = false
            }
            eventTapThreadIsShortcutCurrentlyPressed = false
            if activeShortcutSource == .eventTap {
                activeShortcutSource = nil
            }
            consecutiveDisabledEventCount = 0
            eventTapStateLock.unlock()

            print("🔬 EventTap: dedicated thread stopped")
        }
    }

    private func createEventTapOnCurrentRunLoop() {
        print("🔬 EventTap: creating event tap on dedicated thread")

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

        eventTapStateLock.lock()
        self.globalEventTap = globalEventTap
        self.globalEventTapRunLoopSource = globalEventTapRunLoopSource
        consecutiveDisabledEventCount = 0
        eventTapThreadIsShortcutCurrentlyPressed = false
        eventTapStateLock.unlock()

        CFRunLoopAddSource(CFRunLoopGetCurrent(), globalEventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: globalEventTap, enable: true)
        print("🔬 EventTap: created ✓ | dedicated runLoopSource attached ✓ | tap enabled ✓")
    }

    private func tearDownEventTapOnCurrentRunLoop() {
        eventTapStateLock.lock()
        let runLoopSourceToRemove = globalEventTapRunLoopSource
        let eventTapToInvalidate = globalEventTap
        globalEventTapRunLoopSource = nil
        globalEventTap = nil
        eventTapThreadIsShortcutCurrentlyPressed = false
        consecutiveDisabledEventCount = 0
        eventTapStateLock.unlock()

        if let runLoopSourceToRemove {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSourceToRemove, .commonModes)
        }

        if let eventTapToInvalidate {
            CGEvent.tapEnable(tap: eventTapToInvalidate, enable: false)
            CFMachPortInvalidate(eventTapToInvalidate)
        }
    }

    private func recreateEventTapOnEventTapThread() {
        print("⌨️ Push-to-talk event tap disabled repeatedly; recreating")
        tearDownEventTapOnCurrentRunLoop()
        createEventTapOnCurrentRunLoop()
    }

    private func updatePublishedShortcutPressedState(_ isPressed: Bool) {
        if Thread.isMainThread {
            self.isShortcutCurrentlyPressed = isPressed
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.isShortcutCurrentlyPressed = isPressed
        }
    }

    private func registerCarbonFallbackHotKeyIfNeeded() {
        eventTapStateLock.lock()
        let isAlreadyRegistered = carbonFallbackHotKeyRef != nil || carbonFallbackEventHandlerRef != nil
        eventTapStateLock.unlock()

        guard !isAlreadyRegistered else { return }

        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        var eventHandlerRef: EventHandlerRef?
        let installStatus = eventTypes.withUnsafeBufferPointer { eventTypesBufferPointer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let event, let userData else { return noErr }
                    let shortcutMonitor = Unmanaged<GlobalPushToTalkShortcutMonitor>
                        .fromOpaque(userData)
                        .takeUnretainedValue()
                    shortcutMonitor.handleCarbonFallbackHotKeyEvent(event)
                    return noErr
                },
                eventTypesBufferPointer.count,
                eventTypesBufferPointer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
        }

        guard installStatus == noErr, let eventHandlerRef else {
            print("⚠️ Carbon fallback hotkey handler registration failed")
            return
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyIdentifier = EventHotKeyID(
            signature: carbonFallbackHotKeySignature,
            id: carbonFallbackHotKeyIdentifier
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyIdentifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr, let hotKeyRef else {
            RemoveEventHandler(eventHandlerRef)
            print("⚠️ Carbon fallback hotkey registration failed")
            return
        }

        eventTapStateLock.lock()
        carbonFallbackEventHandlerRef = eventHandlerRef
        carbonFallbackHotKeyRef = hotKeyRef
        eventTapStateLock.unlock()

        print("⌨️ Carbon fallback hotkey registered")
    }

    private func unregisterCarbonFallbackHotKey() {
        eventTapStateLock.lock()
        let hotKeyRefToUnregister = carbonFallbackHotKeyRef
        let eventHandlerRefToRemove = carbonFallbackEventHandlerRef
        carbonFallbackHotKeyRef = nil
        carbonFallbackEventHandlerRef = nil
        if activeShortcutSource == .carbonHotKey {
            activeShortcutSource = nil
        }
        eventTapStateLock.unlock()

        if let hotKeyRefToUnregister {
            UnregisterEventHotKey(hotKeyRefToUnregister)
        }

        if let eventHandlerRefToRemove {
            RemoveEventHandler(eventHandlerRefToRemove)
        }
    }

    private func handleCarbonFallbackHotKeyEvent(_ event: EventRef) {
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            publishCarbonFallbackTransition(.pressed)
        case UInt32(kEventHotKeyReleased):
            publishCarbonFallbackTransition(.released)
        default:
            break
        }
    }

    private func publishCarbonFallbackTransition(_ shortcutTransition: BuddyPushToTalkShortcut.ShortcutTransition) {
        eventTapStateLock.lock()
        defer { eventTapStateLock.unlock() }

        switch shortcutTransition {
        case .pressed:
            if activeShortcutSource == .eventTap {
                activeShortcutSource = .carbonHotKey
                eventTapThreadIsShortcutCurrentlyPressed = true
                print("⌨️ Carbon fallback hotkey pressed")
                return
            }

            guard activeShortcutSource == nil else { return }
            activeShortcutSource = .carbonHotKey
            eventTapThreadIsShortcutCurrentlyPressed = true
            print("⌨️ Carbon fallback hotkey pressed")
            publishShortcutTransitionOnMain(.pressed, shortcutIsCurrentlyPressed: true)
        case .released:
            guard activeShortcutSource == .carbonHotKey else { return }
            activeShortcutSource = nil
            eventTapThreadIsShortcutCurrentlyPressed = false
            print("⌨️ Carbon fallback hotkey released")
            publishShortcutTransitionOnMain(.released, shortcutIsCurrentlyPressed: false)
        case .none:
            break
        }
    }

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        print("⌨️ Push-to-talk raw event: type=\(eventType.rawValue); modifiersRaw=\(event.flags.rawValue); storedPressed=\(eventTapThreadIsShortcutCurrentlyPressed)")

        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            recoverEventTapAfterDisable()
            return Unmanaged.passUnretained(event)
        }

        if eventType == .flagsChanged {
            consecutiveDisabledEventCount = 0
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
            wasShortcutPreviouslyPressed: eventTapThreadIsShortcutCurrentlyPressed
        )

        switch shortcutTransition {
        case .none:
            break
        case .pressed:
            publishShortcutTransition(.pressed, shortcutIsCurrentlyPressed: true, modifierFlagsRawValue: event.flags.rawValue)
        case .released:
            publishShortcutTransition(.released, shortcutIsCurrentlyPressed: false, modifierFlagsRawValue: event.flags.rawValue)
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
        if shortcutIsCurrentlyPressed && !eventTapThreadIsShortcutCurrentlyPressed {
            publishShortcutTransition(.pressed, shortcutIsCurrentlyPressed: true, modifierFlagsRawValue: modifierFlagsRawValue)
            return
        }

        if !shortcutIsCurrentlyPressed && eventTapThreadIsShortcutCurrentlyPressed {
            publishShortcutTransition(.released, shortcutIsCurrentlyPressed: false, modifierFlagsRawValue: modifierFlagsRawValue)
            return
        }

        eventTapThreadIsShortcutCurrentlyPressed = shortcutIsCurrentlyPressed
    }

    private func publishShortcutTransition(
        _ shortcutTransition: BuddyPushToTalkShortcut.ShortcutTransition,
        shortcutIsCurrentlyPressed: Bool,
        modifierFlagsRawValue: UInt64
    ) {
        eventTapStateLock.lock()
        defer { eventTapStateLock.unlock() }

        switch shortcutTransition {
        case .pressed:
            guard activeShortcutSource == nil else { return }
            activeShortcutSource = .eventTap
        case .released:
            guard activeShortcutSource == .eventTap else { return }
            activeShortcutSource = nil
        case .none:
            break
        }

        eventTapThreadIsShortcutCurrentlyPressed = shortcutIsCurrentlyPressed
        let transitionDescription: String
        switch shortcutTransition {
        case .none:
            transitionDescription = "none"
        case .pressed:
            transitionDescription = "pressed"
        case .released:
            transitionDescription = "released"
        }
        print("⌨️ Push-to-talk monitor emitted \(transitionDescription); modifiersRaw=\(modifierFlagsRawValue)")

        publishShortcutTransitionOnMain(shortcutTransition, shortcutIsCurrentlyPressed: shortcutIsCurrentlyPressed)
    }

    private func publishShortcutTransitionOnMain(
        _ shortcutTransition: BuddyPushToTalkShortcut.ShortcutTransition,
        shortcutIsCurrentlyPressed: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isShortcutCurrentlyPressed = shortcutIsCurrentlyPressed
            self?.shortcutTransitionPublisher.send(shortcutTransition)
        }
    }

    private func recoverEventTapAfterDisable() {
        var shouldUpdatePublishedPressedState = false
        var eventTapToReEnable: CFMachPort?
        var shouldRecreateEventTap = false

        eventTapStateLock.lock()
        consecutiveDisabledEventCount += 1
        if activeShortcutSource != .carbonHotKey {
            eventTapThreadIsShortcutCurrentlyPressed = false
            if activeShortcutSource == .eventTap {
                activeShortcutSource = nil
            }
            shouldUpdatePublishedPressedState = true
        }

        if consecutiveDisabledEventCount == 1, let globalEventTap, CFMachPortIsValid(globalEventTap) {
            eventTapToReEnable = globalEventTap
        } else {
            shouldRecreateEventTap = true
        }
        eventTapStateLock.unlock()

        if shouldUpdatePublishedPressedState {
            updatePublishedShortcutPressedState(false)
        }

        if let eventTapToReEnable {
            print("⌨️ Push-to-talk event tap disabled; re-enabling")
            CGEvent.tapEnable(tap: eventTapToReEnable, enable: true)
            return
        }

        if shouldRecreateEventTap {
            recreateEventTapOnEventTapThread()
        }
    }
}
