import WebKit

class StreamDelegate: NSObject, URLSessionDataDelegate {
    let webView: WKWebView
    let parser:  StreamParser
    var buffer = Data()

    init(webView: WKWebView, parser: StreamParser) {
        self.webView = webView; self.parser = parser
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        let str   = String(data: buffer, encoding: .utf8) ?? ""
        let lines = str.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            guard !line.isEmpty, i < lines.count - 1 else { continue }
            if let token = parser.token(from: line) {
                let escaped = token
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                DispatchQueue.main.async {
                    self.webView.evaluateJavaScript("appendToken(`\(escaped)`)", completionHandler: nil)
                }
            }
        }
        buffer = lines.last.flatMap { $0.isEmpty ? nil : $0.data(using: .utf8) } ?? Data()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let isError = error != nil
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("endStream(\(isError))", completionHandler: nil)
        }
    }
}
