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
                Image("logo1")
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                Text("影视星河设备管理系统")
                    .font(.title2.bold()).foregroundColor(.white)
                Text("v4.0 · 苹果原生版")
                    .font(.footnote).foregroundColor(.white.opacity(0.85))
                VStack(spacing: 14) {
                    ZStack(alignment: .leading) {
                        if username.isEmpty {
                            Text("请输入用户名").foregroundColor(Color(hex: 0x9ca3af)).padding(.horizontal, 14)
                        }
                        TextField("", text: $username)
                            .padding(12).foregroundColor(.black)
                            .autocapitalization(.none) // iOS15: .textInputAutocapitalization(.never)
                    }
                    .background(Color(hex: 0xf5f5f5)).cornerRadius(8)
                    ZStack(alignment: .leading) {
                        if password.isEmpty {
                            Text("请输入密码").foregroundColor(Color(hex: 0x9ca3af)).padding(.horizontal, 14)
                        }
                        SecureField("", text: $password)
                            .padding(12).foregroundColor(.black)
                    }
                    .background(Color(hex: 0xf5f5f5)).cornerRadius(8)
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
                    if r["success"] as? Bool == true, let d = r["data"] as? [String: Any], !Api.str(d, "token").isEmpty {
                        session.token = Api.str(d, "token")
                        session.userId = Api.str(d, "id")
                        session.username = Api.str(d, "username")
                        session.displayName = Api.str(d, "display_name")
                        session.role = Api.str(d, "role")
                        session.loggedIn = true
                        PushMonitor.shared.start()
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
