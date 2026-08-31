import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as wagmi from "wagmi";
import { sepolia } from "wagmi/chains";
import App from "./App.tsx";

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

// App only needs to prove it renders/hides these based on connection
// state — their own internals are covered by CreateOrderForm.test.tsx and
// OrderList.test.tsx.
vi.mock("./components/CreateOrderForm.tsx", () => ({
  default: () => <div data-testid="create-order-form" />,
}));
vi.mock("./components/OrderList.tsx", () => ({
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

describe("App", () => {
  test('shows onboarding and "Connect Wallet" while hiding order UI when disconnected', () => {
    render(<App />);

    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Automated limit orders on Sepolia" })).toBeInTheDocument();
    expect(screen.getByText(/Sepolia ETH for gas and Sell orders/)).toBeInTheDocument();
    expect(screen.queryByTestId("create-order-form")).not.toBeInTheDocument();
    expect(screen.queryByTestId("order-list")).not.toBeInTheDocument();
  });

  test("links wallet-less visitors to the official MetaMask download page", () => {
    mockUseConnect.mockReturnValue({
      connect: mockConnect,
      connectors: [],
      isPending: false,
    } as unknown as ReturnType<typeof wagmi.useConnect>);

    render(<App />);

    const link = screen.getByRole("link", { name: "Need a wallet? Get MetaMask" });
    expect(link).toHaveAttribute("href", "https://metamask.io/download/");
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeDisabled();
  });

  test('clicking "Connect Wallet" calls connect() with the injected connector', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole("button", { name: "Connect Wallet" }));

    expect(mockConnect).toHaveBeenCalledWith({ connector: expect.objectContaining({ type: "injected" }) });
  });

  test('shows "Connecting..." and disables the button while a connection is pending', () => {
    mockUseConnect.mockReturnValue({
      connect: mockConnect,
      connectors: [{ type: "injected", id: "injected", name: "Injected" }],
      isPending: true,
    } as unknown as ReturnType<typeof wagmi.useConnect>);

    render(<App />);

    expect(screen.getByRole("button", { name: "Connecting..." })).toBeDisabled();
  });

  test("disables Connect Wallet when no injected connector is available", () => {
    mockUseConnect.mockReturnValue({
      connect: mockConnect,
      connectors: [],
      isPending: false,
    } as unknown as ReturnType<typeof wagmi.useConnect>);

    render(<App />);

    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeDisabled();
  });

  test("shows address, balance, Disconnect, and the order UI once connected", () => {
    setConnected();
    mockUseBalance.mockReturnValue({
      data: { value: 1500000000000000000n, decimals: 18, symbol: "ETH" },
    } as unknown as ReturnType<typeof wagmi.useBalance>);

    render(<App />);

    expect(screen.getByText(/0x369A\.\.\.eA7A/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Disconnect" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Automated limit orders on Sepolia" })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Need a wallet? Get MetaMask" })).not.toBeInTheDocument();
    expect(screen.getByTestId("create-order-form")).toBeInTheDocument();
    expect(screen.getByTestId("order-list")).toBeInTheDocument();
  });

  test("warns a connected wallet on the wrong network", () => {
    setConnected({ chainId: 1 });

    render(<App />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Wrong network. Switch your wallet to Sepolia testnet before creating an order.",
    );
  });

  test("does not show a network warning when connected to Sepolia", () => {
    setConnected();

    render(<App />);

    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  test('shows "..." for the balance while it is still loading', () => {
    setConnected();
    mockUseBalance.mockReturnValue({ data: undefined } as unknown as ReturnType<typeof wagmi.useBalance>);

    render(<App />);

    expect(screen.getByText("...")).toBeInTheDocument();
  });

  test("clicking Disconnect calls disconnect()", async () => {
    const user = userEvent.setup();
    setConnected();

    render(<App />);
    await user.click(screen.getByRole("button", { name: "Disconnect" }));

    expect(mockDisconnect).toHaveBeenCalledOnce();
  });
});
