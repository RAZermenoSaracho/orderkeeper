import Fastify from "fastify";

const app = Fastify({ logger: true });

// Placeholder health check only — order routes depend on the on-chain
// order struct (contracts/) and the Prisma schema built on top of it,
// both still to come.
app.get("/health", async () => ({ status: "ok" }));

const port = Number(process.env.PORT ?? 3001);

app
  .listen({ port, host: "0.0.0.0" })
  .catch((err) => {
    app.log.error(err);
    process.exit(1);
  });
