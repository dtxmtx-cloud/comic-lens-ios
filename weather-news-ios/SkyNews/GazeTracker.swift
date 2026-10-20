import ARKit
import AVFoundation
import Combine
import Foundation
import simd

enum GazeStatus: Equatable {
    case off
    case unsupported
    case permissionDenied
    case starting
    case watching
    case away
    case unavailable

    var label: String {
        switch self {
        case .off: return "視線連動オフ"
        case .unsupported: return "視線非対応・通常再生"
        case .permissionDenied: return "カメラ未許可・通常再生"
        case .starting: return "視線を確認中"
        case .watching: return "画面を見ています"
        case .away: return "視線が外れています"
        case .unavailable: return "視線を取得できません・通常再生"
        }
    }

    var systemImage: String {
        switch self {
        case .watching: return "eye.fill"
        case .away: return "eye.slash.fill"
        case .starting: return "eye"
        case .off: return "eye.slash"
        default: return "exclamationmark.eye"
        }
    }
}

/// A local-only gaze *estimate* using ARKit face tracking. No camera frames,
/// face geometry or gaze coordinates are persisted or sent over the network.
///
/// Scrolling can be stopped explicitly. Unsupported/denied/failing devices
/// revert to normal scrolling rather than becoming permanently blocked.
@MainActor
final class GazeTracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var status: GazeStatus = .off
    @Published private(set) var scrollAllowed = true

    private var session: ARSession?
    private var running = false
    private var generation = 0
    private var candidate: Bool?
    private var candidateSince = Date()
    private var stopDelay: TimeInterval = 0.8
    private var resumeDelay: TimeInterval = 0.5
    private var lastFrameAt = Date()
    private var lastSampledAt = Date.distantPast
    private var watchdog: Timer?

    override init() {
        super.init()
        // ARSession is created only after gaze mode is enabled and supported.
        // Normal news scrolling never instantiates a camera tracking session.
    }

    func configure(enabled: Bool, active: Bool, stopAfter: Double, resumeAfter: Double) {
        stopDelay = max(0.2, min(3.0, stopAfter))
        resumeDelay = max(0.2, min(3.0, resumeAfter))

        if !enabled || !active {
            stopSession()
            status = .off
            scrollAllowed = true
            return
        }
        guard ARFaceTrackingConfiguration.isSupported else {
            stopSession()
            status = .unsupported
            scrollAllowed = true
            return
        }
        if running { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            generation += 1
            let requestGeneration = generation
            status = .starting
            scrollAllowed = false
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == requestGeneration else { return }
                    if granted {
                        self.startSession()
                    } else {
                        self.stopSession()
                        self.status = .permissionDenied
                        self.scrollAllowed = true
                    }
                }
            }
        case .denied, .restricted:
            stopSession()
            status = .permissionDenied
            scrollAllowed = true
        @unknown default:
            stopSession()
            status = .unavailable
            scrollAllowed = true
        }
    }

    private func startSession() {
        guard !running else { return }
        running = true
        candidate = nil
        lastFrameAt = Date()
        status = .starting
        scrollAllowed = false
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        configuration.isLightEstimationEnabled = false
        let newSession = ARSession()
        newSession.delegate = self
        newSession.delegateQueue = DispatchQueue.main
        session = newSession
        lastSampledAt = .distantPast
        newSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkFrames() }
        }
    }

    private func stopSession() {
        generation += 1
        if running { session?.pause() }
        session?.delegate = nil
        session = nil
        running = false
        watchdog?.invalidate()
        watchdog = nil
        candidate = nil
    }

    private func checkFrames() {
        guard running else { return }
        if Date().timeIntervalSince(lastFrameAt) > 2.5 {
            // A session interrupted by a competing camera or iOS error must
            // not silently keep the scroller paused forever.
            stopSession()
            status = .unavailable
            scrollAllowed = true
        }
    }

    private func sample(looking: Bool) {
        guard running else { return }
        let now = Date()
        lastFrameAt = now
        // Limit eye estimation to ~8 samples/second, not camera frame rate.
        guard now.timeIntervalSince(lastSampledAt) >= 0.12 else { return }
        lastSampledAt = now
        if candidate != looking {
            candidate = looking
            candidateSince = now
        }
        let elapsed = now.timeIntervalSince(candidateSince)
        if looking {
            if !scrollAllowed && elapsed >= resumeDelay {
                scrollAllowed = true
                status = .watching
            }
        } else if elapsed >= stopDelay {
            if scrollAllowed { scrollAllowed = false }
            if status != .away { status = .away }
        }
    }

    // ARFaceAnchor.lookAtPoint is in FACE coordinate space, not screen points.
    // Angle-based bounds are an approximation; direct eye contact with the
    // camera is not required. When face tracking is lost, stop after hysteresis.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let face = frame.anchors.compactMap { $0 as? ARFaceAnchor }
            .first(where: { $0.isTracked })
        var isLooking = false
        if let face {
            let point = face.lookAtPoint
            let distance = max(0.12, abs(point.z))
            let horizontal = abs(atan2(point.x, distance))
            let vertical = abs(atan2(point.y, distance))
            // Face orientation is also needed: centered eyes alone should not
            // count as looking at the phone when the head is turned away.
            let faceInCamera = simd_mul(simd_inverse(frame.camera.transform), face.transform)
            let forward = faceInCamera.columns.2
            let facingX = abs(atan2(forward.x, forward.z))
            let facingY = abs(atan2(forward.y, forward.z))
            // atan2(y, -z) can wrap near pi; use the absolute cosine-like ratio.
            let headYaw = atan2(abs(forward.x), max(0.01, abs(forward.z)))
            let headPitch = atan2(abs(forward.y), max(0.01, abs(forward.z)))
            isLooking = horizontal.isFinite && vertical.isFinite
                && facingX.isFinite && facingY.isFinite
                && horizontal < 0.48 && vertical < 0.58
                && headYaw < 0.72 && headPitch < 0.72
        }
        Task { @MainActor [weak self] in
            self?.sample(looking: isLooking)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopSession()
            self.status = .unavailable
            self.scrollAllowed = true
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopSession()
            self.status = .unavailable
            self.scrollAllowed = true
        }
    }
}