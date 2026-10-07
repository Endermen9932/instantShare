import 'dart:math' as math;
import 'dart:typed_data';

/// Every transfer is cut into symbols of this size. It is independent of the
/// QR density: a frame carries as many whole symbols as its level allows, so
/// the sender can switch levels mid-transfer without the receiver losing
/// anything it already has.
const int kSymbolSize = 64;

/// Source symbols per block. Each block is decoded on its own, which keeps
/// the elimination cost per received symbol bounded for large files.
const int kMaxBlockSymbols = 1024;

const int _symbolWords = kSymbolSize ~/ 4;
const int _mask32 = 0xFFFFFFFF;

/// 32-bit multiply that stays exact on the web, where ints are doubles and a
/// full 32×32 bit product would lose its low bits.
int _imul(int a, int b) {
  final al = a & 0xFFFF;
  final ah = (a >> 16) & 0xFFFF;
  final bl = b & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF;
  return (al * bl + ((((ah * bl) + (al * bh)) & 0xFFFF) << 16)) & _mask32;
}

/// lowbias32 integer hash.
int _mix32(int x) {
  x &= _mask32;
  x ^= x >> 16;
  x = _imul(x, 0x7FEB352D);
  x ^= x >> 15;
  x = _imul(x, 0x846CA68B);
  x ^= x >> 16;
  return x;
}

/// mulberry32. Integer-only on purpose: sender and receiver must derive the
/// exact same coefficients on every CPU and OS.
class Mulberry32 {
  Mulberry32(int seed) : _state = seed & _mask32;

  int _state;

  int next() {
    _state = (_state + 0x6D2B79F5) & _mask32;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & _mask32;
    return (t ^ (t >> 14)) & _mask32;
  }
}

int symbolCountFor(int totalLength) =>
    math.max(1, (totalLength + kSymbolSize - 1) ~/ kSymbolSize);

int _lowestBit(int word) => (word & -word).bitLength - 1;

/// How the source symbols are split into blocks and how sequence numbers map
/// onto them. Sequence numbers are interleaved across blocks, so one lost
/// frame costs every block a little instead of one block a lot.
class BlockLayout {
  BlockLayout(this.totalLength)
    : symbolCount = symbolCountFor(totalLength),
      blockCount =
          (symbolCountFor(totalLength) + kMaxBlockSymbols - 1) ~/
          kMaxBlockSymbols;

  final int totalLength;
  final int symbolCount;
  final int blockCount;

  int get _base => symbolCount ~/ blockCount;
  int get _larger => symbolCount % blockCount;

  /// Number of source symbols in block [b]; sizes differ by at most one.
  int blockSize(int b) => _base + (b < _larger ? 1 : 0);

  /// Index of the first source symbol of block [b].
  int blockStart(int b) => b * _base + math.min(b, _larger);

  int blockOf(int seq) => seq % blockCount;

  int localOf(int seq) => seq ~/ blockCount;

  /// (block, column) of global source symbol [index].
  (int, int) locateSymbol(int index) {
    final bigSpan = _larger * (_base + 1);
    if (index < bigSpan) return (index ~/ (_base + 1), index % (_base + 1));
    final rest = index - bigSpan;
    return (_larger + rest ~/ _base, rest % _base);
  }
}

/// Fills [out] with the GF(2) coefficients of encoded symbol [local] of a
/// block with [size] source symbols.
///
/// The first [size] symbols of each block are the source symbols themselves
/// (systematic pass), so a receiver that sees everything needs no decoding at
/// all. Every later symbol XORs a random half of the block, which makes any
/// set of slightly more than [size] received symbols almost surely solvable.
void coefficientsFor(
  int transferId,
  int block,
  int local,
  int size,
  Uint32List out,
) {
  final words = (size + 31) >> 5;
  out.fillRange(0, words, 0);
  if (local < size) {
    out[local >> 5] = 1 << (local & 31);
    return;
  }
  final rng = Mulberry32(
    _mix32(transferId ^ _mix32(block * 0x9E3779B1 + _mix32(local))),
  );
  for (var w = 0; w < words; w++) {
    out[w] = rng.next();
  }
  final tail = size & 31;
  if (tail != 0) out[words - 1] &= (1 << tail) - 1;
  var any = 0;
  for (var w = 0; w < words; w++) {
    any |= out[w];
  }
  if (any == 0) {
    final c = local % size;
    out[c >> 5] = 1 << (c & 31);
  }
}

class FountainEncoder {
  FountainEncoder(this.transferId, Uint8List data)
    : layout = BlockLayout(data.length),
      _source = Uint32List(symbolCountFor(data.length) * _symbolWords) {
    _source.buffer.asUint8List().setRange(0, data.length, data);
  }

  final int transferId;
  final BlockLayout layout;
  final Uint32List _source;
  final Uint32List _coeffs = Uint32List((kMaxBlockSymbols + 31) >> 5);
  final Uint32List _acc = Uint32List(_symbolWords);

  int get totalLength => layout.totalLength;
  int get k => layout.symbolCount;

  /// Writes encoded symbol [seq] into [out] starting at byte [offset].
  void writeSymbol(int seq, Uint8List out, int offset) {
    final block = layout.blockOf(seq);
    final size = layout.blockSize(block);
    final start = layout.blockStart(block);
    coefficientsFor(transferId, block, layout.localOf(seq), size, _coeffs);
    _acc.fillRange(0, _symbolWords, 0);
    final words = (size + 31) >> 5;
    for (var w = 0; w < words; w++) {
      var bits = _coeffs[w];
      while (bits != 0) {
        final b = _lowestBit(bits);
        bits &= bits - 1;
        final s = (start + (w << 5) + b) * _symbolWords;
        for (var i = 0; i < _symbolWords; i++) {
          _acc[i] ^= _source[s + i];
        }
      }
    }
    out.setRange(offset, offset + kSymbolSize, _acc.buffer.asUint8List());
  }
}

/// Incremental Gaussian elimination over GF(2), kept in reduced row echelon
/// form so solved symbols are visible as soon as they are determined.
class _BlockDecoder {
  _BlockDecoder(this.size)
    : words = (size + 31) >> 5,
      stride = ((size + 31) >> 5) + _symbolWords;

  final int size;
  final int words;
  final int stride;

  Uint32List? _rows;
  Int32List? _pivotRow;
  Uint32List? _pivotMask;
  int rank = 0;

  /// Compact solution once the block is complete; the matrix is dropped then.
  Uint32List? solution;

  bool get isComplete => solution != null;

  /// Adds one equation. [row] holds coefficients then data, length [stride];
  /// it is consumed. Returns true if it increased the rank.
  bool insert(Uint32List row) {
    if (isComplete) return false;
    final rows = _rows ??= Uint32List(size * stride);
    final pivotRow = _pivotRow ??= Int32List(size)..fillRange(0, size, -1);
    final pivotMask = _pivotMask ??= Uint32List(words);

    // Clear every pivot column from the new row. Pivot rows have no other
    // pivot columns set, so one pass in any order suffices.
    for (var w = 0; w < words; w++) {
      var bits = row[w] & pivotMask[w];
      while (bits != 0) {
        final b = _lowestBit(bits);
        bits &= bits - 1;
        final p = pivotRow[(w << 5) + b] * stride;
        for (var i = 0; i < stride; i++) {
          row[i] ^= rows[p + i];
        }
      }
    }

    var pivot = -1;
    for (var w = 0; w < words; w++) {
      if (row[w] != 0) {
        pivot = (w << 5) + _lowestBit(row[w]);
        break;
      }
    }
    if (pivot < 0) return false;

    final pw = pivot >> 5;
    final pb = 1 << (pivot & 31);
    for (var r = 0; r < rank; r++) {
      final base = r * stride;
      if (rows[base + pw] & pb == 0) continue;
      for (var i = 0; i < stride; i++) {
        rows[base + i] ^= row[i];
      }
    }
    rows.setRange(rank * stride, (rank + 1) * stride, row);
    pivotRow[pivot] = rank;
    pivotMask[pw] |= pb;
    rank++;

    if (rank == size) {
      final out = Uint32List(size * _symbolWords);
      for (var c = 0; c < size; c++) {
        final base = pivotRow[c] * stride + words;
        out.setRange(c * _symbolWords, (c + 1) * _symbolWords, rows, base);
      }
      solution = out;
      _rows = null;
      _pivotRow = null;
      _pivotMask = null;
    }
    return true;
  }

  /// Data of column [c] if it is already determined, else null.
  Uint32List? solved(int c) {
    final s = solution;
    if (s != null) {
      return Uint32List.sublistView(
        s,
        c * _symbolWords,
        (c + 1) * _symbolWords,
      );
    }
    final pivotRow = _pivotRow;
    if (pivotRow == null || pivotRow[c] < 0) return null;
    final base = pivotRow[c] * stride;
    final rows = _rows!;
    for (var w = 0; w < words; w++) {
      final expected = w == (c >> 5) ? 1 << (c & 31) : 0;
      if (rows[base + w] != expected) return null;
    }
    return Uint32List.sublistView(rows, base + words, base + stride);
  }
}

class FountainDecoder {
  FountainDecoder({required this.transferId, required this.totalLength})
    : layout = BlockLayout(totalLength) {
    _blocks = List.generate(
      layout.blockCount,
      (b) => _BlockDecoder(layout.blockSize(b)),
    );
  }

  final int transferId;
  final int totalLength;
  final BlockLayout layout;
  late final List<_BlockDecoder> _blocks;
  final Set<int> _seen = <int>{};

  int _rank = 0;
  int _receivedCount = 0;
  int _completeBlocks = 0;

  int get k => layout.symbolCount;

  /// Independent equations collected so far; the transfer is done at [k].
  int get rank => _rank;

  /// Distinct symbols received, useful or not.
  int get receivedCount => _receivedCount;

  bool get isComplete => _completeBlocks == _blocks.length;

  double get progress => _rank / k;

  /// Feeds encoded symbol [seq] taken from [bytes] at [offset].
  /// Returns true if it carried new information.
  bool addSymbol(int seq, Uint8List bytes, int offset) {
    if (isComplete || !_seen.add(seq)) return false;
    _receivedCount++;
    final b = layout.blockOf(seq);
    final block = _blocks[b];
    if (block.isComplete) return false;
    final row = Uint32List(block.stride);
    coefficientsFor(transferId, b, layout.localOf(seq), block.size, row);
    // sublistView offsets count elements of the viewed list (32-bit words).
    Uint8List.sublistView(
      row,
      block.words,
    ).setRange(0, kSymbolSize, bytes, offset);
    if (!block.insert(row)) return false;
    _rank++;
    if (block.isComplete) _completeBlocks++;
    return true;
  }

  /// The first [length] bytes if they are all recovered already, else null.
  Uint8List? prefix(int length) {
    length = math.min(length, totalLength);
    final out = Uint8List(length);
    final symbols = (length + kSymbolSize - 1) ~/ kSymbolSize;
    for (var i = 0; i < symbols; i++) {
      final (b, c) = layout.locateSymbol(i);
      final words = _blocks[b].solved(c);
      if (words == null) return null;
      final start = i * kSymbolSize;
      final end = math.min(length, start + kSymbolSize);
      out.setRange(start, end, Uint8List.sublistView(words));
    }
    return out;
  }

  /// The recovered data. Only valid once [isComplete].
  Uint8List get result {
    final out = Uint8List(k * kSymbolSize);
    var offset = 0;
    for (final block in _blocks) {
      final bytes = Uint8List.sublistView(block.solution!);
      out.setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
    }
    return Uint8List.sublistView(out, 0, totalLength);
  }
}
