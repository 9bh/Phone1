import Foundation
import UIKit
import Vision

enum QRCodeImageDecoderError: Error, Equatable {
    case invalidImage
    case noQRCodeFound
    case unreadableQRCode
}

struct QRCodeImageDecoder {
    static func decodeFirstQRCode(from data: Data) async throws -> String {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            throw QRCodeImageDecoderError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if error != nil {
                    continuation.resume(throwing: QRCodeImageDecoderError.unreadableQRCode)
                    return
                }

                let observations = (request.results as? [VNBarcodeObservation]) ?? []
                guard let payload = observations
                    .first(where: { $0.symbology == .qr })?
                    .payloadStringValue,
                    !payload.isEmpty else {
                    continuation.resume(throwing: QRCodeImageDecoderError.noQRCodeFound)
                    return
                }

                continuation.resume(returning: payload)
            }
            request.symbologies = [.qr]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: QRCodeImageDecoderError.unreadableQRCode)
            }
        }
    }
}
