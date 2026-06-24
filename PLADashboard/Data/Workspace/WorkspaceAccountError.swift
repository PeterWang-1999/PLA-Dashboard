import Foundation

enum WorkspaceAccountError: Error, LocalizedError {
    case invalidManifest(String)
    case unsupportedManifestVersion(Int)
    case migrationFailed(String)
    case incompleteMigration(String)
    case accountNotFound(String)
    case importInProgress

    var errorDescription: String? {
        switch self {
        case .invalidManifest(let message):
            "账户配置无效：\(message)"
        case .unsupportedManifestVersion(let version):
            "不支持的账户配置版本：\(version)"
        case .migrationFailed(let message):
            "数据库迁移失败：\(message)"
        case .incompleteMigration(let message):
            "数据库迁移未完成：\(message)"
        case .accountNotFound(let id):
            "账户不存在：\(id)"
        case .importInProgress:
            "导入进行中，无法切换账户"
        }
    }
}
