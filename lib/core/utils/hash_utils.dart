/// 计算字符串的整数 hashCode（与 Java String.hashCode 一致），
/// 再转换为 36 进制字符串，用作缓存 key。
String hashKey(String input) {
  var hash = 0;
  for (int i = 0; i < input.length; i++) {
    hash = ((hash << 5) - hash) + input.codeUnitAt(i);
    hash = hash & 0x7FFFFFFF;
  }
  return hash.toRadixString(36);
}
