import SwiftUI
import UIKit

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
    // 隐私政策：复选框默认不勾选，须由用户自愿、明确勾选后才能登录
    @State private var agreed = false
    @State private var showPrivacy = false
    @State private var rejected = false

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
                Text("v5.3 · 苹果原生版")
                    .font(.footnote).foregroundColor(.white.opacity(0.9))
                VStack(spacing: 14) {
                    if mode == 1 {
                        Text("注册的账号默认为访客，仅可查看内容；需管理员审批通过后才能升级为普通用户并使用全部功能。")
                            .font(.caption).foregroundColor(Color(hex: 0xd46b08))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: 0xfff7e6)).cornerRadius(8)
                    }
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
                    // 隐私政策勾选行：默认空白未勾选，须用户主动勾选
                    HStack(spacing: 8) {
                        Button {
                            agreed.toggle()
                        } label: {
                            Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundColor(agreed ? Color(hex: 0x1890ff) : Color.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(agreed ? "已同意隐私政策，取消勾选" : "同意隐私政策，未勾选"))
                        .accessibilityAddTraits(agreed ? .isSelected : [])
                        Text("我已阅读并同意")
                            .font(.footnote).foregroundColor(.white.opacity(0.85))
                        Button {
                            if let u = URL(string: AppPolicy.privacyURL) { UIApplication.shared.open(u) }
                        } label: {
                            Text("《隐私政策》").font(.footnote.bold()).foregroundColor(Color(hex: 0x7ce7e5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 2)

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

            if rejected {
                PrivacyRejectedView(onReconsider: {
                    rejected = false
                    showPrivacy = true
                })
            }
        }
        .onAppear {
            if UserDefaults.standard.string(forKey: "privacy_agreed_at") == nil && !rejected {
                showPrivacy = true
            }
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyGateView(onAgree: {
                agreed = true
                showPrivacy = false
                PrivacyStore.markAgreed()
            }, onReject: {
                showPrivacy = false
                agreed = false
                rejected = true
            })
        }
        .interactiveDismissDisabled(showPrivacy)
    }

    func doAction() {
        // 未勾选隐私政策：不得提交任何请求，重新弹出政策由用户自愿勾选
        guard agreed else {
            msg = "请先阅读并勾选同意《隐私政策》"
            showPrivacy = true
            return
        }
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
                        msg = "注册成功（访客账户，待管理员审批），请登录"
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

// 隐私政策同意记录：首次启动弹窗同意后写入时间戳，之后不再打扰
enum PrivacyStore {
    private static let key = "privacy_agreed_at"
    static var agreed: Bool { UserDefaults.standard.string(forKey: key) != nil }
    static func markAgreed() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        UserDefaults.standard.set(f.string(from: Date()), forKey: key)
    }
}

/// 隐私政策弹窗：必须提供真实的「不同意」拒绝选项
struct PrivacyGateView: View {
    var onAgree: () -> Void
    var onReject: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Text("隐私政策与用户协议")
                .font(.headline).foregroundColor(T.textMain)
            ScrollView {
                Text("""
                欢迎使用影视星河设备管理系统。我们非常重视你的个人信息与隐私保护。

                在你使用本应用前，请完整阅读并充分理解《隐私政策》。点击「同意并继续」即表示你已阅读并自愿同意政策全部内容；你也可以点击「不同意」拒绝，拒绝后本应用不会收集、上传任何个人信息，且无法继续使用。

                我们仅在实现设备管理、消息通知等核心功能所必需的范围内处理信息，不会向无关第三方提供。你可随时通过「我的 → 投诉举报中心」提交投诉或行使你的权利。
                """)
                .font(.subheadline).foregroundColor(T.textSub)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 260)

            Button {
                if let u = URL(string: AppPolicy.privacyURL) { openURL(u) }
            } label: {
                Text("查看《隐私政策》全文").font(.subheadline.bold()).foregroundColor(T.brand)
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                Button(action: onAgree) {
                    Text("同意并继续").fontWeight(.bold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(13)
                        .background(T.brand).cornerRadius(10)
                }
                Button(action: onReject) {
                    Text("不同意").fontWeight(.semibold).foregroundColor(T.textSub)
                        .frame(maxWidth: .infinity).padding(13)
                        .background(T.chipBG).cornerRadius(10)
                }
                .accessibilityLabel("不同意隐私政策")
            }
        }
        .padding(22)
        .background(T.card)
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .padding(.horizontal, 28)
    }
}

/// 拒绝隐私政策后的阻断页：不收集任何信息，可重新阅读或退出应用
struct PrivacyRejectedView: View {
    var onReconsider: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44)).foregroundColor(Color(hex: 0xfa8c16))
                Text("你已拒绝隐私政策").font(.title3.bold()).foregroundColor(.white)
                Text("拒绝后本应用不会收集、上传任何个人信息，相关功能也无法使用。如需继续使用，请重新阅读并同意《隐私政策》。")
                    .font(.subheadline).foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    Button(action: onReconsider) {
                        Text("重新阅读并同意").fontWeight(.bold).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(13)
                            .background(T.brand).cornerRadius(10)
                    }
                    Button {
                        // 用户明确拒绝且选择退出：结束进程，不做任何数据收集
                        exit(0)
                    } label: {
                        Text("退出应用").fontWeight(.semibold).foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity).padding(13)
                            .background(Color.white.opacity(0.14)).cornerRadius(10)
                    }
                }
                .padding(.top, 6)
            }
            .padding(28)
        }
        // 阻断页需拦截全部点击，避免穿透到下层登录表单
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}
