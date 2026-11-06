interface ExportGrant {
  localId: string;
  expiresAtMs: number;
}

const GRANT_TTL_MS = 60 * 1000;

/**
 * 导出二维码的一次性授权凭证（仅本进程内存）。
 *
 * 账户详情页在本地认证通过后写入，导出页消费；不持久化、不写日志。
 */
let current: ExportGrant | null = null;

export function grantExport(localId: string): void {
  current = {
    localId: localId,
    expiresAtMs: Date.now() + GRANT_TTL_MS
  };
}

export function consumeExportGrant(localId: string): boolean {
  const grant = current;
  current = null;
  if (grant === null) {
    return false;
  }
  return grant.localId === localId && Date.now() <= grant.expiresAtMs;
}

export function revokeExportGrant(): void {
  current = null;
}
