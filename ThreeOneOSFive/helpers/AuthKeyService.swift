import Foundation
import UIKit
import SwiftUI
import AVFoundation

final class AuthKeyService: ObservableObject {
    static let shared = AuthKeyService()
    
    static let apiURL = "http://103.74.103.43/api/connect.php"
    static let packageToken = "a8f402288fc1c75f5db4dd70c8bacaab"
    
    /// TỆP LƯU TRỮ BẢN QUYỀN CHUẨN XÁC DUY NHẤT:
    static let licenseFilePath = "/var/mobile/Documents/.ntamod_license.json"
    
    private let uuidStorageKey = "nta_persistent_uuid"
    
    @Published var isAuthenticated: Bool = false
    @Published var isChecking: Bool = false
    @Published var initialCheckDone: Bool = false
    @Published var errorMessage: String? = nil
    
    @Published var savedKey: String = ""
    @Published var expiryDate: String = ""
    @Published var daysLeft: Int = 0
    @Published var contactLink: String = "https://t.me/tanhh05"
    @Published var countdownText: String = ""
    
    private var diskScanTimer: Timer?
    private var validationTimer: Timer?
    
    static func canAccessVarMobile() -> Bool {
        let fm = FileManager.default
        let docPath = "/var/mobile/Documents"
        if fm.fileExists(atPath: docPath) {
            return fm.isWritableFile(atPath: docPath)
        }
        if fm.fileExists(atPath: "/var/mobile") {
            do {
                try fm.createDirectory(atPath: docPath, withIntermediateDirectories: true)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    static var effectiveLicensePath: String {
        if canAccessVarMobile() {
            return licenseFilePath
        }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ntamod_storage")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent(".ntamod_license.json").path
    }
    
    var formattedRemainingCountdown: String {
        guard !expiryDate.isEmpty else {
            return daysLeft > 0 ? "\(daysLeft) ngày" : "Vĩnh viễn"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? TimeZone(secondsFromGMT: 7 * 3600)
        if let expire = formatter.date(from: expiryDate) {
            let diff = Int(expire.timeIntervalSinceNow)
            if diff <= 0 {
                return "0d 0h 0m"
            }
            let days = diff / 86400
            let hours = (diff % 86400) / 3600
            let minutes = (diff % 3600) / 60
            return "\(days)d \(hours)h \(minutes)m"
        }
        return "\(daysLeft) ngày"
    }
    
    func updateCountdown() {
        countdownText = formattedRemainingCountdown
    }
    
    var deviceUUID: String {
        if let stored = UserDefaults.standard.string(forKey: uuidStorageKey), !stored.isEmpty {
            return stored
        }
        let newUUID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: uuidStorageKey)
        return newUUID
    }
    
    private init() {
        if let saved = loadFromStorage() {
            self.savedKey = saved.key
            self.expiryDate = saved.expiry
            self.daysLeft = saved.days
        }
    }
    
    func saveToStorage() {
        let dict: [String: Any] = [
            "serverUrl": Self.apiURL,
            "packageToken": Self.packageToken,
            "savedKey": savedKey,
            "deviceUuid": deviceUUID,
            "daysLeft": daysLeft,
            "expiryDate": expiryDate
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) else { return }
        
        // 1. Luôn ưu tiên ghi vào /var/mobile/Documents/.ntamod_license.json
        let primaryPath = Self.licenseFilePath
        let parentDir = (primaryPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: primaryPath), options: .atomic)
        
        // 2. Nếu đang trên máy ảo không có quyền /var/mobile, ghi vào fallback
        if !Self.canAccessVarMobile() {
            let fallbackPath = Self.effectiveLicensePath
            let fbParent = (fallbackPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: fbParent, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: fallbackPath), options: .atomic)
        }
    }
    
    func loadFromStorage() -> (key: String, expiry: String, days: Int)? {
        let paths = [Self.licenseFilePath, Self.effectiveLicensePath]
        for p in paths {
            if FileManager.default.fileExists(atPath: p),
               let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
                let key = (json["savedKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let expiry = (json["expiryDate"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let days = json["daysLeft"] as? Int ?? (Int((json["daysLeft"] as? String) ?? "") ?? 0)
                if !key.isEmpty {
                    return (key, expiry, days)
                }
            }
        }
        return nil
    }
    
    func deleteStorageFile() {
        try? FileManager.default.removeItem(atPath: Self.licenseFilePath)
        if !Self.canAccessVarMobile() {
            try? FileManager.default.removeItem(atPath: Self.effectiveLicensePath)
        }
    }
    
    /// Quét trực tiếp ổ đĩa mỗi 1 giây (1000ms):
    /// - Khi key bị xóa khỏi ổ đĩa (/var/mobile/Documents/.ntamod_license.json) hoặc hết hạn:
    ///   Lập tức văng về màn nhập key ngay thời gian thực, không cần vào lại app!
    func checkDiskLicenseAndExpiry() {
        guard isAuthenticated else { return }
        
        let primaryPath = Self.licenseFilePath
        let targetPath = Self.canAccessVarMobile() ? primaryPath : Self.effectiveLicensePath
        
        var fileExists = FileManager.default.fileExists(atPath: targetPath)
        if !fileExists && FileManager.default.fileExists(atPath: primaryPath) {
            fileExists = true
        }
        
        // 1. Tệp key bị xóa khỏi ổ đĩa -> VĂNG NGAY LẬP TỨC
        if !fileExists {
            DispatchQueue.main.async {
                self.invalidateAndRestoreGoc(reason: "Tệp bản quyền đã bị xóa khỏi thiết bị!")
            }
            return
        }
        
        // 2. Tệp key trống hoặc bị sửa đổi -> VĂNG NGAY LẬP TỨC
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: targetPath)),
              let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            DispatchQueue.main.async {
                self.invalidateAndRestoreGoc(reason: "Tệp bản quyền bị lỗi hoặc trống!")
            }
            return
        }
        
        let fileKey = (json["savedKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if fileKey.isEmpty || fileKey != savedKey {
            DispatchQueue.main.async {
                self.invalidateAndRestoreGoc(reason: "Mã key trong tệp không hợp lệ!")
            }
            return
        }
        
        // 3. Kiểm tra hạn dùng
        if !expiryDate.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? TimeZone(secondsFromGMT: 7 * 3600)
            if let expire = formatter.date(from: expiryDate) {
                if expire.timeIntervalSinceNow <= 0 {
                    DispatchQueue.main.async {
                        self.invalidateAndRestoreGoc(reason: "Mã key đã hết hạn sử dụng!")
                    }
                    return
                }
            }
        }
        
        updateCountdown()
    }
    
    func autoCheck() {
        guard let saved = loadFromStorage(), !saved.key.isEmpty else {
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.initialCheckDone = true
            }
            return
        }
        
        self.savedKey = saved.key
        self.expiryDate = saved.expiry
        self.daysLeft = saved.days
        self.isAuthenticated = true
        self.updateCountdown()
        self.startPeriodicValidation()
        
        verifyKey(saved.key, isAuto: true) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.initialCheckDone = true
            }
        }
    }
    
    func verifyKey(_ key: String, isAuto: Bool = false, completion: ((Bool, String?) -> Void)? = nil) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "Vui lòng nhập key!"
                completion?(false, "Vui lòng nhập key!")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isChecking = true
            self.errorMessage = nil
        }
        
        var components = URLComponents(string: Self.apiURL)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "check"),
            URLQueryItem(name: "token", value: Self.packageToken),
            URLQueryItem(name: "key", value: cleanKey),
            URLQueryItem(name: "uuid", value: self.deviceUUID)
        ]
        
        guard let url = components?.url else {
            DispatchQueue.main.async {
                self.isChecking = false
                self.errorMessage = "URL không hợp lệ"
                completion?(false, "URL không hợp lệ")
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isChecking = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    let msg = "Lỗi kết nối máy chủ: \(error.localizedDescription)"
                    self.errorMessage = msg
                    if !isAuto {
                        self.deleteStorageFile()
                    }
                    completion?(false, msg)
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                DispatchQueue.main.async {
                    let msg = "Phản hồi từ server không hợp lệ"
                    self.errorMessage = msg
                    completion?(false, msg)
                }
                return
            }
            
            let status = json["status"] as? Bool ?? false
            let message = json["message"] as? String ?? ""
            let contact = json["contact"] as? String ?? ""
            let expiry = json["expiry"] as? String ?? ""
            let days = json["days_left"] as? Int ?? 0
            
            DispatchQueue.main.async {
                if !contact.isEmpty {
                    self.contactLink = contact
                }
                
                if status {
                    self.isAuthenticated = true
                    self.savedKey = cleanKey
                    self.expiryDate = expiry
                    self.daysLeft = days
                    self.errorMessage = nil
                    self.saveToStorage()
                    self.updateCountdown()
                    self.startPeriodicValidation()
                    completion?(true, nil)
                } else {
                    let displayMsg = message.isEmpty ? "Mã key không hợp lệ hoặc đã hết hạn!" : message
                    self.invalidateAndRestoreGoc(reason: displayMsg)
                    completion?(false, displayMsg)
                }
            }
        }.resume()
    }
    
    func startPeriodicValidation() {
        stopPeriodicValidation()
        checkDiskLicenseAndExpiry()
        
        // Bật giữ tiến trình chạy ngầm qua BackgroundKeeper
        BackgroundKeeper.shared.start()
        
        // Quét trực tiếp ổ đĩa mỗi 1 giây (1000ms) trên RunLoop common (không bị dừng khi cuộn giao diện)
        let diskTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkDiskLicenseAndExpiry()
        }
        RunLoop.main.add(diskTimer, forMode: .common)
        self.diskScanTimer = diskTimer
        
        // Revalidate với server mỗi 20 giây (bắt nhanh việc admin xóa key trên server ngay cả khi chạy ngầm)
        let netTimer = Timer(timeInterval: 20.0, repeats: true) { [weak self] _ in
            self?.revalidateCurrentKey()
        }
        RunLoop.main.add(netTimer, forMode: .common)
        self.validationTimer = netTimer
    }
    
    func stopPeriodicValidation() {
        diskScanTimer?.invalidate()
        diskScanTimer = nil
        validationTimer?.invalidate()
        validationTimer = nil
        BackgroundKeeper.shared.stop()
    }
    
    func revalidateCurrentKey() {
        guard !savedKey.isEmpty, isAuthenticated else { return }
        verifyKey(savedKey, isAuto: true)
    }
    
    func invalidateAndRestoreGoc(reason: String? = nil) {
        stopPeriodicValidation()
        deleteStorageFile()
        UserDefaults.standard.set(false, forKey: "nta_aim_co")
        savedKey = ""
        expiryDate = ""
        daysLeft = 0
        countdownText = ""
        isAuthenticated = false
        if let reason = reason {
            errorMessage = reason
        }
        // Restore cache_goc to game directory and turn off mod
        _ = FFModService.shared.restoreGoc(isMax: false)
    }
    
    func logout() {
        invalidateAndRestoreGoc(reason: nil)
    }
}

// MARK: - Background Keeper (Giữ tiến trình chạy ngầm siêu nhẹ với Silent Audio)
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()
    private var audioPlayer: AVAudioPlayer?
    private var isRunning = false
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log("BackgroundKeeper: failed to set audio session: \(error)")
        }
        
        let wavData = createSilentWavData()
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1 // Lặp vô tận
            audioPlayer?.volume = 0.0 // Hoàn toàn im lặng, không ảnh hưởng game
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            log("BackgroundKeeper: background execution active via silent audio")
        } catch {
            log("BackgroundKeeper: failed to start audioPlayer: \(error)")
        }
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        log("BackgroundKeeper: background execution stopped")
    }
    
    private func createSilentWavData() -> Data {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000
        let subchunk2Size = numSamples
        let chunkSize = 36 + subchunk2Size
        
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        var cs = chunkSize.littleEndian
        data.append(Data(bytes: &cs, count: 4))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
        data.append(Data(bytes: &audioFormat, count: 2))
        var numChannels: UInt16 = 1
        data.append(Data(bytes: &numChannels, count: 2))
        var sr = sampleRate.littleEndian
        data.append(Data(bytes: &sr, count: 4))
        var byteRate = (sampleRate * 1).littleEndian
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: UInt16 = 1
        data.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 8
        data.append(Data(bytes: &bitsPerSample, count: 2))
        data.append(contentsOf: "data".utf8)
        var ds = subchunk2Size.littleEndian
        data.append(Data(bytes: &ds, count: 4))
        let silence = [UInt8](repeating: 0x80, count: Int(numSamples))
        data.append(contentsOf: silence)
        return data
    }
}
