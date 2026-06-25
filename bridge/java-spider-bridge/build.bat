@echo off
REM ============================================
REM Java Spider Bridge 构建脚本
REM 用法: build.bat
REM 前提: JDK 11+ 已安装且 JAVA_HOME 已设置
REM ============================================

set SRC_DIR=%~dp0src
set OUT_DIR=%~dp0build
set JAR_NAME=spider-bridge.jar

echo [1/3] 创建输出目录...
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo [2/3] 编译 Java 源码...
javac -d "%OUT_DIR%" --release 11 "%SRC_DIR%\SpiderBridgeServer.java"
if errorlevel 1 (
    echo 编译失败！请确保已安装 JDK 11+
    pause
    exit /b 1
)

echo [3/3] 打包 JAR...
echo Main-Class: SpiderBridgeServer> "%OUT_DIR%\MANIFEST.MF"
jar cfm "%OUT_DIR%\%JAR_NAME%" "%OUT_DIR%\MANIFEST.MF" -C "%OUT_DIR%" .
del "%OUT_DIR%\MANIFEST.MF"

echo.
echo ============================================
echo 构建成功! JAR 文件: %OUT_DIR%\%JAR_NAME%
echo.
echo 使用方法:
echo   java -jar "%OUT_DIR%\%JAR_NAME%" [port] [spiderJarPath]
echo.
echo 示例:
echo   java -jar "%OUT_DIR%\%JAR_NAME%" 6868 "C:\path\to\spider.jar"
echo ============================================
