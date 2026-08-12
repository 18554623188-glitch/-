import SwiftUI

// 影视星河设备管理系统 v4.0 · 苹果原生版（SwiftUI）
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
    func logout() {
        Task { try? await Api.post("/api/auth/logout", [:]) }
        token = ""; userId = ""; role = ""; username = ""; displayName = ""
        loggedIn = false
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
    static func delete(_ p: String) async throws -> [String: Any] { try await request("DELETE", p) }

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

// 状态徽章（正常/维修中/闲置/已报废）
struct StatusBadge: View {
    let status: String
    private var color: Color {
        switch status {
        case "正常": return Color(hex: 0x52c41a)
        case "维修中": return Color(hex: 0xfa8c16)
        case "已报废": return Color(hex: 0xff4d4f)
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

// 白色圆角卡片
struct CardBG: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}
extension View {
    func card() -> some View { modifier(CardBG()) }
}
