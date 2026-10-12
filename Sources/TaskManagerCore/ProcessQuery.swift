import Foundation

public enum ProcessQuery {
    public static func filter(_ records: [ProcessRecord], query: String) -> [ProcessRecord] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return records }
        return records.filter { record in
            let fields = [record.name, String(record.id.pid), record.user, record.executablePath ?? ""]
            return terms.allSatisfy { term in fields.contains { $0.localizedCaseInsensitiveContains(term) } }
        }
    }
}
