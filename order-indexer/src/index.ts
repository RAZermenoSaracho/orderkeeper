import Fastify from "fastify";
import { loadDeployment } from "./deployment.js";
import { startIndexer } from "./indexer.js";
import { registerOrderRoutes } from "./routes/orders.js";

const app = Fastify({ logger: true });

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
