import SwiftUI
import AppKit
import Combine

class PreviewWindowManager: ObservableObject {
    static let shared = PreviewWindowManager()
    
    @Published var currentPreviewId: UUID?
    @Published var availableHeight: CGFloat = 600
    
    private var lastHideTime: Date = .distantPast
    
    private init() {}
    
    func hidePreview() {
        currentPreviewId = nil
        lastHideTime = Date()
    }
    
    func wasRecentlyOpen() -> Bool {
        return currentPreviewId != nil || Date().timeIntervalSince(lastHideTime) < 0.2
    }
    
    func togglePreview(itemID: UUID) {
        if currentPreviewId == itemID {
            hidePreview()
        } else {
            currentPreviewId = itemID
        }
    }
}
