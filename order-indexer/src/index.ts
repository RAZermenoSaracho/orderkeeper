import { buildApp } from "./app.js";
import { loadDeployment } from "./deployment.js";
import { startIndexer } from "./indexer.js";

const port = Number(process.env.PORT ?? 3001);
const host = process.env.HOST ?? "127.0.0.1";

async function main(): Promise<void> {
  const app = await buildApp();
  const deployment = loadDeployment();

  await startIndexer(deployment.OrderKeeper, BigInt(deployment.deploymentBlock));
  app.log.info(`Indexing OrderKeeper at ${deployment.OrderKeeper}`);

  await app.listen({ port, host });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
