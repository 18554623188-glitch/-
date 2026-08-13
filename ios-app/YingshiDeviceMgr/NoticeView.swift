import SwiftUI

// 通知中心：列表 + 点击已读 + 全部已读；postMode=true 时顶部显示管理员发布表单
struct NoticeView: View {
    var postMode: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var notices: [[String: Any]] = []
    @State private var title = ""
    @State private var content = ""
    @State private var nType = "普通"
    @State private var priority = "普通"
    @State private var msg = ""
    private let types = ["普通", "报修", "维护", "活动"]
    private let priorities = ["普通", "高"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if postMode && Session.shared.role == "admin" {
                        postForm
                    }
                    HStack {
                        Text("通知列表").font(.headline).foregroundColor(T.textMain)
                        Spacer()
                        Button("全部已读") { readAll() }
                            .font(.caption.bold()).foregroundColor(T.brand)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(T.brand.opacity(0.12)).cornerRadius(10)
                    }
                    .padding(.horizontal, 2)
                    ForEach(notices.indices, id: \.self) { i in
                        noticeRow(notices[i])
                    }
                }
                .padding(16)
            }
            .background(T.pageBG)
            .navigationTitle(postMode ? "发布通知" : "通知中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if postMode { Button("关闭") { dismiss() } }
            }
            .onAppear { load() }
        }
    }

    private var postForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("📢 发布通知（仅管理员）").font(.headline).foregroundColor(T.textMain)
            TextField("通知标题", text: $title)
                .foregroundColor(T.textMain)
                .padding(10).background(T.inputBG).cornerRadius(8)
            TextEditor(text: $content)
                .foregroundColor(T.textMain)
                .frame(height: 90)
                .padding(6).background(T.inputBG).cornerRadius(8)
            HStack(spacing: 8) {
                ForEach(types, id: \.self) { t in
                    Button { nType = t } label: {
                        Text(t).font(.caption.bold())
                            .foregroundColor(nType == t ? .white : T.textSub)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(nType == t ? Color(hex: 0x1890ff) : T.chipBG)
                            .cornerRadius(14)
                    }
                }
            }
            HStack(spacing: 8) {
                Text("优先级").font(.caption).foregroundColor(Color(hex: 0x8c8c8c))
                ForEach(priorities, id: \.self) { p in
                    Button { priority = p } label: {
                        Text(p).font(.caption.bold())
                            .foregroundColor(priority == p ? .white : T.textSub)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(priority == p ? Color(hex: 0xfa8c16) : T.chipBG)
                            .cornerRadius(14)
                    }
                }
                Spacer()
            }
            Button { post() } label: {
                Text("发布").font(.subheadline.bold()).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(12)
                    .background(Color(hex: 0x1890ff)).cornerRadius(10)
            }
            if !msg.isEmpty { Text(msg).font(.caption).foregroundColor(.red) }
        }
        .card()
    }

    private func noticeRow(_ n: [String: Any]) -> some View {
        let unread = Api.int(n, "is_read") == 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(unread ? Color(hex: 0xff4d4f) : Color(hex: 0xd9d9d9))
                    .frame(width: 8, height: 8)
                Text(Api.str(n, "title")).font(.subheadline.bold())
                    .foregroundColor(T.textMain)
                Spacer()
                Text(Api.str(n, "priority") == "高" ? "高" : "")
                    .font(.caption2.bold()).foregroundColor(Color(hex: 0xff4d4f))
            }
            Text(Api.str(n, "content")).font(.caption).foregroundColor(T.textSub)
            HStack {
                Text(Api.str(n, "type")).font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x1890ff))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(T.bannerBG).cornerRadius(4)
                Spacer()
                Text(Api.str(n, "created_at")).font(.system(size: 10)).foregroundColor(T.textFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onTapGesture { markRead(n) }
    }

    func post() {
        if title.trimmingCharacters(in: .whitespaces).isEmpty || content.trimmingCharacters(in: .whitespaces).isEmpty {
            msg = "请填写通知标题和内容"; return
        }
        Task {
            let r = try? await Api.post("/api/notifications", [
                "title": title, "content": content, "type": nType, "priority": priority, "target": "全部"
            ])
            await MainActor.run {
                if let r, r["success"] as? Bool == true {
                    msg = ""; title = ""; content = ""
                    load()
                } else { msg = r?["message"] as? String ?? "发布失败" }
            }
        }
    }

    func markRead(_ n: [String: Any]) {
        Task {
            _ = try? await Api.patch("/api/notifications/\(Api.str(n, "id"))/read", [:])
            await MainActor.run { load() }
        }
    }

    func readAll() {
        Task {
            _ = try? await Api.patch("/api/notifications/read-all", [:])
            await MainActor.run { load() }
        }
    }

    func load() {
        Task {
            let r = try? await Api.get("/api/notifications")
            await MainActor.run { if let r { notices = Api.arr(r) } }
        }
    }
}
