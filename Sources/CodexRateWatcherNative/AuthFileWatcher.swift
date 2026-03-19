import Darwin
import Foundation

final class AuthFileWatcher {
  var onChange: (() -> Void)?

  private let directoryURL: URL
  private let queue = DispatchQueue(label: "CodexRateWatcherNative.AuthFileWatcher")
  private var fileDescriptor: CInt = -1
  private var source: DispatchSourceFileSystemObject?

  init(directoryURL: URL) {
    self.directoryURL = directoryURL
  }

  deinit {
    stop()
  }

  func start() {
    stop()

    let path = directoryURL.path
    fileDescriptor = open(path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .rename, .delete, .attrib, .extend, .link],
      queue: queue
    )

    source.setEventHandler { [weak self] in
      self?.onChange?()
    }

    source.setCancelHandler { [weak self] in
      guard let self else { return }
      if self.fileDescriptor >= 0 {
        close(self.fileDescriptor)
        self.fileDescriptor = -1
      }
    }

    self.source = source
    source.resume()
  }

  func stop() {
    source?.cancel()
    source = nil
    if fileDescriptor >= 0 {
      close(fileDescriptor)
      fileDescriptor = -1
    }
  }
}
