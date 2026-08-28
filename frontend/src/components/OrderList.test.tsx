import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import * as wagmi from "wagmi";
import OrderList from "./OrderList.tsx";

// useAccount/useWriteContract/useWaitForTransactionReceipt are mocked (see
// frontend/CLAUDE.md's Testing section); @tanstack/react-query and fetch()
// are left real, driven by a mocked global fetch, so this exercises the
// component's actual data-fetching and owner-filtering logic rather than
// bypassing it.
vi.mock("wagmi", async (importOriginal) => {
  const actual = await importOriginal<typeof wagmi>();
  return {
    ...actual,
    useAccount: vi.fn(),
    useWriteContract: vi.fn(),
    useWaitForTransactionReceipt: vi.fn(),
  };
});

const mockUseAccount = vi.mocked(wagmi.useAccount);
const mockUseWriteContract = vi.mocked(wagmi.useWriteContract);
const mockUseWaitForTransactionReceipt = vi.mocked(wagmi.useWaitForTransactionReceipt);

const CONNECTED_ADDRESS = "0x369A2e8133Ea0670fCC7C96ff3220c43D3ffeA7A";
const OTHER_ADDRESS = "0x1111111111111111111111111111111111111111";

const mockWriteContract = vi.fn();

function baseOrder(overrides: Record<string, unknown> = {}) {
  return {
    orderId: 0,
    owner: CONNECTED_ADDRESS,
    asset: "0x1287B650e882514447b96a49a0f8DC1040B26d2A", // WETH
    condition: "GreaterOrEqual",
    targetPrice: "1000000000000000000000",
    amount: "1000000000000000",
    maxSlippageBps: 100,
    expiry: "2026-08-29T00:00:00.000Z",
    status: "Pending",
    createdAtTx: "0xcreatedtx",
    executionPrice: null,
    keeperFee: null,
    amountOut: null,
    ...overrides,
  };
}

function mockFetchOrders(orders: ReturnType<typeof baseOrder>[]) {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ data: orders, meta: { count: orders.length } }),
    }),
  );
}

function renderOrderList() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <OrderList />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  mockWriteContract.mockReset();
  mockUseAccount.mockReturnValue({ address: CONNECTED_ADDRESS } as unknown as ReturnType<typeof wagmi.useAccount>);
  mockUseWriteContract.mockReturnValue({
    writeContract: mockWriteContract,
    data: undefined,
    isPending: false,
    error: null,
    reset: vi.fn(),
  } as unknown as ReturnType<typeof wagmi.useWriteContract>);
  mockUseWaitForTransactionReceipt.mockReturnValue({
    isLoading: false,
    isSuccess: false,
  } as unknown as ReturnType<typeof wagmi.useWaitForTransactionReceipt>);
});

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

describe("OrderList", () => {
  test("shows only orders owned by the connected wallet, filtering out others client-side", async () => {
    mockFetchOrders([
      baseOrder({ orderId: 1, owner: CONNECTED_ADDRESS }),
      baseOrder({ orderId: 2, owner: OTHER_ADDRESS }),
    ]);

    renderOrderList();

    expect(await screen.findByText("#1")).toBeInTheDocument();
    expect(screen.queryByText("#2")).not.toBeInTheDocument();
  });

  test("owner comparison is case-insensitive", async () => {
    mockFetchOrders([baseOrder({ orderId: 1, owner: CONNECTED_ADDRESS.toLowerCase() })]);

    renderOrderList();

    expect(await screen.findByText("#1")).toBeInTheDocument();
  });

  test("shows 'No orders yet.' when the connected wallet has none", async () => {
    mockFetchOrders([baseOrder({ orderId: 1, owner: OTHER_ADDRESS })]);

    renderOrderList();

    expect(await screen.findByText("No orders yet.")).toBeInTheDocument();
  });

  test("shows the asset label from SUPPORTED_ASSETS for a recognized asset", async () => {
    mockFetchOrders([
      baseOrder({ orderId: 1, asset: "0x779877A7B0D9E8603169DdbD7836e478b4624789" }), // LINK
    ]);

    renderOrderList();

    expect(await screen.findByText(/Asset: LINK/)).toBeInTheDocument();
  });

  test("falls back to a truncated address for an unrecognized asset", async () => {
    mockFetchOrders([baseOrder({ orderId: 1, asset: "0x9999999999999999999999999999999999999a" })]);

    renderOrderList();

    expect(await screen.findByText(/Asset: 0x9999\.\.\.999a/)).toBeInTheDocument();
  });

  test("shows a Cancel button only for a Pending order, not an Executed one", async () => {
    mockFetchOrders([
      baseOrder({ orderId: 1, status: "Pending" }),
      baseOrder({
        orderId: 2,
        status: "Executed",
        executionPrice: "2000000000000000000000",
        keeperFee: "5000000000000",
        amountOut: "1900000",
      }),
    ]);

    renderOrderList();

    await screen.findByText("#1");
    expect(screen.getAllByRole("button", { name: "Cancel" })).toHaveLength(1);
    expect(await screen.findByText(/Executed at \$2000/)).toBeInTheDocument();
  });

  test("clicking Cancel calls cancelOrder with the order's id", async () => {
    const user = userEvent.setup();
    mockFetchOrders([baseOrder({ orderId: 7, status: "Pending" })]);

    renderOrderList();
    await screen.findByText("#7");
    await user.click(screen.getByRole("button", { name: "Cancel" }));

    expect(mockWriteContract).toHaveBeenCalledOnce();
    const call = mockWriteContract.mock.calls[0]![0];
    expect(call.functionName).toBe("cancelOrder");
    expect(call.args).toEqual([7n]);
  });

  test("triggers a refetch after cancellation succeeds", async () => {
    mockFetchOrders([baseOrder({ orderId: 7, status: "Pending" })]);
    mockUseWaitForTransactionReceipt.mockReturnValue({
      isLoading: false,
      isSuccess: true,
    } as unknown as ReturnType<typeof wagmi.useWaitForTransactionReceipt>);

    renderOrderList();
    await screen.findByText("#7");

    // A successful useWaitForTransactionReceipt (mocked as already-true)
    // should trigger exactly one extra fetch beyond the initial load.
    await waitFor(() => expect(vi.mocked(fetch)).toHaveBeenCalledTimes(2));
  });

  test("shows a fetch failure instead of crashing", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 500 }));

    renderOrderList();

    expect(await screen.findByText(/Could not load orders/)).toBeInTheDocument();
  });
});
