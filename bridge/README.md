# 饭太硬 API 代理

App 直连 `http://www.饭太硬.net/tv` 不通（中文域名 DNS 问题），部署这个代理到云端做转发。

## 部署步骤（3 分钟）

### Vercel（推荐）
1. 注册 [vercel.com](https://vercel.com)（GitHub 登录即可，免费）
2. 安装 CLI：`npm i -g vercel`
3. 在 `bridge/` 目录下运行：`vercel --prod`
4. 得到地址如 `https://your-app.vercel.app`

### Deno Deploy
1. 注册 [deno.com/deploy](https://deno.com/deploy)
2. 新建项目，粘贴 `api/proxy.js` 中 Deno 格式的代码
3. 得到地址如 `https://your-app.deno.dev`

## App 端配置

把源地址改成代理地址：
- 打开 App → 设置 → 源管理
- 编辑「饭太硬」源，API 地址改为：`https://你的代理域名/api`

或者直接新增一个源：
- 名称：饭太硬代理
- API：`https://你的代理域名/api`

## 原理

```
App ──→ 代理(Vercel/Deno) ──→ 饭太硬服务器(www.饭太硬.net/tv)
                                  ↓ 跑着所有蜘蛛
                                  ↓ 已汇总 30+ 个源
                                  ↓ 返回标准 CMS JSON
```
