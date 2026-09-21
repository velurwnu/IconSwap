import Foundation

enum IconSwapError: LocalizedError {
    case permissionDenied(path: String)
    case setIconFailed(path: String)
    case downloadFailed(underlying: Error)
    case invalidImage(url: URL)
    case appNotFound(path: String)
    case readOnlyApp(path: String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let path):
            return "macOS не разрешает менять иконку «\(path)». Откройте Системные настройки → Конфиденциальность и безопасность → Управление приложениями и разрешите доступ IconSwap."
        case .setIconFailed(let path):
            return "Не удалось установить иконку для «\(path)»."
        case .downloadFailed(let underlying):
            return "Не удалось скачать иконку: \(underlying.localizedDescription)"
        case .invalidImage(let url):
            return "Файл «\(url.lastPathComponent)» не удалось прочитать как изображение."
        case .appNotFound(let path):
            return "Приложение не найдено: \(path)"
        case .readOnlyApp(let path):
            return "«\(path)» защищено системой (SIP) и недоступно для изменения."
        }
    }

    var isPermissionIssue: Bool {
        if case .permissionDenied = self { return true }
        return false
    }
}
