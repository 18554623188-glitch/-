import SwiftUI

let APP_VER = "5.1.0"

// 版本更新信息（四端统一数据结构，platform 区分 ios/android/harmony/windows）
struct UpdateInfo: Identifiable {
    let id = UUID()
    let version: String
    let notes: String
    let url: String
    let size: Int
    let releasedAt: String
}

enum UpdateChecker {
    // 版本号比较：a>b 返回 1，相等 0，a<b -1
    static func cmpVer(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    // 拉取指定平台最新版本；无更新返回 nil，网络异常抛出
    static func fetchUpdate(platform: String) async throws -> UpdateInfo? {
        let r = try await Api.get("/api/app/version/latest")
        let data = Api.dict(r)
        let v = (data[platform] as? [String: Any]) ?? [:]
        let ver = Api.str(v, "version")
        guard !ver.isEmpty, cmpVer(ver, APP_VER) > 0 else { return nil }
        return UpdateInfo(version: ver, notes: Api.str(v, "notes"), url: Api.str(v, "url"),
                          size: Api.int(v, "size"), releasedAt: Api.str(v, "released_at"))
    }

    static func message(_ u: UpdateInfo) -> String {
        var s = "当前版本：v" + APP_VER + "\n最新版本：v" + u.version
        if u.size > 1048576 { s += String(format: "（%.1f MB）", Double(u.size) / 1048576.0) }
        else if u.size > 1024 { s += String(format: "（%.1f KB）", Double(u.size) / 1024.0) }
        s += "\n\n更新说明：\n" + (u.notes.isEmpty ? "常规更新与问题修复" : u.notes)
        if !u.url.hasPrefix("http") { s += "\n\n尚未配置下载地址，请联系管理员获取安装包。" }
        return s
    }
}

struct MainView: View {
    // 登录后静默检查版本更新（仅发现新版本时弹窗）
    @State private var tab = 0
    @State private var upd: UpdateInfo?
    @State private var updMsg = ""
    @State private var showUpd = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            // 隐藏系统标签栏，改用自定义液态玻璃导航条（iOS 26/27 真玻璃）
            TabView(selection: $tab) {
                HomeView().toolbar(.hidden, for: .tabBar).tag(0)
                DevicesView().toolbar(.hidden, for: .tabBar).tag(1)
                PersonnelView().toolbar(.hidden, for: .tabBar).tag(2)
                MessagesView().toolbar(.hidden, for: .tabBar).tag(3)
                ProfileView().toolbar(.hidden, for: .tabBar).tag(4)
            }
            .tint(Color(hex: 0x1890ff))
            GlassTabBar(tab: $tab)
        }
        .onAppear {
            Task {
                if let u = try? await UpdateChecker.fetchUpdate(platform: "ios") {
                    await MainActor.run { upd = u; updMsg = UpdateChecker.message(u); showUpd = true }
                }
            }
        }
        .alert(upd.map { "发现新版本 v" + $0.version } ?? "检查更新", isPresented: $showUpd) {
            if let u = upd, u.url.hasPrefix("http"), let dl = URL(string: u.url) {
                Button("下载新版本") { openURL(dl) }
                Button("稍后再说", role: .cancel) {}
            } else {
                Button("知道了", role: .cancel) {}
            }
        } message: { Text(updMsg) }
    }
}

// ============ 底部导航：Liquid Glass 悬浮条（iOS 26/27 运行时加载 UIGlassEffect 真玻璃，低版本回退动态色卡片） ============
struct GlassTabBar: View {
    @Binding var tab: Int
    private let titles = ["首页", "设备", "人员", "消息", "我的"]
    private let icons = ["house.fill", "video.fill", "person.2.fill", "bubble.left.and.bubble.right.fill", "person.crop.circle.fill"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                Button {
                    tab = i
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icons[i])
                            .font(.system(size: 18, weight: tab == i ? .semibold : .regular))
                        Text(titles[i]).font(.system(size: 10, weight: tab == i ? .semibold : .regular))
                    }
                    .foregroundColor(tab == i ? Color(hex: 0x1890ff) : T.textHint)
                    // 足够大的触控热区（≥4pt 标准 48pt），整个区域均可点击
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                    .background(tab == i ? Color(hex: 0x1890ff).opacity(0.12) : Color.clear)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .glass(corner: 28)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// ============ 首页：渐变头部 + 天气卡 + 统计 ============
struct HomeView: View {
    @StateObject private var session = Session.shared
    @State private var stats: [String: String] = [:]
    @State private var personnelCount = "-"
    @State private var weather: [String: Any]?
    @State private var city = "青岛"
    @State private var showCityAlert = false
    @State private var cityInput = ""
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    statsGrid.padding(.horizontal, 16).padding(.top, 16)
                    Text("系统消息推送已开启：报修、维修完成、聊天等新消息将通过通知栏实时提醒")
                        .font(.footnote).foregroundColor(Color(hex: 0x1890ff))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(T.bannerBG).cornerRadius(8)
                        .padding(16)
                }
            }
            .background(T.pageBG)
            .ignoresSafeArea(edges: .top)
            .onAppear { loadAll() }
            .onReceive(timer) { _ in loadAll() }
            .alert("切换城市", isPresented: $showCityAlert) {
                TextField("城市名（如 北京）", text: $cityInput)
                Button("确定") {
                    if !cityInput.trimmingCharacters(in: .whitespaces).isEmpty {
                        city = cityInput.trimmingCharacters(in: .whitespaces)
                        loadWeather()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("输入要查看天气的城市") }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("你好，\(session.displayName.isEmpty ? session.username : session.displayName)")
                    .font(.title2.bold()).foregroundColor(.white)
                HStack(spacing: 8) {
                    Text("影视星河设备管理系统 v5.1 · 苹果原生版")
                        .font(.caption).foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 天气卡（悬浮于渐变头部内，点击切换城市）
            HStack(spacing: 12) {
                if let w = weather, let cur = w["current"] as? [String: Any] {
                    Text(weatherIcon(Api.int(cur, "code"))).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(city).font(.subheadline.bold())
                            Text(Api.str(cur, "temp") + "°C").font(.title3.bold())
                            Text(Api.str(cur, "weather")).font(.caption)
                        }
                        if let daily = w["daily"] as? [String: Any] {
                            Text("今日 \(Api.str(daily, "minTemp"))~\(Api.str(daily, "maxTemp"))°C").font(.caption2)
                        }
                        HStack(spacing: 10) {
                            Text("💧 \(Api.str(cur, "humidity"))%").font(.caption2)
                            Text("🌬 \(Api.str(cur, "windSpeed")) km/h").font(.caption2)
                        }
                    }
                    Spacer()
                    Text("点击切换城市").font(.caption2).opacity(0.8)
                } else {
                    Text("🌤 天气加载中…（点击重试）").font(.footnote)
                }
            }
            .foregroundColor(.white)
            .padding(14)
            .background(Color.white.opacity(0.16))
            .cornerRadius(12)
            .onTapGesture { cityInput = ""; showCityAlert = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .padding(.bottom, 18)
        .background(LinearGradient(colors: [Color(hex: 0x1a2980), Color(hex: 0x26d0ce)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("设备总数", stats["total"] ?? "-", Color(hex: 0x1890ff))
            statCard("正常", stats["normal"] ?? "-", Color(hex: 0x52c41a))
            statCard("维修中", stats["repairing"] ?? "-", Color(hex: 0xfa8c16))
            statCard("闲置", stats["idle"] ?? "-", Color(hex: 0x8c8c8c))
            statCard("已报废", stats["scrapped"] ?? "-", Color(hex: 0xff4d4f))
            statCard("人员数量", personnelCount, Color(hex: 0x722ed1))
        }
    }

    private func statCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundColor(color)
            HStack(spacing: 6) {
                Capsule().fill(color).frame(width: 14, height: 3)
                Text(title).font(.footnote).foregroundColor(T.textSub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    func weatherIcon(_ code: Int) -> String {
        if code == 0 { return "☀️" }
        if code <= 3 { return "⛅" }
        if code == 45 || code == 48 { return "🌫" }
        if code >= 51 && code <= 67 { return "🌦" }
        if code >= 71 && code <= 86 { return "🌨" }
        if code >= 95 { return "⛈" }
        return "🌤"
    }

    func loadAll() {
        Task {
            async let a = try? Api.get("/api/devices/stats/summary")
            async let b = try? Api.get("/api/personnel")
            let (ra, rb) = await (a, b)
            let wc = await (try? Api.get("/api/weather/current?city=" + (city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city)))
            await MainActor.run {
                if let ra { let d = Api.dict(ra); stats = ["total": Api.str(d, "total"), "normal": Api.str(d, "normal"), "repairing": Api.str(d, "repairing"), "idle": Api.str(d, "idle"), "scrapped": Api.str(d, "scrapped")] }
                if let rb { personnelCount = String(Api.arr(rb).count) }
                if let wc { weather = wc["data"] as? [String: Any] }
            }
        }
    }

    func loadWeather() {
        Task {
            let r = try? await Api.get("/api/weather/current?city=" + (city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city))
            await MainActor.run {
                if let r { weather = r["data"] as? [String: Any] }
            }
        }
    }
}

// ============ 人员：在线状态 + 登录/下线时间 ============
struct PersonnelView: View {
    @State private var personnel: [[String: Any]] = []
    @State private var allUsers: [[String: Any]] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(personnel.indices, id: \.self) { i in
                        personRow(personnel[i])
                    }
                }
                .padding(16)
            }
            .background(T.pageBG)
            .navigationTitle("人员")
            .onAppear { load() }
        }
    }

    private func personRow(_ p: [String: Any]) -> some View {
        let nm = displayName(p)
        let acc = accountOf(nm)
        let online = (acc?["is_online"] as? Bool) ?? false
        let dept = Api.str(p, "department")
        let pos = Api.str(p, "position")
        let sub = [dept, pos].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(online ? Color(hex: 0x52c41a) : Color(hex: 0xd9d9d9))
                    .frame(width: 10, height: 10)
                Text(nm.isEmpty ? "-" : nm).font(.headline).foregroundColor(T.textMain)
                Spacer()
                Text(online ? "在线" : "离线")
                    .font(.caption.bold())
                    .foregroundColor(online ? T.green : T.textHint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((online ? T.green : Color(hex: 0xd9d9d9)).opacity(0.14))
                    .cornerRadius(8)
            }
            if !sub.isEmpty {
                Text(sub).font(.caption).foregroundColor(T.textHint)
            }
            if let acc {
                let li = Api.str(acc, "last_login")
                let lo = Api.str(acc, "last_logout")
                if !li.isEmpty || !lo.isEmpty {
                    Text("登录：\(li.isEmpty ? "-" : li) 下线：\(lo.isEmpty ? "-" : lo)")
                        .font(.caption).foregroundColor(T.textHint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // 后端 personnel 表主字段为 name，兼容 display_name / 关联账户 username
    func displayName(_ p: [String: Any]) -> String {
        for k in ["name", "display_name", "account_username", "username"] {
            let v = Api.str(p, k)
            if !v.isEmpty { return v }
        }
        return ""
    }

    func accountOf(_ name: String) -> [String: Any]? {
        for u in allUsers {
            var n = Api.str(u, "display_name")
            if n.isEmpty { n = Api.str(u, "username") }
            if n == name { return u }
        }
        return nil
    }

    func load() {
        Task {
            async let a = try? Api.get("/api/personnel")
            async let b = try? Api.get("/api/chat/users")
            let (ra, rb) = await (a, b)
            await MainActor.run {
                if let ra { personnel = Api.arr(ra) }
                if let rb { allUsers = Api.arr(rb) }
            }
        }
    }
}

// ============ 我的：信息 + 通知入口 + 改密 + 退出 ============
struct ProfileView: View {
    @StateObject private var session = Session.shared
    @State private var showPost = false
    @State private var showPwd = false
    @State private var upd: UpdateInfo?
    @State private var updMsg = ""
    @State private var showUpd = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [Color(hex: 0x1a2980), Color(hex: 0x26d0ce)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 72, height: 72)
                            Text(String((session.displayName.isEmpty ? session.username : session.displayName).prefix(1)))
                                .font(.title.bold()).foregroundColor(.white)
                        }
                        Text(session.displayName.isEmpty ? session.username : session.displayName).font(.headline)
                        Text(session.role == "admin" ? "管理员" : "普通用户")
                            .font(.caption).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(session.role == "admin" ? Color(hex: 0x722ed1) : Color(hex: 0x8c8c8c))
                            .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(LinearGradient(colors: [Color(hex: 0x1a2980), Color(hex: 0x26d0ce)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(12)

                    NavigationLink { NoticeView(postMode: false) } label: {
                        menuRow("🔔", "通知中心")
                    }
                    if session.role == "admin" {
                        Button { showPost = true } label: { menuRow("📢", "发布通知（管理员）") }
                            .buttonStyle(.plain)
                    }
                    Button { showPwd = true } label: { menuRow("🔒", "修改密码") }
                        .buttonStyle(.plain)
                    Button { checkUpdate() } label: { menuRow("🔍", "检查更新") }
                        .buttonStyle(.plain)
                    Button { session.logout() } label: {
                        menuRow("🚪", "退出登录").foregroundColor(Color(hex: 0xff4d4f))
                    }
                    .buttonStyle(.plain)

                    Text("影视星河设备管理系统 v5.1").font(.caption2).foregroundColor(T.textFaint).padding(.top, 10)
                }
                .padding(16)
            }
            .background(T.pageBG)
            .navigationTitle("我的")
            .sheet(isPresented: $showPost) { NoticeView(postMode: true) }
            .sheet(isPresented: $showPwd) { ChangePwdView() }
            .alert(upd.map { "发现新版本 v" + $0.version } ?? "检查更新", isPresented: $showUpd) {
                if let u = upd, u.url.hasPrefix("http"), let dl = URL(string: u.url) {
                    Button("下载新版本") { openURL(dl) }
                    Button("稍后再说", role: .cancel) {}
                } else {
                    Button("知道了", role: .cancel) {}
                }
            } message: { Text(updMsg) }
        }
    }

    // 手动检查更新：无更新/失败也给出提示
    func checkUpdate() {
        Task {
            do {
                if let u = try await UpdateChecker.fetchUpdate(platform: "ios") {
                    await MainActor.run { upd = u; updMsg = UpdateChecker.message(u); showUpd = true }
                } else {
                    await MainActor.run { upd = nil; updMsg = "已是最新版本 v" + APP_VER; showUpd = true }
                }
            } catch {
                await MainActor.run { upd = nil; updMsg = "检查更新失败，请检查网络后重试"; showUpd = true }
            }
        }
    }

    private func menuRow(_ icon: String, _ title: String) -> some View {
        HStack {
            Text(icon)
            Text(title).foregroundColor(T.textMain)
            Spacer()
            Text("›").foregroundColor(T.textFaint)
        }
        .padding(14)
        .background(T.card).cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }
}

struct ChangePwdView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldPwd = ""
    @State private var newPwd = ""
    @State private var confirmPwd = ""
    @State private var msg = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField("原密码", text: $oldPwd)
                SecureField("新密码", text: $newPwd)
                SecureField("确认新密码", text: $confirmPwd)
                Button("提交修改") {
                    if newPwd != confirmPwd { msg = "两次输入的新密码不一致"; return }
                    Task {
                        let r = try? await Api.patch("/api/auth/password", ["oldPassword": oldPwd, "newPassword": newPwd])
                        await MainActor.run {
                            if let r, r["success"] as? Bool == true { dismiss() }
                            else { msg = r?["message"] as? String ?? "修改失败" }
                        }
                    }
                }
                if !msg.isEmpty { Text(msg).foregroundColor(.red) }
            }
            .navigationTitle("修改密码")
            .toolbar { Button("关闭") { dismiss() } }
        }
    }
}
