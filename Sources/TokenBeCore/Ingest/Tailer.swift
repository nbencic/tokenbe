import Foundation

/// 06 § Tailing step 3: a file's bytes from its stored offset, split on `\n` into complete lines. The final fragment
/// without a trailing `\n` is not a line: the offset stops before it (a write still in progress). A line longer than
/// `LineParser.maxLineBytes` is reported as too long without being kept in memory.
public struct Tailer: Sendable {
  public enum Item: Sendable, Equatable {
    case line(Data)
    case tooLong(bytes: Int)
  }

  /// A complete line and the offset just after its `\n`.
  public struct Piece: Sendable, Equatable {
    public var item: Item
    public var endOffset: Int64
  }

  /// 06: 64 KiB chunks.
  public static let chunkBytes = 64 * 1024

  private var buffer = Data()
  private var skipping = 0
  private var position: Int64

  /// Starts at `offset`, the first byte not yet processed.
  public init(offset: Int64) {
    position = offset
  }

  /// Feeds the next chunk; returns the complete lines it finished, empty lines left out.
  public mutating func feed(_ chunk: Data) -> [Piece] {
    var pieces: [Piece] = []
    var start = chunk.startIndex
    while let newline = chunk[start...].firstIndex(of: 0x0A) {
      let part = chunk[start..<newline]
      position += Int64(buffer.count + skipping + part.count + 1)
      if skipping > 0 {
        pieces.append(Piece(item: .tooLong(bytes: skipping + part.count), endOffset: position))
        skipping = 0
      } else if buffer.count + part.count > LineParser.maxLineBytes {
        pieces.append(Piece(item: .tooLong(bytes: buffer.count + part.count), endOffset: position))
      } else {
        let line = buffer + part
        if !line.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) {
          pieces.append(Piece(item: .line(Data(line)), endOffset: position))
        }
      }
      buffer.removeAll(keepingCapacity: true)
      start = chunk.index(after: newline)
    }
    let rest = chunk[start...]
    if skipping > 0 || buffer.count + rest.count > LineParser.maxLineBytes {
      // Too long already: count it, keep nothing (the line is rejected when its `\n` arrives).
      skipping += buffer.count + rest.count
      buffer.removeAll()
    } else {
      buffer.append(contentsOf: rest)
    }
    return pieces
  }
}

/// What `stat` says about a file the tailer reads (06 § Tailing step 1).
public struct FileStat: Sendable, Equatable {
  public var inode: Int64
  public var size: Int64
  public var mtime: Date

  public init(inode: Int64, size: Int64, mtime: Date) {
    self.inode = inode
    self.size = size
    self.mtime = mtime
  }

  /// Nil when the path cannot be read (gone, or no permission).
  public static func of(_ url: URL) throws -> FileStat {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return FileStat(
      inode: (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? 0,
      size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
      mtime: attributes[.modificationDate] as? Date ?? .distantPast
    )
  }
}
