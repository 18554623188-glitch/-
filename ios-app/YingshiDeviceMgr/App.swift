import SwiftUI
import UIKit
import UserNotifications

// 影视星河设备管理系统 v5.0 · 苹果原生版（SwiftUI）
// 与鸿蒙端同功能同界面：登录/首页(天气+统计)/设备(扫码)/人员(登录下线时间)/消息(已读回执+群管理)/通知(管理员发布)/我的

@main
struct YingshiApp: App {
    @StateObject private var session = Session.shared
    var body: some Scene {
        WindowGroup {
            if session.loggedIn {
                MainView()
            } else {
                LoginView()
            }
            // 跟随系统深浅色：界面颜色全部通过 T 动态色适配，深色模式下自动切换深色背景/浅色文字
        }
    }
}

final class Session: ObservableObject {
    static let shared = Session()
    static let base = "http://47.104.244.29:3001"
    @Published var loggedIn = false
    var token = ""
    var userId = ""
    var role = ""
    var username = ""
    var displayName = ""

    private init() { restore() }

    // 登录态本地持久化：iOS 后台回收进程后再次启动可恢复 token，无需重新登录
    func persist() {
        let d = UserDefaults.standard
        d.set(token, forKey: "session_token")
        d.set(userId, forKey: "session_userId")
        d.set(role, forKey: "session_role")
        d.set(username, forKey: "session_username")
        d.set(displayName, forKey: "session_displayName")
    }

    private func restore() {
        let d = UserDefaults.standard
        let t = d.string(forKey: "session_token") ?? ""
        guard !t.isEmpty else { return }
        token = t
        userId = d.string(forKey: "session_userId") ?? ""
        role = d.string(forKey: "session_role") ?? ""
        username = d.string(forKey: "session_username") ?? ""
        displayName = d.string(forKey: "session_displayName") ?? ""
        loggedIn = true
        // 启动推送轮询（start 内部会异步到主线程执行，避免启动早期同步调用导致崩溃/闪退）
        PushMonitor.shared.start()
        // 后台校验 token 有效性：已失效（如服务器重启）才退回登录页，网络不可用时保持登录态
        Task { [weak self] in
            let r = try? await Api.get("/api/auth/me")
            guard let self else { return }
            if let r, (r["success"] as? Bool) != true {
                await MainActor.run { self.logout(silent: true) }
            }
        }
    }

    func logout(silent: Bool = false) {
        if !silent { Task { try? await Api.post("/api/auth/logout", [:]) } }
        PushMonitor.shared.stop()
        // @Published 属性必须在主线程修改，否则 SwiftUI 运行时崩溃（本方法可能从异步 Task 调用）
        let work = { [weak self] in
            guard let self else { return }
            self.token = ""; self.userId = ""; self.role = ""; self.username = ""; self.displayName = ""
            let d = UserDefaults.standard
            d.removeObject(forKey: "session_token")
            d.removeObject(forKey: "session_userId")
            d.removeObject(forKey: "session_role")
            d.removeObject(forKey: "session_username")
            d.removeObject(forKey: "session_displayName")
            self.loggedIn = false
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}

// 四端统一推送：8 秒轮询 push_events + 系统通知栏（与安卓/鸿蒙/电脑端同架构）
final class PushMonitor {
    static let shared = PushMonitor()
    private var timer: Timer?
    private var polling = false
    private var cursor = UserDefaults.standard.integer(forKey: "push_cursor")
    private var firstSync = UserDefaults.standard.integer(forKey: "push_cursor") == 0

    func start() {
        // 统一异步到主线程启动，避免在启动早期/非主线程创建 Timer 或请求通知权限导致崩溃
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            self.timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
                self?.poll()
            }
            self.poll()
        }
    }

    func stop() {
        // Timer 必须在主线程 invalidate，跨线程调用会崩溃
        DispatchQueue.main.async { [weak self] in
            self?.stopTimer()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let s = Session.shared
        guard s.loggedIn, !s.token.isEmpty, !polling else { return }
        polling = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.polling = false }
            let r = try? await Api.get("/api/push/events?after=\(self.cursor)")
            guard let r, let rows = r["data"] as? [[String: Any]], !rows.isEmpty else { return }
            var maxId = self.cursor
            for row in rows {
                let id = Api.int(row, "id")
                if id > maxId { maxId = id }
                if !self.firstSync {
                    let content = UNMutableNotificationContent()
                    let t = Api.str(row, "title")
                    content.title = t.isEmpty ? "系统消息" : t
                    content.body = Api.str(row, "body")
                    content.sound = .default
                    let req = UNNotificationRequest(identifier: "push-\(id)", content: content, trigger: nil)
                    try? await UNUserNotificationCenter.current().add(req)
                }
            }
            self.cursor = maxId
            self.firstSync = false
            UserDefaults.standard.set(maxId, forKey: "push_cursor")
        }
    }
}

enum ApiError: LocalizedError {
    case bad(String)
    var errorDescription: String? {
        if case .bad(let s) = self { return s }
        return "网络错误"
    }
}

enum Api {
    static func request(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: Session.base + path) else { throw ApiError.bad("URL 无效") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        let s = Session.shared
        if !s.token.isEmpty { req.setValue("Bearer " + s.token, forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    static func get(_ p: String) async throws -> [String: Any] { try await request("GET", p) }
    static func post(_ p: String, _ b: [String: Any]) async throws -> [String: Any] { try await request("POST", p, b) }
    static func patch(_ p: String, _ b: [String: Any]) async throws -> [String: Any] { try await request("PATCH", p, b) }
        static func put(_ p: String, _ b: [String: Any]) async throws -> [String: Any] { try await request("PUT", p, b) }
    static func delete(_ p: String) async throws -> [String: Any] { try await request("DELETE", p) }

    // 下载附件原始字节（Authorization 头鉴权，用于图片预览/保存）
    static func download(_ path: String) async throws -> Data {
        guard let url = URL(string: Session.base + path) else { throw ApiError.bad("URL 无效") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        let s = Session.shared
        if !s.token.isEmpty { req.setValue("Bearer " + s.token, forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { throw ApiError.bad("下载失败") }
        return data
    }

    static func arr(_ r: [String: Any]) -> [[String: Any]] { r["data"] as? [[String: Any]] ?? [] }
    static func dict(_ r: [String: Any]) -> [String: Any] { r["data"] as? [String: Any] ?? [:] }
    static func str(_ d: [String: Any], _ k: String) -> String {
        if let v = d[k] as? String { return v }
        if let v = d[k] as? Int { return String(v) }
        if let v = d[k] as? Double { return String(Int(v)) }
        return ""
    }
    static func int(_ d: [String: Any], _ k: String) -> Int {
        if let v = d[k] as? Int { return v }
        if let v = d[k] as? String { return Int(v) ?? 0 }
        return 0
    }

    // 聊天附件上传（multipart/form-data，字段名 file）
    static func uploadFile(data: Data, fileName: String, mime: String) async throws -> [String: Any] {
        guard let url = URL(string: Session.base + "/api/chat/upload") else { throw ApiError.bad("URL 无效") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        let s = Session.shared
        if !s.token.isEmpty { req.setValue("Bearer " + s.token, forHTTPHeaderField: "Authorization") }
        let boundary = "----YingshiBoundary" + UUID().uuidString
        req.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (rd, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: rd) as? [String: Any]) ?? [:]
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

// 全局主题色（四端统一视觉规范）：深浅色动态适配，跟随系统外观自动切换
extension UIColor {
    convenience init(hex: UInt) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: 1)
    }
}

enum T {
    // 深浅动态色：light 值 / dark 值
    static func dyn(_ l: UInt, _ d: UInt) -> Color {
        Color(UIColor { t in t.userInterfaceStyle == .dark ? UIColor(hex: d) : UIColor(hex: l) })
    }
    static let brand = Color(hex: 0x1890ff)          // 品牌蓝
    static let brandDeep = Color(hex: 0x1a2980)      // 渐变深蓝
    static let brandTeal = Color(hex: 0x26d0ce)      // 渐变青
    static let purple = Color(hex: 0x722ed1)         // 扫码/群聊紫
    static let textMain = dyn(0x262626, 0xe6e6e6)    // 主文字
    static let textSub = dyn(0x595959, 0xa6a6a6)     // 次级文字
    static let textHint = dyn(0x8c8c8c, 0x8c8c8c)    // 辅助文字
    static let textFaint = dyn(0xbfbfbf, 0x595959)   // 弱化文字
    static let pageBG = dyn(0xf5f6f8, 0x141414)      // 页面底色
    static let inputBG = dyn(0xf5f5f5, 0x262626)     // 输入框底色
    static let card = dyn(0xffffff, 0x1f1f1f)        // 卡片背景
    static let chipBG = dyn(0xf0f0f0, 0x2a2a2a)      // 未选中 chip
    static let bannerBG = dyn(0xe6f4ff, 0x11203a)    // 提示条背景
    static let chatBG = dyn(0xfafafa, 0x181818)      // 聊天区背景
    static let green = Color(hex: 0x52c41a)
    static let orange = Color(hex: 0xfa8c16)
    static let red = Color(hex: 0xff4d4f)
}

// 状态徽章（正常/维修中/闲置/已报废/借用中）
struct StatusBadge: View {
    let status: String
    private var color: Color {
        switch status {
        case "正常": return Color(hex: 0x52c41a)
        case "维修中": return Color(hex: 0xfa8c16)
        case "已报废": return Color(hex: 0xff4d4f)
        case "借用中": return Color(hex: 0x1890ff)
        default: return Color(hex: 0x8c8c8c)
        }
    }
    var body: some View {
        Text(status)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color).cornerRadius(4)
    }
}

// Liquid Glass 背景：运行时动态加载 iOS 26 UIGlassEffect（低版本 SDK 也可编译），非 iOS 26 回退系统薄雾
struct GlassBackground: UIViewRepresentable {
    var corner: CGFloat
    func makeUIView(context: Context) -> UIVisualEffectView {
        let v = UIVisualEffectView()
        if let cls = NSClassFromString("UIGlassEffect") as? UIVisualEffect.Type {
            v.effect = cls.init()
        } else {
            v.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        v.layer.cornerRadius = corner
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        return v
    }
    func updateUIView(_ v: UIVisualEffectView, context: Context) {
        v.layer.cornerRadius = corner
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
    }
}

// Liquid Glass 统一入口：iOS 26+ 真液态玻璃，低版本回退动态色卡片
extension View {
    @ViewBuilder
    func glass(corner: CGFloat = 14) -> some View {
        if #available(iOS 26.0, *) {
            self.background(GlassBackground(corner: corner))
        } else {
            self.background(T.card)
                .cornerRadius(corner)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
}

// 圆角卡片（iOS 26+ 液态玻璃 / 低版本深浅动态背景 + 柔和阴影）
struct CardBG: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(14)
                .background(GlassBackground(corner: 14))
        } else {
            content
                .padding(14)
                .background(T.card)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
}
extension View {
    func card() -> some View { modifier(CardBG()) }
}
