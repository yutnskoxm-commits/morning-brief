import Cocoa
import WebKit

// ── Native Fetch Handler: 绕过 CORS ──────────────────────
// WKWebView 中的 JS fetch 受 CORS 限制，但原生 URLSession 不受。
// 此 Handler 拦截 JS 层对特定 URL 的 fetch 调用，通过原生网络请求后再返回给 JS。
class NativeFetchHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "nativeFetch",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let urlStr = body["url"] as? String,
              let url = URL(string: urlStr)
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String) ?? "GET"
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            let responseText: String
            if let error = error {
                // 返回带 error 字段的 JSON，让 JS 端降级处理
                responseText = "{\"__nativeError\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "'"))\"}"
            } else if let data = data, let text = String(data: data, encoding: .utf8) {
                responseText = text
            } else {
                responseText = "null"
            }

            // 安全转义：反斜杠 → 双反斜杠，单引号 → \'
            let escaped = responseText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")

            let js = """
            (function(){
                var cb=window.__nativeCallbacks&&window.__nativeCallbacks['\(id)'];
                if(cb){
                    cb.resolve(new Response('\(escaped)',{status:200,headers:{'Content-Type':'application/json'}}));
                    delete window.__nativeCallbacks['\(id)'];
                }
            })();
            """

            DispatchQueue.main.async {
                self?.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        task.resume()
    }
}


// ── App Delegate ──────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 窗口
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
        window.titlebarAppearsTransparent = false

        // ── WKWebView 配置 ──────────────────────────────
        let contentController = WKUserContentController()

        // 注入脚本：拦截 Yahoo Finance 等 CORS 受限 URL，转为原生请求
        let proxyScript = """
        (function(){
            var PROXY_HOSTS=['yahoo.com','finance.yahoo.com','query1.finance.yahoo.com',
                             'query2.finance.yahoo.com','api.metals.live'];
            function shouldProxy(url){
                var s=typeof url==='string'?url:(url.url||'');
                for(var i=0;i<PROXY_HOSTS.length;i++){
                    if(s.indexOf(PROXY_HOSTS[i])!==-1)return true;
                }
                return false;
            }
            window.__nativeCallbacks={};
            window.__nativeFetch=function(url,options){
                return new Promise(function(resolve,reject){
                    var id='nf_'+Date.now()+'_'+Math.floor(Math.random()*1000000);
                    window.__nativeCallbacks[id]={resolve:resolve,reject:reject};
                    window.webkit.messageHandlers.nativeFetch.postMessage({
                        id:id,
                        url:typeof url==='string'?url:url.url,
                        method:(options&&options.method)||'GET'
                    });
                });
            };
            var _fetch=window.fetch;
            window.fetch=function(url,options){
                if(shouldProxy(url)){
                    console.log('[FinFlash] Native proxy:',typeof url==='string'?url:url.url);
                    return window.__nativeFetch(url,options);
                }
                return _fetch.apply(this,arguments);
            };
        })();
        """

        let userScript = WKUserScript(
            source: proxyScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)

        let handler = NativeFetchHandler()
        contentController.add(handler, name: "nativeFetch")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // WebView
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        handler.webView = webView

        window.contentView?.addSubview(webView)

        // 加载
        let url = URL(string: "https://yutnskoxm-commits.github.io/morning-brief/")!
        webView.load(URLRequest(url: url))

        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}


// ── Main ──────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
