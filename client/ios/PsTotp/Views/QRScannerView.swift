import AVFoundation
import PsTotpCore
import SwiftUI

/// Live camera QR scanner. Reports each distinct `otpauth://` code once (see `ScanDebouncer`),
/// and keeps scanning afterwards so an invalid code doesn't strand the user.
struct QRScannerView: View {
    let onCode: (String) -> Void

    private enum Access { case checking, authorized, denied, unavailable }
    @State private var access: Access = .checking

    var body: some View {
        Group {
            switch access {
            case .checking:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .authorized:
                CameraPreview(onCode: onCode)
                    .overlay(ViewfinderFrame())
                    .accessibilityIdentifier("scan.preview")
            case .denied:
                placeholder(
                    symbol: "camera.fill",
                    title: "Camera access is off",
                    detail: "Allow camera access in Settings to scan QR codes.",
                    id: "scan.denied"
                ) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .unavailable:
                placeholder(
                    symbol: "camera.slash",
                    title: "Camera unavailable",
                    detail: "This device has no camera. Use Image, Manual or Paste URI instead.",
                    id: "scan.unavailable"
                ) { EmptyView() }
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task { await resolveAccess() }
    }

    private func resolveAccess() async {
        guard AVCaptureDevice.default(for: .video) != nil else { access = .unavailable; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .authorized
        case .notDetermined:
            access = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        default:
            access = .denied
        }
    }

    private func placeholder<Action: View>(
        symbol: String, title: String, detail: String, id: String, @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(Palette.onSurfaceVariant)
            Text(title).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

private struct ViewfinderFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, dash: [28, 18]))
            .frame(width: 220, height: 220)
            .shadow(color: .black.opacity(0.35), radius: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - AVFoundation bridge

private struct CameraPreview: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> CameraController { CameraController(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attach(to: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: CameraController) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Owns the capture session. Session start/stop happen on a private serial queue (they block);
/// metadata callbacks are delivered on the main queue.
private final class CameraController: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    var onCode: (String) -> Void
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.pstanar.pstotp.camera")
    private var debouncer = ScanDebouncer()
    private var stopped = false

    init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

    func attach(to layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
        queue.async { [self] in
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()
            if !stopped { session.startRunning() }
        }
    }

    func stop() {
        stopped = true
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from _: AVCaptureConnection
    ) {
        for case let code as AVMetadataMachineReadableCodeObject in objects {
            // Only authenticator codes; anything else a camera happens to see is ignored (as on Android).
            guard let value = code.stringValue, value.hasPrefix("otpauth://"),
                  debouncer.shouldHandle(value) else { continue }
            onCode(value)
            return
        }
    }
}
