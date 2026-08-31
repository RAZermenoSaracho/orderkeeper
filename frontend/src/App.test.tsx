import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import App from "./App.tsx";

vi.mock("./layout/Layout.tsx", () => ({
  default: () => <div data-testid="layout" />,
}));

afterEach(() => {
  cleanup();
});

describe("App", () => {
  test("renders the application layout", () => {
    render(<App />);

    expect(screen.getByTestId("layout")).toBeInTheDocument();
  });
});
