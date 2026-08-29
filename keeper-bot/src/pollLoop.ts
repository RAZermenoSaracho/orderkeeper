export function startPollLoop(
  runCycle: () => Promise<void>,
  intervalMs: number,
  onError: (error: unknown) => void,
): () => void {
  let stopped = false;
  let timeout: ReturnType<typeof setTimeout>;

  const tick = async () => {
    try {
      await runCycle();
    } catch (error) {
      onError(error);
    } finally {
      if (!stopped) timeout = setTimeout(tick, intervalMs);
    }
  };

  timeout = setTimeout(tick, intervalMs);
  return () => {
    stopped = true;
    clearTimeout(timeout);
  };
}
