import Foundation
import Supabase

/// Service for handling GDPR data export functionality
/// Per plan.md Phase 10 Section 10.3: Data Export GDPR
/// - Provide "Export My Data" button in Privacy and Data section
/// - Generate ZIP file containing all user data
/// - Deliver via email or download link
/// - Process within 48 hours
/// - Send notification when ready
@MainActor
final class DataExportService: ObservableObject {

    // MARK: - Singleton

    static let shared = DataExportService()

    // MARK: - Published Properties

    @Published private(set) var isExporting: Bool = false
    @Published private(set) var currentExportRequest: DataExportRequest?
    @Published private(set) var error: DataExportError?

    // MARK: - Private Properties

    private let database: PostgrestClient
    private let functions: FunctionsClient
    private let storage: SupabaseStorageClient

    // MARK: - Constants

    /// Export expiration in days (per plan.md)
    static let exportExpirationDays = 7

    // MARK: - Initialization

    init(database: PostgrestClient? = nil,
         functions: FunctionsClient? = nil,
         storage: SupabaseStorageClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
        self.functions = functions ?? SupabaseConfig.functions
        self.storage = storage ?? SupabaseConfig.storage
    }

    // MARK: - Public Methods

    /// Request a data export for the specified user
    /// Per plan.md Section 10.3:
    /// - Creates export request in database
    /// - Calls Edge Function to generate ZIP
    /// - Returns download URL when complete
    /// - Parameter userId: The user's UUID
    /// - Parameter deliveryMethod: How to deliver (download or email)
    /// - Parameter email: Email address for email delivery
    /// - Returns: The export result with download URL
    func requestExport(
        userId: UUID,
        deliveryMethod: DeliveryMethod = .download,
        email: String? = nil
    ) async throws -> DataExportResult {
        isExporting = true
        error = nil
        defer { isExporting = false }

        do {
            // Check for existing pending request
            if let existing = try await getExistingPendingRequest(userId: userId) {
                currentExportRequest = existing
                if existing.status == .completed, let downloadUrl = existing.downloadUrl {
                    return DataExportResult(
                        success: true,
                        requestId: existing.id,
                        downloadUrl: downloadUrl,
                        expiresAt: existing.expiresAt,
                        message: "Your previous export is still available"
                    )
                } else if existing.status == .processing {
                    return DataExportResult(
                        success: true,
                        requestId: existing.id,
                        downloadUrl: nil,
                        expiresAt: nil,
                        message: "Export is being processed. You'll be notified when ready."
                    )
                }
            }

            // Call Edge Function to generate export
            let requestBody = ExportRequestBody(
                userId: userId.uuidString,
                requestId: nil,
                deliveryMethod: deliveryMethod.rawValue,
                email: email
            )

            let result: EdgeFunctionResponse = try await functions.invoke(
                "export-user-data",
                options: FunctionInvokeOptions(body: requestBody)
            )

            if result.success {
                // Update current request
                if let requestId = result.requestId {
                    currentExportRequest = DataExportRequest(
                        id: requestId,
                        userId: userId,
                        status: .completed,
                        downloadUrl: result.downloadUrl,
                        expiresAt: result.expiresAt != nil ? ISO8601DateFormatter().date(from: result.expiresAt!) : nil,
                        fileSizeBytes: result.fileSizeBytes
                    )
                }

                return DataExportResult(
                    success: true,
                    requestId: result.requestId,
                    downloadUrl: result.downloadUrl,
                    expiresAt: result.expiresAt != nil ? ISO8601DateFormatter().date(from: result.expiresAt!) : nil,
                    fileSizeBytes: result.fileSizeBytes,
                    message: deliveryMethod == .email
                        ? "Export link sent to your email"
                        : "Your data export is ready"
                )
            } else {
                throw DataExportError.exportFailed(result.error ?? "Unknown error")
            }

        } catch let exportError as DataExportError {
            self.error = exportError
            throw exportError
        } catch {
            let exportError = DataExportError.networkError(error.localizedDescription)
            self.error = exportError
            throw exportError
        }
    }

    /// Get the status of an existing export request
    /// - Parameter requestId: The export request UUID
    /// - Parameter userId: The user's UUID (for validation)
    /// - Returns: The export request details
    func getExportStatus(requestId: UUID, userId: UUID) async throws -> DataExportRequest {
        do {
            // Call database function to get download info
            let params: [String: String] = [
                "p_request_id": requestId.uuidString,
                "p_user_id": userId.uuidString
            ]

            let data: [String: AnyJSON] = try await database
                .rpc("get_export_download_info", params: params)
                .single()
                .execute()
                .value

            // Check for error in response
            if case let .string(errorMessage) = data["error"] {
                if errorMessage == "Export request not found" {
                    throw DataExportError.requestNotFound
                } else if errorMessage == "Export has expired" {
                    throw DataExportError.exportExpired
                } else {
                    throw DataExportError.exportFailed(errorMessage)
                }
            }

            // Parse file path to get signed URL
            var downloadUrl: String? = nil
            if case let .string(filePath) = data["file_path"] {
                // Generate signed URL
                let signedUrlResult = try await storage
                    .from("data-exports")
                    .createSignedURL(path: filePath, expiresIn: 60 * 60) // 1 hour

                downloadUrl = signedUrlResult.absoluteString
            }

            var expiresAt: Date? = nil
            if case let .string(expiresStr) = data["expires_at"] {
                expiresAt = ISO8601DateFormatter().date(from: expiresStr)
            }

            var fileSizeBytes: Int? = nil
            if case let .double(size) = data["file_size_bytes"] {
                fileSizeBytes = Int(size)
            } else if case let .integer(size) = data["file_size_bytes"] {
                fileSizeBytes = size
            }

            return DataExportRequest(
                id: requestId,
                userId: userId,
                status: .completed,
                downloadUrl: downloadUrl,
                expiresAt: expiresAt,
                fileSizeBytes: fileSizeBytes
            )

        } catch let exportError as DataExportError {
            throw exportError
        } catch {
            throw DataExportError.networkError(error.localizedDescription)
        }
    }

    /// Check for existing pending or completed export request
    /// - Parameter userId: The user's UUID
    /// - Returns: Existing request if found
    private func getExistingPendingRequest(userId: UUID) async throws -> DataExportRequest? {
        do {
            struct ExportRequestRow: Decodable {
                let id: UUID
                let user_id: UUID
                let status: String
                let file_path: String?
                let file_size_bytes: Int?
                let expires_at: String?
                let requested_at: String
            }

            let response: [ExportRequestRow] = try await database
                .from("data_export_requests")
                .select("id, user_id, status, file_path, file_size_bytes, expires_at, requested_at")
                .eq("user_id", value: userId.uuidString)
                .in("status", values: ["pending", "processing", "completed"])
                .order("requested_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let row = response.first else {
                return nil
            }

            // For completed exports, check if not expired
            if row.status == "completed" {
                if let expiresStr = row.expires_at,
                   let expiresAt = ISO8601DateFormatter().date(from: expiresStr),
                   expiresAt < Date() {
                    return nil // Expired
                }
            }

            // Generate download URL if completed and has file path
            var downloadUrl: String? = nil
            if row.status == "completed", let filePath = row.file_path {
                let signedUrlResult = try await storage
                    .from("data-exports")
                    .createSignedURL(path: filePath, expiresIn: 60 * 60)

                downloadUrl = signedUrlResult.absoluteString
            }

            return DataExportRequest(
                id: row.id,
                userId: row.user_id,
                status: DataExportStatus(rawValue: row.status) ?? .pending,
                downloadUrl: downloadUrl,
                expiresAt: row.expires_at != nil ? ISO8601DateFormatter().date(from: row.expires_at!) : nil,
                fileSizeBytes: row.file_size_bytes
            )

        } catch {
            // Log but don't throw - this is a convenience check
            print("[DataExportService] Error checking existing request: \(error)")
            return nil
        }
    }
}

// MARK: - Models

/// Data export request status
enum DataExportStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case expired = "expired"
}

/// Delivery method for export
enum DeliveryMethod: String, Codable {
    case download = "download"
    case email = "email"
}

/// Data export request model
struct DataExportRequest: Identifiable {
    let id: UUID
    let userId: UUID
    let status: DataExportStatus
    let downloadUrl: String?
    let expiresAt: Date?
    let fileSizeBytes: Int?

    var formattedFileSize: String {
        guard let bytes = fileSizeBytes else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    var expiresInDays: Int? {
        guard let expiresAt = expiresAt else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiresAt)
        return max(0, components.day ?? 0)
    }
}

/// Result from export request
struct DataExportResult {
    let success: Bool
    let requestId: UUID?
    let downloadUrl: String?
    let expiresAt: Date?
    var fileSizeBytes: Int?
    let message: String?
}

/// Error types for data export
enum DataExportError: LocalizedError {
    case exportFailed(String)
    case requestNotFound
    case exportExpired
    case networkError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .requestNotFound:
            return "Export request not found"
        case .exportExpired:
            return "Export has expired. Please request a new export."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Private Models for API

/// Request body for Edge Function
private struct ExportRequestBody: Encodable {
    let userId: String
    let requestId: String?
    let deliveryMethod: String
    let email: String?
}

/// Response from Edge Function
private struct EdgeFunctionResponse: Decodable {
    let success: Bool
    let requestId: UUID?
    let downloadUrl: String?
    let fileSizeBytes: Int?
    let expiresAt: String?
    let deliveryMethod: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case requestId = "request_id"
        case downloadUrl = "download_url"
        case fileSizeBytes = "file_size_bytes"
        case expiresAt = "expires_at"
        case deliveryMethod = "delivery_method"
        case error
    }
}
