// Serves `zig build site`'s output the way it is hosted: the app on
// http://localhost:5173 and, from another origin, the playground's frame on
// http://localhost:5174 (the default -Dplayground_url). Files are served as
// they are; any other path gets index.html, since routes are client-side.
//
//   zig build site && node scripts/serve.mjs
//
// Node >= 18, no dependencies.
import { createServer } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const site = resolve(dirname(fileURLToPath(import.meta.url)), "../zig-out/site");
if (!existsSync(join(site, "index.html"))) {
  console.error(`no site in ${site}; run \`zig build site\` first`);
  process.exit(1);
}

const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".css": "text/css",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".txt": "text/plain; charset=utf-8",
};

function serve(req, res) {
  const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
  const file = normalize(join(site, path));
  if (!file.startsWith(site)) return res.writeHead(400).end();
  if (existsSync(file) && statSync(file).isFile()) {
    res.writeHead(200, { "content-type": mime[extname(file)] ?? "application/octet-stream" });
    return res.end(readFileSync(file));
  }
  if (extname(path)) return res.writeHead(404).end("not found");
  res.writeHead(200, { "content-type": mime[".html"] });
  res.end(readFileSync(join(site, "index.html")));
}

for (const [port, what] of [[5173, "app"], [5174, "playground frame"]]) {
  createServer(serve).listen(port, "localhost", () => console.log(`${what}: http://localhost:${port}`));
}
