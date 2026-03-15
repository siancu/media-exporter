import AVFoundation
import ArgumentParser
import CoreImage
import Foundation
import ImageIO
import Photos

struct MediaExporter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "media-exporter",
        abstract: "Export photos and videos from Photos library within a date range"
    )

    @Option(name: .long, help: "The start date of the export range (YYYY-MM-DD).")
    var fromDate: String

    @Option(name: .long, help: "The end date of the export range (YYYY-MM-DD).")
    var toDate: String

    @Option(name: .long, help: "The destination folder for the exported files.")
    var outputFolder: String

    func run() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        guard let startDate = dateFormatter.date(from: fromDate),
            let endDate = dateFormatter.date(from: toDate)
        else {
            print("Error: Invalid date format. Please use YYYY-MM-DD.")
            return
        }

        guard startDate <= endDate else {
            print("Error: Start date must be before or equal to end date.")
            return
        }

        do {
            print("=== Media Export Started ===")
            print("Date range: \(fromDate) to \(toDate)")
            print("Output folder: \(outputFolder)")
            print()

            try createOutputFolder()

            // Run the export on a background queue to avoid any main thread blocking
            let exportQueue = DispatchQueue(label: "media-exporter.background", qos: .userInitiated)
            let mainSemaphore = DispatchSemaphore(value: 0)
            var exportedCount = 0
            var exportError: Error?
            let overallStartTime = Date()

            exportQueue.async {
                do {
                    exportedCount = try self.exportAssets(from: startDate, to: endDate)
                } catch {
                    exportError = error
                }
                mainSemaphore.signal()
            }

            mainSemaphore.wait()
            let totalDuration = Date().timeIntervalSince(overallStartTime)

            if let error = exportError {
                throw error
            }

            print("\n=== Export Complete ===")
            print("Successfully exported \(exportedCount) files to \(outputFolder)")
            print("Total time: \(String(format: "%.2f", totalDuration)) seconds")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func createOutputFolder() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputFolder) {
            try fileManager.createDirectory(
                atPath: outputFolder, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func exportAssets(from startDate: Date, to endDate: Date) throws -> Int {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@", startDate as NSDate,
            endDate as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        fetchOptions.includeHiddenAssets = true

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        let totalAssets = fetchResult.count
        var exportedCount = 0

        print("Found \(totalAssets) assets to export...")

        // Process each asset sequentially using a simple loop without semaphores
        for i in 0..<fetchResult.count {
            let asset = fetchResult.object(at: i)

            let success: Bool
            switch asset.mediaType {
            case .image:
                success = exportPhotoSync(asset: asset, index: i + 1, total: totalAssets)
            case .video:
                success = exportVideoSync(asset: asset, index: i + 1, total: totalAssets)
            default:
                print("[\(i + 1)/\(totalAssets)] Skipping unsupported asset type")
                success = false
            }

            if success { exportedCount += 1 }
        }

        return exportedCount
    }

    private func exportPhotoSync(asset: PHAsset, index: Int, total: Int) -> Bool {
        let startTime = Date()
        print("[\(index)/\(total)] Starting photo export...")

        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true  // Allow iCloud downloads
        options.isSynchronous = true  // Make it synchronous to avoid deadlock

        var imageData: Data?
        var requestError: Error?

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
            data, dataUTI, orientation, info in
            imageData = data
            if let error = info?[PHImageErrorKey] as? Error {
                requestError = error
            }
        }

        if let error = requestError {
            let duration = Date().timeIntervalSince(startTime)
            print(
                "[\(index)/\(total)] ❌ Photo request error: \(error.localizedDescription) (\(String(format: "%.2f", duration))s)"
            )
            return false
        }

        guard let data = imageData else {
            let duration = Date().timeIntervalSince(startTime)
            print(
                "[\(index)/\(total)] ❌ Failed to get image data (\(String(format: "%.2f", duration))s)"
            )
            return false
        }

        do {
            let tempFileName = UUID().uuidString + ".jpg"
            let tempFilePath = (outputFolder as NSString).appendingPathComponent(tempFileName)
            let tempURL = URL(fileURLWithPath: tempFilePath)

            let jpegData = try convertToJPEG(data: data)
            try jpegData.write(to: tempURL)

            let creationDate = extractCreationDate(from: data) ?? asset.creationDate ?? Date()
            let finalFileName = generateFileName(from: creationDate, isVideo: false)
            let finalFilePath = (outputFolder as NSString).appendingPathComponent(finalFileName)

            try FileManager.default.moveItem(atPath: tempFilePath, toPath: finalFilePath)

            let duration = Date().timeIntervalSince(startTime)
            print(
                "[\(index)/\(total)] ✅ Photo exported: \(finalFileName) (\(String(format: "%.2f", duration))s)"
            )
            return true
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print(
                "[\(index)/\(total)] ❌ Error processing photo: \(error.localizedDescription) (\(String(format: "%.2f", duration))s)"
            )
            return false
        }
    }

    private func exportVideoSync(asset: PHAsset, index: Int, total: Int) -> Bool {
        let startTime = Date()
        let isEdited = asset.hasAdjustments
        let exportMethod = isEdited ? "re-encoding" : "copying"
        print("[\(index)/\(total)] Starting video export (\(exportMethod))...")

        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true  // Allow iCloud downloads

        var avAssetResult: AVAsset?
        let assetSemaphore = DispatchSemaphore(value: 0)

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) {
            avAsset, audioMix, info in
            avAssetResult = avAsset
            assetSemaphore.signal()
        }

        assetSemaphore.wait()

        guard let avAsset = avAssetResult else {
            let duration = Date().timeIntervalSince(startTime)
            print(
                "[\(index)/\(total)] ❌ Failed to get AVAsset for video (\(String(format: "%.2f", duration))s)"
            )
            return false
        }

        let creationDate = asset.creationDate ?? Date()
        let finalFileName = generateFileName(from: creationDate, isVideo: true)
        let finalFilePath = (outputFolder as NSString).appendingPathComponent(finalFileName)
        let outputURL = URL(fileURLWithPath: finalFilePath)

        // Use passthrough for original videos (fast copy), highest quality for edited videos
        let preset = isEdited ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough

        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset) else {
            let duration = Date().timeIntervalSince(startTime)
            print(
                "[\(index)/\(total)] ❌ Failed to create export session (\(String(format: "%.2f", duration))s)"
            )
            return false
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov

        let exportSemaphore = DispatchSemaphore(value: 0)
        var exportSuccess = false

        exportSession.exportAsynchronously {
            let duration = Date().timeIntervalSince(startTime)
            switch exportSession.status {
            case .completed:
                print(
                    "[\(index)/\(total)] ✅ Video exported: \(finalFileName) (\(String(format: "%.2f", duration))s)"
                )
                exportSuccess = true
            case .failed, .cancelled:
                print(
                    "[\(index)/\(total)] ❌ Video export failed: \(exportSession.error?.localizedDescription ?? "Unknown error") (\(String(format: "%.2f", duration))s)"
                )
                exportSuccess = false
            default:
                print(
                    "[\(index)/\(total)] ❌ Video export failed with unknown status (\(String(format: "%.2f", duration))s)"
                )
                exportSuccess = false
            }
            exportSemaphore.signal()
        }

        exportSemaphore.wait()
        return exportSuccess
    }

    private func convertToJPEG(data: Data) throws -> Data {
        guard let ciImage = CIImage(data: data) else {
            throw NSError(
                domain: "MediaExporter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create CIImage"])
        }

        let context = CIContext()
        guard
            let jpegData = context.jpegRepresentation(
                of: ciImage, colorSpace: CGColorSpaceCreateDeviceRGB())
        else {
            throw NSError(
                domain: "MediaExporter", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert to JPEG"])
        }

        return jpegData
    }

    private func extractCreationDate(from imageData: Data) -> Date? {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
                as? [String: Any],
            let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
            let dateTimeOriginal = exifDict[kCGImagePropertyExifDateTimeOriginal as String]
                as? String
        else {
            return nil
        }

        let exifDateFormatter = DateFormatter()
        exifDateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return exifDateFormatter.date(from: dateTimeOriginal)
    }

    private func generateFileName(from date: Date, isVideo: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = formatter.string(from: date)
        let fileExtension = isVideo ? "mov" : "jpg"

        var counter = 0
        var fileName = "\(baseName).\(fileExtension)"
        let fileManager = FileManager.default

        while fileManager.fileExists(
            atPath: (outputFolder as NSString).appendingPathComponent(fileName))
        {
            counter += 1
            fileName = String(format: "%@ %02d.%@", baseName, counter, fileExtension)
        }

        return fileName
    }
}

@main
struct Main {
    static func main() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if status == .notDetermined {
            let semaphore = DispatchSemaphore(value: 0)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                if newStatus == .limited {
                    print("⚠️  Limited Photos access granted. You may not see all your photos.")
                    print("   To export all photos, go to Settings > Privacy & Security > Photos")
                    print("   and select 'Full Library Access' for this app.")
                } else if newStatus != .authorized {
                    print(
                        "Error: Photo library access denied. Please grant permission in System Preferences."
                    )
                    exit(1)
                }
                semaphore.signal()
            }
            semaphore.wait()
        } else if status == .limited {
            print("⚠️  LIMITED PHOTOS ACCESS DETECTED")
            print(
                "   Currently accessing only \(status.rawValue == 3 ? "selected" : "limited") photos."
            )
            print("   To export ALL your photos:")
            print("   1. Go to Settings > Privacy & Security > Photos")
            print("   2. Find this app and select 'Full Library Access'")
            print("   3. Run the export again")
            print("")
            print("Proceeding with limited access...")
        } else if status != .authorized {
            print(
                "Error: Photo library access denied. Please grant permission in System Preferences."
            )
            exit(1)
        }

        MediaExporter.main()
    }
}
