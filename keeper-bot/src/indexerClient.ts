interface PendingOrder {
  orderId: number;
}

interface OrdersResponse {
  data: PendingOrder[];
  meta: { count: number };
}

/// Fetches currently-pending orders from order-indexer's GET /orders API
/// (see .claude/rules/api-conventions.md). Uses Node's built-in fetch — no
/// extra HTTP client dependency needed for a single GET request.
export async function fetchPendingOrders(indexerUrl: string): Promise<PendingOrder[]> {
  const response = await fetch(`${indexerUrl}/orders?status=pending`);
  if (!response.ok) {
    throw new Error(`order-indexer returned ${response.status}: ${await response.text()}`);
  }

  const body = (await response.json()) as OrdersResponse;
  return body.data;
}
