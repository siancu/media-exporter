import ArgumentParser
import Foundation
import Photos
import ImageIO
import AVFoundation
import CoreImage

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
              let endDate = dateFormatter.date(from: toDate) else {
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
            let overallStartTime = Date()
            let exportedCount = try exportAssets(from: startDate, to: endDate)
            let totalDuration = Date().timeIntervalSince(overallStartTime)
            
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
            try fileManager.createDirectory(atPath: outputFolder, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func exportAssets(from startDate: Date, to endDate: Date) throws -> Int {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", startDate as NSDate, endDate as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        var exportedCount = 0
        let totalAssets = fetchResult.count
        
        print("Found \(totalAssets) assets to export...")
        
        for i in 0..<fetchResult.count {
            let asset = fetchResult.object(at: i)
            let semaphore = DispatchSemaphore(value: 0)
            var success = false
            
            switch asset.mediaType {
            case .image:
                exportPhoto(asset: asset, index: i + 1, total: totalAssets) { exportSuccess in
                    success = exportSuccess
                    semaphore.signal()
                }
            case .video:
                exportVideo(asset: asset, index: i + 1, total: totalAssets) { exportSuccess in
                    success = exportSuccess
                    semaphore.signal()
                }
            default:
                print("[\(i + 1)/\(totalAssets)] Skipping unsupported asset type")
                semaphore.signal()
            }
            
            semaphore.wait()
            if success { exportedCount += 1 }
        }
        
        return exportedCount
    }
    
    private func exportPhoto(asset: PHAsset, index: Int, total: Int, completion: @escaping (Bool) -> Void) {
        let startTime = Date()
        print("[\(index)/\(total)] Starting photo export...")
        
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { [self] data, dataUTI, orientation, info in
            guard let imageData = data else {
                let duration = Date().timeIntervalSince(startTime)
                print("[\(index)/\(total)] ❌ Failed to get image data (\(String(format: "%.2f", duration))s)")
                completion(false)
                return
            }
            
            do {
                let tempFileName = UUID().uuidString + ".jpg"
                let tempFilePath = (outputFolder as NSString).appendingPathComponent(tempFileName)
                let tempURL = URL(fileURLWithPath: tempFilePath)
                
                let jpegData = try convertToJPEG(data: imageData)
                try jpegData.write(to: tempURL)
                
                let creationDate = extractCreationDate(from: imageData) ?? asset.creationDate ?? Date()
                let finalFileName = generateFileName(from: creationDate, isVideo: false)
                let finalFilePath = (outputFolder as NSString).appendingPathComponent(finalFileName)
                
                try FileManager.default.moveItem(atPath: tempFilePath, toPath: finalFilePath)
                
                let duration = Date().timeIntervalSince(startTime)
                print("[\(index)/\(total)] ✅ Photo exported: \(finalFileName) (\(String(format: "%.2f", duration))s)")
                completion(true)
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                print("[\(index)/\(total)] ❌ Error processing photo: \(error.localizedDescription) (\(String(format: "%.2f", duration))s)")
                completion(false)
            }
        }
    }
    
    private func exportVideo(asset: PHAsset, index: Int, total: Int, completion: @escaping (Bool) -> Void) {
        let startTime = Date()
        let isEdited = asset.hasAdjustments
        let exportMethod = isEdited ? "re-encoding" : "copying"
        print("[\(index)/\(total)] Starting video export (\(exportMethod))...")
        
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [self] avAsset, audioMix, info in
            guard let avAsset = avAsset else {
                let duration = Date().timeIntervalSince(startTime)
                print("[\(index)/\(total)] ❌ Failed to get AVAsset for video (\(String(format: "%.2f", duration))s)")
                completion(false)
                return
            }
            
            let creationDate = asset.creationDate ?? Date()
            let finalFileName = generateFileName(from: creationDate, isVideo: true)
            let finalFilePath = (outputFolder as NSString).appendingPathComponent(finalFileName)
            let outputURL = URL(fileURLWithPath: finalFilePath)
            
            // Use passthrough for original videos (fast copy), highest quality for edited videos
            let preset = isEdited ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
            
            guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset) else {
                let duration = Date().timeIntervalSince(startTime)
                print("[\(index)/\(total)] ❌ Failed to create export session (\(String(format: "%.2f", duration))s)")
                completion(false)
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            
            exportSession.exportAsynchronously {
                let duration = Date().timeIntervalSince(startTime)
                switch exportSession.status {
                case .completed:
                    print("[\(index)/\(total)] ✅ Video exported: \(finalFileName) (\(String(format: "%.2f", duration))s)")
                    completion(true)
                case .failed, .cancelled:
                    print("[\(index)/\(total)] ❌ Video export failed: \(exportSession.error?.localizedDescription ?? "Unknown error") (\(String(format: "%.2f", duration))s)")
                    completion(false)
                default:
                    print("[\(index)/\(total)] ❌ Video export failed with unknown status (\(String(format: "%.2f", duration))s)")
                    completion(false)
                }
            }
        }
    }
    
    private func convertToJPEG(data: Data) throws -> Data {
        guard let ciImage = CIImage(data: data) else {
            throw NSError(domain: "MediaExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CIImage"])
        }
        
        let context = CIContext()
        guard let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
            throw NSError(domain: "MediaExporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert to JPEG"])
        }
        
        return jpegData
    }
    
    private func extractCreationDate(from imageData: Data) -> Date? {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let dateTimeOriginal = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String else {
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
        
        while fileManager.fileExists(atPath: (outputFolder as NSString).appendingPathComponent(fileName)) {
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
                if newStatus != .authorized {
                    print("Error: Photo library access denied. Please grant permission in System Preferences.")
                    exit(1)
                }
                semaphore.signal()
            }
            semaphore.wait()
        } else if status != .authorized {
            print("Error: Photo library access denied. Please grant permission in System Preferences.")
            exit(1)
        }
        
        MediaExporter.main()
    }
}