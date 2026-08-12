import SwiftUI

struct LoginView: View {
    @StateObject private var session = Session.shared
    @State private var username = ""
    @State private var password = ""
    @State private var msg = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1a2980), Color(hex: 0x26d0ce)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("🎬").font(.system(size: 56))
                Text("影视星河设备管理系统")
                    .font(.title2.bold()).foregroundColor(.white)
                Text("v4.0 · 苹果原生版")
                    .font(.footnote).foregroundColor(.white.opacity(0.85))
                VStack(spacing: 14) {
                    TextField("用户名", text: $username)
                        .padding(12).background(Color(hex: 0xf5f5f5)).cornerRadius(8)
                        .autocapitalization(.none) // iOS15: .textInputAutocapitalization(.never)
                    SecureField("密码", text: $password)
                        .padding(12).background(Color(hex: 0xf5f5f5)).cornerRadius(8)
                    Button(action: doLogin) {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text("登 录").fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity).padding(12)
                        .background(LinearGradient(colors: [Color(hex: 0x1a2980), Color(hex: 0x1890ff)],
                                                   startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(8)
                    }
                    .disabled(busy)
                }
                .padding(22)
                .background(Color.white).cornerRadius(16)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.horizontal, 28)
                if !msg.isEmpty {
                    Text(msg).font(.footnote).foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.top, 60)
        }
    }

    func doLogin() {
        if username.isEmpty || password.isEmpty { msg = "请输入用户名和密码"; return }
        busy = true; msg = ""
        Task {
            do {
                let r = try await Api.post("/api/auth/login", ["username": username, "password": password])
                await MainActor.run {
                    busy = false
                    if r["success"] as? Bool == true, let d = r["data"] as? [String: Any], let u = d["user"] as? [String: Any] {
                        session.token = Api.str(d, "token")
                        session.userId = Api.str(u, "id")
                        session.username = Api.str(u, "username")
                        session.displayName = Api.str(u, "display_name")
                        session.role = Api.str(u, "role")
                        session.loggedIn = true
                    } else {
                        msg = Api.str(r, "message").isEmpty ? "登录失败" : Api.str(r, "message")
                    }
                }
            } catch {
                await MainActor.run { busy = false; msg = "网络错误：\(error.localizedDescription)" }
            }
        }
    }
}
