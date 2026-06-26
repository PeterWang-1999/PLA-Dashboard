import Foundation

/// 将系统级 `NSError` 转为面向用户的中文导入错误说明。
enum ImportUserFacingError {
    static func message(for error: Error, phase: ImportFailurePhase? = nil) -> String {
        if let staging = error as? ImportStagingError {
            return staging.errorDescription ?? fallback(error, phase: phase)
        }
        if let normalization = error as? ImportTextNormalizationError {
            return normalization.errorDescription ?? fallback(error, phase: phase)
        }
        if let pipeline = error as? ImportPipelineError {
            return pipeline.localizedDescription
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty,
           description != error.localizedDescription {
            return description
        }
        if let nsError = error as NSError? {
            return message(forNSError: nsError, phase: phase)
        }
        return fallback(error, phase: phase)
    }

    private static func message(forNSError error: NSError, phase: ImportFailurePhase?) -> String {
        let prefix = phase.map { "\($0.userTitle)：" } ?? ""

        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoPermissionError:
                return prefix + "无法读取所选文件。请重新通过「选择文件」授权，或确认文件未被其他程序独占。"
            case NSFileReadNoSuchFileError:
                return prefix + "找不到所选文件，可能已被移动或删除。"
            case NSFileReadCorruptFileError:
                return prefix + "文件已损坏或格式异常，无法读取。"
            case NSFileReadTooLargeError:
                return prefix + "文件过大，无法一次性读入内存。请将文件另存为 UTF-8 编码后再试。"
            case NSFileWriteOutOfSpaceError:
                return prefix + "磁盘空间不足，无法完成文件复制。请清理空间后重试。"
            case NSFileWriteNoPermissionError:
                return prefix + "无法写入应用数据目录，请检查磁盘权限与可用空间。"
            case 260:
                return prefix + "无法打开文件。请确认文件仍存在且未被移动。"
            case 4:
                return prefix + "无法读取文件内容，请确认文件完整且未被占用。"
            default:
                break
            }
        }

        if error.domain == NSPOSIXErrorDomain {
            switch error.code {
            case Int(ENOMEM):
                return prefix + "内存不足，无法处理该大小的文件。请关闭其他应用后重试。"
            case Int(ENOSPC):
                return prefix + "磁盘空间不足，无法完成导入。"
            default:
                break
            }
        }

        let systemMessage = error.localizedDescription
        if systemMessage.isEmpty || systemMessage == "The operation couldn’t be completed." {
            return prefix + "导入过程中发生未知错误（\(error.domain) \(error.code)）。"
        }

        if systemMessage == "The file couldn't be opened." {
            return prefix + "无法打开或读取文件。若文件较大，请确认磁盘空间充足；也可尝试将文件复制到桌面后重新选择。"
        }

        return prefix + systemMessage
    }

    private static func fallback(_ error: Error, phase: ImportFailurePhase?) -> String {
        let prefix = phase.map { "\($0.userTitle)：" } ?? ""
        let description = error.localizedDescription
        if description.isEmpty {
            return prefix + "导入失败，请重试。"
        }
        return prefix + description
    }
}

enum ImportFailurePhase: Sendable {
    case stagingCopy
    case stagingEncoding
    case stagingChecksum
    case stagingBookmark
    case parsing
    case writing

    var userTitle: String {
        switch self {
        case .stagingCopy: "复制文件"
        case .stagingEncoding: "检查文本编码"
        case .stagingChecksum: "校验文件"
        case .stagingBookmark: "保存导入记录"
        case .parsing: "解析文件"
        case .writing: "写入数据库"
        }
    }
}
