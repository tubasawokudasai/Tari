import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    @AppStorage("retentionPeriod") private var retentionPeriod: Int = 30
    @AppStorage("maxRecordCount") private var maxRecordCount: Int = 1000
    @State private var showClearAlert = false
    
    @State private var hasCentered = false
    @State private var currentWindow: NSWindow?
    
    var body: some View {
        Form {
            Section(header: Text("常规设置")) {
                Toggle("开机启动 Tari", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setLaunchAtLogin(enabled: $0) }
                ))
                
                if let desc = launchManager.statusDescription {
                    HStack {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        Button("打开系统设置") {
                            launchManager.openSystemLoginItemsSettings()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
                
                if let errorMsg = launchManager.errorMessage {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Section(header: Text("快捷键设置")) {
                KeyboardShortcuts.Recorder("唤醒剪贴板面板", name: .toggleBottomClip)
            }
            
            Section(header: Text("剪贴板历史")) {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("历史保留时间", selection: $retentionPeriod) {
                        Text("1 周").tag(7)
                        Text("1 个月").tag(30)
                        Text("6 个月").tag(180)
                        Text("永久保留").tag(0)
                    }
                    Text("超过此时间的剪贴记录将被自动清理")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
                
                Picker("最大存储条数", selection: $maxRecordCount) {
                    Text("100 条").tag(100)
                    Text("500 条").tag(500)
                    Text("1000 条").tag(1000)
                    Text("5000 条").tag(5000)
                    Text("10000 条").tag(10000)
                    Text("无限制").tag(0)
                }
                .padding(.vertical, 2)
            }
            
            Section(header: Text("数据管理")) {
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    Text("清空剪贴板历史记录")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 440)
        .background(
            WindowAccessor { window in
                self.currentWindow = window
                configureWindow(window)
            }
        )
        .onAppear {
            launchManager.refreshStatus()
            (NSApp.delegate as? AppDelegate)?.closePanel()
            if let window = currentWindow {
                configureWindow(window)
            }
        }
        .alert("确定要清空所有剪贴板历史记录吗？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空所有记录", role: .destructive) {
                (NSApp.delegate as? AppDelegate)?.clearClipboard()
            }
        } message: {
            Text("此操作将彻底删除所有本地存储剪贴板历史数据，该过程不可撤销。")
        }
    }
    
    private func configureWindow(_ window: NSWindow) {
        window.level = .statusBar
        if !hasCentered {
            window.center()
            hasCentered = true
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Window Accessor
private struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView()
        view.configure = configure
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let accessorView = nsView as? WindowAccessorView {
            accessorView.configure = configure
            if let window = accessorView.window {
                window.level = .statusBar
            }
        }
    }
}

private class WindowAccessorView: NSView {
    var configure: ((NSWindow) -> Void)?
    private var observer: NSObjectProtocol?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        
        if let window = window {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self = self, let window = window else { return }
                self.configure?(window)
            }
            
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self = self, let window = window else { return }
                self.configure?(window)
            }
        }
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

