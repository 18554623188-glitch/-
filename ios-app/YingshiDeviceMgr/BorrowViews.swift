import SwiftUI
import PhotosUI

// ============ 设备借用/归还 ============
// 从已有设备中选择设备、从已有成员中选择借用人、可上传借用/归还照片，
// 借用时间与归还时间由服务器自动记录

// 借用/归还照片缩略图（带 Authorization 头下载）
struct LoanPhotoView: View {
    let fileId: String
    var size: CGFloat = 56
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let img {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .cornerRadius(8).clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(T.chipBG)
                    .frame(width: size, height: size)
                    .overlay(Image(systemName: "photo").foregroundColor(T.textFaint).font(.caption))
            }
        }
        .task {
            guard img == nil, !fileId.isEmpty else { return }
            if let data = try? await Api.download("/api/loans/photo/" + fileId) {
                img = UIImage(data: data)
            }
        }
    }
}

struct BorrowListView: View {
    @State private var loans: [[String: Any]] = []
    @State private var statusFilter = ""
    @State private var showLoan = false
    @State private var returnLoan: [String: Any]?
    private let chips = ["全部", "借用中", "已归还"]

    private var filtered: [[String: Any]] {
        statusFilter.isEmpty ? loans : loans.filter { Api.str($0, "status") == statusFilter }
    }

    private func load() {
        Task {
            if let r = try? await Api.get("/api/loans") {
                await MainActor.run { loans = Api.arr(r) }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 状态筛选 chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { f in
                            Button {
                                statusFilter = (f == "全部") ? "" : f
                            } label: {
                                Text(f)
                                    .font(.caption.bold())
                                    .foregroundColor(((statusFilter == "" && f == "全部") || statusFilter == f) ? .white : T.textSub)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(((statusFilter == "" && f == "全部") || statusFilter == f) ? Color(hex: 0x1890ff) : T.card)
                                    .cornerRadius(16)
                            }
                        }
                    }
                }

                ForEach(filtered.indices, id: \.self) { i in
                    loanCard(filtered[i])
                }

                if filtered.isEmpty {
                    Text("暂无借用记录")
                        .font(.footnote).foregroundColor(T.textHint)
                        .padding(.top, 30)
                }
            }
            .padding(16)
        }
        .background(T.pageBG)
        .navigationTitle("设备借用")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { showLoan = true } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $showLoan) {
            LoanFormView(isReturn: false, loan: nil) { load() }
        }
        .sheet(isPresented: Binding(get: { returnLoan != nil }, set: { if !$0 { returnLoan = nil } })) {
            if let l = returnLoan {
                LoanFormView(isReturn: true, loan: l) { load() }
            }
        }
    }

    private func loanCard(_ l: [String: Any]) -> some View {
        let returned = Api.str(l, "status") == "已归还"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Api.str(l, "device_name").isEmpty ? "未知设备" : Api.str(l, "device_name"))
                    .font(.subheadline.bold()).foregroundColor(T.textMain)
                Spacer()
                Text(Api.str(l, "status"))
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(returned ? Color(hex: 0x52c41a) : Color(hex: 0xfa8c16))
                    .cornerRadius(8)
            }
            Text("👤 借用人：" + Api.str(l, "borrower"))
                .font(.caption).foregroundColor(T.textSub)
            Text("📤 借用时间：" + (Api.str(l, "loan_time").isEmpty ? "-" : Api.str(l, "loan_time")))
                .font(.caption).foregroundColor(T.textSub)
            Text("📥 归还时间：" + (Api.str(l, "return_time").isEmpty ? "-" : Api.str(l, "return_time")))
                .font(.caption).foregroundColor(T.textSub)
            if !Api.str(l, "loan_photo").isEmpty || !Api.str(l, "return_photo").isEmpty {
                HStack(spacing: 8) {
                    if !Api.str(l, "loan_photo").isEmpty { LoanPhotoView(fileId: Api.str(l, "loan_photo")) }
                    if !Api.str(l, "return_photo").isEmpty { LoanPhotoView(fileId: Api.str(l, "return_photo")) }
                }
                .padding(.top, 2)
            }
            if !returned {
                Button {
                    returnLoan = l
                } label: {
                    Text("↩ 归还设备")
                        .font(.subheadline.bold()).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Color(hex: 0x1890ff)).cornerRadius(10)
                }
                .padding(.top, 4)
            }
        }
        .card()
    }
}

// 借用/归还表单（共用骨架）：设备与人员下拉均来自已有数据
struct LoanFormView: View {
    let isReturn: Bool
    let loan: [String: Any]?
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var devices: [[String: Any]] = []
    @State private var personnel: [[String: Any]] = []
    @State private var deviceId = ""
    @State private var personName = ""
    @State private var remark = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoId = ""
    @State private var uploading = false
    @State private var busy = false
    @State private var errMsg = ""
    @State private var showErr = false

    // 可借用设备（排除已报废）；归还时保证记录中的设备在选项中
    private var deviceOptions: [[String: Any]] {
        var list = devices.filter { Api.str($0, "status") != "已报废" }
        if isReturn, let l = loan, !list.contains(where: { Api.str($0, "id") == Api.str(l, "device_id") }) {
            list.insert(["id": Api.str(l, "device_id"), "name": Api.str(l, "device_name"), "type": "", "status": "借用中"], at: 0)
        }
        return list
    }

    // 可选人员；归还时保证记录中的借用人在选项中
    private var personOptions: [[String: Any]] {
        var list = personnel
        if isReturn, let l = loan, !list.contains(where: { Api.str($0, "name") == Api.str(l, "borrower") }) {
            list.insert(["id": Api.str(l, "borrower_id"), "name": Api.str(l, "borrower"), "department": ""], at: 0)
        }
        return list
    }

    private func load() {
        Task {
            let rd = try? await Api.get("/api/devices")
            let rp = try? await Api.get("/api/personnel")
            await MainActor.run {
                if let rd { devices = Api.arr(rd) }
                if let rp { personnel = Api.arr(rp) }
                if isReturn, let l = loan {
                    deviceId = Api.str(l, "device_id")
                    personName = Api.str(l, "borrower")
                } else {
                    deviceId = deviceOptions.first.map { Api.str($0, "id") } ?? ""
                    personName = personOptions.first.map { Api.str($0, "name") } ?? ""
                }
            }
        }
    }

    private func submit() {
        if deviceId.isEmpty || personName.isEmpty {
            errMsg = "请选择设备与人员"; showErr = true
            return
        }
        busy = true
        Task {
            do {
                let pid = personOptions.first(where: { Api.str($0, "name") == personName }).map { Api.str($0, "id") } ?? ""
                var body: [String: Any] = [
                    "device_id": deviceId,
                    "borrower": personName,
                    "borrower_id": pid,
                    "photo": photoId
                ]
                let r: [String: Any]
                if isReturn, let l = loan {
                    r = try await Api.post("/api/loans/" + Api.str(l, "id") + "/return", body)
                } else {
                    body["remark"] = remark
                    r = try await Api.post("/api/loans", body)
                }
                await MainActor.run {
                    busy = false
                    if r["success"] as? Bool == true {
                        onDone()
                        dismiss()
                    } else {
                        errMsg = Api.str(r, "message").isEmpty ? "操作失败" : Api.str(r, "message")
                        showErr = true
                    }
                }
            } catch {
                await MainActor.run {
                    busy = false
                    errMsg = "网络错误，请重试"
                    showErr = true
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isReturn ? "归还设备（可重新选择）" : "借用设备") {
                    Picker(isReturn ? "归还设备" : "借用设备", selection: $deviceId) {
                        ForEach(deviceOptions.indices, id: \.self) { i in
                            let d = deviceOptions[i]
                            Text("\(Api.str(d, "name"))（\(Api.str(d, "type")) / \(Api.str(d, "status"))）")
                                .tag(Api.str(d, "id"))
                        }
                    }
                    Picker(isReturn ? "归还人" : "借用人", selection: $personName) {
                        ForEach(personOptions.indices, id: \.self) { i in
                            let p = personOptions[i]
                            let dept = Api.str(p, "department")
                            Text(dept.isEmpty ? Api.str(p, "name") : "\(Api.str(p, "name")) · \(dept)")
                                .tag(Api.str(p, "name"))
                        }
                    }
                }
                Section(isReturn ? "归还照片（选填）" : "借用照片（选填）") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "camera.fill").foregroundColor(T.purple)
                            Text(uploading ? "照片上传中…" : (photoId.isEmpty ? "选择照片" : "✅ 照片已上传（点击更换）"))
                                .foregroundColor(T.textMain)
                            Spacer()
                            if let photoData, let ui = UIImage(data: photoData) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6).clipped()
                            }
                        }
                    }
                }
                if !isReturn {
                    Section("备注（选填）") {
                        TextField("如：剧组拍摄借用", text: $remark, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                Section {
                    Button {
                        submit()
                    } label: {
                        Text(busy ? "提交中…" : (isReturn ? "确认归还" : "确认借用"))
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(busy || uploading)
                } footer: {
                    Text(isReturn ? "确认归还后，服务器将自动记录归还时间。" : "确认借用后，服务器将自动记录借用时间。")
                }
            }
            .navigationTitle(isReturn ? "归还设备" : "借用设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { load() }
            .onChange(of: photoItem) { item in
                guard let item else { return }
                uploading = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run { photoData = data }
                        if let r = try? await Api.uploadFile(data: data, fileName: "loan_photo_\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg"),
                           r["success"] as? Bool == true {
                            let d = Api.dict(r)
                            await MainActor.run { photoId = Api.str(d, "fileId"); uploading = false }
                        } else {
                            await MainActor.run {
                                uploading = false
                                photoData = nil
                                errMsg = "照片上传失败，请重试"
                                showErr = true
                            }
                        }
                    } else {
                        await MainActor.run { uploading = false }
                    }
                }
            }
            .alert("提示", isPresented: $showErr) {
                Button("知道了", role: .cancel) {}
            } message: { Text(errMsg) }
        }
    }
}
