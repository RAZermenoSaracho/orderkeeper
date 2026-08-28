import type { FastifyError, FastifyInstance } from "fastify";
import { prisma } from "../db.js";
import type { Order } from "@prisma/client";

const VALID_STATUSES = ["pending", "executed", "cancelled"] as const;
type StatusParam = (typeof VALID_STATUSES)[number];

// Public, unauthenticated API — this bounds abuse/DoS exposure. 100/min
// comfortably covers several open frontend tabs (OrderList polls every
// ~10s) plus multiple keeper-bot instances (see ROADMAP.md's Multiple
// Competing Keeper Bots milestone) polling normally from the same IP.
// Overridable via env, matching the pattern used for indexer.ts's tunable
// knobs (GETLOGS_BLOCK_RANGE, BACKFILL_DELAY_MS, WATCH_POLL_INTERVAL_MS).
const RATE_LIMIT_MAX = Number(process.env.RATE_LIMIT_MAX ?? 100);
const RATE_LIMIT_WINDOW_MS = Number(process.env.RATE_LIMIT_WINDOW_MS ?? 60_000);

// Response shape and error format follow .claude/rules/api-conventions.md.
// Only GET /orders is implemented here — that's all keeper-bot needs; the
// broader read surface (GET /orders/:id, owner filtering, pagination)
// waits for the frontend task that actually needs it.
export function registerOrderRoutes(app: FastifyInstance): void {
  // Catches anything a route handler (or a plugin's preHandler, e.g.
  // @fastify/rate-limit) doesn't handle itself, so the client always gets
  // the documented {error:{code,message}} shape instead of Fastify's
  // default error response. Errors that already carry a specific
  // .statusCode (rate-limit's 429, Fastify's own validation errors, etc.)
  // keep that status; only truly unclassified errors (e.g. a DB failure)
  // fall back to a generic 500 — forcing 500 unconditionally here would
  // silently downgrade those more specific statuses.
  app.setErrorHandler<FastifyError>((error, request, reply) => {
    request.log.error(error);
    const statusCode = typeof error.statusCode === "number" ? error.statusCode : 500;
    reply.code(statusCode);

    if (statusCode === 429) {
      return {
        error: {
          code: "RATE_LIMIT_EXCEEDED",
          message: error.message,
        },
      };
    }

    return {
      error: {
        code: "INTERNAL_ERROR",
        message: "An unexpected error occurred",
      },
    };
  });

  app.get(
    "/orders",
    {
      config: {
        rateLimit: {
          max: RATE_LIMIT_MAX,
          timeWindow: RATE_LIMIT_WINDOW_MS,
        },
      },
    },
    async (request, reply) => {
      const statusParam = (request.query as { status?: string }).status;

      if (statusParam !== undefined && !VALID_STATUSES.includes(statusParam.toLowerCase() as StatusParam)) {
        reply.code(400);
        return {
          error: {
            code: "INVALID_STATUS",
            message: `status must be one of: ${VALID_STATUSES.join(", ")}`,
          },
        };
      }

      const orders = await prisma.order.findMany({
        where: statusParam ? { status: capitalize(statusParam.toLowerCase()) as Order["status"] } : undefined,
        orderBy: { orderId: "asc" },
      });

      return {
        data: orders.map(serializeOrder),
        meta: { count: orders.length },
      };
    },
  );
}

function capitalize(status: string): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

// Prisma's Decimal/BigInt fields don't survive Fastify's default
// JSON.stringify serialization — converted to strings here rather than
// numbers, since 18-decimal wei-scale values can exceed JS's safe integer
// range.
export function serializeOrder(order: Order) {
  return {
    orderId: order.orderId,
    owner: order.owner,
    asset: order.asset,
    condition: order.condition,
    // Decimal.toString() switches to exponential notation above 1e21
    // (targetPrice/executionPrice, at PRICE_DECIMALS=18, cross that at a
    // $1,000 asset price) — toFixed() with no argument always returns
    // plain integer digits, matching api-conventions.md's documented
    // format and what consumers' BigInt(value) calls require.
    targetPrice: order.targetPrice.toFixed(),
    amount: order.amount.toFixed(),
    maxSlippageBps: order.maxSlippageBps,
    expiry: order.expiry.toISOString(),
    status: order.status,
    createdAtBlock: order.createdAtBlock.toString(),
    createdAtTx: order.createdAtTx,
    executedAtBlock: order.executedAtBlock?.toString() ?? null,
    executedAtTx: order.executedAtTx,
    executionPrice: order.executionPrice?.toFixed() ?? null,
    keeperFee: order.keeperFee?.toFixed() ?? null,
    amountOut: order.amountOut?.toFixed() ?? null,
    cancelledAtBlock: order.cancelledAtBlock?.toString() ?? null,
    cancelledAtTx: order.cancelledAtTx,
  };
}
