import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import * as wagmi from "wagmi";
import { sepolia } from "wagmi/chains";
import Layout from "./Layout.tsx";

vi.mock("wagmi", async (importOriginal) => {
  const actual = await importOriginal<typeof wagmi>();
  return {
    ...actual,
    useAccount: vi.fn(),
    useBalance: vi.fn(),
    useConnect: vi.fn(),
    useDisconnect: vi.fn(),
  };
});

vi.mock("../components/CreateOrderForm.tsx", () => ({
  default: () => <div data-testid="create-order-form" />,
}));
vi.mock("../components/OrderList.tsx", () => ({
  default: () => <div data-testid="order-list" />,
}));

const mockUseAccount = vi.mocked(wagmi.useAccount);
const mockUseBalance = vi.mocked(wagmi.useBalance);
const mockUseConnect = vi.mocked(wagmi.useConnect);
const mockUseDisconnect = vi.mocked(wagmi.useDisconnect);

const mockConnect = vi.fn();
const mockDisconnect = vi.fn();

function setConnected(overrides: Record<string, unknown> = {}) {
  mockUseAccount.mockReturnValue({
    address: "0x369A2e8133Ea0670fCC7C96ff3220c43D3ffeA7A",
    isConnected: true,
    chainId: sepolia.id,
    ...overrides,
  } as unknown as ReturnType<typeof wagmi.useAccount>);
}

beforeEach(() => {
  mockConnect.mockReset();
  mockDisconnect.mockReset();
  mockUseAccount.mockReturnValue({
    address: undefined,
    isConnected: false,
  } as unknown as ReturnType<typeof wagmi.useAccount>);
  mockUseBalance.mockReturnValue({ data: undefined } as unknown as ReturnType<typeof wagmi.useBalance>);
  mockUseConnect.mockReturnValue({
    connect: mockConnect,
    connectors: [{ type: "injected", id: "injected", name: "Injected" }],
    isPending: false,
  } as unknown as ReturnType<typeof wagmi.useConnect>);
  mockUseDisconnect.mockReturnValue({ disconnect: mockDisconnect } as unknown as ReturnType<typeof wagmi.useDisconnect>);
});

afterEach(() => {
  cleanup();
});

describe("Layout", () => {
  test("shows onboarding and a wallet connection action while disconnected", () => {
    render(<Layout />);

    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Automated limit orders on Sepolia" })).toBeInTheDocument();
    expect(screen.queryByTestId("create-order-form")).not.toBeInTheDocument();
    expect(screen.queryByTestId("order-list")).not.toBeInTheDocument();
  });

  test("keeps installation guidance available when no injected wallet exists", () => {
    mockUseConnect.mockReturnValue({
      connect: mockConnect,
      connectors: [],
      isPending: false,
    } as unknown as ReturnType<typeof wagmi.useConnect>);

    render(<Layout />);

    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeDisabled();
    expect(screen.getByRole("link", { name: "Need a wallet? Get MetaMask" })).toBeInTheDocument();
  });

  test("connects with the injected wallet connector", async () => {
    const user = userEvent.setup();
    render(<Layout />);

    await user.click(screen.getByRole("button", { name: "Connect Wallet" }));

    expect(mockConnect).toHaveBeenCalledWith({ connector: expect.objectContaining({ type: "injected" }) });
  });

  test("shows a pending wallet connection", () => {
    mockUseConnect.mockReturnValue({
      connect: mockConnect,
      connectors: [{ type: "injected", id: "injected", name: "Injected" }],
      isPending: true,
    } as unknown as ReturnType<typeof wagmi.useConnect>);

    render(<Layout />);

    expect(screen.getByRole("button", { name: "Connecting..." })).toBeDisabled();
  });

  test("shows wallet details and the application while connected", () => {
    setConnected();
    mockUseBalance.mockReturnValue({
      data: { value: 1500000000000000000n, decimals: 18, symbol: "ETH" },
    } as unknown as ReturnType<typeof wagmi.useBalance>);

    render(<Layout />);

    expect(screen.getByText("1.5 ETH")).toBeInTheDocument();
    expect(screen.getByText(/0x369A\.\.\.eA7A/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Disconnect" })).toBeInTheDocument();
    expect(screen.getByTestId("create-order-form")).toBeInTheDocument();
    expect(screen.getByTestId("order-list")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Automated limit orders on Sepolia" })).not.toBeInTheDocument();
  });

  test("disconnects the connected wallet", async () => {
    const user = userEvent.setup();
    setConnected();
    render(<Layout />);

    await user.click(screen.getByRole("button", { name: "Disconnect" }));

    expect(mockDisconnect).toHaveBeenCalledOnce();
  });

  test("shows the application with a warning on the wrong network", () => {
    setConnected({ chainId: 1 });

    render(<Layout />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Wrong network. Switch your wallet to Sepolia testnet before creating an order.",
    );
    expect(screen.getByTestId("create-order-form")).toBeInTheDocument();
    expect(screen.getByTestId("order-list")).toBeInTheDocument();
  });

  test("does not warn a wallet connected to Sepolia", () => {
    setConnected();

    render(<Layout />);

    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
});
