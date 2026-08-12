import SwiftUI
import PhotosUI

struct ConvRef: Hashable {
    let id: String
    let title: String
}

// ============ 消息页：会话列表 + 发起单聊/群聊 ============
struct MessagesView: View {
    @State private var convs: [[String: Any]] = []
    @State private var path = NavigationPath()
    @State private var showNew = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(convs.indices, id: \.self) { i in
                    Button {
                        path.append(ConvRef(id: Api.str(convs[i], "id"), title: convTitle(convs[i])))
                    } label: {
                        convRow(convs[i])
                    }
                    .listRowBackground(Color.white)
                }
            }
            .listStyle(.plain)
            .background(Color(hex: 0xf5f6f8))
            .navigationTitle("消息")
            .navigationDestination(for: ConvRef.self) { ref in
                ChatRoomView(convId: ref.id, title: ref.title)
            }
            .toolbar {
                Button { showNew = true } label: { Image(systemName: "square.and.pencil") }
            }
            .onAppear { load() }
            .sheet(isPresented: $showNew) {
                NewChatView { ref in
                    showNew = false
                    path.append(ref)
                }
            }
        }
    }

    func convTitle(_ c: [String: Any]) -> String {
        let n = Api.str(c, "name")
        return n.isEmpty ? "会话" : n
    }

    private func convRow(_ c: [String: Any]) -> some View {
        HStack {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0x1a2980), Color(hex: 0x26d0ce)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Text(String(convTitle(c).prefix(1))).foregroundColor(.white).font(.headline)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(convTitle(c)).font(.headline).foregroundColor(Color(hex: 0x262626))
                    if Api.str(c, "type") == "group" {
                        Text("群").font(.caption2).foregroundColor(Color(hex: 0x722ed1))
                    }
                    Spacer()
                    if let lm = c["last_message"] as? [String: Any] {
                        Text(Api.str(lm, "created_at").suffix(11)).font(.caption2).foregroundColor(Color(hex: 0xbfbfbf))
                    }
                }
                HStack {
                    if let lm = c["last_message"] as? [String: Any] {
                        Text(Api.str(lm, "sender_name") + "：" + preview(lm))
                            .font(.caption).foregroundColor(Color(hex: 0x8c8c8c)).lineLimit(1)
                    } else {
                        Text("暂无消息").font(.caption).foregroundColor(Color(hex: 0xbfbfbf))
                    }
                    Spacer()
                    let unread = Api.int(c, "unread")
                    if unread > 0 {
                        Text(String(unread))
                            .font(.caption2.bold()).foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(hex: 0xff4d4f)).clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    func preview(_ m: [String: Any]) -> String {
        let t = Api.str(m, "msg_type").isEmpty ? Api.str(m, "type") : Api.str(m, "msg_type")
        if t == "image" { return "[图片]" }
        if t == "video" { return "[视频]" }
        if t == "file" { return "[文件]" }
        return Api.str(m, "content")
    }

    func load() {
        Task {
            let r = try? await Api.get("/api/chat/conversations")
            await MainActor.run { if let r { convs = Api.arr(r) } }
        }
    }
}

// ============ 发起单聊 / 创建群聊 ============
struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    var onOpen: (ConvRef) -> Void
    @State private var users: [[String: Any]] = []
    @State private var selected: [String] = []
    @State private var groupName = ""
    @State private var mode = "direct"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text("单聊").tag("direct")
                    Text("群聊").tag("group")
                }
                .pickerStyle(.segmented)
                .padding()

                if mode == "group" {
                    TextField("群名称", text: $groupName)
                        .padding(10).background(Color(hex: 0xf5f5f5)).cornerRadius(8)
                        .padding(.horizontal)
                }
                List(users.indices, id: \.self) { i in
                    let u = users[i]
                    let uid = Api.str(u, "id")
                    let nm = Api.str(u, "display_name").isEmpty ? Api.str(u, "username") : Api.str(u, "display_name")
                    if mode == "direct" {
                        Button {
                            openDirect(uid: uid, name: nm)
                        } label: {
                            HStack { Text(nm).foregroundColor(Color(hex: 0x262626)); Spacer() }
                        }
                    } else {
                        Button {
                            if let idx = selected.firstIndex(of: uid) { selected.remove(at: idx) } else { selected.append(uid) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(uid) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected.contains(uid) ? Color(hex: 0x1890ff) : Color(hex: 0xd9d9d9))
                                Text(nm).foregroundColor(Color(hex: 0x262626))
                            }
                        }
                    }
                }
                if mode == "group" {
                    Button {
                        createGroup()
                    } label: {
                        Text("创建群聊（已选 \(selected.count) 人）")
                            .font(.subheadline.bold()).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(12)
                            .background(Color(hex: 0x1890ff)).cornerRadius(10)
                    }
                    .padding()
                }
            }
            .navigationTitle("发起聊天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() } }
            .onAppear {
                Task {
                    let r = try? await Api.get("/api/chat/users")
                    await MainActor.run { if let r { users = Api.arr(r).filter { Api.str($0, "id") != Session.shared.userId } } }
                }
            }
        }
    }

    func openDirect(uid: String, name: String) {
        Task {
            let r = try? await Api.post("/api/chat/conversations", ["type": "direct", "userId": uid])
            await MainActor.run {
                if let r, r["success"] as? Bool == true {
                    onOpen(ConvRef(id: Api.str(Api.dict(r), "id"), title: name))
                }
            }
        }
    }

    func createGroup() {
        if groupName.isEmpty || selected.isEmpty { return }
        Task {
            let r = try? await Api.post("/api/chat/conversations", ["type": "group", "name": groupName, "memberIds": selected])
            await MainActor.run {
                if let r, r["success"] as? Bool == true {
                    onOpen(ConvRef(id: Api.str(Api.dict(r), "id"), title: groupName))
                }
            }
        }
    }
}

// ============ 聊天室：气泡 + 已读回执 + 表情 + 附件 + 群管理 ============
struct ChatRoomView: View {
    let convId: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = Session.shared
    @State private var messages: [[String: Any]] = []
    @State private var maxId = 0
    @State private var input = ""
    @State private var readMap: [String: [String: Any]] = [:]
    @State private var convInfo: [String: Any]?
    @State private var showManage = false
    @State private var pickerItem: PhotosPickerItem?
    private let msgTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let readTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private let emojis = ["😀", "😂", "👍", "🙏", "", "❤️", "😅", "🤝", "💪", "", "", "🤔"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages.indices, id: \.self) { i in
                            bubble(messages[i]).id(Api.int(messages[i], "id"))
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last { proxy.scrollTo(Api.int(last, "id"), anchor: .bottom) }
                }
            }
            // 表情行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(emojis.indices, id: \.self) { i in
                        Button { input += emojis[i] } label: { Text(emojis[i]).font(.title3) }
                    }
                }
                .padding(.horizontal, 10)
            }
            .background(Color(hex: 0xfafafa))
            // 输入行
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.circle").font(.title2).foregroundColor(Color(hex: 0x1890ff))
                }
                TextField("输入消息…", text: $input)
                    .padding(8).background(Color(hex: 0xf0f0f0)).cornerRadius(8)
                Button { send() } label: {
                    Text("发送").font(.subheadline.bold()).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(hex: 0x1890ff)).cornerRadius(8)
                }
            }
            .padding(10)
            .background(Color.white)
        }
        .background(Color(hex: 0xf5f6f8))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                Button { showManage = true } label: { Text("⚙ 管理").font(.subheadline) }
            }
        }
        .sheet(isPresented: $showManage) {
            ManageView(convId: convId, convInfo: convInfo) {
                dismiss()
            }
        }
        .onAppear { loadConvInfo(); loadMessages(); loadReadStatus() }
        .onReceive(msgTimer) { _ in loadMessages() }
        .onReceive(readTimer) { _ in loadReadStatus() }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await uploadImage(data)
                }
                await MainActor.run { pickerItem = nil }
            }
        }
    }

    private var isOwner: Bool {
        guard let c = convInfo else { return false }
        return Api.str(c, "type") == "group" && Api.str(c, "creator_id") == session.userId
    }

    private func bubble(_ m: [String: Any]) -> some View {
        let mine = Api.str(m, "sender_id") == session.userId
        let t = Api.str(m, "msg_type").isEmpty ? Api.str(m, "type") : Api.str(m, "msg_type")
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine {
                    Text(Api.str(m, "sender_name")).font(.caption2).foregroundColor(Color(hex: 0x8c8c8c))
                }
                Group {
                    if t == "image", let fu = fileUrl(m) {
                        AsyncImage(url: fu) { img in img.resizable().scaledToFill() } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: 180, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if t == "video" || t == "file" {
                        Text((t == "video" ? "🎬 " : "📎 ") + Api.str(m, "file_name"))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(mine ? Color(hex: 0x1890ff) : Color.white)
                            .foregroundColor(mine ? .white : Color(hex: 0x262626))
                            .cornerRadius(10)
                    } else {
                        Text(Api.str(m, "content"))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(mine ? Color(hex: 0x1890ff) : Color.white)
                            .foregroundColor(mine ? .white : Color(hex: 0x262626))
                            .cornerRadius(10)
                    }
                }
                if mine {
                    Text(readText(m))
                        .font(.system(size: 10))
                        .foregroundColor(readText(m).hasPrefix("未读") ? Color(hex: 0xfa8c16) : Color(hex: 0x52c41a))
                }
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    func fileUrl(_ m: [String: Any]) -> URL? {
        let fu = Api.str(m, "file_url")
        guard !fu.isEmpty else { return nil }
        return URL(string: Session.base + fu + "?token=" + session.token)
    }

    func readText(_ m: [String: Any]) -> String {
        let id = String(Api.int(m, "id"))
        guard let rs = readMap[id] else { return "" }
        let rc = Api.int(rs, "read_count")
        let tot = Api.int(rs, "total_others")
        if tot <= 0 { return "" }
        if tot == 1 { return rc >= 1 ? "已读" : "未读" }
        return rc >= tot ? "全部已读" : "\(rc)/\(tot) 人已读"
    }

    func send() {
        let content = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return }
        input = ""
        Task {
            _ = try? await Api.post("/api/chat/conversations/\(convId)/messages", ["type": "text", "content": content])
            await MainActor.run { loadMessages() }
        }
    }

    func uploadImage(_ data: Data) async {
        let r = try? await Api.uploadFile(data: data, fileName: "photo.jpg", mime: "image/jpeg")
        if let r, r["success"] as? Bool == true {
            let d = Api.dict(r)
            _ = try? await Api.post("/api/chat/conversations/\(convId)/messages", [
                "type": "image", "fileId": Api.str(d, "fileId"), "content": Api.str(d, "fileName")
            ])
            await MainActor.run { loadMessages() }
        }
    }

    func loadConvInfo() {
        Task {
            let r = try? await Api.get("/api/chat/conversations")
            await MainActor.run {
                if let r {
                    for c in Api.arr(r) where Api.str(c, "id") == convId { convInfo = c }
                }
            }
        }
    }

    func loadMessages() {
        Task {
            let r = try? await Api.get("/api/chat/conversations/\(convId)/messages?after=\(maxId)")
            await MainActor.run {
                if let r {
                    let arr = Api.arr(r)
                    if maxId == 0 { messages = arr } else if !arr.isEmpty { messages.append(contentsOf: arr) }
                    for m in arr { maxId = max(maxId, Api.int(m, "id")) }
                }
            }
        }
    }

    func loadReadStatus() {
        Task {
            let r = try? await Api.get("/api/chat/conversations/\(convId)/read-status")
            await MainActor.run {
                if let r, let d = r["data"] as? [String: [String: Any]] { readMap = d }
            }
        }
    }
}

// ============ 群管理：移除成员 + 解散群聊 ============
struct ManageView: View {
    @Environment(\.dismiss) private var dismiss
    let convId: String
    let convInfo: [String: Any]?
    var onDisband: () -> Void = {}
    @State private var msg = ""

    var body: some View {
        NavigationStack {
            List {
                Section("成员") {
                    ForEach(memberIndices(), id: \.self) { i in
                        memberRow(members[i])
                    }
                }
                Section {
                    Button {
                        disband()
                    } label: {
                        Text("解散群聊").foregroundColor(Color(hex: 0xff4d4f)).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("群管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() } }
        }
    }

    private var members: [[String: Any]] {
        (convInfo?["members"] as? [[String: Any]]) ?? []
    }

    private func memberIndices() -> [Int] { Array(members.indices) }

    private func memberRow(_ m: [String: Any]) -> some View {
        let uid = Api.str(m, "id")
        let nm = Api.str(m, "display_name").isEmpty ? Api.str(m, "username") : Api.str(m, "display_name")
        return HStack {
            Text(nm)
            if uid == Api.str(convInfo ?? [:], "creator_id") {
                Text("群主").font(.caption2).foregroundColor(Color(hex: 0x722ed1))
            }
            Spacer()
            if uid != Session.shared.userId {
                Button("移除") { remove(uid) }
                    .font(.caption).foregroundColor(Color(hex: 0xff4d4f))
            }
        }
    }

    func remove(_ uid: String) {
        Task {
            let r = try? await Api.delete("/api/chat/conversations/\(convId)/members/\(uid)")
            await MainActor.run {
                if let r { msg = r["success"] as? Bool == true ? "已移除" : (Api.str(r, "message")) }
                dismiss()
            }
        }
    }

    func disband() {
        Task {
            _ = try? await Api.delete("/api/chat/conversations/\(convId)")
            await MainActor.run {
                dismiss()
                onDisband()
            }
        }
    }
}
