// POST /api/admin/thanks/undo {day, id?} -> 200 {day, id, taken}: UNDO ON THAT RECEIPT (with id) and UNDO THE WHOLE DAY
// (without) in THANKS BY DAY on APPROVED (docs/upload-flow.md, Thanks). undoThanks in _lib/social.js takes that UTC
// day's thanks off the receipts for good: with id only that receipt's, which then takes no more thanks that day; without
// it every receipt's, and nobody can thank on sapu.earth for the rest of that day. taken is what came off. 404 code day
// when there is nothing to undo, 503 code migration before migration 0007. Behind the admin check
// (functions/api/admin/_middleware.js).
import { HttpError, ID_RE, handle, json, readJson } from "../../../_lib/util.js";
import { noSocialTables, undoThanks } from "../../../_lib/social.js";

export const onRequestPost = handle(async ({ request, env }) => {
  const b = await readJson(request, 1024);
  if (typeof b.day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(b.day)) throw new HttpError(400, "day must be YYYY-MM-DD.");
  const id = b.id === undefined || b.id === null || b.id === "" ? null : b.id;
  if (id !== null && (typeof id !== "string" || !ID_RE.test(id))) throw new HttpError(400, "Invalid receipt id.");
  let r;
  try {
    r = await undoThanks(env, b.day, id);
  } catch (e) {
    if (noSocialTables(e)) throw new HttpError(503, "Thanks are not set up yet.", "migration");
    throw e;
  }
  if (!r) throw new HttpError(404, id ? "Nothing to undo on that receipt that day." : "Nothing to undo on that day.", "day");
  return json({ day: b.day, id, taken: r.taken });
});
