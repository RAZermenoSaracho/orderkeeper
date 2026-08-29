import { afterEach, describe, expect, test, vi } from "vitest";
import { startPollLoop } from "./pollLoop.js";

afterEach(() => {
  vi.useRealTimers();
});

describe("startPollLoop", () => {
  test("waits for one cycle to finish before scheduling the next", async () => {
    vi.useFakeTimers();
    let finishFirstCycle: (() => void) | undefined;
    const runCycle = vi
      .fn()
      .mockImplementationOnce(() => new Promise<void>((resolve) => (finishFirstCycle = resolve)))
      .mockResolvedValue(undefined);
    const stop = startPollLoop(runCycle, 1_000, vi.fn());

    await vi.advanceTimersByTimeAsync(1_000);
    expect(runCycle).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(10_000);
    expect(runCycle).toHaveBeenCalledTimes(1);

    finishFirstCycle?.();
    await vi.advanceTimersByTimeAsync(1_000);
    expect(runCycle).toHaveBeenCalledTimes(2);

    stop();
  });
});
