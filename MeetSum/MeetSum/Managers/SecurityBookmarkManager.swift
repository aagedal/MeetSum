//
//  SecurityBookmarkManager.swift
//  MeetSum
//
//  Manages security-scoped bookmark access for sandboxed apps
//

import Foundation

/// Errors related to security-scoped bookmarks
enum SecurityBookmarkError: LocalizedError {
    case bookmarkCreationFailed
    case bookmarkResolutionFailed
    case staleBookmark
    case accessDenied
    
    var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed:
            return "Failed to create security-scoped bookmark"
        case .bookmarkResolutionFailed:
            return "Failed to resolve security-scoped bookmark"
        case .staleBookmark:
            return "Security-scoped bookmark is stale"
        case .accessDenied:
            return "Access to security-scoped resource denied"
        }
    }
}

/// Manages security-scoped bookmark storage and access
class SecurityBookmarkManager {
    
    private var currentAccessedURL: URL?
    
    // MARK: - Save Bookmark
    
    /// Save a security-scoped bookmark for the given URL
    /// - Parameter url: URL to save bookmark for
    /// - Returns: true if successful
    func saveBookmark(for url: URL) -> Bool {
        Logger.info("Saving security-scoped bookmark for: \(url.path)", category: Logger.general)
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            ModelSettings.modelDirectoryBookmark = bookmarkData
            Logger.info("Security-scoped bookmark saved successfully", category: Logger.general)
            return true
            
        } catch {
            Logger.error("Failed to create security-scoped bookmark", error: error, category: Logger.general)
            return false
        }
    }
    
    // MARK: - Restore Bookmark
    
    /// Restore a security-scoped bookmark from storage
    /// - Returns: URL if bookmark was restored successfully, nil otherwise
    func restoreBookmark() -> URL? {
        Logger.debug("Attempting to restore security-scoped bookmark", category: Logger.general)
        
        guard let bookmarkData = ModelSettings.modelDirectoryBookmark else {
            Logger.debug("No bookmark data found", category: Logger.general)
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                Logger.warning("Security-scoped bookmark is stale", category: Logger.general)
                // Could try to recreate the bookmark here if needed
                return nil
            }
            
            Logger.info("Security-scoped bookmark restored: \(url.path)", category: Logger.general)
            return url
            
        } catch {
            Logger.error("Failed to resolve security-scoped bookmark", error: error, category: Logger.general)
            return nil
        }
    }
    
    // MARK: - Access Management
    
    /// Start accessing a security-scoped resource
    /// - Parameter url: URL to access
    /// - Returns: true if access was granted
    func startAccessingSecurityScopedResource(url: URL) -> Bool {
        Logger.debug("Starting access to security-scoped resource: \(url.path)", category: Logger.general)
        
        let granted = url.startAccessingSecurityScopedResource()
        
        if granted {
            currentAccessedURL = url
            Logger.info("Access granted to security-scoped resource", category: Logger.general)
        } else {
            Logger.error("Access denied to security-scoped resource", category: Logger.general)
        }
        
        return granted
    }
    
    /// Stop accessing the current security-scoped resource
    func stopAccessingSecurityScopedResource() {
        if let url = currentAccessedURL {
            Logger.debug("Stopping access to security-scoped resource: \(url.path)", category: Logger.general)
            url.stopAccessingSecurityScopedResource()
            currentAccessedURL = nil
        }
    }
    
    deinit {
        stopAccessingSecurityScopedResource()
    }
}
