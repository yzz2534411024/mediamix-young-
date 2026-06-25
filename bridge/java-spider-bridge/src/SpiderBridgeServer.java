import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;

import java.io.*;
import java.lang.reflect.Method;
import java.net.InetSocketAddress;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

/**
 * Java Spider Bridge Server
 *
 * 为 MediaMix Flutter 应用提供 TVBox Java 蜘蛛（csp_*Guard 等）的 HTTP 桥接调用能力。
 *
 * 启动方式：java -jar spider-bridge.jar [port] [spiderJarPath]
 *   - port: HTTP 监听端口，默认 6868
 *   - spiderJarPath: TVBox 蜘蛛 JAR 文件路径
 *
 * HTTP API:
 *   POST /init        { "spiderKey": "csp_XXX", "config": {...} }
 *   POST /home        { "spiderKey": "csp_XXX", "page": 1 }
 *   POST /category    { "spiderKey": "csp_XXX", "tid": "1", "page": 1, "filter": {...} }
 *   POST /detail      { "spiderKey": "csp_XXX", "id": "xxx" }
 *   POST /search      { "spiderKey": "csp_XXX", "keyword": "xxx", "page": 1 }
 *   POST /player      { "spiderKey": "csp_XXX", "flag": "xxx", "id": "xxx" }
 *   GET  /status      → 桥接状态
 *   GET  /spiders     → 已加载蜘蛛列表
 *   POST /shutdown    → 关闭桥接
 *
 * 响应格式: { "code": 0, "data": ... }  或  { "code": -1, "msg": "error" }
 */
public class SpiderBridgeServer {

    private static final String TAG = "[SpiderBridge]";
    private static final Map<String, Object> spiderInstances = new ConcurrentHashMap<>();
    private static final Map<String, String> spiderClassMap = new ConcurrentHashMap<>();
    private static URLClassLoader jarClassLoader;
    private static HttpServer server;
    private static int port = 6868;

    public static void main(String[] args) throws Exception {
        if (args.length >= 1) {
            try { port = Integer.parseInt(args[0]); } catch (NumberFormatException ignored) {}
        }

        String spiderJarPath = args.length >= 2 ? args[1] : null;

        log("启动 Java Spider Bridge, port=" + port);

        // 加载蜘蛛 JAR
        if (spiderJarPath != null && !spiderJarPath.isEmpty()) {
            loadSpiderJar(spiderJarPath);
        }

        // 创建 HTTP 服务器
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        server.setExecutor(null); // 使用默认线程池

        // 注册路由
        server.createContext("/status", new StatusHandler());
        server.createContext("/spiders", new SpidersHandler());
        server.createContext("/init", new SpiderMethodHandler("init"));
        server.createContext("/home", new SpiderMethodHandler("homeContent"));
        server.createContext("/category", new SpiderMethodHandler("categoryContent"));
        server.createContext("/detail", new SpiderMethodHandler("detailContent"));
        server.createContext("/search", new SpiderMethodHandler("searchContent"));
        server.createContext("/player", new SpiderMethodHandler("playerContent"));
        server.createContext("/shutdown", new ShutdownHandler());

        server.start();
        log("Bridge 已启动, 监听 127.0.0.1:" + port);
        log("已加载 " + spiderClassMap.size() + " 个蜘蛛类");

        // 输出 JSON 状态到 stdout 供 Dart 端解析
        System.out.println("{\"bridge_ready\":true,\"port\":" + port
                + ",\"spiders\":" + spiderClassMap.size() + "}");
    }

    // ==================== JAR 加载 ====================

    private static void loadSpiderJar(String jarPath) {
        try {
            File jarFile = new File(jarPath);
            if (!jarFile.exists()) {
                log("蜘蛛 JAR 不存在: " + jarPath);
                return;
            }

            log("加载蜘蛛 JAR: " + jarPath + " (" + jarFile.length() + " bytes)");

            jarClassLoader = new URLClassLoader(
                    new URL[]{jarFile.toURI().toURL()},
                    SpiderBridgeServer.class.getClassLoader()
            );

            // 扫描 JAR 中所有 class 文件，建立 spiderKey → className 映射
            try (JarFile jar = new JarFile(jarFile)) {
                Enumeration<JarEntry> entries = jar.entries();
                while (entries.hasMoreElements()) {
                    JarEntry entry = entries.nextElement();
                    String name = entry.getName();
                    if (name.endsWith(".class") && !name.contains("$")) {
                        String className = name.replace('/', '.').replace(".class", "");
                        String simpleName = className.substring(className.lastIndexOf('.') + 1);

                        // 尝试检查是否实现了 Spider 接口
                        try {
                            Class<?> cls = jarClassLoader.loadClass(className);
                            if (isSpiderClass(cls)) {
                                // 用类名作为 key（如 csp_WoGGGuard → csp_WoGGGuard）
                                spiderClassMap.put(simpleName, className);
                                log("  发现蜘蛛: " + simpleName + " → " + className);
                            }
                        } catch (Throwable t) {
                            // 某些类可能依赖 Android 框架，加载失败时跳过
                        }
                    }
                }
            }

            log("JAR 扫描完成, 发现 " + spiderClassMap.size() + " 个蜘蛛类");

        } catch (Exception e) {
            log("加载蜘蛛 JAR 失败: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * 判断一个类是否是蜘蛛类：
     * 1. 实现了包含 homeContent/categoryContent/detailContent 等方法的接口
     * 2. 或者是类名以 csp_ 开头的（TVBox 命名约定）
     */
    private static boolean isSpiderClass(Class<?> cls) {
        // 检查是否包含 TVBox 蜘蛛标准方法
        try {
            // TVBox 蜘蛛通常有 init(Context, String) 或 homeContent() 方法
            for (Method m : cls.getMethods()) {
                String mName = m.getName();
                if (mName.equals("homeContent") || mName.equals("categoryContent")
                        || mName.equals("detailContent") || mName.equals("searchContent")
                        || mName.equals("playerContent")) {
                    return true;
                }
            }
        } catch (Throwable ignored) {}

        // 检查类名是否符合 csp_ 命名约定
        String simpleName = cls.getSimpleName();
        if (simpleName.startsWith("csp_")) {
            return true;
        }

        // 检查实现的接口
        for (Class<?> iface : cls.getInterfaces()) {
            String ifaceName = iface.getSimpleName();
            if (ifaceName.equals("Spider") || ifaceName.equals("SpiderExt")
                    || ifaceName.equals("CSPSpider") || ifaceName.equals("ISpider")) {
                return true;
            }
        }

        return false;
    }

    // ==================== 蜘蛛实例管理 ====================

    private static Object getOrCreateSpider(String spiderKey) throws Exception {
        if (spiderInstances.containsKey(spiderKey)) {
            return spiderInstances.get(spiderKey);
        }

        String className = spiderClassMap.get(spiderKey);
        if (className == null) {
            // 尝试模糊匹配：spiderKey 可能直接就是类名
            for (Map.Entry<String, String> entry : spiderClassMap.entrySet()) {
                if (entry.getValue().endsWith("." + spiderKey) || entry.getKey().equals(spiderKey)) {
                    className = entry.getValue();
                    break;
                }
            }
        }

        if (className == null) {
            throw new Exception("未找到蜘蛛: " + spiderKey
                    + " (已加载 " + spiderClassMap.size() + " 个)");
        }

        Class<?> cls = jarClassLoader.loadClass(className);
        Object instance = cls.getDeclaredConstructor().newInstance();
        spiderInstances.put(spiderKey, instance);
        log("创建蜘蛛实例: " + spiderKey + " → " + className);
        return instance;
    }

    // ==================== 反射调用蜘蛛方法 ====================

    private static String invokeSpiderMethod(Object spider, String methodName, Map<String, Object> params) {
        try {
            Class<?> cls = spider.getClass();

            // 查找匹配方法（TVBox 蜘蛛方法签名有多种变体）
            Method targetMethod = null;

            for (Method m : cls.getMethods()) {
                if (!m.getName().equals(methodName)) continue;

                Class<?>[] paramTypes = m.getParameterTypes();

                switch (methodName) {
                    case "init":
                        // init(String config) 或 init(Context, String)
                        if (paramTypes.length == 1 && paramTypes[0] == String.class) {
                            targetMethod = m;
                        }
                        break;

                    case "homeContent":
                        // homeContent(boolean useCache) 或 homeContent()
                        if (paramTypes.length == 0 || paramTypes.length == 1) {
                            targetMethod = m;
                        }
                        break;

                    case "categoryContent":
                        // categoryContent(String tid, String page, boolean filter, Map filter)
                        // categoryContent(String tid, String page, Map filter)
                        if (paramTypes.length >= 2) {
                            targetMethod = m;
                        }
                        break;

                    case "detailContent":
                        // detailContent(String id)
                        if (paramTypes.length == 1 && paramTypes[0] == String.class) {
                            targetMethod = m;
                        }
                        break;

                    case "searchContent":
                        // searchContent(String keyword) 或 searchContent(String key, ...)
                        if (paramTypes.length >= 1) {
                            targetMethod = m;
                        }
                        break;

                    case "playerContent":
                        // playerContent(String flag, String id, Map dict)
                        // playerContent(String flag, String id)
                        if (paramTypes.length >= 2) {
                            targetMethod = m;
                        }
                        break;
                }

                if (targetMethod != null) break;
            }

            if (targetMethod == null) {
                return errorJson("方法未找到: " + methodName + " (参数类型: "
                        + Arrays.toString(cls.getMethods()) + ")");
            }

            // 根据方法签名构造参数
            Class<?>[] paramTypes = targetMethod.getParameterTypes();
            Object[] args = buildMethodArgs(methodName, paramTypes, params);

            // 调用方法
            Object result = targetMethod.invoke(spider, args);
            String resultStr = result != null ? result.toString() : "{}";

            return successJson(resultStr);

        } catch (Exception e) {
            log("调用蜘蛛方法失败: " + methodName + " - " + e.getMessage());
            e.printStackTrace();
            return errorJson("调用失败: " + e.getMessage());
        }
    }

    private static Object[] buildMethodArgs(String methodName, Class<?>[] paramTypes, Map<String, Object> params) {
        switch (methodName) {
            case "init": {
                String config = params.getOrDefault("config", "{}").toString();
                return new Object[]{config};
            }
            case "homeContent": {
                if (paramTypes.length == 1 && paramTypes[0] == boolean.class) {
                    return new Object[]{false};
                }
                return new Object[]{};
            }
            case "categoryContent": {
                String tid = params.getOrDefault("tid", "0").toString();
                String page = params.getOrDefault("page", "1").toString();
                if (paramTypes.length == 2) {
                    return new Object[]{tid, page};
                }
                if (paramTypes.length == 3) {
                    return new Object[]{tid, page, false};
                }
                if (paramTypes.length >= 4) {
                    return new Object[]{tid, page, false, null};
                }
                return new Object[]{tid, page};
            }
            case "detailContent": {
                String id = params.getOrDefault("id", "").toString();
                return new Object[]{id};
            }
            case "searchContent": {
                String keyword = params.getOrDefault("keyword", "").toString();
                if (paramTypes.length == 1) {
                    return new Object[]{keyword};
                }
                // searchContent(String key, String keyword, ...)
                return new Object[]{"", keyword, false};
            }
            case "playerContent": {
                String flag = params.getOrDefault("flag", "").toString();
                String id = params.getOrDefault("id", "").toString();
                if (paramTypes.length == 2) {
                    return new Object[]{flag, id};
                }
                // playerContent(String flag, String id, Map dict)
                return new Object[]{flag, id, new HashMap<>()};
            }
            default:
                return new Object[]{};
        }
    }

    // ==================== JSON 工具 ====================

    private static String successJson(String data) {
        // data 已经是 JSON 字符串，直接嵌入
        return "{\"code\":0,\"data\":" + data + "}";
    }

    private static String errorJson(String msg) {
        return "{\"code\":-1,\"msg\":\"" + escapeJson(msg) + "\"}";
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    private static Map<String, Object> parseJsonBody(String body) {
        // 极简 JSON 解析器，只处理一层 key-value
        Map<String, Object> result = new HashMap<>();
        if (body == null || body.isEmpty()) return result;

        body = body.trim();
        if (body.startsWith("{")) body = body.substring(1);
        if (body.endsWith("}")) body = body.substring(0, body.length() - 1);

        // 简单状态机解析
        int i = 0;
        while (i < body.length()) {
            // 跳过空白和逗号
            while (i < body.length() && (body.charAt(i) == ',' || body.charAt(i) == ' '
                    || body.charAt(i) == '\n' || body.charAt(i) == '\r'
                    || body.charAt(i) == '\t')) i++;
            if (i >= body.length()) break;

            // 读 key
            if (body.charAt(i) != '"') { i++; continue; }
            i++; // skip "
            int keyStart = i;
            while (i < body.length() && body.charAt(i) != '"') {
                if (body.charAt(i) == '\\') i++;
                i++;
            }
            String key = body.substring(keyStart, i);
            i++; // skip "

            // skip :
            while (i < body.length() && body.charAt(i) != ':') i++;
            i++;

            // skip whitespace
            while (i < body.length() && (body.charAt(i) == ' ' || body.charAt(i) == '\n'
                    || body.charAt(i) == '\r' || body.charAt(i) == '\t')) i++;
            if (i >= body.length()) break;

            // 读 value
            char c = body.charAt(i);
            if (c == '"') {
                // 字符串值
                i++;
                int valStart = i;
                while (i < body.length() && body.charAt(i) != '"') {
                    if (body.charAt(i) == '\\') i++;
                    i++;
                }
                result.put(key, body.substring(valStart, i));
                i++;
            } else if (c == '{' || c == '[') {
                // 嵌套对象/数组 — 找到匹配的闭合括号
                char open = c, close = c == '{' ? '}' : ']';
                int depth = 1;
                int valStart = i;
                i++;
                boolean inStr = false;
                while (i < body.length() && depth > 0) {
                    char ch = body.charAt(i);
                    if (ch == '"' && (i == 0 || body.charAt(i - 1) != '\\')) inStr = !inStr;
                    if (!inStr) {
                        if (ch == open) depth++;
                        else if (ch == close) depth--;
                    }
                    i++;
                }
                result.put(key, body.substring(valStart, i));
            } else if (c == 't' || c == 'f') {
                // boolean
                if (body.startsWith("true", i)) { result.put(key, true); i += 4; }
                else if (body.startsWith("false", i)) { result.put(key, false); i += 5; }
            } else if (c == 'n') {
                result.put(key, null); i += 4;
            } else if (c == '-' || (c >= '0' && c <= '9')) {
                int valStart = i;
                if (c == '-') i++;
                while (i < body.length() && body.charAt(i) >= '0' && body.charAt(i) <= '9') i++;
                if (i < body.length() && body.charAt(i) == '.') {
                    i++;
                    while (i < body.length() && body.charAt(i) >= '0' && body.charAt(i) <= '9') i++;
                    result.put(key, Double.parseDouble(body.substring(valStart, i)));
                } else {
                    result.put(key, Long.parseLong(body.substring(valStart, i)));
                }
            } else {
                i++;
            }
        }
        return result;
    }

    private static void log(String msg) {
        System.err.println(TAG + " " + msg);
    }

    // ==================== HTTP Handlers ====================

    private static String readRequestBody(HttpExchange exchange) throws IOException {
        try (InputStream is = exchange.getRequestBody()) {
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) != -1) baos.write(buf, 0, n);
            return baos.toString("UTF-8");
        }
    }

    private static void sendResponse(HttpExchange exchange, String json) throws IOException {
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
        exchange.sendResponseHeaders(200, bytes.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(bytes);
        }
    }

    /** GET /status */
    static class StatusHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            String json = "{\"code\":0,\"data\":{"
                    + "\"status\":\"running\","
                    + "\"port\":" + port + ","
                    + "\"spiderCount\":" + spiderClassMap.size() + ","
                    + "\"instanceCount\":" + spiderInstances.size() + ","
                    + "\"jarLoaded\":" + (jarClassLoader != null)
                    + "}}";
            sendResponse(exchange, json);
        }
    }

    /** GET /spiders */
    static class SpidersHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            StringBuilder sb = new StringBuilder("[");
            boolean first = true;
            for (Map.Entry<String, String> entry : spiderClassMap.entrySet()) {
                if (!first) sb.append(",");
                sb.append("{\"key\":\"").append(escapeJson(entry.getKey()))
                        .append("\",\"class\":\"").append(escapeJson(entry.getValue()))
                        .append("\",\"loaded\":").append(spiderInstances.containsKey(entry.getKey()))
                        .append("}");
                first = false;
            }
            sb.append("]");
            sendResponse(exchange, "{\"code\":0,\"data\":" + sb + "}");
        }
    }

    /** POST /home, /category, /detail, /search, /player, /init */
    static class SpiderMethodHandler implements HttpHandler {
        private final String methodName;

        SpiderMethodHandler(String methodName) {
            this.methodName = methodName;
        }

        @Override
        public void handle(HttpExchange exchange) throws IOException {
            try {
                if (!"POST".equalsIgnoreCase(exchange.getRequestMethod())) {
                    sendResponse(exchange, errorJson("仅支持 POST 请求"));
                    return;
                }

                String body = readRequestBody(exchange);
                Map<String, Object> params = parseJsonBody(body);
                String spiderKey = params.getOrDefault("spiderKey", "").toString();

                if (spiderKey.isEmpty()) {
                    sendResponse(exchange, errorJson("缺少 spiderKey 参数"));
                    return;
                }

                Object spider = getOrCreateSpider(spiderKey);

                // init 方法特殊处理
                if ("init".equals(methodName)) {
                    String result = invokeSpiderMethod(spider, "init", params);
                    sendResponse(exchange, result);
                    return;
                }

                String result = invokeSpiderMethod(spider, methodName, params);
                sendResponse(exchange, result);

            } catch (Exception e) {
                log("处理请求失败: " + e.getMessage());
                sendResponse(exchange, errorJson(e.getMessage()));
            }
        }
    }

    /** POST /shutdown */
    static class ShutdownHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            sendResponse(exchange, "{\"code\":0,\"data\":{\"message\":\"Bridge 正在关闭\"}}");
            log("收到关闭请求");
            new Thread(() -> {
                try { Thread.sleep(500); } catch (InterruptedException ignored) {}
                server.stop(0);
                System.exit(0);
            }).start();
        }
    }
}
