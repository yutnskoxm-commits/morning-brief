import Cocoa
import WebKit

// ═══════════════════════════════════════════════════════════
// FinFlash Desktop — macOS Native App
// 原理：用原生 URLSession 获取所有 API 数据（无 CORS 限制），
// 通过 WKUserScript 在页面加载前注入 window.__finflashNative，
// 页面的 main() 在 JSON 404 时会优先使用注入数据，不再触发 CORS 报错。
// ═══════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 1100, height: 820)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FinFlash"
        window.center()
        window.minSize = NSSize(width: 800, height: 600)

        // 先获取原生数据，再加载页面
        fetchAllNativeData { [weak self] nativeJSON in
            self?.loadPage(with: nativeJSON)
        }

        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // ── 页面加载 ─────────────────────────────────────────

    func loadPage(with nativeJSON: String?) {
        let contentController = WKUserContentController()

        // 注入原生数据（在页面任何脚本执行前）
        if let json = nativeJSON {
            let script = "window.__finflashNative = \(json);"
            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            contentController.addUserScript(userScript)
            print("[FinFlash] Native data will be injected at document start")
        } else {
            print("[FinFlash] JSON report exists, no native data needed")
        }

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)

        let url = URL(string: "https://yutnskoxm-commits.github.io/morning-brief/")!
        webView.load(URLRequest(url: url))
    }

    // ── 原生 API 数据获取 ────────────────────────────────

    func fetchAllNativeData(completion: @escaping (String?) -> Void) {
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let dateISO = dateISOString()

        // 先检查今天的 JSON 报告是否已存在
        group.enter()
        queue.async {
            self.httpGet("https://yutnskoxm-commits.github.io/morning-brief/reports/\(dateISO).json") { data in
                if data != nil {
                    // JSON 报告存在，不需要原生数据
                    print("[FinFlash] JSON report found for \(dateISO), skipping native fetch")
                }
                group.leave()
            }
        }

        // 同步获取所有 API 数据
        var cryptoData: [String: Any]?
        var fgData: [String: Any]?
        var goldPrice: Double?
        var stocks: [String: [String: Any]] = [:]
        let symbols = ["000001.SS", "^HSI", "^GSPC", "^IXIC", "^DJI", "CL=F"]

        group.enter(); queue.async {
            self.httpGet("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true&include_market_cap=true") { cryptoData = $0; group.leave() }
        }
        group.enter(); queue.async {
            self.httpGet("https://api.alternative.me/fng/?limit=1") { fgData = $0; group.leave() }
        }
        group.enter(); queue.async {
            self.httpGetArray("https://api.metals.live/v1/spot/gold") { arr in
                if let first = arr?.first, let price = first["price"] as? Double {
                    goldPrice = price
                }
                group.leave()
            }
        }
        for sym in symbols {
            group.enter(); queue.async {
                let url = "https://query1.finance.yahoo.com/v8/finance/chart/\(sym)?interval=1d&range=5d"
                self.httpGet(url) { stocks[sym] = $0; group.leave() }
            }
        }

        group.notify(queue: .main) {
            let native = self.buildData(crypto: cryptoData, fg: fgData, gold: goldPrice, stocks: stocks)
            let json = self.serialize(native)
            completion(json)
        }
    }

    // ── 数据组装 ─────────────────────────────────────────

    func buildData(
        crypto: [String: Any]?,
        fg: [String: Any]?,
        gold: Double?,
        stocks: [String: [String: Any]]
    ) -> [String: Any] {
        var data: [String: Any] = [:]

        // Crypto
        var c: [String: Any] = [:]
        if let raw = crypto {
            let b = raw["bitcoin"] as? [String: Any] ?? [:]
            let e = raw["ethereum"] as? [String: Any] ?? [:]
            c["btc"] = ["price": b["usd"] ?? 0, "change": b["usd_24h_change"] ?? 0, "mc": b["usd_market_cap"] ?? 0]
            c["eth"] = ["price": e["usd"] ?? 0, "change": e["usd_24h_change"] ?? 0, "mc": e["usd_market_cap"] ?? 0]
        }
        data["crypto"] = c

        // Fear & Greed
        var f: [String: Any] = [:]
        if let raw = fg, let arr = raw["data"] as? [[String: Any]], let first = arr.first {
            f["value"] = Int(first["value"] as? String ?? "0") ?? 0
            f["label"] = first["value_classification"] ?? ""
        }
        data["fg"] = f

        // Gold
        if let p = gold { data["gold"] = ["price": p] }
        else { data["gold"] = [:] }

        // Stocks
        var sd: [String: Any] = [:]
        let keys = ["sse", "hsi", "sp500", "nasdaq", "dji", "oil"]
        let names = ["000001.SS", "^HSI", "^GSPC", "^IXIC", "^DJI", "CL=F"]
        for (i, name) in names.enumerated() {
            if let raw = stocks[name] {
                sd[keys[i]] = parseYahoo(raw)
            }
        }
        data["stocks"] = sd

        return data
    }

    func parseYahoo(_ raw: [String: Any]) -> [String: Any] {
        guard let chart = raw["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any]
        else { return [:] }
        let price = meta["regularMarketPrice"] as? Double ?? 0
        let prev = meta["previousClose"] as? Double ?? 0
        let change = prev > 0 ? ((price - prev) / prev) * 100 : 0
        return ["price": price, "change": change]
    }

    // ── 工具函数 ─────────────────────────────────────────

    func dateISOString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    func httpGet(_ urlStr: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard error == nil, let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { completion(nil); return }
            completion(json)
        }.resume()
    }

    func httpGetArray(_ urlStr: String, completion: @escaping ([[String: Any]]?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard error == nil, let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]]
            else { completion(nil); return }
            completion(json)
        }.resume()
    }

    func serialize(_ dict: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }
}

// ── Main ──────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
