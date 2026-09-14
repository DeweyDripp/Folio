import Foundation

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recent
    case title
    case author
    case imported

    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "Recently Read"
        case .title: "Title"
        case .author: "Author"
        case .imported: "Recently Added"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .title: "textformat"
        case .author: "person"
        case .imported: "calendar.badge.plus"
        }
    }

    func sort(_ books: [Book], lastRead: (UUID) -> Date?) -> [Book] {
        books.sorted { lhs, rhs in
            switch self {
            case .recent:
                let leftDate = lastRead(lhs.id) ?? lhs.importDate
                let rightDate = lastRead(rhs.id) ?? rhs.importDate
                return leftDate > rightDate
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author:
                let authorOrder = lhs.author.localizedCaseInsensitiveCompare(rhs.author)
                return authorOrder == .orderedSame
                    ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    : authorOrder == .orderedAscending
            case .imported:
                return lhs.importDate > rhs.importDate
            }
        }
    }
}
