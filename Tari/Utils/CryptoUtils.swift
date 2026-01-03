import CryptoKit
import Foundation

// MARK: - SHA256 哈希工具类
extension Data {
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

struct CryptoUtils {
    static func sha256(_ data: Data) -> Data {
        return Data(SHA256.hash(data: data))
    }
    
    static func sha256(_ string: String) -> Data {
        guard let data = string.data(using: .utf8) else {
            return Data()
        }
        return sha256(data)
    }
    
    static func sha256Hex(_ string: String) -> String {
        return sha256(string).hexString
    }
    
    static func sha256Hex(_ data: Data) -> String {
        return sha256(data).hexString
    }
}
