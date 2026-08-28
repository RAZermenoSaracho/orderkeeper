import { afterEach, describe, expect, test, vi } from "vitest";
import { fetchPendingOrders } from "./indexerClient.js";

const INDEXER_URL = "http://localhost:3001";

function mockFetchOnce(response: Partial<Response>) {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      text: async () => "",
      ...response,
    }),
  );
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("fetchPendingOrders", () => {
  test("requests GET {indexerUrl}/orders?status=pending", async () => {
    mockFetchOnce({ json: async () => ({ data: [], meta: { count: 0 } }) });

    await fetchPendingOrders(INDEXER_URL);

    expect(fetch).toHaveBeenCalledOnce();
    const [url] = vi.mocked(fetch).mock.calls[0]!;
    expect(url).toBe(`${INDEXER_URL}/orders?status=pending`);
  });

  test("passes an AbortSignal so a hung order-indexer fails fast rather than hanging forever", async () => {
    mockFetchOnce({ json: async () => ({ data: [], meta: { count: 0 } }) });

    await fetchPendingOrders(INDEXER_URL);

    const [, options] = vi.mocked(fetch).mock.calls[0]!;
    expect(options?.signal).toBeInstanceOf(AbortSignal);
  });

  test("returns the data array from a successful response", async () => {
    const orders = [{ orderId: 1 }, { orderId: 2 }];
    mockFetchOnce({ json: async () => ({ data: orders, meta: { count: 2 } }) });

    const result = await fetchPendingOrders(INDEXER_URL);

    expect(result).toEqual(orders);
  });

  test("throws an error including the status code and response body on a non-ok response", async () => {
    mockFetchOnce({ ok: false, status: 503, text: async () => "Service Unavailable" });

    await expect(fetchPendingOrders(INDEXER_URL)).rejects.toThrow(
      "order-indexer returned 503: Service Unavailable",
    );
  });

  test("propagates a network-level fetch rejection (e.g. connection refused) unmodified", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("fetch failed")));

    await expect(fetchPendingOrders(INDEXER_URL)).rejects.toThrow("fetch failed");
  });
});
