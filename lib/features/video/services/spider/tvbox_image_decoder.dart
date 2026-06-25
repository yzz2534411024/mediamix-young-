// TVBox 图片伪装配置解码器
// 饭太硬等 TVBox 接口使用图片伪装技术隐藏 JSON 配置：
// [图片数据] [8字符标识] ** [Base64编码的JSON]
// 支持 JPEG (FF D8...FF D9) 和 BMP (BM...) 两种伪装格式
import 'dart:convert';
import 'dart:typed_data';

class TvBoxImageDecoder {
  TvBoxImageDecoder._();

  /// 从二进制数据中提取 TVBox JSON 配置
  /// 支持以下格式：
  /// 1. JPEG 伪装：FF D8 ... FF D9 [标识]**[Base64 JSON]
  /// 2. BMP 伪装：BM ... [标识]**[Base64 JSON]
  /// 3. 纯 Base64 文本
  /// 4. 纯 JSON 文本
  static Map<String, dynamic>? decode(List<int> bytes) {
    if (bytes.isEmpty) return null;

    // 尝试方式1：JPEG 伪装格式
    final jpegResult = _decodeFromJpeg(bytes);
    if (jpegResult != null) return jpegResult;

    // 尝试方式2：BMP 伪装格式
    final bmpResult = _decodeFromBmp(bytes);
    if (bmpResult != null) return bmpResult;

    // 尝试方式3：直接作为 UTF-8 文本解析
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final decoded = _decodeText(text);
      if (decoded != null) return decoded;
    } catch (_) {}

    // 方式4：尝试 GBK 解码（部分 CMS 站点使用 GBK 编码）
    try {
      final text = _decodeGbk(bytes);
      if (text != null) {
        final decoded = _decodeText(text);
        if (decoded != null) return decoded;
      }
    } catch (_) {}

    // 方式5：提取所有可打印 ASCII 字符后尝试解码
    final asciiText = String.fromCharCodes(
      bytes.where((b) => b >= 32 && b <= 126),
    );
    if (asciiText.isNotEmpty) {
      final decoded = _decodeText(asciiText);
      if (decoded != null) return decoded;
    }

    return null;
  }

  /// 从 JPEG 伪装格式中提取 JSON
  /// JPEG 可能包含嵌入缩略图（也有 FF D9 标记），
  /// 必须找到**最后一个** FF D9 才是真正的主图结束位置
  static Map<String, dynamic>? _decodeFromJpeg(List<int> bytes) {
    // 检查是否为 JPEG 文件（FF D8 开头）
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }

    // 查找最后一个 JPEG 结束标记 FF D9（避免缩略图干扰）
    int jpegEnd = -1;
    for (int i = bytes.length - 2; i >= 0; i--) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
        jpegEnd = i + 2;
        break;
      }
    }

    if (jpegEnd < 0 || jpegEnd >= bytes.length - 2) return null;

    // 提取 JPEG 之后的附加数据
    final trailing = bytes.sublist(jpegEnd);
    return _decodeTrailing(trailing);
  }

  /// 从 BMP 伪装格式中提取 JSON
  /// BMP 文件头格式：BM [4字节文件大小] [4字节保留] [4字节偏移]
  /// 附加数据可能在 BMP 数据之后
  static Map<String, dynamic>? _decodeFromBmp(List<int> bytes) {
    // 检查是否为 BMP 文件（BM 开头）
    if (bytes.length < 14 || bytes[0] != 0x42 || bytes[1] != 0x4D) {
      return null;
    }

    // 读取 BMP 文件头中的数据偏移量（字节 10-13，小端序）
    final dataOffset = bytes[10] | (bytes[11] << 8) | (bytes[12] << 16) | (bytes[13] << 24);

    // 读取 BMP 文件大小（字节 2-5，小端序）
    final declaredSize = bytes[2] | (bytes[3] << 8) | (bytes[4] << 16) | (bytes[5] << 24);

    // 策略1：如果文件实际大小大于声明大小，附加数据在声明大小之后
    if (declaredSize > 0 && bytes.length > declaredSize + 2) {
      final trailing = bytes.sublist(declaredSize);
      final result = _decodeTrailing(trailing);
      if (result != null) return result;
    }

    // 策略2：如果文件实际大小大于数据偏移+像素数据，尝试从数据偏移处开始搜索
    // 某些 BMP 伪装可能在像素数据之后直接附加
    if (dataOffset > 0 && dataOffset < bytes.length) {
      // 尝试从不同位置查找 ** 标记
      for (int start = dataOffset; start < bytes.length - 10; start++) {
        // 查找 ** 标记（0x2A 0x2A）
        if (bytes[start] == 0x2A && bytes[start + 1] == 0x2A) {
          // 找到了 ** 标记，提取从标记前8字符开始的数据
          final textStart = start >= 8 ? start - 8 : 0;
          final trailing = bytes.sublist(textStart);
          final result = _decodeTrailing(trailing);
          if (result != null) return result;
          break;
        }
      }
    }

    // 策略3：直接提取所有可打印 ASCII 字符
    final asciiText = String.fromCharCodes(
      bytes.where((b) => b >= 32 && b <= 126),
    );
    return _decodeText(asciiText);
  }

  /// 解码图片数据之后的附加数据
  static Map<String, dynamic>? _decodeTrailing(List<int> trailing) {
    if (trailing.isEmpty) return null;

    // 先尝试 UTF-8 解码（Base64 文本是 ASCII，UTF-8 兼容）
    try {
      final text = utf8.decode(trailing, allowMalformed: true);
      final result = _decodeText(text);
      if (result != null) return result;
    } catch (_) {}

    // 兜底：只取可打印 ASCII 字符
    final asciiText = String.fromCharCodes(
      trailing.where((b) => b >= 32 && b <= 126),
    );
    return _decodeText(asciiText);
  }

  /// 简单的 GBK 解码（覆盖常见中文字符）
  /// GBK 双字节编码：第一字节 0x81-0xFE，第二字节 0x40-0xFE
  static String? _decodeGbk(List<int> bytes) {
    try {
      final sb = StringBuffer();
      int i = 0;
      while (i < bytes.length) {
        final b = bytes[i];
        if (b < 0x80) {
          // ASCII 字符
          sb.writeCharCode(b);
          i++;
        } else if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
          final b2 = bytes[i + 1];
          if (b2 >= 0x40 && b2 <= 0xFE) {
            // GBK 双字节字符 — 查表解码
            final code = _gbkToUnicode(b, b2);
            if (code != null) {
              sb.writeCharCode(code);
            }
            i += 2;
          } else {
            sb.writeCharCode(b);
            i++;
          }
        } else {
          sb.writeCharCode(b);
          i++;
        }
      }
      return sb.toString();
    } catch (_) {
      return null;
    }
  }

  /// GBK 双字节到 Unicode 的映射（常见中文字符）
  static int? _gbkToUnicode(int b1, int b2) {
    final gbkCode = (b1 << 8) | b2;

    // GB2312 汉字区
    if (gbkCode >= 0xB0A1 && gbkCode <= 0xF7FE) {
      final section = b1 - 0xB0;
      final position = b2 - (b2 >= 0xA1 ? 0xA1 : 0x40);
      final index = section * 94 + position;
      return 0x4E00 + index;
    }

    // GBK 扩展区
    if (gbkCode >= 0x8140 && gbkCode <= 0xA0FE) {
      final index = (b1 - 0x81) * 190 + (b2 - 0x40);
      return 0x4E00 + index;
    }

    return null;
  }

  /// 从文本中提取并解码 JSON
  static Map<String, dynamic>? _decodeText(String text) {
    text = text.trim();
    if (text.isEmpty) return null;

    // 方式1：直接是 JSON（支持注释）
    if (text.startsWith('{') || text.startsWith('[')) {
      final result = _parseJsonWithComments(text);
      if (result != null) return result;
    }

    // 方式2：包含 ** 分隔符的 Base64 格式（标识**Base64）
    final markerIdx = text.indexOf('**');
    if (markerIdx >= 0) {
      // 跳过标识符，取 ** 之后的 Base64 数据
      final b64Data = text.substring(markerIdx + 2).trim();
      final decoded = _tryBase64Decode(b64Data);
      if (decoded != null) return decoded;
    }

    // 方式3：纯 Base64 编码
    final decoded = _tryBase64Decode(text);
    return decoded;
  }

  /// 尝试 Base64 解码并解析为 JSON
  static Map<String, dynamic>? _tryBase64Decode(String b64) {
    try {
      // 清理 Base64 字符串（移除可能的空白和非法字符）
      final cleaned = b64.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      if (cleaned.isEmpty) return null;

      final decoded = base64Decode(cleaned);
      final jsonStr = utf8.decode(decoded);
      return _parseJsonWithComments(jsonStr);
    } catch (_) {
      return null;
    }
  }

  /// 解析可能包含 JavaScript 风格注释的 JSON
  /// TVBox 配置文件常含 // 单行注释和 /* */ 多行注释
  static Map<String, dynamic>? _parseJsonWithComments(String text) {
    // 先尝试直接解析
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {}

    // 剥离注释后再解析
    final cleaned = _stripJsonComments(text);
    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {}

    return null;
  }

  /// 剥离 JSON 中的 JavaScript 风格注释
  /// 支持 // 单行注释和 /* */ 多行注释
  /// 注意：不能简单用正则，因为注释标记可能出现在字符串内
  static String _stripJsonComments(String text) {
    final sb = StringBuffer();
    int i = 0;
    bool inString = false;
    String? stringChar;

    while (i < text.length) {
      // 在字符串内，直接输出
      if (inString) {
        final ch = text[i];
        sb.write(ch);
        if (ch == '\\' && i + 1 < text.length) {
          // 转义字符，输出下一个字符
          i++;
          sb.write(text[i]);
        } else if (ch == stringChar) {
          inString = false;
        }
        i++;
        continue;
      }

      // 不在字符串内
      if (text[i] == '"' || text[i] == "'") {
        inString = true;
        stringChar = text[i];
        sb.write(text[i]);
        i++;
      } else if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '/') {
        // 单行注释：跳到行尾
        i += 2;
        while (i < text.length && text[i] != '\n' && text[i] != '\r') {
          i++;
        }
        // 保留换行符以维持行号
      } else if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '*') {
        // 多行注释：跳到 */
        i += 2;
        while (i + 1 < text.length && !(text[i] == '*' && text[i + 1] == '/')) {
          i++;
        }
        i += 2; // 跳过 */
      } else {
        sb.write(text[i]);
        i++;
      }
    }

    return sb.toString();
  }

  /// 检测二进制数据是否为 JPEG 伪装格式
  static bool isJpegDisguise(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0xFF && bytes[1] == 0xD8;
  }

  /// 检测二进制数据是否为 BMP 伪装格式
  static bool isBmpDisguise(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x42 && bytes[1] == 0x4D;
  }

  /// 从 Uint8List 解码
  static Map<String, dynamic>? decodeFromUint8List(Uint8List bytes) {
    return decode(bytes.toList());
  }
}
