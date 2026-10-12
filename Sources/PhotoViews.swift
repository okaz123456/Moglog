import SwiftUI
import UIKit

// サムネイル（正方形に切り抜き）
struct ThumbnailImage: View {
    let data: Data
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)   // 画像として読めないデータ（サンプル等）
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// 拡大表示
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data

    var body: some View {
        NavigationStack {
            Group {
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView("表示できません", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// 拡大表示する写真の受け渡し用
struct ViewerItem: Identifiable {
    let id = UUID()
    let data: Data
}
