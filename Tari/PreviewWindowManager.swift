import SwiftUI
import AppKit
import Combine

class PreviewWindowManager: ObservableObject {
    static let shared = PreviewWindowManager()
    
    @Published var currentPreviewId: UUID?
    @Published var availableHeight: CGFloat = 600
    
    private init() {}
    
    func hidePreview() {
        currentPreviewId = nil
    }
    
    func togglePreview(itemID: UUID) {
        if currentPreviewId == itemID {
            hidePreview()
        } else {
            currentPreviewId = itemID
        }
    }
}
