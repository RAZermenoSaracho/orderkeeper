import { buildApp } from "./app.js";
import { loadDeployment } from "./deployment.js";
import { startIndexer } from "./indexer.js";

const port = Number(process.env.PORT ?? 3001);

async function main(): Promise<void> {
  const app = await buildApp();
  const deployment = loadDeployment();

  await startIndexer(deployment.OrderKeeper);
  app.log.info(`Indexing OrderKeeper at ${deployment.OrderKeeper}`);

  await app.listen({ port, host: "0.0.0.0" });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
