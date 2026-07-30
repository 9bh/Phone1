import AVFoundation
import SwiftUI
import UIKit

struct QRCodeScannerScreen: View {
    @Environment(\.dismiss) private var dismiss

    let onScan: (ScannedTOTPAccount) -> Void

    @State private var scannerIdentity = UUID()
    @State private var permissionDenied = false
    @State private var scannerError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if permissionDenied {
                permissionDeniedView
            } else {
                QRCodeCameraView(
                    onCode: handleScannedCode,
                    onPermissionDenied: {
                        permissionDenied = true
                    },
                    onFailure: { message in
                        scannerError = message
                    }
                )
                .id(scannerIdentity)
                .ignoresSafeArea()

                scannerOverlay
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("مسح رمز QR")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
            }
            .environment(\.layoutDirection, .leftToRight)

            if let scannerError {
                scannerErrorOverlay(scannerError)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var scannerOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 270, height: 270)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.accentColor.opacity(0.9), lineWidth: 1)
                        .padding(5)
                }

            Text("ضع رمز المصادقة داخل الإطار")
                .font(.body.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55))
                .clipShape(Capsule())

            Text("تتم القراءة محليًا داخل الجهاز ولا تُحفظ صورة الرمز.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Spacer()
        }
        .allowsHitTesting(false)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundColor(.white)

            Text("يلزم السماح باستخدام الكاميرا")
                .font(.title3.bold())
                .foregroundColor(.white)

            Text("افتح إعدادات VaultX وفعّل إذن الكاميرا لمسح رموز المصادقة.")
                .font(.body)
                .foregroundColor(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("فتح الإعدادات") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)

            Button("إلغاء") {
                dismiss()
            }
            .foregroundColor(.white)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func scannerErrorOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 18) {
                Text("تعذر قراءة الرمز")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 12) {
                    Button("إلغاء") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("إعادة المحاولة") {
                        scannerError = nil
                        scannerIdentity = UUID()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 30)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }

    private func handleScannedCode(_ value: String) {
        do {
            let parsed = try TOTPQRCodeParser.parse(value)
            onScan(parsed)
            dismiss()
        } catch let error as TOTPQRCodeParserError {
            scannerError = error.arabicMessage
        } catch {
            scannerError = "تعذر تفسير بيانات رمز QR."
        }
    }
}

private struct QRCodeCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onPermissionDenied: () -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeCameraViewController {
        QRCodeCameraViewController(
            onCode: onCode,
            onPermissionDenied: onPermissionDenied,
            onFailure: onFailure
        )
    }

    func updateUIViewController(_ uiViewController: QRCodeCameraViewController, context: Context) {}
}

private final class QRCodeCameraViewController: UIViewController,
    AVCaptureMetadataOutputObjectsDelegate
{
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.smartsphere.VaultX.qr-session")
    private let metadataQueue = DispatchQueue(label: "com.smartsphere.VaultX.qr-metadata")

    private let onCode: (String) -> Void
    private let onPermissionDenied: () -> Void
    private let onFailure: (String) -> Void

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didEmitCode = false
    private var isConfigured = false
    private var isVisible = false

    init(
        onCode: @escaping (String) -> Void,
        onPermissionDenied: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        self.onCode = onCode
        self.onPermissionDenied = onPermissionDenied
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        prepareCamera()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        startSessionIfReady()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    if granted {
                        self.configureAndStartSession()
                    } else {
                        self.onPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            onPermissionDenied()
        @unknown default:
            onPermissionDenied()
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            guard let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ) ?? AVCaptureDevice.default(for: .video) else {
                self.captureSession.commitConfiguration()
                self.reportFailure("لم يتم العثور على كاميرا متاحة على هذا الجهاز.")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.captureSession.canAddInput(input) else {
                    self.captureSession.commitConfiguration()
                    self.reportFailure("تعذر تشغيل إدخال الكاميرا.")
                    return
                }
                self.captureSession.addInput(input)
            } catch {
                self.captureSession.commitConfiguration()
                self.reportFailure("تعذر الوصول إلى الكاميرا.")
                return
            }

            let output = AVCaptureMetadataOutput()
            guard self.captureSession.canAddOutput(output) else {
                self.captureSession.commitConfiguration()
                self.reportFailure("تعذر تشغيل قارئ رمز QR.")
                return
            }

            self.captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: self.metadataQueue)

            guard output.availableMetadataObjectTypes.contains(.qr) else {
                self.captureSession.commitConfiguration()
                self.reportFailure("قراءة رمز QR غير متاحة على هذا الجهاز.")
                return
            }

            output.metadataObjectTypes = [.qr]
            self.captureSession.commitConfiguration()

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = self.view.bounds
                self.view.layer.insertSublayer(previewLayer, at: 0)
                self.previewLayer = previewLayer
                self.isConfigured = true
                self.startSessionIfReady()
            }
        }
    }

    private func startSessionIfReady() {
        guard isConfigured, isVisible else { return }

        sessionQueue.async { [captureSession] in
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmitCode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              !value.isEmpty else {
            return
        }

        didEmitCode = true
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }

        DispatchQueue.main.async { [onCode] in
            onCode(value)
        }
    }

    private func reportFailure(_ message: String) {
        DispatchQueue.main.async { [onFailure] in
            onFailure(message)
        }
    }
}
