# Tari - 智能剪贴板管理器

Tari 是一个功能强大的 macOS 剪贴板管理应用，帮助您高效地管理和使用剪贴板内容。

## ✨ 主要功能

- **智能记录**: 自动捕捉并保存剪贴板历史，包括文本、图片和文件
- **拖拽排序**: 轻松调整剪贴板项目的顺序
- **快速搜索**: 实时搜索历史记录，快速找到需要的内容
- **预览功能**: 点击空格键预览剪贴板内容
- **一键粘贴**: 双击项目即可复制并粘贴到当前应用
- **持久化存储**: 使用 Core Data 安全保存所有剪贴板历史
- **分页加载**: 优化性能，支持大量剪贴板历史

## 🛠 技术栈

- **语言**: Swift 5.0+
- **UI框架**: SwiftUI
- **持久化**: Core Data
- **事件处理**: Combine
- **平台**: macOS (10.15+)

## 📦 项目结构

```
Tari/
├── Assets.xcassets/          # 应用资源文件
├── Managers/                 # 业务逻辑管理
│   └── ClipboardManager.swift  # 剪贴板管理器
├── Models/                   # 数据模型
│   └── ClipboardItem.swift     # 剪贴板项目模型
├── Utils/                    # 工具类
│   └── Formatters.swift        # 格式化工具
├── Views/                    # 视图组件
│   ├── EffectViews.swift       # 效果视图
│   └── ItemCard.swift          # 剪贴板项目卡片
├── AppDelegate.swift         # 应用代理
├── ContentView.swift         # 主视图
├── Persistence.swift         # Core Data 配置
└── TariApp.swift             # 应用入口
```

## 🚀 安装与运行

### 前提条件

- macOS 10.15+ (Catalina 或更高版本)
- Xcode 12.0+ (Swift 5.3+)

### 安装步骤

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd Tari
   ```

2. **打开项目**
   ```bash
   open Tari.xcodeproj
   ```

3. **构建并运行**
   - 在 Xcode 中选择合适的模拟器或真机
   - 点击运行按钮 (▶️) 或使用快捷键 `Cmd+R`

## 📖 使用说明

### 基本操作

- **查看历史**: 应用启动后自动显示剪贴板历史
- **搜索内容**: 在顶部搜索栏输入关键词筛选
- **选择项目**: 点击项目进行选择
- **双击粘贴**: 双击项目即可复制并粘贴到当前应用
- **预览内容**: 选择项目后按空格键显示预览
- **拖拽排序**: 拖动项目调整顺序
- **删除项目**: 选择项目后按 Delete 键删除

### 高级功能

- **分页加载**: 滚动到底部自动加载更多历史记录
- **智能去重**: 相同内容自动合并为一条记录
- **内容分类**: 自动识别文本、图片和文件类型

## 🎨 界面特点

- **现代设计**: 采用 macOS Big Sur 及更高版本的设计风格
- **玻璃态效果**: 半透明背景，与系统界面无缝融合
- **流畅动画**: 平滑的过渡和交互动画
- **响应式布局**: 适配不同屏幕尺寸

## 🔧 核心功能实现

### 剪贴板监听

应用通过定时检查剪贴板变化来自动记录内容：

```swift
private func checkClipboard() {
    guard pasteboard.changeCount != lastChangeCount else { return }
    lastChangeCount = pasteboard.changeCount
    
    // 检查剪贴板内容类型并处理
    // ...
}
```

### 内容分类

支持多种剪贴板内容类型：

```swift
enum ClipboardContentType: String, Codable {
    case text      // 文本内容
    case fileURL   // 文件路径
    case image     // 图片
    case unknown   // 未知类型
}
```

### 持久化存储

使用 Core Data 存储剪贴板历史：

```swift
private func saveNewItem(text: String, contentType: ClipboardContentType, additionalData: Data? = nil) {
    // 创建并保存新的剪贴板项目
    // ...
}
```

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request 来帮助改进 Tari！

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 📞 联系方式

如有问题或建议，欢迎通过以下方式联系：

- 项目 Issues: [GitHub Issues](<repository-url>/issues)
- 邮件: <your-email@example.com>

---

**Tari** - 让剪贴板管理更智能、更高效！
