import Foundation
import SwiftUI

final class FFModService: ObservableObject {
    static let shared = FFModService()
    
    @Published var resolvedPath: String?
    @Published var isProcessing: Bool = false
    
    private init() {}
    
    // Candidate bundle identifiers for Free Fire
    static let standardBundleIDs = [
        "com.dts.freefireth",
        "com.dts.freefirevn",
        "com.dts.freefire"
    ]
    
    static let maxBundleIDs = [
        "com.dts.freefiremax"
    ]
    
    /// Finds the Free Fire container directory on the device
    func findGameContainer(isMax: Bool = false) -> String? {
        let bundleIDs = isMax ? Self.maxBundleIDs : Self.standardBundleIDs
        
        // 1. Try MobileContainerManager resolution via ContainerStore
        for bid in bundleIDs {
            if let path = ContainerStore.resolveAppContainerPath(bundleID: bid),
               ContainerStore.isApplicationContainerPath(path) {
                _ = ContainerStore.grantContainerAccess(path)
                return path
            }
        }
        
        // 2. Try scanning /var/mobile/Containers/Data/Application
        let appDataRoot = ContainerStore.appDataRoot
        let dirs = ContainerStore.enumerateDirectories(path: appDataRoot)
        for dir in dirs {
            // Check metadata plist
            if let meta = ContainerStore.readContainerMetadata(containerPath: dir) {
                let lower = meta.bundleID.lowercased()
                if bundleIDs.contains(meta.bundleID) || (isMax ? lower.contains("freefiremax") : (lower.contains("freefire") && !lower.contains("freefiremax"))) {
                    let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
                    _ = ContainerStore.grantContainerAccess(canonical)
                    return canonical
                }
            }
            
            // Check if Documents/contentcache exists in this container
            let candidateContentCache = (dir as NSString).appendingPathComponent("Documents/contentcache")
            if FileManager.default.fileExists(atPath: candidateContentCache) {
                let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
                _ = ContainerStore.grantContainerAccess(canonical)
                return canonical
            }
        }
        
        // 3. Fallback for Simulator testing
        #if targetEnvironment(simulator)
        let fm = FileManager.default
        if let simDoc = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let simMock = simDoc.appendingPathComponent("SimulatedFreeFire").path
            return simMock
        }
        #endif
        
        return nil
    }
    
    /// Finds the existing gameassetbundles directory inside container (case-insensitive & recursive check)
    func findGameAssetBundlesDir(in container: String) -> String? {
        let fm = FileManager.default
        let possibleRelativePaths = [
            "Documents/contentcache/Compulsory/ios/gameassetbundles",
            "Documents/contentcache/Compulsory/iOS/gameassetbundles",
            "Documents/contentcache/Compulsory/IOS/gameassetbundles",
            "Documents/contentcache/compulsory/ios/gameassetbundles",
            "Documents/contentcache/compulsory/iOS/gameassetbundles"
        ]
        
        for rel in possibleRelativePaths {
            let full = (container as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                return full
            }
        }
        
        // Dynamic search in container/Documents/contentcache
        let contentCacheDir = (container as NSString).appendingPathComponent("Documents/contentcache")
        if let enumerator = fm.enumerator(atPath: contentCacheDir) {
            while let element = enumerator.nextObject() as? String {
                if element.lowercased().hasSuffix("gameassetbundles") {
                    let full = (contentCacheDir as NSString).appendingPathComponent(element)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                        return full
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Applies cache_mod into Documents/contentcache/Compulsory/ios/gameassetbundles
    @discardableResult
    func applyMod(isMax: Bool = false) -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        
        guard let container = findGameContainer(isMax: isMax),
              let targetDir = findGameAssetBundlesDir(in: container) else {
            return false
        }
        
        resolvedPath = container
        let targetFile = (targetDir as NSString).appendingPathComponent(FFModPayload.fileName)
        
        let data = getModData()
        guard !data.isEmpty else { return false }
        
        do {
            try data.write(to: URL(fileURLWithPath: targetFile), options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    /// Restores cache_goc into Documents/contentcache/Compulsory/ios/gameassetbundles
    @discardableResult
    func restoreGoc(isMax: Bool = false) -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        
        guard let container = findGameContainer(isMax: isMax),
              let targetDir = findGameAssetBundlesDir(in: container) else {
            return false
        }
        
        resolvedPath = container
        let targetFile = (targetDir as NSString).appendingPathComponent(FFModPayload.fileName)
        
        let data = getGocData()
        guard !data.isEmpty else { return false }
        
        do {
            try data.write(to: URL(fileURLWithPath: targetFile), options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    private func getModData() -> Data {
        if let bundleURL = Bundle.main.url(forResource: "cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D", withExtension: nil, subdirectory: "cache_mod"),
           let d = try? Data(contentsOf: bundleURL), !d.isEmpty {
            return d
        }
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("cache_mod/cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D"),
           let d = try? Data(contentsOf: bundleURL), !d.isEmpty {
            return d
        }
        let docsPath = "/Users/tanh/Downloads/3105_mod/3105/docs/cache_mod/cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D"
        if let d = try? Data(contentsOf: URL(fileURLWithPath: docsPath)), !d.isEmpty {
            return d
        }
        return FFModPayload.modData
    }
    
    private func getGocData() -> Data {
        if let bundleURL = Bundle.main.url(forResource: "cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D", withExtension: nil, subdirectory: "cache_goc"),
           let d = try? Data(contentsOf: bundleURL), !d.isEmpty {
            return d
        }
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("cache_goc/cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D"),
           let d = try? Data(contentsOf: bundleURL), !d.isEmpty {
            return d
        }
        let docsPath = "/Users/tanh/Downloads/3105_mod/3105/docs/cache_goc/cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D"
        if let d = try? Data(contentsOf: URL(fileURLWithPath: docsPath)), !d.isEmpty {
            return d
        }
        return FFModPayload.gocData
    }
}
