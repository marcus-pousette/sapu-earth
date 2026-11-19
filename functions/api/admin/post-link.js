// POST /api/admin/post-link {id, slot, url} -> {id, post_links: {crew, sapu}, social}
// A cleanup's links to posts on Instagram or TikTok (docs/upload-flow.md, Post links and thanks): slot "sapu" is Sapu
// Earth's own post, which Marcus pastes on the APPROVED card (COMMENTS LINK: SAVE, REMOVE); slot "crew" is the link the
// crew sent with the cleanup, which he can only remove (REMOVE LINK on PENDING, REMOVE CREW LINK on APPROVED), never
// replace, so a link nobody sent is never shown as the crew's. url undefined, null or "" removes; a url sets slot sapu,
// only in its stored form (postLink in _lib/social.js), never a short link, and a TikTok post only on @sapu.earth, so
// the receipt never calls a crew's TikTok "our post". Instagram post links name no account: OPEN POST before SAVE is
// the check there. social: what the receipt shows now (socialPick). Public pages catch up within 5 minutes.
// 400 for a bad id, slot or link (code post_link, field url), 404 for an unknown cleanup, 409 code state when the
// cleanup is not approved (sapu) or is rejected, also when it was unpublished meanwhile, 503 code migration before
// migration 0007.
import { HttpError, ID_RE, err, handle, json, readJson } from "../../_lib/util.js";
import { SAPU_TIKTOK, noSocialTables, postLink, socialPick } from "../../_lib/social.js";

const SLOTS = ["sapu", "crew"];
const NOT_YET = "Your post can be linked once the cleanup is approved.";
const REJECTED = "This cleanup was rejected.";

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request, 4096);
  if (typeof b.id !== "string" || !ID_RE.test(b.id)) return err(400, "Invalid id.");
  if (!SLOTS.includes(b.slot)) return err(400, "slot must be sapu or crew.");
  const remove = b.url === undefined || b.url === null || b.url === "";
  if (b.slot === "crew" && !remove) throw new HttpError(400, "The crew's link can only be removed.", "post_link");
  let post = null;
  if (!remove) {
    post = postLink(b.url);
    if (!post || !post.url) {
      throw new HttpError(400, post && post.short
        ? "Short links like vt.tiktok.com cannot be checked. Open the link, then paste the full address it shows (instagram.com/p/..., instagram.com/reel/... or tiktok.com/@sapu.earth/video/...)."
        : "That is not the link to one Instagram or TikTok post.", "post_link", "url");
    }
    if (post.site === "tiktok" && post.account !== SAPU_TIKTOK) {
      throw new HttpError(400, "That TikTok post is not on @sapu.earth. Paste the link to your own post.", "post_link", "url");
    }
  }

  const sub = await env.DB.prepare(
    "SELECT s.status, p.active FROM submissions s JOIN partners p ON p.id = s.partner_id WHERE s.id = ?1"
  ).bind(b.id).first();
  if (!sub) return err(404, "Cleanup not found.");
  if (sub.status === "rejected") throw new HttpError(409, REJECTED, "state");
  if (b.slot === "sapu" && sub.status !== "approved") throw new HttpError(409, NOT_YET, "state");

  const write = post
    // The cleanup is checked again inside the write: one unpublished meanwhile takes no link (409 below).
    ? env.DB.prepare(
      `INSERT INTO post_links (submission_id, sapu_url) SELECT ?1, ?2 WHERE EXISTS (SELECT 1 FROM submissions WHERE id = ?1 AND status = 'approved')
       ON CONFLICT (submission_id) DO UPDATE SET sapu_url = excluded.sapu_url`
    ).bind(b.id, post.url)
    : env.DB.prepare(`UPDATE post_links SET ${b.slot === "sapu" ? "sapu_url" : "crew_url"} = NULL WHERE submission_id = ?1`).bind(b.id);
  let res;
  try {
    // One batch: the write, the row deleted once both slots are empty, and what is stored now.
    res = await env.DB.batch([
      write,
      env.DB.prepare("DELETE FROM post_links WHERE submission_id = ?1 AND crew_url IS NULL AND sapu_url IS NULL").bind(b.id),
      env.DB.prepare("SELECT crew_url, sapu_url FROM post_links WHERE submission_id = ?1").bind(b.id),
    ]);
  } catch (e) {
    if (noSocialTables(e)) throw new HttpError(503, "Post links are not set up yet. Run migration 0007 (docs/upload-flow.md).", "migration");
    throw e;
  }
  const row = res[2].results?.[0] || {};
  const post_links = { crew: row.crew_url ?? null, sapu: row.sapu_url ?? null };
  if (post && post_links.sapu !== post.url) throw new HttpError(409, REJECTED, "state");
  return json({ id: b.id, post_links, social: socialPick(post_links.sapu, post_links.crew, Number(sub.active) === 1) });
});
