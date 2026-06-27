import 'dart:convert';

/// 计算字符串的 SHA-256 哈希，取前 16 位十六进制字符作为缓存 key。
///
/// 输出空间为 16^16 ≈ 1.8×10^19，碰撞概率极低。
String hashKey(String input) {
  final bytes = utf8.encode(input);
  final digest = _sha256(bytes);
  // 取前 8 字节（16 位十六进制）
  return digest.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 简化的 SHA-256 实现（纯 Dart，无外部依赖）
List<int> _sha256(List<int> input) {
  // 初始哈希值（前 8 个质数的平方根的小数部分的前 32 位）
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  // 64 个常量（前 64 个质数的立方根的小数部分的前 32 位）
  const k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  // 预处理：填充消息
  final bitLength = input.length * 8;
  final paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
  final padded = List<int>.filled(paddedLength, 0);
  padded.setAll(0, input);
  padded[input.length] = 0x80;
  // 追加原始消息长度（64 位大端）
  for (var i = 0; i < 8; i++) {
    padded[paddedLength - 1 - i] = (bitLength >> (i * 8)) & 0xff;
  }

  // 处理每个 512 位块
  for (var offset = 0; offset < paddedLength; offset += 64) {
    // 准备消息调度表
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      w[i] = (padded[offset + i * 4] << 24) |
          (padded[offset + i * 4 + 1] << 16) |
          (padded[offset + i * 4 + 2] << 8) |
          padded[offset + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    // 初始化工作变量
    var a = h0, b = h1, c = h2, d = h3;
    var e = h4, f = h5, g = h6, h = h7;

    // 压缩函数
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e) & g);
      final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    // 更新哈希值
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  // 生成最终哈希值
  return [
    (h0 >> 24) & 0xff, (h0 >> 16) & 0xff, (h0 >> 8) & 0xff, h0 & 0xff,
    (h1 >> 24) & 0xff, (h1 >> 16) & 0xff, (h1 >> 8) & 0xff, h1 & 0xff,
    (h2 >> 24) & 0xff, (h2 >> 16) & 0xff, (h2 >> 8) & 0xff, h2 & 0xff,
    (h3 >> 24) & 0xff, (h3 >> 16) & 0xff, (h3 >> 8) & 0xff, h3 & 0xff,
    (h4 >> 24) & 0xff, (h4 >> 16) & 0xff, (h4 >> 8) & 0xff, h4 & 0xff,
    (h5 >> 24) & 0xff, (h5 >> 16) & 0xff, (h5 >> 8) & 0xff, h5 & 0xff,
    (h6 >> 24) & 0xff, (h6 >> 16) & 0xff, (h6 >> 8) & 0xff, h6 & 0xff,
    (h7 >> 24) & 0xff, (h7 >> 16) & 0xff, (h7 >> 8) & 0xff, h7 & 0xff,
  ];
}

/// 右旋转
int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
