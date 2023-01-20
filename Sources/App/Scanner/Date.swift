import Foundation
import NIO

// A Date formatter based on Vapor's RFC1123
private final class MangaseeTime {
    private static let thread: ThreadSpecificVariable<MangaseeTime> = .init()

    static var shared: MangaseeTime {
        if let existing = thread.currentValue {
            return existing
        } else {
            let new = MangaseeTime()
            thread.currentValue = new
            return new
        }
    }

    private let formatter: DateFormatter

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)
        formatter.calendar = Calendar(identifier: .gregorian)
        self.formatter = formatter
    }

    func date(from string: String) -> Date? {
        return formatter.date(from: string)
    }
}

extension Date {
    init?(mangaseeTime time: String) {
        guard let date = MangaseeTime.shared.date(from: time) else {
            print("Failed to parse date \(time)")
            return nil
        }

        self = date
    }
}
