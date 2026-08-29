module.exports = {
  apps: [
    {
      name: "orderkeeper-indexer",
      cwd: `${__dirname}/order-indexer`,
      script: "npm",
      args: "start",
      autorestart: true,
      env: { NODE_ENV: "production" },
    },
    {
      name: "orderkeeper-keeper",
      cwd: `${__dirname}/keeper-bot`,
      script: "npm",
      args: "start",
      autorestart: true,
      env: { NODE_ENV: "production" },
    },
    {
      name: "orderkeeper-frontend",
      cwd: `${__dirname}/frontend`,
      script: "npm",
      args: "start",
      autorestart: true,
      env: { NODE_ENV: "production" },
    },
  ],
};
