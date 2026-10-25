//
//  FaceTracker.swift
//  Resonance
//
//  Hands-free pointer using the TrueDepth front camera (PLAN.pdf Section 13).
//  ARKit gives the face's position and direction about 60 times a second. We use the
//  direction the face points (its forward axis) as the raw input, map it to the screen with
//  a calibrated GazeMapper, and smooth it.
//
//  Privacy: camera frames are never shown, saved or sent anywhere.
//  Needs an iPhone with Face ID. It does not work in the Simulator.
//

import Foundation
import ARKit
import QuartzCore
import Observation

@MainActor
@Observable
final class FaceTracker {
    private(set) var isRunning = false
    private(set) var faceVisible = false
    /// Raw head direction (unitless), used for calibration.
    private(set) var raw: CGPoint?
    /// Smoothed pointer in the Talk board's coordinate space, once calibrated.
    private(set) var pointer: CGPoint?
    /// True while both eyes are closed (for optional blink-to-select).
    private(set) var eyesClosed = false

    var mapper: GazeMapper? = GazeMapper.load()

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    @ObservationIgnored private let session = ARSession()
    @ObservationIgnored private var delegate: FaceSessionDelegate?
    @ObservationIgnored private var smoother = PointerSmoother()

    func start() {
        guard Self.isSupported, !isRunning else { return }
        let proxy = FaceSessionDelegate { [weak self] direction, closed, tracked in
            Task { @MainActor in self?.handle(direction: direction, eyesClosed: closed, tracked: tracked) }
        }
        delegate = proxy
        session.delegate = proxy
        let configuration = ARFaceTrackingConfiguration()
        configuration.worldAlignment = .camera
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        session.pause()
        isRunning = false
        faceVisible = false
        pointer = nil
        smoother.reset()
    }

    func setMapper(_ newMapper: GazeMapper) {
        mapper = newMapper
        newMapper.save()
        smoother.reset()
    }

    /// When the face was last seen. A pointer older than `staleAfter` is not used, so a
    /// lost face or a paused session can never keep choosing the same tile.
    private(set) var lastUpdate: Double = 0
    static let staleAfter = 0.3

    var livePointer: CGPoint? {
        guard let pointer, CACurrentMediaTime() - lastUpdate < Self.staleAfter else { return nil }
        return pointer
    }

    private func handle(direction: CGPoint?, eyesClosed closed: Bool, tracked: Bool) {
        faceVisible = tracked
        guard tracked, let direction else {
            // Face lost: forget the pointer and don't treat the eyes as closed.
            pointer = nil
            eyesClosed = false
            smoother.reset()
            return
        }
        eyesClosed = closed
        lastUpdate = CACurrentMediaTime()
        raw = direction
        if let mapper {
            pointer = smoother.add(mapper.map(direction))
        }
    }
}

/// ARKit calls this object; it forwards what we need to FaceTracker.
private final class FaceSessionDelegate: NSObject, ARSessionDelegate {
    let onUpdate: (CGPoint?, Bool, Bool) -> Void

    init(onUpdate: @escaping (CGPoint?, Bool, Bool) -> Void) {
        self.onUpdate = onUpdate
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        guard face.isTracked else {
            onUpdate(nil, false, false)
            return
        }
        // The face's forward axis (third column of its transform). Turning or tilting the head
        // changes its x and y; calibration turns that into screen coordinates.
        let forward = face.transform.columns.2
        let direction = CGPoint(x: CGFloat(forward.x), y: CGFloat(forward.y))
        let left = face.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let right = face.blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        onUpdate(direction, left > 0.7 && right > 0.7, true)
    }
}
