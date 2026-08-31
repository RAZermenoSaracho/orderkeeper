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
    expect(screen.getByText(/Connect your wallet to create and view your orders/)).toBeInTheDocument();
  });

  test("links to the official MetaMask download page safely", () => {
    render(<Onboarding />);

    const link = screen.getByRole("link", { name: "Need a wallet? Get MetaMask" });
    expect(link).toHaveAttribute("href", "https://metamask.io/download/");
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
  });
});
