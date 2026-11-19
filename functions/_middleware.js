// Backstop only. The real protection is that scripts/build-site.sh deploys an allowlist
// (dist/), so internal folders are not part of the deployed output at all.
// _routes.json sends every path it does not exclude here. The zone normalizes paths before
// Pages sees them ("Normalize URLs to origin"), but this does not rely on it: we normalize
// (decode, collapse slashes, lowercase) before matching, so /%6fps/ is /ops/ here too.
// Any first path segment that starts with a dot (.env.cloudflare, .dev.vars, .git, .github, .claude, .wrangler...),
// except /.well-known/, and the folders that are not part of the site, so even a deploy of the repo folder itself
// (instead of dist/) would not serve them.
const PRIVATE = [
  /^\/\.(?!well-known(\/|$))/,
  /^\/(ops|docs|functions|migrations|scripts|tests|assets|reports|research_notes|public-repo)(\/|$)/,
  /^\/readme\.md$/,
  /^\/data\/readme\.md$/,
];

const notFound = () => new Response("Not found", { status: 404, headers: { "content-type": "text/plain" } });

export async function onRequest(context) {
  let path;
  try {
    path = decodeURIComponent(new URL(context.request.url).pathname);
  } catch {
    return notFound();
  }
  path = path.replace(/\\/g, "/").replace(/\/{2,}/g, "/").toLowerCase();
  if (PRIVATE.some((re) => re.test(path))) return notFound();
  return context.next();
}
