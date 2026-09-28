import Foundation
import SwiftUI

struct ServerModInfo: Codable {
    var fileName: String
    var targetSubPath: String
    var downloadUrl: String
    var version: String?
}

struct ServerModFile: Codable, Identifiable, Equatable {
    let id: Int
    let category: String
    let displayName: String
    let fileName: String
    let targetSubPath: String
    let fileSize: Int
    let fileMd5: String
    let version: String
    let downloadUrl: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, category, version
        case displayName = "display_name"
        case fileName = "file_name"
        case targetSubPath = "target_sub_path"
        case fileSize = "file_size"
        case fileMd5 = "file_md5"
        case downloadUrl = "download_url"
        case updatedAt = "updated_at"
    }
}

struct GetModsResponse: Codable {
    let status: Bool
    let message: String?
    let projectId: Int?
    let projectName: String?
    let totalFiles: Int?
    let files: [ServerModFile]?

    enum CodingKeys: String, CodingKey {
        case status, message
        case projectId = "project_id"
        case projectName = "project_name"
        case totalFiles = "total_files"
        case files
    }
}

final class FFModService: ObservableObject {
    static let shared = FFModService()
    
    static let modsApiURL = "http://103.74.103.43/api/get_mods.php"
    
    @Published var resolvedPath: String?
    @Published var isProcessing: Bool = false
    @Published var serverMod: ServerModInfo?
    @Published var serverFiles: [ServerModFile] = []
    
    private init() {}
    
    // Thư mục lưu trữ bản backup file gốc nằm an toàn trong App Documents
    var backupDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Original_Backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // Candidate bundle identifiers for Free Fire
    static let standardBundleIDs = [
        "com.dts.freefireth",
        "com.dts.freefirevn",
        "com.dts.freefire"
    ]
    
    static let maxBundleIDs = [
        "com.dts.freefiremax"
    ]
    
    // MARK: - 1. Fetch Mod Info From Server API
    func fetchModsFromAPI(key: String, completion: ((Bool, [ServerModFile]) -> Void)? = nil) {
        guard !key.isEmpty,
              let cleanKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.modsApiURL)?key=\(cleanKey)") else {
            completion?(false, [])
            return
        }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                completion?(false, [])
                return
            }
            
            if let decoded = try? JSONDecoder().decode(GetModsResponse.self, from: data),
               let files = decoded.files, !files.isEmpty {
                DispatchQueue.main.async {
                    self?.serverFiles = files
                    // Cập nhật serverMod mặc định là aim neck nếu có
                    if let aimNeck = files.first(where: { $0.id == 2 || $0.displayName.lowercased().contains("neck") }) {
                        self?.serverMod = ServerModInfo(
                            fileName: aimNeck.fileName,
                            targetSubPath: aimNeck.targetSubPath,
                            downloadUrl: aimNeck.downloadUrl,
                            version: aimNeck.version
                        )
                    }
                    completion?(true, files)
                }
                return
            }
            
            // Fallback parse
            let parsed = Self.parseModResponse(data)
            DispatchQueue.main.async {
                if let parsed = parsed {
                    self?.serverMod = parsed
                }
                completion?(false, [])
            }
        }.resume()
    }
    
    // Helper tìm file theo id hoặc từ khóa
    func getFile(byId id: Int) -> ServerModFile? {
        serverFiles.first(where: { $0.id == id })
    }
    
    func getFiles(byCategory cat: String) -> [ServerModFile] {
        serverFiles.filter({ $0.category.lowercased() == cat.lowercased() })
    }
    
    func getFiles(byDisplayName keyword: String) -> [ServerModFile] {
        serverFiles.filter({ $0.displayName.lowercased().contains(keyword.lowercased()) })
    }
    
    // Parser linh hoạt đọc mọi kiểu JSON trả về từ get_mods.php
    static func parseModResponse(_ data: Data) -> ServerModInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        
        func extract(from dict: [String: Any]) -> ServerModInfo? {
            let fileName = (dict["file_name"] as? String) ?? (dict["fileName"] as? String)
            let subPath = (dict["target_sub_path"] as? String) ?? (dict["targetSubPath"] as? String)
            let download = (dict["download_url"] as? String) ?? (dict["downloadUrl"] as? String) ?? (dict["url"] as? String)
            let ver = (dict["version"] as? String) ?? (dict["version_hash"] as? String)
            
            if let f = fileName, !f.isEmpty,
               let s = subPath, !s.isEmpty,
               let d = download, !d.isEmpty {
                return ServerModInfo(fileName: f, targetSubPath: s, downloadUrl: d, version: ver)
            }
            return nil
        }
        
        if let dict = json as? [String: Any] {
            if let info = extract(from: dict) { return info }
            if let dataDict = dict["data"] as? [String: Any], let info = extract(from: dataDict) { return info }
            if let dataArr = dict["data"] as? [[String: Any]], let first = dataArr.first, let info = extract(from: first) { return info }
            if let modsArr = dict["mods"] as? [[String: Any]], let first = modsArr.first, let info = extract(from: first) { return info }
            if let featArr = dict["features"] as? [[String: Any]], let first = featArr.first, let info = extract(from: first) { return info }
        } else if let arr = json as? [[String: Any]], let first = arr.first {
            return extract(from: first)
        }
        
        return nil
    }
    
    // MARK: - 2. Auto-Backup Cache Gốc vào App
    @discardableResult
    func autoBackupOriginalFile(gameFilePath: String, fileName: String) -> Bool {
        let fm = FileManager.default
        let backupDestination = backupDirectory.appendingPathComponent(fileName)
        
        // Nếu App đã có file backup rồi thì giữ nguyên bản gốc đầu tiên, tuyệt đối không copy đè
        if fm.fileExists(atPath: backupDestination.path) {
            if let attr = try? fm.attributesOfItem(atPath: backupDestination.path),
               let size = attr[.size] as? UInt64, size > 0 {
                return true
            }
        }
        
        // Nếu chưa có, copy file hiện tại từ game vào App
        guard fm.fileExists(atPath: gameFilePath) else { return false }
        
        // Kiểm tra dung lượng file trong game
        if let attr = try? fm.attributesOfItem(atPath: gameFilePath),
           let size = attr[.size] as? UInt64, size == 0 {
            return false
        }
        
        do {
            try fm.copyItem(atPath: gameFilePath, toPath: backupDestination.path)
            print("[AutoBackup] Đã lưu cache gốc vào App:", backupDestination.path)
            return true
        } catch {
            print("[AutoBackup] Lỗi lưu cache gốc:", error)
            return false
        }
    }
    
    // MARK: - 3. Tìm Container & Thư mục Game
    func findGameContainer(isMax: Bool = false) -> String? {
        // Trên iOS 18: Chỉ quét container và can thiệp file sau khi ấn kích hoạt trong trang chủ
        if AppInfo.isIOS18 && !KernelExploit.hasSandboxAccess() && !KernelExploit.isActivated {
            log("findGameContainer: iOS 18 chưa kích hoạt — bỏ qua quét container")
            return nil
        }
        
        let bundleIDs = isMax ? Self.maxBundleIDs : Self.standardBundleIDs
        
        // 1. Kiểm tra trực tiếp từng bundle ID qua appInfoForBundleID (nhanh nhất & chuẩn xác nhất từ LaunchServices)
        for bid in bundleIDs {
            if let info = appInfoForBundleID(bid) as? [String: Any],
               let container = info["container"] as? String,
               !container.isEmpty {
                let canonical = ContainerDiscoveryMerger.canonicalPath(container)
                if ContainerStore.isValidContainerPath(canonical) {
                    _ = ContainerStore.grantContainerAccess(canonical)
                    log("findGameContainer: Tìm thấy container qua appInfoForBundleID(\(bid)): \(canonical)")
                    return canonical
                }
            }
        }
        
        // 2. Kiểm tra qua ContainerStore.resolveAppContainerPath
        for bid in bundleIDs {
            if let path = ContainerStore.resolveAppContainerPath(bundleID: bid) {
                let canonical = ContainerDiscoveryMerger.canonicalPath(path)
                if ContainerStore.isValidContainerPath(canonical) {
                    _ = ContainerStore.grantContainerAccess(canonical)
                    log("findGameContainer: Tìm thấy container qua resolveAppContainerPath(\(bid)): \(canonical)")
                    return canonical
                }
            }
        }
        
        // 3. Quét toàn bộ installedAppInfo() tìm Free Fire (hỗ trợ cả trường hợp đổi bundle ID hoặc cài qua TrollStore/Scarlet/Esign)
        let allApps = installedAppInfo() as? [String: [String: Any]] ?? [:]
        for (installedBID, info) in allApps {
            let lowerBID = installedBID.lowercased()
            let appName = (info["name"] as? String ?? "").lowercased()
            let isFFMatch = lowerBID.contains("freefire") || lowerBID.contains("free_fire") || appName.contains("free fire") || appName.contains("freefire")
            guard isFFMatch else { continue }
            
            let isMaxApp = lowerBID.contains("max") || appName.contains("max")
            if isMax == isMaxApp {
                if let container = info["container"] as? String, !container.isEmpty {
                    let canonical = ContainerDiscoveryMerger.canonicalPath(container)
                    if ContainerStore.isValidContainerPath(canonical) {
                        _ = ContainerStore.grantContainerAccess(canonical)
                        log("findGameContainer: Tìm thấy container qua installedAppInfo scan (\(installedBID)): \(canonical)")
                        return canonical
                    }
                }
            }
        }
        
        // 4. Nếu vẫn không thấy, thử tìm bất kỳ bản Free Fire nào có trong máy
        for (installedBID, info) in allApps {
            let lowerBID = installedBID.lowercased()
            let appName = (info["name"] as? String ?? "").lowercased()
            if lowerBID.contains("freefire") || appName.contains("free fire") {
                if let container = info["container"] as? String, !container.isEmpty {
                    let canonical = ContainerDiscoveryMerger.canonicalPath(container)
                    if ContainerStore.isValidContainerPath(canonical) {
                        _ = ContainerStore.grantContainerAccess(canonical)
                        log("findGameContainer: Tìm thấy container dự phòng qua installedAppInfo (\(installedBID)): \(canonical)")
                        return canonical
                    }
                }
            }
        }
        
        // 5. Quét thư mục ContainerStore.appDataRoot
        let appDataRoot = ContainerStore.appDataRoot
        let dirs = ContainerStore.enumerateDirectories(path: appDataRoot)
        for dir in dirs {
            if let meta = ContainerStore.readContainerMetadata(containerPath: dir) {
                let lower = meta.bundleID.lowercased()
                if bundleIDs.contains(meta.bundleID) || (isMax ? lower.contains("freefiremax") : (lower.contains("freefire") && !lower.contains("freefiremax"))) {
                    let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
                    _ = ContainerStore.grantContainerAccess(canonical)
                    log("findGameContainer: Tìm thấy container qua metadata scan: \(canonical)")
                    return canonical
                }
            }
            
            let candidateContentCache = (dir as NSString).appendingPathComponent("Documents/contentcache")
            if FileManager.default.fileExists(atPath: candidateContentCache) {
                let canonical = ContainerDiscoveryMerger.canonicalPath(dir)
                _ = ContainerStore.grantContainerAccess(canonical)
                log("findGameContainer: Tìm thấy container qua contentcache check: \(canonical)")
                return canonical
            }
        }
        
        #if targetEnvironment(simulator)
        let fm = FileManager.default
        if let simDoc = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let simMock = simDoc.appendingPathComponent("SimulatedFreeFire").path
            return simMock
        }
        #endif
        
        log("findGameContainer: Không tìm thấy container cho \(isMax ? "Free Fire MAX" : "Free Fire")")
        return nil
    }
    
    func findAssetBundlesDir(in container: String, subFolder: String = "Compulsory") -> String? {
        let fm = FileManager.default
        let possibleRelativePaths = [
            "Documents/contentcache/\(subFolder)/ios/gameassetbundles",
            "Documents/contentcache/\(subFolder)/iOS/gameassetbundles",
            "Documents/contentcache/\(subFolder)/IOS/gameassetbundles",
            "Documents/contentcache/\(subFolder.lowercased())/ios/gameassetbundles",
            "Documents/contentcache/\(subFolder.lowercased())/iOS/gameassetbundles"
        ]
        
        for rel in possibleRelativePaths {
            let full = (container as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                return full
            }
        }
        
        let contentCacheDir = (container as NSString).appendingPathComponent("Documents/contentcache")
        if let enumerator = fm.enumerator(atPath: contentCacheDir) {
            while let element = enumerator.nextObject() as? String {
                if element.lowercased().contains(subFolder.lowercased()) && element.lowercased().hasSuffix("gameassetbundles") {
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

    func findGameAssetBundlesDir(in container: String) -> String? {
        return findAssetBundlesDir(in: container, subFolder: "Compulsory")
    }
    
    // MARK: - 4. Áp Dụng & Khôi Phục Danh Sách File Mod từ API
    static func writeFileSafely(data: Data, targetPath: String) -> Bool {
        let url = URL(fileURLWithPath: targetPath)
        let dir = (targetPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        if (try? data.write(to: url, options: .atomic)) != nil {
            return true
        }
        if (try? data.write(to: url)) != nil {
            return true
        }
        let pathC = (targetPath as NSString).utf8String
        if let fp = fopen(pathC, "wb") {
            defer { fclose(fp) }
            let written = data.withUnsafeBytes { ptr in
                fwrite(ptr.baseAddress, 1, data.count, fp)
            }
            return written == data.count
        }
        return false
    }

    func applyModFiles(_ files: [ServerModFile], isMax: Bool = false, completion: @escaping (Bool, String) -> Void) {
        guard !files.isEmpty else {
            completion(false, "Không có file mod để cài đặt")
            return
        }
        
        guard let container = findGameContainer(isMax: isMax) else {
            completion(false, "Chưa tải game")
            return
        }
        
        resolvedPath = container
        isProcessing = true
        
        let fm = FileManager.default
        let group = DispatchGroup()
        var hasError = false
        var lastError = ""
        
        for file in files {
            group.enter()
            let targetDir = (container as NSString).appendingPathComponent(file.targetSubPath)
            let targetFile = (targetDir as NSString).appendingPathComponent(file.fileName)
            
            // Backup file gốc nếu có
            _ = autoBackupOriginalFile(gameFilePath: targetFile, fileName: file.fileName)
            try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
            
            guard let downloadUrl = URL(string: file.downloadUrl) else {
                hasError = true
                lastError = "Link tải không hợp lệ"
                group.leave()
                continue
            }
            
            URLSession.shared.downloadTask(with: downloadUrl) { tempURL, _, err in
                defer { group.leave() }
                guard let tempURL = tempURL, err == nil,
                      let data = try? Data(contentsOf: tempURL), !data.isEmpty else {
                    hasError = true
                    lastError = "Lỗi tải file \(file.displayName)"
                    return
                }
                
                if Self.writeFileSafely(data: data, targetPath: targetFile) {
                    // Success
                } else {
                    hasError = true
                    lastError = "Lỗi ghi file vào game: \(file.displayName)"
                }
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isProcessing = false
            if hasError {
                completion(false, lastError)
            } else {
                completion(true, "Thành công")
            }
        }
    }
    
    @discardableResult
    func restoreModFiles(_ files: [ServerModFile], isMax: Bool = false) -> Bool {
        guard let container = findGameContainer(isMax: isMax) else { return false }
        resolvedPath = container
        isProcessing = true
        defer { isProcessing = false }
        
        let fm = FileManager.default
        var allOk = true
        
        for file in files {
            let targetDir = (container as NSString).appendingPathComponent(file.targetSubPath)
            let targetFile = (targetDir as NSString).appendingPathComponent(file.fileName)
            let backupDestination = backupDirectory.appendingPathComponent(file.fileName)
            
            if fm.fileExists(atPath: backupDestination.path) {
                do {
                    if fm.fileExists(atPath: targetFile) {
                        try fm.removeItem(atPath: targetFile)
                    }
                    try fm.copyItem(atPath: backupDestination.path, toPath: targetFile)
                } catch {
                    allOk = false
                }
            } else {
                // File inject mới không có file gốc trong game -> Xóa đi
                if fm.fileExists(atPath: targetFile) {
                    try? fm.removeItem(atPath: targetFile)
                }
            }
        }
        
        return allOk
    }

    // MARK: - 5. BẬT MOD ONLINE (Tải Server -> Backup Gốc -> Dán File)
    func applyModOnline(isMax: Bool = false, key: String = "", completion: @escaping (Bool, String) -> Void) {
        isProcessing = true
        
        guard let container = findGameContainer(isMax: isMax) else {
            isProcessing = false
            completion(false, "Chưa tìm thấy game Free Fire trên máy")
            return
        }
        
        resolvedPath = container
        
        // Lấy thông tin Server Mod nếu chưa có
        if serverMod == nil && !key.isEmpty {
            fetchModsFromAPI(key: key) { [weak self] ok, info in
                guard let self = self else { return }
                self.executeApplyFlow(container: container, isMax: isMax, completion: completion)
            }
        } else {
            executeApplyFlow(container: container, isMax: isMax, completion: completion)
        }
    }
    
    private func executeApplyFlow(container: String, isMax: Bool, completion: @escaping (Bool, String) -> Void) {
        let fm = FileManager.default
        let fileName = serverMod?.fileName ?? FFModPayload.fileName
        let subPath = serverMod?.targetSubPath ?? FFModPayload.subPath
        
        // Đường dẫn thư mục & file đích trong Game
        let targetDir = (container as NSString).appendingPathComponent(subPath)
        let targetFile = (targetDir as NSString).appendingPathComponent(fileName)
        
        // 1. TỰ ĐỘNG SAO LƯU GỐC VÀO APP TRƯỚC
        _ = autoBackupOriginalFile(gameFilePath: targetFile, fileName: fileName)
        
        // Tạo thư mục cha nếu chưa có
        try? fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
        
        // 2. NẾU CÓ LINK DOWNLOAD TỪ SERVER -> TẢI VỀ
        if let downloadUrlString = serverMod?.downloadUrl,
           let downloadUrl = URL(string: downloadUrlString) {
            
            URLSession.shared.downloadTask(with: downloadUrl) { [weak self] tempURL, _, error in
                guard let self = self else { return }
                
                if let tempURL = tempURL, error == nil,
                   let downloadedData = try? Data(contentsOf: tempURL), !downloadedData.isEmpty {
                    if Self.writeFileSafely(data: downloadedData, targetPath: targetFile) {
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            completion(true, "Đã tải từ server & dán mod thành công!")
                        }
                        return
                    } else {
                        print("[ModApply] Lỗi ghi file tải về:", targetFile)
                    }
                }
                
                // Dự phòng: Nếu tải từ server lỗi, ghi dữ liệu local
                self.fallbackLocalApply(targetFile: targetFile, completion: completion)
            }.resume()
        } else {
            // Không có link download -> Dùng dữ liệu local payload
            fallbackLocalApply(targetFile: targetFile, completion: completion)
        }
    }
    
    private func fallbackLocalApply(targetFile: String, completion: @escaping (Bool, String) -> Void) {
        let data = getModData()
        guard !data.isEmpty else {
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(false, "Không tìm thấy dữ liệu mod")
            }
            return
        }
        
        if Self.writeFileSafely(data: data, targetPath: targetFile) {
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(true, "Đã bật aim cổ thành công (Bản dự phòng)")
            }
        } else {
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(false, "Lỗi ghi file vào game")
            }
        }
    }
    
    // MARK: - 5. TẮT MOD (Dán lại File Gốc cache_goc & shader_goc)
    @discardableResult
    func restoreAimGoc(isMax: Bool? = nil) -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        
        let gocData = getGocData()
        guard !gocData.isEmpty else {
            log("restoreAimGoc: Không có dữ liệu cache_goc")
            return false
        }
        
        let fileName = "cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D"
        let subPath = "Documents/contentcache/Compulsory/ios/gameassetbundles"
        
        var containers: [String] = []
        if let isMax = isMax {
            if let c = findGameContainer(isMax: isMax) {
                containers.append(c)
            }
        } else {
            if let std = findGameContainer(isMax: false) {
                containers.append(std)
            }
            if let mx = findGameContainer(isMax: true) {
                containers.append(mx)
            }
        }
        
        let uniqueContainers = Array(Set(containers))
        guard !uniqueContainers.isEmpty else {
            log("restoreAimGoc: Không tìm thấy container game")
            return false
        }
        
        var success = false
        let fm = FileManager.default
        let backupDestination = backupDirectory.appendingPathComponent(fileName)
        if fm.fileExists(atPath: backupDestination.path) {
            try? fm.removeItem(at: backupDestination)
        }
        
        for container in uniqueContainers {
            let assetDir = findGameAssetBundlesDir(in: container) ?? (container as NSString).appendingPathComponent(subPath)
            let targetFile = (assetDir as NSString).appendingPathComponent(fileName)
            
            if Self.writeFileSafely(data: gocData, targetPath: targetFile) {
                log("restoreAimGoc: Đã dán lại cache_goc vào: \(targetFile)")
                success = true
            } else {
                log("restoreAimGoc: Lỗi dán cache_goc vào: \(targetFile)")
            }
        }
        return success
    }
    
    @discardableResult
    func restoreDinhViGoc(isMax: Bool? = nil) -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        
        let gocData = getShaderGocData()
        guard !gocData.isEmpty else {
            log("restoreDinhViGoc: Không có dữ liệu shader_goc")
            return false
        }
        
        let fileName = "shaders.P0K3UG2TfecMBhWMMV~2Fu8ReudIk~3D"
        let subPath = "Documents/contentcache/Optional/ios/gameassetbundles"
        
        var containers: [String] = []
        if let isMax = isMax {
            if let c = findGameContainer(isMax: isMax) {
                containers.append(c)
            }
        } else {
            if let std = findGameContainer(isMax: false) {
                containers.append(std)
            }
            if let mx = findGameContainer(isMax: true) {
                containers.append(mx)
            }
        }
        
        let uniqueContainers = Array(Set(containers))
        guard !uniqueContainers.isEmpty else {
            log("restoreDinhViGoc: Không tìm thấy container game")
            return false
        }
        
        var success = false
        let fm = FileManager.default
        let backupDestination = backupDirectory.appendingPathComponent(fileName)
        if fm.fileExists(atPath: backupDestination.path) {
            try? fm.removeItem(at: backupDestination)
        }
        
        for container in uniqueContainers {
            let assetDir = findAssetBundlesDir(in: container, subFolder: "Optional") ?? (container as NSString).appendingPathComponent(subPath)
            let targetFile = (assetDir as NSString).appendingPathComponent(fileName)
            
            try? fm.createDirectory(atPath: assetDir, withIntermediateDirectories: true)
            
            if Self.writeFileSafely(data: gocData, targetPath: targetFile) {
                log("restoreDinhViGoc: Đã dán lại shader_goc vào: \(targetFile)")
                success = true
            } else {
                log("restoreDinhViGoc: Lỗi dán shader_goc vào: \(targetFile)")
            }
        }
        return success
    }
    
    @discardableResult
    func restoreGoc(isMax: Bool = false) -> Bool {
        return restoreAimGoc(isMax: isMax)
    }
    
    // MARK: - 6. Xóa sạch 2 file Menu C# (Assembly-CSharp-patch.bytes & localConfig.json)
    @discardableResult
    func removeMenuCSharpFiles() -> Bool {
        // Trên iOS 18: Chỉ quét container và dọn dẹp file sau khi ấn kích hoạt trong trang chủ
        if AppInfo.isIOS18 && !KernelExploit.hasSandboxAccess() {
            log("removeMenuCSharpFiles: iOS 18 chưa kích hoạt — bỏ qua dọn dẹp file")
            return false
        }
        
        let fm = FileManager.default
        var deletedAny = false
        
        let cSharpFileNames = [
            "Assembly-CSharp-patch.bytes",
            "localConfig.json"
        ]
        
        // 1. Danh sách đường dẫn cần xóa
        var targets: [(subPath: String, fileName: String)] = [
            ("Documents", "Assembly-CSharp-patch.bytes"),
            ("Documents", "localConfig.json")
        ]
        
        // Bổ sung thêm bất kỳ file nào từ server thuộc nhóm "menu"
        let menuFiles = getFiles(byCategory: "menu") + getFiles(byDisplayName: "menu")
        for f in menuFiles {
            if !targets.contains(where: { $0.fileName == f.fileName && $0.subPath == f.targetSubPath }) {
                targets.append((f.targetSubPath, f.fileName))
            }
        }
        
        // Quét tất cả container của Free Fire (cả Standard và MAX)
        var containersToScan: [String] = []
        if let std = findGameContainer(isMax: false) {
            containersToScan.append(std)
        }
        if let mx = findGameContainer(isMax: true) {
            containersToScan.append(mx)
        }
        let uniqueContainers = Array(Set(containersToScan))
        
        for container in uniqueContainers {
            // Xóa theo target_sub_path và file_name
            for target in targets {
                let targetDir = (container as NSString).appendingPathComponent(target.subPath)
                let filePath = (targetDir as NSString).appendingPathComponent(target.fileName)
                if fm.fileExists(atPath: filePath) {
                    do {
                        try fm.removeItem(atPath: filePath)
                        print("[MenuCSharp] Đã xóa file mod:", filePath)
                        deletedAny = true
                    } catch {
                        print("[MenuCSharp] Lỗi xóa file \(filePath):", error)
                    }
                }
            }
            
            // Quét kiểm tra thẳng trong Documents
            let docsDir = (container as NSString).appendingPathComponent("Documents")
            for name in cSharpFileNames {
                let p = (docsDir as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: p) {
                    try? fm.removeItem(atPath: p)
                    deletedAny = true
                }
            }
        }
        
        // Xóa luôn bản lưu backup nếu có trong App
        for name in cSharpFileNames {
            let backupFile = backupDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: backupFile.path) {
                try? fm.removeItem(at: backupFile)
            }
        }
        for f in menuFiles {
            let backupFile = backupDirectory.appendingPathComponent(f.fileName)
            if fm.fileExists(atPath: backupFile.path) {
                try? fm.removeItem(at: backupFile)
            }
        }
        
        return deletedAny
    }
    
    // MARK: - 7. Dữ liệu Payload Local dự phòng
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
    
    func getGocData() -> Data {
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
        let resPath = "/Users/tanh/Downloads/3105_mod/3105/ThreeOneOSFive/Resources/cache_goc/cache_res.GkLlYqzsX4AtTdE55sDMRh9sJOI~3D"
        if let d = try? Data(contentsOf: URL(fileURLWithPath: resPath)), !d.isEmpty {
            return d
        }
        return FFModPayload.gocData
    }

    func getShaderGocData() -> Data {
        if let bundleURL = Bundle.main.url(forResource: "shaders.P0K3UG2TfecMBhWMMV~2Fu8ReudIk~3D", withExtension: nil, subdirectory: "shader_goc"),
           let d = try? Data(contentsOf: bundleURL), !d.isEmpty {
            return d
        }
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("shader_goc/shaders.P0K3UG2TfecMBhWMMV~2Fu8ReudIk~3D"),
           let d = try? Data(contentsOf: bundleURL), !d.isEmpty {
            return d
        }
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("shaders.P0K3UG2TfecMBhWMMV~2Fu8ReudIk~3D"),
           let d = try? Data(contentsOf: bundleURL), !d.isEmpty {
            return d
        }
        let docsPath = "/Users/tanh/Downloads/3105_mod/3105/docs/shader_goc/shaders.P0K3UG2TfecMBhWMMV~2Fu8ReudIk~3D"
        if let d = try? Data(contentsOf: URL(fileURLWithPath: docsPath)), !d.isEmpty {
            return d
        }
        let resPath = "/Users/tanh/Downloads/3105_mod/3105/ThreeOneOSFive/Resources/shader_goc/shaders.P0K3UG2TfecMBhWMMV~2Fu8ReudIk~3D"
        if let d = try? Data(contentsOf: URL(fileURLWithPath: resPath)), !d.isEmpty {
            return d
        }
        return Data()
    }
}
