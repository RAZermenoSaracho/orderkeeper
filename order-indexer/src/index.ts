import Fastify from "fastify";
import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import { loadDeployment } from "./deployment.js";
import { startIndexer } from "./indexer.js";
import { registerOrderRoutes } from "./routes/orders.js";

const app = Fastify({ logger: true });

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

const port = Number(process.env.PORT ?? 3001);

async function main(): Promise<void> {
  const deployment = loadDeployment();

  await startIndexer(deployment.OrderKeeper);
  app.log.info(`Indexing OrderKeeper at ${deployment.OrderKeeper}`);

  await app.listen({ port, host: "0.0.0.0" });
}

main().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
