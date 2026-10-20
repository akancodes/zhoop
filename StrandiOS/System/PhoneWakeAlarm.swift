#if os(iOS)
import Foundation
import SwiftUI
import StrandDesign
#if canImport(AlarmKit)
import AlarmKit
#endif

/// The iPhone half of the wake alarm (fork): a real iOS alarm through AlarmKit (iOS 26+), at the moments the
/// strap alarm is armed for. Opt-in and OFF by default, for a strap whose buzz is not guaranteed (a WHOOP 5/MG
/// arms its firmware alarm only with Protocol probes on, and even then wakes are reported, not promised).
///
/// It follows the strap alarm's settings and nothing else: the time, the weekdays and the per-day overrides
/// that `AppModel.nextSmartAlarmDate` resolves, scheduled as one weekly-repeating alarm per distinct time, so
/// it keeps ringing on the right days with NOOP closed and never needs re-arming. Unlike the backup
/// notification it sounds through silent mode and Focus, which is what AlarmKit exists for.
///
/// An alert with a Stop button and nothing else. A snooze, or any other countdown, is a countdown presentation,
/// and AlarmKit expects a widget extension with a Live Activity for those: without one "the system may
/// unexpectedly dismiss alarms and fail to alert" (Apple, "Scheduling an alarm with AlarmKit"). This build
/// leaves the widget extension out (no App Group, see FORK.md), so it offers no snooze rather than an alarm
/// that might not ring. A plain alert is drawn by the system and needs no extension.
///
/// AlarmKit is linked weak (project.yml), so on an iOS older than 26 the app still launches and none of this
/// is offered.
@MainActor
enum PhoneWakeAlarm {
    /// The Alarms screen's switch. OFF until the wearer turns it on.
    nonisolated static let enabledKey = "alarm.phone.enabled"

    /// Set once anything has been scheduled, so that with the switch off and nothing of ours scheduled this
    /// never touches AlarmKit at all: no read of its state, no prompt, no change.
    private static let scheduledKey = "alarm.phone.scheduled"

    nonisolated static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// True where AlarmKit exists (iOS 26+). The switch is offered only here.
    nonisolated static var isSupported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    enum Permission: Equatable { case unsupported, notDetermined, authorized, denied }

    /// The alarm permission as iOS holds it now. It lives in Settings and can change while NOOP is closed,
    /// so read it fresh rather than keeping a copy.
    static var permission: Permission {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return .authorized
            case .denied: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .denied
            }
        }
        #endif
        return .unsupported
    }

    /// Ask for the alarm permission if it was never asked, and say where it landed. iOS shows its prompt only
    /// once; after that this just reports the answer.
    static func requestPermission() async -> Permission {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            guard AlarmManager.shared.authorizationState == .notDetermined else { return permission }
            _ = try? await AlarmManager.shared.requestAuthorization()
            return permission
        }
        #endif
        return .unsupported
    }

    /// One weekly alarm: a wake time (minutes since local midnight) and the Calendar weekdays (1 = Sun … 7 = Sat)
    /// it rings on.
    struct Slot: Equatable, Hashable {
        let minutes: Int
        let weekdays: Set<Int>
    }

    /// The weekly alarms that ring at exactly the moments `AppModel.nextSmartAlarmDate` resolves, one per
    /// distinct time.
    ///
    /// The same rules, in the same order: an empty weekday set means every day, a non-empty one that holds no
    /// valid day means no alarm at all, an override counts only on a day 1…7 with a minute in [0, 1440) and
    /// only on a day that rings, and a day without one rings at `minutes`. Kept pure so the two can be checked
    /// against each other off-device.
    nonisolated static func slots(minutes: Int, weekdays: Set<Int>, overrides: [Int: Int]) -> [Slot] {
        let valid = weekdays.filter { (1...7).contains($0) }
        if !weekdays.isEmpty && valid.isEmpty { return [] }
        let cleanOverrides = overrides.filter { (1...7).contains($0.key) && (0..<24 * 60).contains($0.value) }
        var daysByTime: [Int: Set<Int>] = [:]
        for day in weekdays.isEmpty ? Set(1...7) : valid {
            let wake = cleanOverrides[day] ?? minutes
            // `nextSmartAlarmDate` finds no fire time for an hour past 23 either, so neither rings.
            guard (0..<24 * 60).contains(wake) else { continue }
            daysByTime[wake, default: []].insert(day)
        }
        return daysByTime.keys.sorted().map { Slot(minutes: $0, weekdays: daysByTime[$0] ?? []) }
    }

    /// A stable alarm id for a slot, so a re-sync recognises the alarms it already scheduled and replaces only
    /// what changed, instead of cancelling and rescheduling everything on every call. A version-8 UUID: the
    /// bytes "NOOPWK", the time and a weekday bit mask.
    nonisolated static func alarmID(for slot: Slot) -> UUID {
        let mask = slot.weekdays.filter { (1...7).contains($0) }.reduce(UInt8(0)) { $0 | UInt8(1 << $1) }
        let minutes = UInt16(clamping: slot.minutes)
        return UUID(uuid: (0x4E, 0x4F, 0x4F, 0x50, 0x57, 0x4B, 0x80, 0x00,
                           0x80, 0x00, UInt8(minutes >> 8), UInt8(minutes & 0xFF), mask, 0x00, 0x00, 0x00))
    }

    /// Bring the scheduled alarms in line with the strap alarm's settings. Called from `AppModel.applySmartAlarm`
    /// on every change and re-arm, so it is idempotent: alarms that already match stay as they are.
    ///
    /// `alarmOn` is the strap alarm's own switch. Off, or with this switch off, every alarm of ours goes.
    static func sync(alarmOn: Bool, minutes: Int, weekdays: Set<Int>, overrides: [Int: Int],
                     log: @escaping (String) -> Void) {
        let wanted = alarmOn && isEnabled
        let defaults = UserDefaults.standard
        guard wanted || defaults.bool(forKey: scheduledKey) else { return }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let wantedSlots = wanted ? Self.slots(minutes: minutes, weekdays: weekdays, overrides: overrides) : []
            // One reconcile at a time, in call order: each reads what is scheduled now, so the last call
            // decides the result even when several land within one schedule's await.
            let previous = pending
            pending = Task { @MainActor in
                await previous?.value
                await reconcile(wantedSlots, log: log)
            }
        }
        #endif
    }

    /// The reconcile in flight, which the next `sync` waits behind.
    private static var pending: Task<Void, Never>?

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func reconcile(_ slots: [Slot], log: (String) -> Void) async {
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else {
            // Denied (or never granted): nothing can be scheduled, and iOS keeps none of ours either.
            if !slots.isEmpty { log("Phone alarm: NOT set (alarms are not allowed for NOOP in Settings)") }
            return
        }
        let scheduled: [Alarm]
        do {
            scheduled = try manager.alarms
        } catch {
            log("Phone alarm: could not read the scheduled alarms (\(error.localizedDescription))")
            return
        }
        let wantedByID = Dictionary(slots.map { (alarmID(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        var failed = false
        for alarm in scheduled where wantedByID[alarm.id] == nil {
            do {
                try manager.cancel(id: alarm.id)
            } catch {
                failed = true
                log("Phone alarm: could not remove an old alarm (\(error.localizedDescription))")
            }
        }
        let have = Set(scheduled.map(\.id))
        for (id, slot) in wantedByID.sorted(by: { $0.value.minutes < $1.value.minutes }) where !have.contains(id) {
            do {
                _ = try await manager.schedule(id: id, configuration: configuration(for: slot))
                UserDefaults.standard.set(true, forKey: scheduledKey)
                log("Phone alarm: set for \(describe(slot))")
            } catch {
                failed = true
                log("Phone alarm: NOT set for \(describe(slot)) (\(error.localizedDescription))")
            }
        }
        // Nothing of ours left and nothing wanted: back to never touching AlarmKit until switched on again.
        if slots.isEmpty && !failed { UserDefaults.standard.set(false, forKey: scheduledKey) }
    }

    @available(iOS 26.0, *)
    private static func configuration(for slot: Slot) -> AlarmManager.AlarmConfiguration<WakeAlarmMetadata> {
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "Wake up")
        } else {
            alert = AlarmPresentation.Alert(title: "Wake up",
                                            stopButton: AlarmButton(text: "Stop", textColor: StrandPalette.accent,
                                                                    systemImageName: "stop.circle"))
        }
        let attributes = AlarmAttributes<WakeAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                            tintColor: StrandPalette.accent)
        let time = Alarm.Schedule.Relative.Time(hour: slot.minutes / 60, minute: slot.minutes % 60)
        let days = slot.weekdays.sorted().compactMap(localeWeekday)
        return .alarm(schedule: .relative(.init(time: time, repeats: .weekly(days))), attributes: attributes)
    }
    #endif

    /// Calendar weekday number (1 = Sun … 7 = Sat) to `Locale.Weekday`.
    private static func localeWeekday(_ day: Int) -> Locale.Weekday? {
        switch day {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    /// "07:30 on days 2,3,4,5,6", for the strap log.
    private static func describe(_ slot: Slot) -> String {
        String(format: "%02d:%02d", slot.minutes / 60, slot.minutes % 60)
            + " on days " + slot.weekdays.sorted().map { String($0) }.joined(separator: ",")
    }
}

#if canImport(AlarmKit)
/// AlarmKit carries app metadata with every alarm; the wake alarm has none to carry.
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {}
#endif
#endif
