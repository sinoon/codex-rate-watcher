import Foundation

/// Lightweight profile loader for CLI tools.
/// Reads the profile index and snapshot files managed by the GUI app.
public enum ProfileLoader {

  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()

  /// Load all registered profiles, sorted by availability (best first).
  public static func loadProfiles() -> [AuthProfileRecord] {
    guard let data = try? Data(contentsOf: AppPaths.profileIndexFile),
          let profiles = try? decoder.decode([AuthProfileRecord].self, from: data) else {
      return []
    }
    return profiles.sorted {
      ($0.latestUsage?.effectiveAvailablePercent ?? 0) > ($1.latestUsage?.effectiveAvailablePercent ?? 0)
    }
  }

  /// Load the auth snapshot for a specific profile from its snapshot file.
  public static func loadAuth(for profile: AuthProfileRecord) -> AuthSnapshot? {
    let url = AppPaths.profilesDirectory.appending(path: profile.snapshotFileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? AuthStore().envelope(from: data).snapshot
  }

  /// Get the currently active auth and its matching profile record (if any).
  public static func activeAuth() -> (AuthSnapshot, AuthProfileRecord?)? {
    let store = AuthStore()
    guard let auth = try? store.load() else { return nil }
    let envelope = try? store.loadEnvelope()
    let profiles = loadProfiles()
    let match = envelope.flatMap { env in
      profiles.first { $0.fingerprint == env.fingerprint }
    } ?? profiles.first { $0.accountID == auth.accountID }
    return (auth, match)
  }

  /// Find the best usable profile, optionally excluding one by ID.
  public static func bestProfile(excluding: UUID? = nil) -> (AuthSnapshot, AuthProfileRecord)? {
    let profiles = loadProfiles()
    for profile in profiles {
      if profile.id == excluding { continue }
      if profile.validationError != nil { continue }
      if profile.latestUsage?.isBlocked == true { continue }
      if let auth = loadAuth(for: profile) {
        return (auth, profile)
      }
    }
    return nil
  }
}
