// GET /api/events -> approved partner cleanups in the site event schema.
// Every homepage visit also runs the application retention job after the response, so the
// "about a day" and "3 months" promises on /apply/ hold even when nobody applies or opens /admin/.
import { approvedEvents } from "../_lib/events.js";
import { expireApplications, noApplicationsTable } from "../_lib/applications.js";
import { handle, json, noBindings } from "../_lib/util.js";

export const onRequestGet = handle(async ({ env, waitUntil }) => {
  const missing = noBindings(env);
  if (missing) return missing;
  const events = await approvedEvents(env);
  if (typeof waitUntil === "function") {
    waitUntil(expireApplications(env).catch((e) => {
      if (!noApplicationsTable(e)) console.error("application cleanup", e);
    }));
  }
  return json(events, 200, { "cache-control": "public, max-age=60" });
});
