import Flutter
import UIKit
import Vision

/// One-shot, on-device MRZ capture. Vision text recognition never leaves the
/// device; Dart performs TD3 normalization and ICAO check-digit validation.
final class PassportMRZScanner: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  private weak var presenter: UIViewController?
  private var pending: FlutterResult?

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func scan(result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "mrz_scan_busy", message: "An MRZ scan is already active.", details: nil))
      return
    }
    guard UIImagePickerController.isSourceTypeAvailable(.camera), let presenter else {
      result(FlutterError(code: "camera_unavailable", message: "Camera is unavailable.", details: nil))
      return
    }
    pending = result
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.cameraCaptureMode = .photo
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    pending?(FlutterError(code: "mrz_scan_cancelled", message: "MRZ scan cancelled.", details: nil))
    pending = nil
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    guard let image = info[.originalImage] as? UIImage, let cgImage = image.cgImage else {
      pending?(FlutterError(code: "mrz_image_invalid", message: "Camera image is unavailable.", details: nil))
      pending = nil
      return
    }
    let request = VNRecognizeTextRequest { [weak self] request, error in
      DispatchQueue.main.async {
        guard let self else { return }
        defer { self.pending = nil }
        if let error {
          self.pending?(FlutterError(code: "mrz_ocr_failed", message: error.localizedDescription, details: nil))
          return
        }
        let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
          .compactMap { $0.topCandidates(1).first?.string }
        self.pending?(lines.joined(separator: "\n"))
      }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
      } catch {
        DispatchQueue.main.async {
          self.pending?(FlutterError(code: "mrz_ocr_failed", message: error.localizedDescription, details: nil))
          self.pending = nil
        }
      }
    }
  }
}
