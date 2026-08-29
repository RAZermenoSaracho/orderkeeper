import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as wagmi from "wagmi";
import CreateOrderForm from "./CreateOrderForm.tsx";

// Unit-tests component behavior against mocked wagmi hooks, rather than a
// real wallet/RPC — see frontend/CLAUDE.md's Testing section for why.
vi.mock("wagmi", async (importOriginal) => {
  const actual = await importOriginal<typeof wagmi>();
  return {
    ...actual,
    useAccount: vi.fn(),
    useReadContract: vi.fn(),
    useWriteContract: vi.fn(),
    useWaitForTransactionReceipt: vi.fn(),
  };
});

const mockUseAccount = vi.mocked(wagmi.useAccount);
const mockUseReadContract = vi.mocked(wagmi.useReadContract);
const mockUseWriteContract = vi.mocked(wagmi.useWriteContract);
const mockUseWaitForTransactionReceipt = vi.mocked(wagmi.useWaitForTransactionReceipt);

const CONNECTED_ADDRESS = "0x369A2e8133Ea0670fCC7C96ff3220c43D3ffeA7A";

const mockWriteContract = vi.fn();
const mockWriteApprove = vi.fn();
const mockReset = vi.fn();
const mockRefetchAllowance = vi.fn();

// Real return types are large discriminated unions (idle/pending/success/
// error variants with many mutually-exclusive fields) — these helpers only
// need the handful of fields CreateOrderForm actually reads, so they're
// typed loosely and double-cast, rather than constructing a fully valid
// union member for every test.
//
// The component calls useWriteContract twice per render (approve, then
// create) and useWaitForTransactionReceipt twice to match, both
// unconditionally and in that fixed order. So the mocks alternate by call
// index: even = approve, odd = create.
//
// mockReturnValueOnce chains can't be used here — React re-renders on every
// state change, and the queued values are exhausted after the first render,
// leaving later renders with undefined.
function setHookStates(
  options: {
    approve?: Record<string, unknown>;
    create?: Record<string, unknown>;
    approveReceipt?: Record<string, unknown>;
    createReceipt?: Record<string, unknown>;
  } = {},
) {
  mockUseWriteContract.mockReset();
  mockUseWaitForTransactionReceipt.mockReset();

  let writeCall = 0;
  mockUseWriteContract.mockImplementation((() => {
    const isApprove = writeCall++ % 2 === 0;
    return (
      isApprove
        ? {
            writeContract: mockWriteApprove,
            data: undefined,
            isPending: false,
            error: null,
            reset: vi.fn(),
            ...options.approve,
          }
        : {
            writeContract: mockWriteContract,
            data: undefined,
            isPending: false,
            error: null,
            reset: mockReset,
            ...options.create,
          }
    ) as unknown;
  }) as unknown as typeof wagmi.useWriteContract);

  let receiptCall = 0;
  mockUseWaitForTransactionReceipt.mockImplementation((() => {
    const isApprove = receiptCall++ % 2 === 0;
    return {
      isLoading: false,
      isSuccess: false,
      ...(isApprove ? options.approveReceipt : options.createReceipt),
    } as unknown;
  }) as unknown as typeof wagmi.useWaitForTransactionReceipt);
}

/// Sets the quoteToken allowance the component reads for Buy orders.
/// LivePrice's getAssetPrice read shares this mock, so it's keyed on the
/// requested functionName rather than returning one shape for both.
function setAllowance(allowance: bigint | undefined) {
  mockUseReadContract.mockImplementation(((args: { functionName?: string }) => {
    if (args?.functionName === "allowance") {
      return { data: allowance, refetch: mockRefetchAllowance } as unknown;
    }
    return { data: undefined, error: null, dataUpdatedAt: 0 } as unknown;
  }) as unknown as typeof wagmi.useReadContract);
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-08-28T12:00:00.000Z"));

  mockWriteContract.mockReset();
  mockWriteApprove.mockReset();
  mockReset.mockReset();
  mockRefetchAllowance.mockReset();

  mockUseAccount.mockReturnValue({ address: CONNECTED_ADDRESS } as unknown as ReturnType<typeof wagmi.useAccount>);
  setAllowance(0n);
  setHookStates();
});

afterEach(() => {
  vi.useRealTimers();
  cleanup();
});

async function fillSellForm(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("Target price (USD)"), "4000");
  await user.type(screen.getByLabelText("ETH to deposit"), "0.01");
}

async function selectBuySide(user: ReturnType<typeof userEvent.setup>) {
  await user.selectOptions(screen.getByRole("combobox", { name: "Side" }), "1");
}

describe("CreateOrderForm", () => {
  test("defaults to a Sell order with GreaterOrEqual and the standard slippage/expiry", () => {
    render(<CreateOrderForm />);

    expect(screen.getByRole("combobox", { name: "Side" })).toHaveValue("0");
    expect(screen.getByRole("combobox", { name: "Condition (on ETH price)" })).toHaveValue("0");
    expect(screen.getByLabelText("ETH to deposit")).toBeInTheDocument();
    expect(screen.getByLabelText("Max slippage (bps)")).toHaveValue(100);
    expect(screen.getByLabelText("Expiry (hours from now)")).toHaveValue(24);
  });

  test("rejects a zero deposit amount without calling writeContract", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await user.type(screen.getByLabelText("Target price (USD)"), "4000");
    await user.type(screen.getByLabelText("ETH to deposit"), "0");
    await user.click(screen.getByRole("button", { name: "Create Order" }));

    expect(screen.getByText("Deposit amount must be greater than 0")).toBeInTheDocument();
    expect(mockWriteContract).not.toHaveBeenCalled();
  });

  test("submits a Sell order with side 0, ETH-denominated amount, and matching msg.value", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await fillSellForm(user);
    await user.click(screen.getByRole("button", { name: "Create Order" }));

    expect(mockWriteContract).toHaveBeenCalledOnce();
    const call = mockWriteContract.mock.calls[0]![0];
    expect(call.functionName).toBe("createOrder");
    expect(call.args[0]).toBe(0); // Sell
    expect(call.args[1]).toBe(0); // GreaterOrEqual
    expect(call.args[2]).toBe(4000000000000000000000n); // parseUnits("4000", 18)
    expect(call.args[3]).toBe(10000000000000000n); // parseUnits("0.01", 18)
    expect(call.args[4]).toBe(100n);
    expect(call.args[5]).toBe(1788004800n); // 2026-08-28T12:00:00Z + 24h
    // Sell funds itself from msg.value, which must equal the stated amount.
    expect(call.value).toBe(10000000000000000n);
  });

  test("switching to Buy relabels the deposit field and flips the default condition", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await selectBuySide(user);

    expect(screen.getByLabelText("mUSDC to deposit")).toBeInTheDocument();
    expect(screen.queryByLabelText("ETH to deposit")).not.toBeInTheDocument();
    // Buy is useful with "when ETH falls to", so LessOrEqual is the default.
    expect(screen.getByRole("combobox", { name: "Condition (on ETH price)" })).toHaveValue("1");
  });

  test("switching sides clears the amount, since the two are denominated differently", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await user.type(screen.getByLabelText("ETH to deposit"), "0.01");
    await selectBuySide(user);

    expect(screen.getByLabelText("mUSDC to deposit")).toHaveValue(null);
  });

  test("a Buy order with insufficient allowance shows Approve instead of Create", async () => {
    const user = userEvent.setup({ delay: null });
    setAllowance(0n);
    render(<CreateOrderForm />);

    await selectBuySide(user);
    await user.type(screen.getByLabelText("mUSDC to deposit"), "25");

    expect(screen.getByRole("button", { name: "Approve mUSDC" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Create Order" })).not.toBeInTheDocument();
  });

  test("clicking Approve requests exactly the order amount, in quoteToken decimals", async () => {
    const user = userEvent.setup({ delay: null });
    setAllowance(0n);
    render(<CreateOrderForm />);

    await selectBuySide(user);
    await user.type(screen.getByLabelText("mUSDC to deposit"), "25");
    await user.click(screen.getByRole("button", { name: "Approve mUSDC" }));

    expect(mockWriteApprove).toHaveBeenCalledOnce();
    const call = mockWriteApprove.mock.calls[0]![0];
    expect(call.functionName).toBe("approve");
    // 25 mUSDC at 6 decimals — not 18. Getting this wrong would approve a
    // wildly incorrect amount.
    expect(call.args[1]).toBe(25000000n);
  });

  test("a Buy order with sufficient allowance skips approval and submits with side 1 and zero value", async () => {
    const user = userEvent.setup({ delay: null });
    setAllowance(1000000000n); // far above the order amount
    render(<CreateOrderForm />);

    await selectBuySide(user);
    await user.type(screen.getByLabelText("Target price (USD)"), "2000");
    await user.type(screen.getByLabelText("mUSDC to deposit"), "25");
    await user.click(screen.getByRole("button", { name: "Create Order" }));

    expect(mockWriteContract).toHaveBeenCalledOnce();
    const call = mockWriteContract.mock.calls[0]![0];
    expect(call.args[0]).toBe(1); // Buy
    expect(call.args[1]).toBe(1); // LessOrEqual (Buy default)
    expect(call.args[3]).toBe(25000000n); // 6-decimal deposit
    // Buy's deposit is pulled as quoteToken; the contract rejects stray ETH.
    expect(call.value).toBe(0n);
  });

  test("shows 'Confirm in wallet...' while the create prompt is pending", () => {
    setHookStates({ create: { isPending: true } });
    render(<CreateOrderForm />);

    expect(screen.getByRole("button", { name: "Confirm in wallet..." })).toBeDisabled();
  });

  test("shows 'Creating order...' while waiting for the transaction receipt", () => {
    setHookStates({ create: { data: "0xabc" }, createReceipt: { isLoading: true } });
    render(<CreateOrderForm />);

    expect(screen.getByRole("button", { name: "Creating order..." })).toBeDisabled();
  });

  test("shows the decoded revert message when the create transaction errors", () => {
    setHookStates({ create: { error: new Error("user rejected the request") } });
    render(<CreateOrderForm />);

    expect(screen.getByText("user rejected the request")).toBeInTheDocument();
  });

  test("shows a success message with an Etherscan link once the transaction confirms", () => {
    const hash = "0xbcf21a948ab0600f77496c99acfb6a8f1d5cc1f66272fa93f07c55b278dadb3a";
    setHookStates({ create: { data: hash }, createReceipt: { isSuccess: true } });
    render(<CreateOrderForm />);

    expect(screen.getByText(/Order created/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "view on Etherscan" })).toHaveAttribute(
      "href",
      `https://sepolia.etherscan.io/tx/${hash}`,
    );
  });

  test("does not show a 'Create another' button — the form stays as-is after success", () => {
    const hash = "0xbcf21a948ab0600f77496c99acfb6a8f1d5cc1f66272fa93f07c55b278dadb3a";
    setHookStates({ create: { data: hash }, createReceipt: { isSuccess: true } });
    render(<CreateOrderForm />);

    expect(screen.queryByRole("button", { name: "Create another" })).not.toBeInTheDocument();
  });
});
