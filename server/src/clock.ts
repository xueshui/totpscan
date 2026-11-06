/** 可注入时钟，便于测试时间窗、过期与限流。 */
export interface Clock {
  /** Unix 毫秒。 */
  now(): number;
}

export const systemClock: Clock = {
  now: () => Date.now(),
};

/** 手动时钟：测试中用于推进时间。 */
export class ManualClock implements Clock {
  private current: number;

  constructor(startEpochMs = 1762396800000) {
    this.current = startEpochMs;
  }

  now(): number {
    return this.current;
  }

  advanceMs(ms: number): void {
    this.current += ms;
  }

  set(epochMs: number): void {
    this.current = epochMs;
  }
}
