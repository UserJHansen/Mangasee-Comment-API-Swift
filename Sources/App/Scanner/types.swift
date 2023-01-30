import Foundation

struct MangaseeResponse<T: Codable>: Codable {
    let success: Bool
    let val: T
}

extension JSONDecoder.DateDecodingStrategy {
    static var mangasee: JSONDecoder.DateDecodingStrategy {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)
        formatter.calendar = Calendar(identifier: .gregorian)
        return .formatted(formatter)
    }
}
