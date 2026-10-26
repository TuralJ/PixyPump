import SwiftUI
import VisionKit
import AVFoundation

/// Camera barcode scanner screen (pushed inside "Add food"),
/// with a type-the-number fallback.
struct BarcodeScannerScreen: View {
    let onCode: (String) -> Void

    @State private var cameraReady: Bool?
    @State private var typeNumber = false
    @State private var manualCode = ""
    @State private var cameraMissingSetting = false
    /// A code was found: a green frame snaps on before the result opens.
    @State private var snapped = false

    var body: some View {
        Group {
            if typeNumber || cameraReady == false {
                Form {
                    Section {
                        TextField("Barcode number", text: $manualCode)
                            .keyboardType(.numberPad)
                        Button("Look up") { onCode(manualCode.trimmingCharacters(in: .whitespaces)) }
                            .disabled(manualCode.trimmingCharacters(in: .whitespaces).count < 8)
                    } footer: {
                        if cameraMissingSetting {
                            Text("Camera scanning needs the NSCameraUsageDescription setting in Xcode (target → Info tab). Until then, type the number under the barcode.")
                        } else if cameraReady == false {
                            Text("The camera isn't available (simulator, or camera access is off in Settings → \(AppInfo.name) → Camera). Type the number under the barcode instead.")
                        } else {
                            Text("Type the number printed under the barcode.")
                        }
                    }
                    .listRowBackground(Color.ppCard)
                }
                .ppScreen()
            } else if cameraReady == true {
                ZStack(alignment: .bottom) {
                    BarcodeScannerView(onCode: { found($0) })
                        .ignoresSafeArea(edges: .bottom)
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .strokeBorder(Color.ppDone, lineWidth: 5)
                        .frame(width: 270, height: 150)
                        .scaleEffect(snapped ? 1 : 1.35)
                        .opacity(snapped ? 1 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    Text("Point the camera at the barcode")
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color.ppText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
            } else {
                ProgressView("Starting camera…")
            }
        }
        .navigationTitle("Scan barcode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if cameraReady == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(typeNumber ? "Camera" : "Type number") { typeNumber.toggle() }
                }
            }
        }
        .task {
            // iOS kills the app if the camera is used without the
            // NSCameraUsageDescription text — fall back to typing instead.
            guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
                cameraMissingSetting = true
                cameraReady = false
                return
            }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraReady = granted
                && DataScannerViewController.isSupported
                && DataScannerViewController.isAvailable
        }
    }
}

/// Wraps Apple's live-camera scanner (VisionKit).
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> ScannerHostController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],          // all barcode types
            qualityLevel: .accurate,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return ScannerHostController(scanner: scanner)
    }

    func updateUIViewController(_ host: ScannerHostController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var handled = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        private func handle(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            guard !handled else { return }
            for item in items {
                if case .barcode(let barcode) = item,
                   let code = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !code.isEmpty {
                    handled = true
                    scanner.stopScanning()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(code)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems, in: dataScanner)
        }

        // Some barcodes are first seen without their number and only update later.
        func dataScanner(_ dataScanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(updatedItems, in: dataScanner)
        }

        // Tapping a highlighted barcode also picks it.
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item], in: dataScanner)
        }
    }
}

/// Holds the scanner and only starts the camera once it's actually on screen
/// (starting earlier silently fails and leaves a black / frozen view).
final class ScannerHostController: UIViewController {
    let scanner: DataScannerViewController

    init(scanner: DataScannerViewController) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }
}

extension BarcodeScannerScreen {
    /// Got one: snap the green frame on, then hand the code over.
    fileprivate func found(_ code: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { snapped = true }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            onCode(code)
        }
    }
}
