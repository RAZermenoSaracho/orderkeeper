import { beforeEach, describe, expect, test, vi } from "vitest";

// Fixed low enough to actually trigger a 429 in a test without firing 100
// real requests — read once at orders.ts's module-evaluation time, so this
// must be set before buildApp (and therefore routes/orders.js) is first
// imported below. This applies to every test in this file, not just the
// rate-limit ones; the others each make well under 3 requests per test.
process.env.RATE_LIMIT_MAX = "3";
process.env.RATE_LIMIT_WINDOW_MS = "60000";

const mockFindMany = vi.fn();
vi.mock("./db.js", () => ({
  prisma: { order: { findMany: (...args: unknown[]) => mockFindMany(...args) } },
}));

const { buildApp } = await import("./app.js");

beforeEach(() => {
  mockFindMany.mockReset();
  mockFindMany.mockResolvedValue([]);
});

describe("GET /health", () => {
  test("returns 200 and {status: 'ok'}", async () => {
    const app = await buildApp({ logger: false });

    const response = await app.inject({ method: "GET", url: "/health" });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ok" });
  });

  test("is never rate-limited, even after /orders' limit is exhausted", async () => {
    const app = await buildApp({ logger: false });

    for (let i = 0; i < 3; i++) await app.inject({ method: "GET", url: "/orders" });
    const healthResponse = await app.inject({ method: "GET", url: "/health" });

    expect(healthResponse.statusCode).toBe(200);
  });
});

describe("GET /orders", () => {
  test("returns the {data, meta} shape from prisma", async () => {
    mockFindMany.mockResolvedValue([]);
    const app = await buildApp({ logger: false });

    const response = await app.inject({ method: "GET", url: "/orders" });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ data: [], meta: { count: 0 } });
  });

  test("returns 400 with the documented error shape for an invalid ?status=", async () => {
    const app = await buildApp({ logger: false });

    const response = await app.inject({ method: "GET", url: "/orders?status=bogus" });

    expect(response.statusCode).toBe(400);
    expect(response.json()).toEqual({
      error: { code: "INVALID_STATUS", message: "status must be one of: pending, executed, cancelled" },
    });
    expect(mockFindMany).not.toHaveBeenCalled();
  });

  test("accepts a valid ?status= case-insensitively and capitalizes it for prisma", async () => {
    const app = await buildApp({ logger: false });

    await app.inject({ method: "GET", url: "/orders?status=PENDING" });

    expect(mockFindMany).toHaveBeenCalledWith(expect.objectContaining({ where: { status: "Pending" } }));
  });

  test("returns 500 with the generic error shape when prisma throws", async () => {
    mockFindMany.mockRejectedValue(new Error("db connection lost"));
    const app = await buildApp({ logger: false });

    const response = await app.inject({ method: "GET", url: "/orders" });

    expect(response.statusCode).toBe(500);
    expect(response.json()).toEqual({ error: { code: "INTERNAL_ERROR", message: "An unexpected error occurred" } });
  });

  test("enforces the per-IP rate limit and returns 429 with the standard error shape once exceeded", async () => {
    const app = await buildApp({ logger: false });

    for (let i = 0; i < 3; i++) {
      const response = await app.inject({ method: "GET", url: "/orders" });
      expect(response.statusCode).toBe(200);
    }
    const limited = await app.inject({ method: "GET", url: "/orders" });

    expect(limited.statusCode).toBe(429);
    expect(limited.json()).toEqual({
      error: { code: "RATE_LIMIT_EXCEEDED", message: expect.stringContaining("Rate limit exceeded") },
    });
  });

  test("reflects the request Origin in Access-Control-Allow-Origin (CORS)", async () => {
    const app = await buildApp({ logger: false });

    const response = await app.inject({
      method: "GET",
      url: "/orders",
      headers: { origin: "http://localhost:5173" },
    });

    expect(response.headers["access-control-allow-origin"]).toBe("http://localhost:5173");
  });

  test("responds to a CORS preflight (OPTIONS) request", async () => {
    const app = await buildApp({ logger: false });

    const response = await app.inject({
      method: "OPTIONS",
      url: "/orders",
      headers: { origin: "http://localhost:5173", "access-control-request-method": "GET" },
    });

    expect(response.statusCode).toBe(204);
    expect(response.headers["access-control-allow-origin"]).toBe("http://localhost:5173");
  });
});
