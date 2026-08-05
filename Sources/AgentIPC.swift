import Darwin
import Foundation

enum AgentIPC {
  static let maximumEventBytes = 64 * 1024

  static var supportDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/TmuxVTab", isDirectory: true)
  }

  static var defaultSocketPath: String {
    if let override = ProcessInfo.processInfo.environment["TMUXVTAB_SOCKET_PATH"],
       !override.isEmpty {
      return override
    }
    return supportDirectory.appendingPathComponent("agent-events.sock").path
  }

  static var defaultStateURL: URL {
    supportDirectory.appendingPathComponent("agent-state.json")
  }

  static var hookExecutableURL: URL {
    supportDirectory.appendingPathComponent("TmuxVTab-hook")
  }

  static func ensurePrivateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: url.path
    )
  }

  /// Publishes the exact GUI executable as the stable hook client. Plugin
  /// caches therefore never need to bundle or independently update a binary.
  static func publishCurrentExecutable() throws {
    guard let executableURL = Bundle.main.executableURL else { return }
    try ensurePrivateDirectory(supportDirectory)

    var existing = stat()
    if lstat(hookExecutableURL.path, &existing) == 0 {
      guard (existing.st_mode & S_IFMT) == S_IFLNK else {
        throw AgentIPCError.pathOccupied(hookExecutableURL.path)
      }
      try FileManager.default.removeItem(at: hookExecutableURL)
    }
    try FileManager.default.createSymbolicLink(
      at: hookExecutableURL,
      withDestinationURL: executableURL.resolvingSymlinksInPath()
    )
  }

  static func send(_ event: AgentEvent, socketPath: String = defaultSocketPath) -> Bool {
    guard let data = try? JSONEncoder().encode(event), data.count <= maximumEventBytes else {
      return false
    }

    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { Darwin.close(descriptor) }

    var noSignal: Int32 = 1
    _ = withUnsafePointer(to: &noSignal) { pointer in
      Darwin.setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        pointer,
        socklen_t(MemoryLayout<Int32>.size)
      )
    }

    guard var address = unixAddress(path: socketPath),
          connect(descriptor, to: &address)
    else { return false }

    let sentAll = data.withUnsafeBytes { buffer -> Bool in
      guard let base = buffer.baseAddress else { return false }
      var offset = 0
      while offset < buffer.count {
        let sent = Darwin.send(descriptor, base.advanced(by: offset), buffer.count - offset, 0)
        guard sent > 0 else { return false }
        offset += sent
      }
      return true
    }
    _ = Darwin.shutdown(descriptor, SHUT_WR)
    return sentAll
  }

  fileprivate static func isAcceptingConnections(at socketPath: String) -> Bool {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { Darwin.close(descriptor) }
    guard var address = unixAddress(path: socketPath) else { return false }
    return connect(descriptor, to: &address)
  }

  private static func connect(
    _ descriptor: Int32,
    to address: inout sockaddr_un,
    timeoutMilliseconds: Int32 = 100
  ) -> Bool {
    let originalFlags = Darwin.fcntl(descriptor, F_GETFL, 0)
    guard originalFlags >= 0,
          Darwin.fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
    else { return false }

    let result = withSocketAddress(&address) { pointer, length in
      Darwin.connect(descriptor, pointer, length)
    }
    if result == 0 {
      _ = Darwin.fcntl(descriptor, F_SETFL, originalFlags)
      return true
    }
    guard errno == EINPROGRESS else { return false }

    var descriptorState = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
    guard Darwin.poll(&descriptorState, 1, timeoutMilliseconds) > 0 else { return false }

    var socketError: Int32 = 0
    var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
    let optionResult = withUnsafeMutablePointer(to: &socketError) { pointer in
      Darwin.getsockopt(descriptor, SOL_SOCKET, SO_ERROR, pointer, &socketErrorLength)
    }
    guard optionResult == 0, socketError == 0 else { return false }
    _ = Darwin.fcntl(descriptor, F_SETFL, originalFlags)
    return true
  }

  fileprivate static func unixAddress(path: String) -> sockaddr_un? {
    let bytes = Array(path.utf8CString)
    var address = sockaddr_un()
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count <= capacity else { return nil }

    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
      for (index, byte) in bytes.enumerated() {
        destination[index] = UInt8(bitPattern: byte)
      }
    }
    return address
  }

  fileprivate static func withSocketAddress<T>(
    _ address: inout sockaddr_un,
    _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
  ) -> T {
    withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
        body(socketPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
  }
}

final class AgentEventServer: @unchecked Sendable {
  typealias EventHandler = @Sendable (AgentEvent) -> Void

  private let socketPath: String
  private let eventHandler: EventHandler
  private let acceptQueue = DispatchQueue(label: "app.tru2dagame.tmuxvtab.agent-events.accept")
  private let clientQueue = DispatchQueue(
    label: "app.tru2dagame.tmuxvtab.agent-events.client",
    attributes: .concurrent
  )
  private var source: DispatchSourceRead?

  init(socketPath: String = AgentIPC.defaultSocketPath, eventHandler: @escaping EventHandler) {
    self.socketPath = socketPath
    self.eventHandler = eventHandler
  }

  func start() throws {
    guard source == nil else { return }
    let socketURL = URL(fileURLWithPath: socketPath)
    try AgentIPC.ensurePrivateDirectory(socketURL.deletingLastPathComponent())

    var existing = stat()
    if lstat(socketPath, &existing) == 0 {
      guard (existing.st_mode & S_IFMT) == S_IFSOCK else {
        throw AgentIPCError.pathOccupied(socketPath)
      }
      guard !AgentIPC.isAcceptingConnections(at: socketPath) else {
        throw AgentIPCError.socketAlreadyActive
      }
      guard Darwin.unlink(socketPath) == 0 else {
        throw AgentIPCError.posix("unlink", errno)
      }
    }

    let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else { throw AgentIPCError.posix("socket", errno) }

    var address = AgentIPC.unixAddress(path: socketPath)
    guard address != nil else {
      Darwin.close(listener)
      throw AgentIPCError.socketPathTooLong
    }

    let bindResult = AgentIPC.withSocketAddress(&address!) { pointer, length in
      Darwin.bind(listener, pointer, length)
    }
    guard bindResult == 0 else {
      let code = errno
      Darwin.close(listener)
      throw AgentIPCError.posix("bind", code)
    }
    guard Darwin.chmod(socketPath, 0o600) == 0 else {
      let code = errno
      Darwin.close(listener)
      Darwin.unlink(socketPath)
      throw AgentIPCError.posix("chmod", code)
    }
    guard Darwin.listen(listener, 16) == 0 else {
      let code = errno
      Darwin.close(listener)
      Darwin.unlink(socketPath)
      throw AgentIPCError.posix("listen", code)
    }

    _ = Darwin.fcntl(listener, F_SETFL, O_NONBLOCK)
    let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: acceptQueue)
    source.setEventHandler { [weak self] in self?.acceptPendingClients(listener: listener) }
    source.setCancelHandler { [socketPath] in
      Darwin.close(listener)
      Darwin.unlink(socketPath)
    }
    self.source = source
    source.resume()
  }

  func stop() {
    source?.cancel()
    source = nil
  }

  deinit { stop() }

  private func acceptPendingClients(listener: Int32) {
    while true {
      let client = Darwin.accept(listener, nil, nil)
      if client < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK { return }
        return
      }
      clientQueue.async { [weak self] in self?.readClient(client) }
    }
  }

  private func readClient(_ client: Int32) {
    defer { Darwin.close(client) }

    var peerUID: uid_t = 0
    var peerGID: gid_t = 0
    guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == geteuid() else {
      return
    }

    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    _ = withUnsafePointer(to: &timeout) { pointer in
      Darwin.setsockopt(
        client,
        SOL_SOCKET,
        SO_RCVTIMEO,
        pointer,
        socklen_t(MemoryLayout<timeval>.size)
      )
    }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count <= AgentIPC.maximumEventBytes {
      let count = Darwin.recv(client, &buffer, buffer.count, 0)
      if count == 0 { break }
      guard count > 0 else { return }
      data.append(buffer, count: count)
    }
    guard !data.isEmpty, data.count <= AgentIPC.maximumEventBytes,
          let event = try? JSONDecoder().decode(AgentEvent.self, from: data),
          event.version == AgentEvent.protocolVersion
    else { return }
    eventHandler(event)
  }
}

enum AgentIPCError: LocalizedError {
  case socketPathTooLong
  case socketAlreadyActive
  case pathOccupied(String)
  case posix(String, Int32)

  var errorDescription: String? {
    switch self {
    case .socketPathTooLong:
      "Agent socket path is too long"
    case .socketAlreadyActive:
      "Another TmuxVTab agent socket is already active"
    case .pathOccupied(let path):
      "Refusing to replace non-socket path at \(path)"
    case .posix(let operation, let code):
      "\(operation) failed: \(String(cString: strerror(code)))"
    }
  }
}
