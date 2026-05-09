import Foundation

let url = URL(fileURLWithPath: "/Users/henery/.openclaw/agents/main/sessions/191badcb-b891-4a51-b899-7b7e95f63b43.trajectory.jsonl")
let data = try Data(contentsOf: url)
let content = String(data: data, encoding: .utf8)!

let iso8601Formatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

let iso8601FormatterNoFraction: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()

var count = 0
var latestDate: Date? = nil
for line in content.split(separator: "\n") {
  guard let lineData = line.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
        let type = obj["type"] as? String,
        type == "model.completed" else { continue }
        
  count += 1
  if let tsString = obj["ts"] as? String {
    let date = iso8601Formatter.date(from: tsString) ?? iso8601FormatterNoFraction.date(from: tsString)
    print("Parsed \(tsString) -> \(date != nil ? "Success" : "Failed")")
    if let date {
      if latestDate == nil || date > latestDate! { latestDate = date }
    }
  }
}
print("Total model.completed: \(count), Latest date: \(String(describing: latestDate))")
