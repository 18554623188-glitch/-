import SwiftUI

struct LoginView: View {
    @StateObject private var session = Session.shared
    @State private var username = ""
    @State private var password = ""
    @State private var msg = ""
    @State private var busy = false
    // 0=登录 1=注册 2=忘记密码
    @State private var mode = 0
    @State private var displayName = ""
    @State private var confirmPwd = ""
    @State private var phone = ""

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
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                Text("影视星河设备管理系统")
                    .font(.title2.bold()).foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                Text("v5.2 · 苹果原生版")
                    .font(.footnote).foregroundColor(.white.opacity(0.9))
                VStack(spacing: 14) {
                    ZStack(alignment: .leading) {
                        if username.isEmpty {
                            Text("请输入用户名").foregroundColor(T.textHint).padding(.horizontal, 14)
                        }
                        TextField("", text: $username)
                            .padding(12).foregroundColor(T.textMain)
                            .autocapitalization(.none) // iOS15: .textInputAutocapitalization(.never)
                    }
                    .background(T.inputBG).cornerRadius(10)
                    if mode == 1 {
                        ZStack(alignment: .leading) {
                            if displayName.isEmpty {
                                Text("昵称（显示名称）").foregroundColor(T.textHint).padding(.horizontal, 14)
                            }
                            TextField("", text: $displayName)
                                .padding(12).foregroundColor(T.textMain)
                        }
                        .background(T.inputBG).cornerRadius(10)
                    }
                    ZStack(alignment: .leading) {
                        if password.isEmpty {
                            Text(mode == 2 ? "新密码（不少于6位）" : "请输入密码").foregroundColor(T.textHint).padding(.horizontal, 14)
                        }
                        SecureField("", text: $password)
                            .padding(12).foregroundColor(T.textMain)
                    }
                    .background(T.inputBG).cornerRadius(10)
                    if mode != 0 {
                        ZStack(alignment: .leading) {
                            if confirmPwd.isEmpty {
                                Text("确认密码").foregroundColor(T.textHint).padding(.horizontal, 14)
                            }
                            SecureField("", text: $confirmPwd)
                                .padding(12).foregroundColor(T.textMain)
                        }
                        .background(T.inputBG).cornerRadius(10)
                        ZStack(alignment: .leading) {
                            if phone.isEmpty {
                                Text(mode == 1 ? "手机号（选填，用于忘记密码找回）" : "绑定手机号").foregroundColor(T.textHint).padding(.horizontal, 14)
                            }
                            TextField("", text: $phone)
                                .padding(12).foregroundColor(T.textMain)
                                .keyboardType(.numberPad)
                        }
                        .background(T.inputBG).cornerRadius(10)
                    }
                    Button(action: doAction) {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(mode == 0 ? "登 录" : (mode == 1 ? "注 册" : "重置密码")).fontWeight(.bold).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity).padding(13)
                        .background(LinearGradient(colors: [Color(hex: 0x1a2980), Color(hex: 0x1890ff)],
                                                   startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(10)
                        .shadow(color: Color(hex: 0x1890ff).opacity(0.35), radius: 8, y: 4)
                    }
                    .disabled(busy)
                    HStack {
                        Button(mode == 0 ? "注册账号" : "返回登录") {
                            mode = mode == 0 ? 1 : 0; msg = ""
                        }
                        .font(.footnote).foregroundColor(Color(hex: 0x1890ff))
                        Spacer()
                        Button(mode == 2 ? "返回登录" : "忘记密码？") {
                            mode = mode == 2 ? 0 : 2; msg = ""
                        }
                        .font(.footnote).foregroundColor(Color(hex: 0x1890ff))
                    }
                    .padding(.horizontal, 4)
                }
                .padding(22)
                .glass(corner: 18)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.horizontal, 28)
                if !msg.isEmpty {
                    Text(msg).font(.footnote.bold()).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.black.opacity(0.28)).cornerRadius(14)
                }
                Spacer()
            }
            .padding(.top, 60)
        }
    }

    func doAction() {
        if mode == 0 { doLogin(); return }
        if mode == 1 { doRegister(); return }
        doForgot()
    }

    func doRegister() {
        if username.isEmpty || password.isEmpty { msg = "请输入用户名和密码"; return }
        if password != confirmPwd { msg = "两次输入的密码不一致"; return }
        busy = true; msg = ""
        Task {
            do {
                let r = try await Api.post("/api/auth/register", [
                    "username": username, "password": password,
                    "display_name": displayName.isEmpty ? username : displayName,
                    "phone": phone
                ])
                await MainActor.run {
                    busy = false
                    if r["success"] as? Bool == true {
                        msg = "注册成功，请登录"
                        mode = 0; password = ""; confirmPwd = ""
                    } else {
                        msg = Api.str(r, "message").isEmpty ? "注册失败" : Api.str(r, "message")
                    }
                }
            } catch {
                await MainActor.run { busy = false; msg = "网络错误：\(error.localizedDescription)" }
            }
        }
    }

    func doForgot() {
        if username.isEmpty || phone.isEmpty || password.isEmpty { msg = "请输入用户名、绑定手机号和新密码"; return }
        if password != confirmPwd { msg = "两次输入的密码不一致"; return }
        busy = true; msg = ""
        Task {
            do {
                let r = try await Api.post("/api/auth/forgot-password", [
                    "username": username, "phone": phone, "newPassword": password
                ])
                await MainActor.run {
                    busy = false
                    if r["success"] as? Bool == true {
                        msg = "密码重置成功，请用新密码登录"
                        mode = 0; password = ""; confirmPwd = ""
                    } else {
                        msg = Api.str(r, "message").isEmpty ? "重置失败" : Api.str(r, "message")
                    }
                }
            } catch {
                await MainActor.run { busy = false; msg = "网络错误：\(error.localizedDescription)" }
            }
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
                        session.persist()
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
