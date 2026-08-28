import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import { registerOrderRoutes } from "./routes/orders.js";

/// Builds a fully configured Fastify instance (CORS, rate limiting,
/// routes) without starting it — split out from index.ts so tests can
/// exercise the real route/plugin stack via .inject(), with no real
/// port/server or indexer startup needed. index.ts calls this, then adds
/// the parts that only make sense for a real run (starting the indexer,
/// listening on a port).
export async function buildApp(options: { logger?: boolean } = {}): Promise<FastifyInstance> {
  const app = Fastify({ logger: options.logger ?? true });

  // Permissive by design: this API is fully public and read-only (see
  // CLAUDE.md, api-conventions.md) — there's no auth or per-origin data to
  // protect, and no production deployment target yet, so reflecting any
  // origin is no less safe than *, but also works for the Vite dev server's
  // origin without hardcoding its port.
  await app.register(cors, { origin: true });

  // global: false — applied per-route (see routes/orders.ts) rather than to
  // every route. /health deliberately stays unthrottled: it's meant for
  // uptime monitoring (see ROADMAP.md's Operational Monitoring milestone),
  // which shouldn't compete with real traffic for the same budget.
  await app.register(rateLimit, { global: false });

  app.get("/health", async () => ({ status: "ok" }));

  registerOrderRoutes(app);

  return app;
}
