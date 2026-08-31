import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, test } from "vitest";
import Onboarding from "./Onboarding.tsx";

afterEach(() => {
  cleanup();
});

describe("Onboarding", () => {
  test("explains the wallet and Sepolia requirements", () => {
    render(<Onboarding />);

    expect(screen.getByRole("heading", { name: "Automated limit orders on Sepolia" })).toBeInTheDocument();
    expect(screen.getByText(/MetaMask or another compatible Ethereum wallet/)).toBeInTheDocument();
    expect(screen.getByText(/switch it to Sepolia testnet/)).toBeInTheDocument();
    expect(screen.getByText(/Sepolia ETH for gas and Sell orders/)).toBeInTheDocument();
    expect(screen.getByText(/Buy orders require mock USDC \(mUSDC\)/)).toBeInTheDocument();
    expect(screen.getByText("5000000")).toBeInTheDocument();
    expect(screen.getByText(/Connect your wallet to create and view your orders/)).toBeInTheDocument();
  });

  test("provides safe links to MetaMask and the deployed Sepolia contracts", () => {
    render(<Onboarding />);

    expect(screen.getByRole("link", { name: "Need a wallet? Get MetaMask" })).toHaveAttribute(
      "href",
      "https://metamask.io/download/",
    );
    expect(screen.getByRole("link", { name: "Get test mUSDC" })).toHaveAttribute(
      "href",
      "https://sepolia.etherscan.io/address/0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929#writeContract",
    );
    expect(screen.getByRole("link", { name: "OrderKeeper ↗" })).toHaveAttribute(
      "href",
      "https://sepolia.etherscan.io/address/0x907dC6392df5973aD82816C05E2e15F821054503#code",
    );
    expect(screen.getByRole("link", { name: "Mock USDC ↗" })).toHaveAttribute(
      "href",
      "https://sepolia.etherscan.io/address/0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929#code",
    );

    for (const link of screen.getAllByRole("link")) {
      expect(link).toHaveAttribute("target", "_blank");
      expect(link).toHaveAttribute("rel", "noopener noreferrer");
    }
  });
});
