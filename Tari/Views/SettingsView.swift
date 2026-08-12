import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @AppStorage("retentionPeriod") private var retentionPeriod: Int = 30
    @AppStorage("maxRecordCount") private var maxRecordCount: Int = 1000
    @State private var showClearAlert = false
    
    var body: some View {
        Form {
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
        .frame(width: 450, height: 380)
        .alert("确定要清空所有剪贴板历史记录吗？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空所有记录", role: .destructive) {
                (NSApp.delegate as? AppDelegate)?.clearClipboard()
            }
        } message: {
            Text("此操作将彻底删除所有本地存储剪贴板历史数据，该过程不可撤销。")
        }
    }
}
