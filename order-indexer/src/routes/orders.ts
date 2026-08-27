import type { FastifyInstance } from "fastify";
import { prisma } from "../db.js";
import type { Order } from "@prisma/client";

const VALID_STATUSES = ["pending", "executed", "cancelled"] as const;
type StatusParam = (typeof VALID_STATUSES)[number];

// Response shape and error format follow .claude/rules/api-conventions.md.
// Only GET /orders is implemented here — that's all keeper-bot needs; the
// broader read surface (GET /orders/:id, owner filtering, pagination)
// waits for the frontend task that actually needs it.
export function registerOrderRoutes(app: FastifyInstance): void {
  // Catches anything a route handler doesn't handle itself (e.g. a DB
  // failure from prisma.order.findMany) so the client still gets the
  // documented {error:{code,message}} shape instead of Fastify's default
  // error response.
  app.setErrorHandler((error, request, reply) => {
    request.log.error(error);
    reply.code(500);
    return {
      error: {
        code: "INTERNAL_ERROR",
        message: "An unexpected error occurred",
      },
    };
  });

  app.get("/orders", async (request, reply) => {
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
  });
}

function capitalize(status: string): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

// Prisma's Decimal/BigInt fields don't survive Fastify's default
// JSON.stringify serialization — converted to strings here rather than
// numbers, since 18-decimal wei-scale values can exceed JS's safe integer
// range.
function serializeOrder(order: Order) {
  return {
    orderId: order.orderId,
    owner: order.owner,
    asset: order.asset,
    condition: order.condition,
    targetPrice: order.targetPrice.toString(),
    amount: order.amount.toString(),
    maxSlippageBps: order.maxSlippageBps,
    expiry: order.expiry.toISOString(),
    status: order.status,
    createdAtBlock: order.createdAtBlock.toString(),
    createdAtTx: order.createdAtTx,
    executedAtBlock: order.executedAtBlock?.toString() ?? null,
    executedAtTx: order.executedAtTx,
    executionPrice: order.executionPrice?.toString() ?? null,
    keeperFee: order.keeperFee?.toString() ?? null,
    amountOut: order.amountOut?.toString() ?? null,
    cancelledAtBlock: order.cancelledAtBlock?.toString() ?? null,
    cancelledAtTx: order.cancelledAtTx,
  };
}
