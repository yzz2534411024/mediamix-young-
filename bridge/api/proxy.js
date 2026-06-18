// 饭太硬 TVBox API 云函数代理
// 部署到 Vercel / Netlify Functions / Deno Deploy 均可
// App 端把源地址改成这个代理地址即可

// 后端 TVBox 网关（云函数能访问，用户设备直连不通）
const BACKEND = 'http://www.饭太硬.net/tv';

// Vercel 格式
export default async function handler(req, res) {
  // 允许跨域
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(200).end();

  // 把 App 发来的参数原样转发给 TVBox 后端
  const url = new URL(BACKEND);
  for (const [k, v] of Object.entries(req.query)) {
    url.searchParams.set(k, v);
  }

  try {
    const r = await fetch(url.toString(), {
      headers: {
        'User-Agent': 'okhttp/3.12.11',
        'Accept': 'application/json, */*',
      },
    });
    const data = await r.text();
    res.setHeader('Content-Type', r.headers.get('content-type') || 'application/json; charset=utf-8');
    res.status(r.status).send(data);
  } catch (e) {
    res.status(502).json({ code: -1, msg: `后端不可达: ${e.message}` });
  }
}

// Deno Deploy / Netlify Functions 格式（如用 Deno 就把上面那段删掉用这个）
// export default async (req: Request) => {
//   const u = new URL(req.url);
//   const params = Object.fromEntries(u.searchParams);
//   const target = new URL(BACKEND);
//   for (const [k, v] of Object.entries(params)) {
//     target.searchParams.set(k, v);
//   }
//   try {
//     const r = await fetch(target.toString(), {
//       headers: { 'User-Agent': 'okhttp/3.12.11' },
//     });
//     return new Response(await r.text(), {
//       status: r.status,
//       headers: { 'Content-Type': r.headers.get('content-type') || 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*' },
//     });
//   } catch (e) {
//     return new Response(JSON.stringify({ code: -1, msg: `后端不可达: ${e.message}` }), {
//       status: 502,
//       headers: { 'Content-Type': 'application/json' },
//     });
//   }
// };
