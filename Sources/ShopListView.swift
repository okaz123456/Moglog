import SwiftUI
import SwiftData

// 一覧の表示切替（D-25）
enum ShopStatusFilter: String, CaseIterable, Identifiable {
    case all = "すべて"
    case visited = "行った"
    case wantToGo = "行きたい"
    var id: String { rawValue }
}

// 並べ替え（F-11）
enum ShopSortOrder: String, CaseIterable, Identifiable {
    case lastVisit = "最終来店日"
    case rating = "平均評価"
    case name = "店名"
    case created = "登録日"
    var id: String { rawValue }
}

struct ShopListView: View {
    @Query(sort: \Shop.updatedAt, order: .reverse) private var shops: [Shop]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]

    @State private var addMode: AddMode?
    @State private var searchText = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var showTagFilter = false

    // 次回起動時も保持（D-25）
    @AppStorage("listStatusFilter") private var statusRaw = ShopStatusFilter.all.rawValue
    @AppStorage("listSortOrder") private var sortRaw = ShopSortOrder.lastVisit.rawValue

    enum AddMode: String, Identifiable {
        case keyword, photo, manual
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if shops.isEmpty {
                    ContentUnavailableView(
                        "まだ記録がありません",
                        systemImage: "fork.knife",
                        description: Text("右上の＋からお店を登録できます")
                    )
                } else {
                    listContent
                }
            }
            .navigationTitle("お店")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("並べ替え", selection: $sortRaw) {
                            ForEach(ShopSortOrder.allCases) { order in
                                Text(order.rawValue).tag(order.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTagFilter = true
                    } label: {
                        Image(systemName: selectedTagIDs.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { addMode = .keyword } label: {
                            Label("キーワードで探す", systemImage: "magnifyingglass")
                        }
                        Button { addMode = .photo } label: {
                            Label("写真から登録", systemImage: "photo")
                        }
                        Button { addMode = .manual } label: {
                            Label("手入力", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $addMode) { mode in
                switch mode {
                case .keyword:
                    KeywordSearchView()
                case .photo:
                    PhotoRegisterView()
                case .manual:
                    NavigationStack {
                        ShopEditView(mode: .new(ShopDraft(source: .manual)))
                    }
                }
            }
            .sheet(isPresented: $showTagFilter) {
                TagFilterSheet(tags: allTags, selected: $selectedTagIDs)
            }
        }
    }

    private var listContent: some View {
        List {
            Section {
                Picker("表示", selection: $statusRaw) {
                    ForEach(ShopStatusFilter.allCases) { status in
                        Text(status.rawValue).tag(status.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                if !selectedTagIDs.isEmpty {
                    HStack {
                        Image(systemName: "tag")
                        Text(selectedTagNames)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("解除") { selectedTagIDs.removeAll() }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
            }
            let list = filteredShops
            if list.isEmpty {
                Section {
                    Text("条件に合うお店がありません")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(list) { shop in
                        NavigationLink {
                            ShopDetailView(shop: shop)
                        } label: {
                            ShopRowView(shop: shop)
                        }
                    }
                } header: {
                    Text("\(list.count)件・\(currentSort.rawValue)順")
                }
            }
        }
        .searchable(text: $searchText, prompt: "店名・住所・メモ")
    }

    // ---- 絞り込みと並べ替え ----

    private var currentStatus: ShopStatusFilter {
        ShopStatusFilter(rawValue: statusRaw) ?? .all
    }

    private var currentSort: ShopSortOrder {
        ShopSortOrder(rawValue: sortRaw) ?? .lastVisit
    }

    private var selectedTagNames: String {
        let names: [String] = allTags.filter { selectedTagIDs.contains($0.id) }.map(\.name)
        return names.joined(separator: "・")
    }

    private var filteredShops: [Shop] {
        let keyword: String = TagRules.normalized(searchText)
        var result: [Shop] = []
        for shop in shops {
            if shop.isDeleted || shop.modelContext == nil { continue }
            if !matchesStatus(shop) { continue }
            if !matchesKeyword(shop, keyword) { continue }
            if !matchesTags(shop) { continue }
            result.append(shop)
        }
        return sorted(result)
    }

    private func matchesStatus(_ shop: Shop) -> Bool {
        switch currentStatus {
        case .all: return true
        case .visited: return shop.isVisited
        case .wantToGo: return !shop.isVisited
        }
    }

    // 店名・住所・店メモ・来店メモの部分一致（D-27）
    private func matchesKeyword(_ shop: Shop, _ keyword: String) -> Bool {
        if keyword.isEmpty { return true }
        let fields: [String] = [shop.name, shop.address, shop.memo]
        for field in fields {
            if TagRules.normalized(field).contains(keyword) { return true }
        }
        for visit in shop.visits {
            if TagRules.normalized(visit.memo).contains(keyword) { return true }
        }
        return false
    }

    // 選んだタグをすべて含む（D-26）
    private func matchesTags(_ shop: Shop) -> Bool {
        if selectedTagIDs.isEmpty { return true }
        let shopTagIDs: Set<UUID> = Set(shop.tags.map(\.id))
        return selectedTagIDs.isSubset(of: shopTagIDs)
    }

    private func sorted(_ list: [Shop]) -> [Shop] {
        switch currentSort {
        case .lastVisit:
            // 来店記録のない店（行きたい）は末尾
            return list.sorted { a, b in
                let dateA: Date = a.lastVisitDate ?? .distantPast
                let dateB: Date = b.lastVisitDate ?? .distantPast
                if dateA != dateB { return dateA > dateB }
                return a.updatedAt > b.updatedAt
            }
        case .rating:
            // 未評価の店は末尾
            return list.sorted { a, b in
                let ratingA: Double = a.averageRating ?? -1
                let ratingB: Double = b.averageRating ?? -1
                if ratingA != ratingB { return ratingA > ratingB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        case .name:
            return list.sorted { a, b in
                a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        case .created:
            return list.sorted { a, b in a.createdAt > b.createdAt }
        }
    }
}

// 一覧の1行（サムネイル付き）
struct ShopRowView: View {
    let shop: Shop

    // 最新の来店記録の1枚目の写真
    private var coverThumbnail: Data? {
        let visits: [Visit] = shop.visits
            .filter { !$0.isDeleted && $0.modelContext != nil }
            .sorted { $0.date > $1.date }
        for visit in visits {
            let photos: [Photo] = visit.sortedPhotos.filter { !$0.isDeleted && $0.modelContext != nil }
            if let first = photos.first {
                return first.thumbnailData
            }
        }
        return nil
    }

    private var ratingText: String? {
        guard let average = shop.averageRating else { return nil }
        let averageText: String = String(format: "%.1f", average)
        if let latest = shop.latestRating {
            return "★\(averageText)（直近\(latest)）"
        }
        return "★\(averageText)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let data = coverThumbnail {
                ThumbnailImage(data: data, size: 56)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(shop.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(shop.isVisited ? "行った" : "行きたい")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background((shop.isVisited ? Color.green : Color.orange).opacity(0.2),
                                    in: Capsule())
                }
                HStack(spacing: 12) {
                    if let ratingText {
                        Text(ratingText)
                    }
                    if let last = shop.lastVisitDate {
                        Text("最終来店 " + last.formatted(date: .numeric, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !shop.tags.isEmpty {
                    Text(shop.sortedTags.map(\.name).joined(separator: "・"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// タグで絞り込み
struct TagFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tags: [Tag]
    @Binding var selected: Set<UUID>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TagChipsView(tags: tags, selected: $selected)
                } footer: {
                    Text("選んだタグをすべて含むお店を表示します")
                }
            }
            .navigationTitle("タグで絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("クリア") { selected.removeAll() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
