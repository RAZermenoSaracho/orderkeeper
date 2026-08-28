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
    useReadContract: vi.fn(),
    useWriteContract: vi.fn(),
    useWaitForTransactionReceipt: vi.fn(),
  };
});

const mockUseReadContract = vi.mocked(wagmi.useReadContract);
const mockUseWriteContract = vi.mocked(wagmi.useWriteContract);
const mockUseWaitForTransactionReceipt = vi.mocked(wagmi.useWaitForTransactionReceipt);

const mockWriteContract = vi.fn();
const mockReset = vi.fn();

// Real return types are large discriminated unions (idle/pending/success/
// error variants with many mutually-exclusive fields) — these helpers only
// need the handful of fields CreateOrderForm actually reads, so they're
// typed loosely and double-cast, rather than constructing a fully valid
// union member for every test.
function setWriteContractState(overrides: Record<string, unknown> = {}) {
  mockUseWriteContract.mockReturnValue({
    writeContract: mockWriteContract,
    data: undefined,
    isPending: false,
    error: null,
    reset: mockReset,
    ...overrides,
  } as unknown as ReturnType<typeof wagmi.useWriteContract>);
}

function setReceiptState(overrides: Record<string, unknown> = {}) {
  mockUseWaitForTransactionReceipt.mockReturnValue({
    isLoading: false,
    isSuccess: false,
    ...overrides,
  } as unknown as ReturnType<typeof wagmi.useWaitForTransactionReceipt>);
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-08-28T12:00:00.000Z"));

  mockWriteContract.mockReset();
  mockReset.mockReset();
  // LivePrice's read — not under test here, just needs a stable shape.
  mockUseReadContract.mockReturnValue({
    data: undefined,
    error: null,
    dataUpdatedAt: 0,
  } as unknown as ReturnType<typeof wagmi.useReadContract>);
  setWriteContractState();
  setReceiptState();
});

afterEach(() => {
  vi.useRealTimers();
  cleanup();
});

async function fillValidForm(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("Target price (USD)"), "4000");
  await user.type(screen.getByLabelText("ETH to deposit"), "0.01");
}

describe("CreateOrderForm", () => {
  test("renders with WETH selected and default slippage/expiry values", () => {
    render(<CreateOrderForm />);

    expect(screen.getByRole("combobox", { name: "Asset" })).toHaveValue("0");
    expect(screen.getByText(/WETH/)).toBeInTheDocument();
    expect(screen.getByLabelText("Max slippage (bps)")).toHaveValue(100);
    expect(screen.getByLabelText("Expiry (hours from now)")).toHaveValue(24);
  });

  test("rejects a zero ETH amount without calling writeContract", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await user.type(screen.getByLabelText("Target price (USD)"), "4000");
    await user.type(screen.getByLabelText("ETH to deposit"), "0");
    await user.click(screen.getByRole("button", { name: "Create Order" }));

    expect(screen.getByText("ETH amount must be greater than 0")).toBeInTheDocument();
    expect(mockWriteContract).not.toHaveBeenCalled();
  });

  test("submits createOrder with correctly parsed args for the default (WETH) asset", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await fillValidForm(user);
    await user.click(screen.getByRole("button", { name: "Create Order" }));

    expect(mockWriteContract).toHaveBeenCalledOnce();
    const call = mockWriteContract.mock.calls[0]![0];
    expect(call.functionName).toBe("createOrder");
    expect(call.args[0]).toBe("0x1287B650e882514447b96a49a0f8DC1040B26d2A"); // WETH
    expect(call.args[1]).toBe(0); // GreaterOrEqual (default)
    expect(call.args[2]).toBe(4000000000000000000000n); // parseUnits("4000", 18)
    expect(call.args[3]).toBe(100n); // default max slippage
    expect(call.args[4]).toBe(1788004800n); // 2026-08-28T12:00:00Z + 24h, in seconds
    expect(call.value).toBe(10000000000000000n); // parseEther("0.01")
  });

  test("submits createOrder with the selected asset's address, not WETH's", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await user.selectOptions(screen.getByRole("combobox", { name: "Asset" }), "3"); // USDC
    await fillValidForm(user);
    await user.click(screen.getByRole("button", { name: "Create Order" }));

    expect(mockWriteContract.mock.calls[0]![0].args[0]).toBe("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  });

  test("submits condition=1 (LessOrEqual) when selected", async () => {
    const user = userEvent.setup({ delay: null });
    render(<CreateOrderForm />);

    await user.selectOptions(screen.getByRole("combobox", { name: "Condition" }), "1");
    await fillValidForm(user);
    await user.click(screen.getByRole("button", { name: "Create Order" }));

    expect(mockWriteContract.mock.calls[0]![0].args[1]).toBe(1)
  });

  test("shows 'Confirm in wallet...' while the wallet prompt is pending", () => {
    setWriteContractState({ isPending: true });
    render(<CreateOrderForm />);

    expect(screen.getByRole("button", { name: "Confirm in wallet..." })).toBeDisabled();
  });

  test("shows 'Creating order...' while waiting for the transaction receipt", () => {
    setWriteContractState({ data: "0xabc" as `0x${string}` });
    setReceiptState({ isLoading: true });
    render(<CreateOrderForm />);

    expect(screen.getByRole("button", { name: "Creating order..." })).toBeDisabled();
  });

  test("shows the decoded revert message when writeContract errors", () => {
    setWriteContractState({ error: new Error("user rejected the request") });
    render(<CreateOrderForm />);

    expect(screen.getByText("user rejected the request")).toBeInTheDocument();
  });

  test("shows a success message with an Etherscan link once the transaction confirms", () => {
    const hash = "0xbcf21a948ab0600f77496c99acfb6a8f1d5cc1f66272fa93f07c55b278dadb3a" as `0x${string}`;
    setWriteContractState({ data: hash });
    setReceiptState({ isSuccess: true });
    render(<CreateOrderForm />);

    expect(screen.getByText(/Order created/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "view on Etherscan" })).toHaveAttribute(
      "href",
      `https://sepolia.etherscan.io/tx/${hash}`,
    );
  });

  test("'Create another' resets the write state", async () => {
    const user = userEvent.setup({ delay: null });
    const hash = "0xbcf21a948ab0600f77496c99acfb6a8f1d5cc1f66272fa93f07c55b278dadb3a" as `0x${string}`;
    setWriteContractState({ data: hash });
    setReceiptState({ isSuccess: true });
    render(<CreateOrderForm />);

    await user.click(screen.getByRole("button", { name: "Create another" }));

    expect(mockReset).toHaveBeenCalledOnce();
  });
});
