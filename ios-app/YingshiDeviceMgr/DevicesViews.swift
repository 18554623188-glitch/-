import SwiftUI
import AVFoundation
import Vision

// ============ 设备页：搜索 + 扫码查设备 + 状态筛选 + 列表 ============
struct DevicesView: View {
    @State private var devices: [[String: Any]] = []
    @State private var keyword = ""
    @State private var statusFilter = ""
    @State private var showScan = false
    @State private var showAdd = false
    private let filters = ["全部", "正常", "维修中", "闲置", "已报废"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 搜索行
                    HStack(spacing: 10) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(T.textFaint)
                            TextField("搜索名称 / 编号 / 位置", text: $keyword)
                                .foregroundColor(T.textMain)
                                .onSubmit { load() }
                        }
                        .padding(10).background(T.card).cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                        Button("搜索") { load() }
                            .font(.subheadline.bold()).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color(hex: 0x1890ff)).cornerRadius(20)
                    }
                    // 扫条形码查设备（紫色按钮，与鸿蒙端一致）
                    Button {
                        requestCameraAndScan()
                    } label: {
                        HStack {
                            Text("📷").font(.headline)
                            Text("扫条形码查设备").fontWeight(.bold)
                            Text("扫描设备条码，自动按编号检索").font(.caption2).opacity(0.85)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(LinearGradient(colors: [Color(hex: 0x722ed1), Color(hex: 0x9254de)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(22)
                    }
                    // 设备借用/归还入口（橙色按钮，与安卓/鸿蒙端一致）
                    NavigationLink {
                        BorrowListView()
                    } label: {
                        HStack {
                            Text("🔄").font(.headline)
                            Text("设备借用 / 归还").fontWeight(.bold)
                            Text("可上传照片，自动记录时间").font(.caption2).opacity(0.85)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(LinearGradient(colors: [Color(hex: 0xfa8c16), Color(hex: 0xffa940)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(22)
                    }
                    // 状态筛选 chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { f in
                                Button {
                                    statusFilter = (f == "全部") ? "" : f
                                    load()
                                } label: {
                                    Text(f)
                                        .font(.caption.bold())
                                        .foregroundColor((statusFilter == "" && f == "全部") || statusFilter == f ? .white : T.textSub)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(((statusFilter == "" && f == "全部") || statusFilter == f) ? Color(hex: 0x1890ff) : T.card)
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(devices.indices, id: \.self) { i in
                            NavigationLink { DeviceDetailView(device: devices[i]) } label: {
                                deviceRow(devices[i])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(T.pageBG)
            .navigationTitle("设备")
            .toolbar {
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            .onAppear { load() }
            .fullScreenCover(isPresented: $showScan) {
                ScannerView { code in
                    showScan = false
                    if !code.isEmpty {
                        keyword = code
                        load()
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddDeviceView() }
        }
    }

    private func deviceRow(_ d: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Api.str(d, "name")).font(.headline).foregroundColor(T.textMain)
                Spacer()
                StatusBadge(status: Api.str(d, "status"))
            }
            Text("类型：\(Api.str(d, "type")) 编号：\(Api.str(d, "serial_number"))")
                .font(.caption).foregroundColor(Color(hex: 0x8c8c8c))
            Text("位置：\(Api.str(d, "location")) 负责人：\(Api.str(d, "responsible_person"))")
                .font(.caption).foregroundColor(Color(hex: 0x8c8c8c))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    func requestCameraAndScan() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { showScan = true }
        }
    }

    func load() {
        var query = "/api/devices?_=1"
        if !keyword.trimmingCharacters(in: .whitespaces).isEmpty {
            query += "&keyword=" + (keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        if !statusFilter.isEmpty {
            query += "&status=" + (statusFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        let path = query
        Task {
            let r = try? await Api.get(path)
            await MainActor.run { if let r { devices = Api.arr(r) } }
        }
    }
}

// ============ 设备详情 + 报修（全员）+ 编辑（仅管理员） ============
struct DeviceDetailView: View {
    @StateObject private var session = Session.shared
    @State private var current: [String: Any]
    @State private var showRepair = false
    @State private var showEdit = false
    @State private var toast = ""

    init(device: [String: Any]) {
        _current = State(initialValue: device)
    }

    private var deviceId: String { Api.str(current, "id") }
    private var status: String { Api.str(current, "status") }
    private var isAdmin: Bool { session.role == "admin" }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text(Api.str(current, "name")).font(.title3.bold()).foregroundColor(T.textMain)
                    Spacer()
                    StatusBadge(status: status)
                }
                .card()
                row("类型", Api.str(current, "type"))
                row("编号", Api.str(current, "serial_number"))
                row("型号", Api.str(current, "model"))
                row("位置", Api.str(current, "location"))
                row("负责人", Api.str(current, "responsible_person"))
                row("购入日期", Api.str(current, "purchase_date"))
                row("保修期至", Api.str(current, "warranty_date"))
                row("描述", Api.str(current, "description"))
                // 操作区：报修全员可用；编辑仅管理员可见
                HStack(spacing: 12) {
                    if status != "维修中" && status != "已报废" {
                        Button { showRepair = true } label: {
                            Label("报修", systemImage: "wrench.and.screwdriver.fill")
                                .font(.subheadline.bold()).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(12)
                                .background(Color(hex: 0xfa8c16)).cornerRadius(12)
                        }
                    }
                    if isAdmin {
                        Button { showEdit = true } label: {
                            Label("编辑信息", systemImage: "square.and.pencil")
                                .font(.subheadline.bold()).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(12)
                                .background(Color(hex: 0x1890ff)).cornerRadius(12)
                        }
                    }
                }
                if !toast.isEmpty {
                    Text(toast).font(.footnote.bold()).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(hex: 0x52c41a)).cornerRadius(14)
                }
            }
            .padding(16)
        }
        .background(T.pageBG)
        .navigationTitle("设备详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRepair) {
            RepairSheet(deviceId: deviceId, deviceName: Api.str(current, "name")) { updated, m in apply(updated, m) }
        }
        .sheet(isPresented: $showEdit) {
            EditDeviceSheet(device: current) { updated, m in apply(updated, m) }
        }
    }

    private func apply(_ updated: [String: Any]?, _ m: String) {
        if let updated, !updated.isEmpty { current = updated }
        toast = m
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundColor(Color(hex: 0x8c8c8c))
                .frame(width: 76, alignment: .leading)
            Text(value.isEmpty ? "-" : value).font(.subheadline).foregroundColor(T.textMain)
            Spacer()
        }
        .card()
    }
}

// ============ 报修单：所有用户可提交，提交后设备标记为维修中并通知管理员 ============
struct RepairSheet: View {
    @Environment(\.dismiss) private var dismiss
    let deviceId: String
    let deviceName: String
    var onDone: ([String: Any]?, String) -> Void
    @State private var remark = ""
    @State private var msg = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("报修信息") {
                    Text("设备：\(deviceName)")
                    TextField("故障描述（选填）", text: $remark, axis: .vertical)
                        .lineLimit(3...5)
                }
                Section {
                    Button { submit() } label: {
                        HStack {
                            if busy { ProgressView() }
                            Text("提交报修").fontWeight(.bold).frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(busy)
                    if !msg.isEmpty { Text(msg).foregroundColor(.red) }
                }
                Text("提交后设备将标记为「维修中」，并通知全部管理员处理。")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .navigationTitle("设备报修")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { dismiss() } }
        }
    }

    func submit() {
        busy = true; msg = ""
        Task {
            let r = try? await Api.patch("/api/devices/" + deviceId + "/repair", ["remark": remark])
            await MainActor.run {
                busy = false
                if let r, r["success"] as? Bool == true {
                    onDone(r["data"] as? [String: Any], Api.str(r, "message").isEmpty ? "报修成功" : Api.str(r, "message"))
                    dismiss()
                } else {
                    msg = r?["message"] as? String ?? "报修失败，请稍后重试"
                }
            }
        }
    }
}

// ============ 编辑设备：仅管理员，PUT /api/devices/:id ============
struct EditDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onDone: ([String: Any]?, String) -> Void
    @State private var deviceId: String
    @State private var name: String
    @State private var type: String
    @State private var model: String
    @State private var serial: String
    @State private var status: String
    @State private var location: String
    @State private var purchaseDate: String
    @State private var warrantyDate: String
    @State private var responsible: String
    @State private var desc: String
    @State private var msg = ""
    @State private var busy = false
    private let statuses = ["正常", "维修中", "闲置", "已报废"]

    init(device: [String: Any], onDone: @escaping ([String: Any]?, String) -> Void) {
        _deviceId = State(initialValue: Api.str(device, "id"))
        _name = State(initialValue: Api.str(device, "name"))
        _type = State(initialValue: Api.str(device, "type"))
        _model = State(initialValue: Api.str(device, "model"))
        _serial = State(initialValue: Api.str(device, "serial_number"))
        _status = State(initialValue: Api.str(device, "status"))
        _location = State(initialValue: Api.str(device, "location"))
        _purchaseDate = State(initialValue: Api.str(device, "purchase_date"))
        _warrantyDate = State(initialValue: Api.str(device, "warranty_date"))
        _responsible = State(initialValue: Api.str(device, "responsible_person"))
        _desc = State(initialValue: Api.str(device, "description"))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("设备名称 *", text: $name)
                    TextField("类型 *", text: $type)
                    TextField("型号", text: $model)
                    TextField("编号 / 序列号", text: $serial)
                    Picker("状态", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0) }
                    }
                }
                Section("其他") {
                    TextField("位置", text: $location)
                    TextField("购入日期", text: $purchaseDate)
                    TextField("保修期至", text: $warrantyDate)
                    TextField("负责人", text: $responsible)
                    TextField("描述", text: $desc)
                }
                Section {
                    Button { submit() } label: {
                        HStack {
                            if busy { ProgressView() }
                            Text("保存修改").fontWeight(.bold).frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(busy || name.isEmpty || type.isEmpty)
                    if !msg.isEmpty { Text(msg).foregroundColor(.red) }
                }
            }
            .navigationTitle("编辑设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { dismiss() } }
        }
    }

    func submit() {
        busy = true; msg = ""
        Task {
            let r = try? await Api.put("/api/devices/" + deviceId, [
                "name": name, "type": type, "model": model, "serial_number": serial,
                "status": status, "location": location, "purchase_date": purchaseDate,
                "warranty_date": warrantyDate, "responsible_person": responsible, "description": desc
            ])
            await MainActor.run {
                busy = false
                if let r, r["success"] as? Bool == true {
                    onDone(r["data"] as? [String: Any], Api.str(r, "message").isEmpty ? "保存成功" : Api.str(r, "message"))
                    dismiss()
                } else {
                    msg = r?["message"] as? String ?? "保存失败，请稍后重试"
                }
            }
        }
    }
}

// ============ 添加设备：类型 chips + 扫码录编号 ============
struct AddDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = ""
    @State private var customType = ""
    @State private var model = ""
    @State private var serial = ""
    @State private var location = ""
    @State private var responsible = ""
    @State private var purchaseDate = ""
    @State private var desc = ""
    @State private var msg = ""
    @State private var showScan = false
    private let types = ["摄像机", "镜头", "灯光", "音响", "监视器", "三脚架", "轨道", "录音设备", "道具", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("设备名称 *", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(types, id: \.self) { t in
                                Button {
                                    type = t
                                } label: {
                                    Text(t)
                                        .font(.caption.bold())
                                        .foregroundColor(type == t ? .white : T.textSub)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(type == t ? Color(hex: 0x1890ff) : T.chipBG)
                                        .cornerRadius(14)
                                }
                            }
                        }
                    }
                    if type == "其他" { TextField("自定义类型", text: $customType) }
                    TextField("型号", text: $model)
                }
                Section("编号（可扫码录入）") {
                    HStack {
                        TextField("设备编号 / 序列号", text: $serial)
                        Button {
                            AVCaptureDevice.requestAccess(for: .video) { _ in
                                DispatchQueue.main.async { showScan = true }
                            }
                        } label: {
                            Text("📷 扫码").font(.subheadline.bold()).foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color(hex: 0x722ed1)).cornerRadius(8)
                        }
                    }
                }
                Section("其他") {
                    TextField("位置", text: $location)
                    TextField("购入日期（如 2024-05-01）", text: $purchaseDate)
                    TextField("负责人", text: $responsible)
                    TextField("描述", text: $desc)
                }
                Section {
                    Button("提交添加") { submit() }
                    if !msg.isEmpty { Text(msg).foregroundColor(.red) }
                }
            }
            .navigationTitle("添加设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() } }
            .fullScreenCover(isPresented: $showScan) {
                ScannerView { code in
                    showScan = false
                    if !code.isEmpty { serial = code }
                }
            }
        }
    }

    func submit() {
        let finalType = (type == "其他" && !customType.trimmingCharacters(in: .whitespaces).isEmpty) ? customType.trimmingCharacters(in: .whitespaces) : type
        if name.isEmpty || finalType.isEmpty { msg = "请填写设备名称并选择设备类型"; return }
        Task {
            let r = try? await Api.post("/api/devices", [
                "name": name, "type": finalType, "model": model, "serial_number": serial,
                "status": "正常", "location": location, "purchase_date": purchaseDate,
                "responsible_person": responsible, "description": desc
            ])
            await MainActor.run {
                if let r, r["success"] as? Bool == true { dismiss() }
                else { msg = r?["message"] as? String ?? "添加失败" }
            }
        }
    }
}

// ============ 原生扫码页（AVFoundation + Vision，支持 Code128/EAN-13/QR） ============
struct ScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onResult = onResult
        return vc
    }
    func updateUIViewController(_ vc: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onResult: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var detecting = false
    private var finished = false

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        setupCamera()
    }

    private func setupUI() {
        let btn = UIButton(type: .system)
        btn.setTitle("✕ 返回", for: .normal)
        btn.tintColor = .white
        btn.titleLabel?.font = .boldSystemFont(ofSize: 16)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(btn)

        let box = UIView()
        box.layer.borderColor = UIColor(red: 0.15, green: 0.82, blue: 0.81, alpha: 1).cgColor
        box.layer.borderWidth = 2
        box.layer.cornerRadius = 12
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)

        let label = UILabel()
        label.text = "将条形码对准框内，自动识别中…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            btn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 280),
            box.heightAnchor.constraint(equalToConstant: 170),
            label.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 26),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "scan.queue"))
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            previewLayer = preview
            view.layer.insertSublayer(preview, at: 0)
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        } catch {
        }
    }

    @objc private func close() {
        guard !finished else { return }
        finished = true
        session.stopRunning()
        onResult?("")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !detecting, !finished, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        detecting = true
        let req = VNDetectBarcodesRequest { [weak self] request, _ in
            guard let self else { return }
            if !self.finished,
               let obs = request.results?.first as? VNBarcodeObservation,
               let s = obs.payloadStringValue, !s.isEmpty {
                self.finished = true
                DispatchQueue.main.async {
                    self.session.stopRunning()
                    self.onResult?(s)
                }
            }
            self.detecting = false
        }
        req.symbologies = [.code128, .ean13, .qr]
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, options: [:])
        try? handler.perform([req])
    }
}
