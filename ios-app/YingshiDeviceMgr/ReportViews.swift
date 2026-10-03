import SwiftUI

// 投诉举报中心 + 隐私政策（苹果端）
// 举报渠道对所有账号公开、透明、无障碍：会话内可举报，「我的」页有全局投诉入口，
// 提交后可查询处理进度，并公示整体受理情况。

// TODO(上线前替换): 以下为占位联系方式，请替换为真实受理渠道后重新打包
enum AppPolicy {
    /// 隐私政策网页（三端统一）
    static let privacyURL = "https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2050261183788804032"
    /// 举报受理邮箱
    static let reportEmail = "report@example.com"
    /// 举报受理电话
    static let reportPhone = "400-000-0000"
    /// 受理时间
    static let reportHours = "工作日 9:00 - 18:00"
    /// 承诺办结时限
    static let reportSla = "受理后 3 个工作日内反馈处理结果"

    /// 会话内举报理由
    static let chatReasons = ["辱骂攻击", "骚扰威胁", "色情低俗", "广告诈骗", "违法违规", "其他"]
    /// 全局投诉理由
    static let generalReasons = ["违法违规", "侵权投诉", "功能异常", "账号问题", "服务态度", "其他"]

    static let platform = "ios"
}

/// 举报提交表单：会话内举报（带对象）与全局投诉（不带对象）共用
struct ReportFormView: View {
    /// general = 全局投诉；chat = 会话内举报
    let category: String
    /// 会话内举报时的会话/对象信息，全局投诉留空
    var convId: String = ""
    var convName: String = ""
    var reportedUserId: String = ""
    var reportedUserName: String = ""
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var description = ""
    @State private var contact = ""
    @State private var busy = false
    @State private var msg = ""
    @State private var showMsg = false

    private var reasons: [String] { category == "general" ? AppPolicy.generalReasons : AppPolicy.chatReasons }
    private var targetText: String {
        if category == "general" { return "全局投诉（不针对具体会话）" }
        return reportedUserName.isEmpty ? "整个群聊「\(convName)」" : reportedUserName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("举报对象").font(.caption).foregroundColor(T.textHint)
                        Text(targetText).font(.subheadline.bold()).foregroundColor(T.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(T.bannerBG).cornerRadius(10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("请选择理由（必选）").font(.subheadline.bold()).foregroundColor(T.textMain)
                        FlowChips(items: reasons, selected: $reason)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(category == "general" ? "投诉内容（必填）" : "补充说明（选填）")
                            .font(.subheadline.bold()).foregroundColor(T.textMain)
                        TextEditor(text: $description)
                            .frame(minHeight: 110)
                            .padding(6)
                            .background(T.inputBG).cornerRadius(10)
                            .foregroundColor(T.textMain)
                        Text("\(description.count)/500").font(.caption2).foregroundColor(T.textFaint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("回访方式（选填，便于反馈处理结果）").font(.subheadline.bold()).foregroundColor(T.textMain)
                        TextField("手机号或邮箱", text: $contact)
                            .padding(12).background(T.inputBG).cornerRadius(10)
                            .foregroundColor(T.textMain)
                    }

                    Text("提交后管理员会收到通知并核实处理，你可在「投诉举报中心 → 我的举报」查看进度。")
                        .font(.caption).foregroundColor(T.textSub)

                    Button { submit() } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "提交中…" : "提交举报").fontWeight(.bold).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity).padding(13)
                        .background(reason.isEmpty || busy ? Color(hex: 0xbfbfbf) : T.red)
                        .cornerRadius(10)
                    }
                    .disabled(reason.isEmpty || busy)
                }
                .padding(16)
            }
            .background(T.pageBG)
            .navigationTitle("投诉举报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { dismiss() } }
            .alert("提示", isPresented: $showMsg) {
                Button("知道了") { if msg.hasPrefix("举报已提交") || msg.hasPrefix("投诉已提交") { dismiss(); onDone?() } }
            } message: { Text(msg) }
        }
    }

    func submit() {
        guard !reason.isEmpty else { msg = "请选择举报理由"; showMsg = true; return }
        if category == "general" && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            msg = "请填写投诉内容"; showMsg = true; return
        }
        busy = true
        var body: [String: Any] = [
            "category": category,
            "reason": reason,
            "description": String(description.prefix(500)),
            "contact": contact,
            "platform": AppPolicy.platform
        ]
        if category != "general" {
            body["conversation_id"] = convId
            body["conversation_name"] = convName
            body["reported_user_id"] = reportedUserId
            body["reported_user_name"] = reportedUserName
        }
        let requestBody = body
        Task {
            do {
                let r = try await Api.post("/api/chat/report", requestBody)
                await MainActor.run {
                    busy = false
                    if r["success"] as? Bool == true {
                        msg = Api.str(r, "message").isEmpty ? "举报已提交" : Api.str(r, "message")
                    } else {
                        msg = Api.str(r, "message").isEmpty ? "提交失败" : Api.str(r, "message")
                    }
                    showMsg = true
                }
            } catch {
                await MainActor.run { busy = false; msg = "网络错误：\(error.localizedDescription)"; showMsg = true }
            }
        }
    }
}

/// 简易横向换行标签选择器（理由单选）
struct FlowChips: View {
    let items: [String]
    @Binding var selected: String

    var body: some View {
        // iOS 16 无原生 Flow 布局，用固定两列 LazyVGrid 保证低版本可编译且点击区域足够大（无障碍）
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { it in
                Button {
                    selected = (selected == it) ? "" : it
                } label: {
                    Text(it)
                        .font(.subheadline)
                        .foregroundColor(selected == it ? .white : T.textSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(selected == it ? T.red : T.chipBG)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(it))
                .accessibilityAddTraits(selected == it ? .isSelected : [])
            }
        }
    }
}

/// 投诉举报中心：渠道公示 + 受理情况公示 + 提交投诉 + 我的举报进度
struct ReportCenterView: View {
    @Environment(\.openURL) private var openURL
    @State private var showForm = false
    @State private var mine: [[String: Any]] = []
    @State private var stats: [String: Any]?
    @State private var serverLimited = false
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                channelsCard
                statsCard
                Button { showForm = true } label: {
                    HStack {
                        Image(systemName: "flag.fill").foregroundColor(.white)
                        Text("提交投诉举报").fontWeight(.bold).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(14).background(T.red).cornerRadius(12)
                }
                .buttonStyle(.plain)
                mineCard
            }
            .padding(16)
        }
        .background(T.pageBG)
        .navigationTitle("投诉举报中心")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .onAppear { Task { await reload() } }
        .sheet(isPresented: $showForm) {
            ReportFormView(category: "general") { Task { await reload() } }
        }
    }

    // 举报渠道公示：应用内表单 + 邮箱 + 电话 + 受理时限，全部可直接点击（无障碍）
    private var channelsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("举报渠道（公开透明）").font(.headline).foregroundColor(T.textMain)
            channelRow("📮", "举报邮箱", AppPolicy.reportEmail, "mailto:" + AppPolicy.reportEmail)
            channelRow("📞", "受理电话", AppPolicy.reportPhone + "（" + AppPolicy.reportHours + "）", "tel:" + AppPolicy.reportPhone)
            channelRow("⏱", "办结时限", AppPolicy.reportSla, nil)
            channelRow("📄", "隐私政策", "点击查看完整隐私政策", AppPolicy.privacyURL)
            Text("处理流程：提交 → 管理员核实 → 处理/驳回并附说明 → 结果在下方「我的举报」公示。对处理结果有异议可再次提交投诉或拨打受理电话申诉。")
                .font(.caption).foregroundColor(T.textSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func channelRow(_ icon: String, _ label: String, _ value: String, _ link: String?) -> some View {
        HStack(spacing: 10) {
            Text(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(T.textHint)
                if let link, let u = URL(string: link) {
                    Button { openURL(u) } label: {
                        Text(value).font(.subheadline).foregroundColor(T.brand)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(value).font(.subheadline).foregroundColor(T.textMain)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // 受理情况公示：仅汇总数字，不含任何个人信息
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("受理情况公示").font(.headline).foregroundColor(T.textMain)
            if serverLimited {
                Text("当前服务器版本暂不支持公示数据，投诉提交与处理不受影响。")
                    .font(.caption).foregroundColor(T.orange)
            } else if let s = stats {
                HStack(spacing: 0) {
                    statCell("累计受理", Api.str(s, "total"), T.textMain)
                    statCell("待处理", Api.str(s, "pending"), T.orange)
                    statCell("已处理", Api.str(s, "handled"), T.green)
                    statCell("已驳回", Api.str(s, "rejected"), T.textSub)
                }
                let last = Api.str(s, "last_handled_at")
                Text(last.isEmpty ? "暂无已办结记录" : "最近办结时间：\(last)")
                    .font(.caption).foregroundColor(T.textHint)
            } else if loading {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func statCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value.isEmpty ? "0" : value).font(.title3.bold()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(T.textHint)
        }
        .frame(maxWidth: .infinity)
    }

    // 我的举报：本人提交记录 + 处理状态/处理人/处理意见
    private var mineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的举报").font(.headline).foregroundColor(T.textMain)
                Spacer()
                if loading { ProgressView() }
            }
            if serverLimited {
                Text("当前服务器版本暂不支持进度查询，请通过举报邮箱或受理电话跟进。")
                    .font(.caption).foregroundColor(T.orange)
            } else if mine.isEmpty {
                Text("你还没有提交过举报").font(.caption).foregroundColor(T.textHint)
            } else {
                ForEach(mine.indices, id: \.self) { i in
                    mineRow(mine[i])
                    if i < mine.count - 1 { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func mineRow(_ r: [String: Any]) -> some View {
        let status = Api.str(r, "status")
        let isGeneral = Api.str(r, "category") == "general"
        let target = isGeneral ? "全局投诉" : (Api.str(r, "reported_user_name").isEmpty ? Api.str(r, "conversation_name") : Api.str(r, "reported_user_name"))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status)
                    .font(.caption2.bold()).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(status == "已处理" ? T.green : (status == "已驳回" ? Color(hex: 0x8c8c8c) : T.orange))
                    .cornerRadius(4)
                Text(isGeneral ? "投诉" : "举报").font(.caption2).foregroundColor(T.textHint)
                Spacer()
                Text(Api.str(r, "created_at")).font(.caption2).foregroundColor(T.textFaint)
            }
            Text("对象：\(target.isEmpty ? "—" : target)　理由：\(Api.str(r, "reason"))")
                .font(.subheadline).foregroundColor(T.textMain)
            let desc = Api.str(r, "description")
            if !desc.isEmpty {
                Text(desc).font(.caption).foregroundColor(T.textSub).lineLimit(3)
            }
            if status != "待处理" {
                VStack(alignment: .leading, spacing: 2) {
                    Text("处理人：\(Api.str(r, "handled_by").isEmpty ? "—" : Api.str(r, "handled_by"))　处理时间：\(Api.str(r, "handled_at"))")
                        .font(.caption2).foregroundColor(T.textHint)
                    let note = Api.str(r, "handle_note")
                    if !note.isEmpty {
                        Text("处理意见：\(note)").font(.caption).foregroundColor(T.brand)
                    }
                }
                .padding(8).background(T.inputBG).cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }

    func reload() async {
        await MainActor.run { loading = true }
        // 老版本服务器没有 /api/reports/mine 与 /api/reports/stats，返回空字典时降级提示，不影响举报提交
        let m = try? await Api.get("/api/reports/mine")
        let s = try? await Api.get("/api/reports/stats")
        await MainActor.run {
            loading = false
            if let m, m["success"] as? Bool == true {
                mine = Api.arr(m)
                serverLimited = false
            } else {
                mine = []
                serverLimited = true
            }
            if let s, s["success"] as? Bool == true {
                stats = Api.dict(s)
            } else {
                stats = nil
            }
        }
    }
}

/// 会话内举报对象选择：单聊直接举报对方，群聊可选成员或整个群聊
struct ChatReportPicker: View {
    let convId: String
    let convName: String
    let convInfo: [String: Any]?
    @Environment(\.dismiss) private var dismiss
    @State private var target: ReportTarget?

    struct ReportTarget: Identifiable {
        let id: String
        let userId: String
        let userName: String
    }

    private var others: [[String: Any]] {
        let mem = (convInfo?["members"] as? [[String: Any]]) ?? []
        return mem.filter { Api.str($0, "id") != Session.shared.userId }
    }
    private var isGroup: Bool { Api.str(convInfo ?? [:], "type") == "group" }

    var body: some View {
        NavigationStack {
            List {
                if isGroup {
                    Button {
                        target = ReportTarget(id: "conv", userId: "", userName: "")
                    } label: {
                        Label("🚩 举报整个群聊「\(convName)」", systemImage: "flag")
                            .foregroundColor(T.red)
                    }
                }
                Section("选择要举报的成员") {
                    ForEach(others.indices, id: \.self) { i in
                        let m = others[i]
                        let name = Api.str(m, "display_name").isEmpty ? Api.str(m, "username") : Api.str(m, "display_name")
                        Button {
                            target = ReportTarget(id: Api.str(m, "id"), userId: Api.str(m, "id"), userName: name)
                        } label: {
                            HStack { Text(name).foregroundColor(T.textMain); Spacer(); Text("举报 ›").font(.caption).foregroundColor(T.red) }
                        }
                    }
                }
            }
            .navigationTitle("选择举报对象")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { dismiss() } }
            .sheet(item: $target) { t in
                ReportFormView(category: "chat", convId: convId, convName: convName,
                               reportedUserId: t.userId, reportedUserName: t.userName) {
                    target = nil
                }
            }
        }
    }
}
