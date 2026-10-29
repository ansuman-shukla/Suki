import Foundation

enum MeetingAutoStopCoreTests {
    static func run() {
        thresholdsMatchTheAgreedLimits()
        callEndsThirtySecondsAfterLastCallAppLetsGo()
        graceCountsFromFirstQuietPoll()
        callThatComesBackWithinGraceKeepsRecording()
        switchingCallAppsIsNotAnEnd()
        meetingWithoutCallAppNeverEndsAsCall()
        silenceCountsFromRecordingStartBeforeAnyoneSpeaks()
        speechResetsSilence()
        silenceAppliesDuringACall()
        hardCapStopsEvenWhileTalking()
        hardCapWinsOverOtherReasons()
        callEndedWinsOverSilence()
        noticesNameTheReason()
    }

    private static let call: Set<String> = ["Google Chrome"]

    private static func thresholdsMatchTheAgreedLimits() {
        TestSupport.expectEqual(MeetingAutoStopPolicy.callEndedGraceSeconds, 30)
        TestSupport.expectEqual(MeetingAutoStopPolicy.silenceSeconds, 600)
        TestSupport.expectEqual(MeetingAutoStopPolicy.maxDurationSeconds, 14_400)
    }

    private static func callEndsThirtySecondsAfterLastCallAppLetsGo() {
        var policy = MeetingAutoStopPolicy()
        TestSupport.expect(!policy.sawCallApp, "A new recording has seen no call yet")
        TestSupport.expectEqual(policy.update(elapsed: 0, callApps: call, lastSpeechTime: nil), nil)
        TestSupport.expectEqual(policy.update(elapsed: 10, callApps: call, lastSpeechTime: 9), nil)
        TestSupport.expect(policy.sawCallApp, "A call app using the mic is remembered")
        TestSupport.expectEqual(policy.update(elapsed: 12, callApps: [], lastSpeechTime: 11), nil)
        TestSupport.expectEqual(policy.update(elapsed: 41, callApps: [], lastSpeechTime: 40), nil)
        TestSupport.expectEqual(policy.update(elapsed: 42, callApps: [], lastSpeechTime: 41), .callEnded)
    }

    private static func graceCountsFromFirstQuietPoll() {
        var policy = MeetingAutoStopPolicy()
        _ = policy.update(elapsed: 0, callApps: call, lastSpeechTime: nil)
        for elapsed in stride(from: 2.0, through: 30, by: 2) {
            TestSupport.expectEqual(policy.update(elapsed: elapsed, callApps: [], lastSpeechTime: elapsed), nil)
        }
        TestSupport.expectEqual(policy.update(elapsed: 31.5, callApps: [], lastSpeechTime: 31), nil)
        TestSupport.expectEqual(policy.update(elapsed: 32, callApps: [], lastSpeechTime: 31), .callEnded)
    }

    private static func callThatComesBackWithinGraceKeepsRecording() {
        var policy = MeetingAutoStopPolicy()
        _ = policy.update(elapsed: 0, callApps: call, lastSpeechTime: nil)
        TestSupport.expectEqual(policy.update(elapsed: 10, callApps: [], lastSpeechTime: 10), nil)
        TestSupport.expectEqual(policy.update(elapsed: 39, callApps: [], lastSpeechTime: 39), nil)
        TestSupport.expectEqual(policy.update(elapsed: 39.5, callApps: call, lastSpeechTime: 39), nil)
        TestSupport.expectEqual(policy.update(elapsed: 50, callApps: [], lastSpeechTime: 50), nil)
        TestSupport.expectEqual(policy.update(elapsed: 79, callApps: [], lastSpeechTime: 79), nil)
        TestSupport.expectEqual(policy.update(elapsed: 80, callApps: [], lastSpeechTime: 80), .callEnded)
    }

    private static func switchingCallAppsIsNotAnEnd() {
        var policy = MeetingAutoStopPolicy()
        _ = policy.update(elapsed: 0, callApps: ["Zoom"], lastSpeechTime: nil)
        TestSupport.expectEqual(policy.update(elapsed: 20, callApps: ["Zoom", "Slack"], lastSpeechTime: 20), nil)
        TestSupport.expectEqual(policy.update(elapsed: 60, callApps: ["Slack"], lastSpeechTime: 60), nil)
        TestSupport.expectEqual(policy.update(elapsed: 100, callApps: ["Slack"], lastSpeechTime: 100), nil)
    }

    private static func meetingWithoutCallAppNeverEndsAsCall() {
        var policy = MeetingAutoStopPolicy()
        for elapsed in [0, 2, 31, 60, 300, 3_600] as [TimeInterval] {
            TestSupport.expectEqual(policy.update(elapsed: elapsed, callApps: [], lastSpeechTime: elapsed), nil)
        }
        TestSupport.expect(!policy.sawCallApp, "No call app was ever seen")
    }

    private static func silenceCountsFromRecordingStartBeforeAnyoneSpeaks() {
        var policy = MeetingAutoStopPolicy()
        TestSupport.expectEqual(policy.update(elapsed: 2, callApps: [], lastSpeechTime: nil), nil)
        TestSupport.expectEqual(policy.update(elapsed: 599, callApps: [], lastSpeechTime: nil), nil)
        TestSupport.expectEqual(policy.update(elapsed: 600, callApps: [], lastSpeechTime: nil), .silence)
    }

    private static func speechResetsSilence() {
        var policy = MeetingAutoStopPolicy()
        TestSupport.expectEqual(policy.update(elapsed: 600, callApps: [], lastSpeechTime: 0.5), nil)
        TestSupport.expectEqual(policy.update(elapsed: 699, callApps: [], lastSpeechTime: 100), nil)
        TestSupport.expectEqual(policy.update(elapsed: 700, callApps: [], lastSpeechTime: 100), .silence)
    }

    private static func silenceAppliesDuringACall() {
        var policy = MeetingAutoStopPolicy()
        TestSupport.expectEqual(policy.update(elapsed: 650, callApps: call, lastSpeechTime: 50.5), nil)
        TestSupport.expectEqual(policy.update(elapsed: 650, callApps: call, lastSpeechTime: 50), .silence)
    }

    private static func hardCapStopsEvenWhileTalking() {
        var policy = MeetingAutoStopPolicy()
        TestSupport.expectEqual(policy.update(elapsed: 14_399, callApps: call, lastSpeechTime: 14_398), nil)
        TestSupport.expectEqual(policy.update(elapsed: 14_400, callApps: call, lastSpeechTime: 14_399), .maxDuration)
    }

    private static func hardCapWinsOverOtherReasons() {
        var policy = MeetingAutoStopPolicy()
        _ = policy.update(elapsed: 0, callApps: call, lastSpeechTime: nil)
        _ = policy.update(elapsed: 2, callApps: [], lastSpeechTime: nil)
        TestSupport.expectEqual(policy.update(elapsed: 14_400, callApps: [], lastSpeechTime: nil), .maxDuration)
    }

    private static func callEndedWinsOverSilence() {
        var policy = MeetingAutoStopPolicy()
        _ = policy.update(elapsed: 0, callApps: call, lastSpeechTime: nil)
        _ = policy.update(elapsed: 2, callApps: [], lastSpeechTime: nil)
        TestSupport.expectEqual(policy.update(elapsed: 700, callApps: [], lastSpeechTime: nil), .callEnded)
    }

    private static func noticesNameTheReason() {
        TestSupport.expectEqual(MeetingAutoStopReason.allCases.map(\.notice), [
            "Meeting saved: call ended",
            "Meeting saved: no one talking",
            "Meeting saved: Mac went to sleep",
            "Meeting saved: 4 hour limit",
        ])
    }
}
