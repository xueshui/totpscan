import { promptAction } from '@kit.ArkUI';
import { TotpError } from 'totpscan';

export function toast(message: string): void {
  promptAction.showToast({ message: message, duration: 2000 });
}

/** 错误转中文用户文案；不拼接 message，避免把实现细节或敏感值带到界面。 */
export function errorText(error: Object): string {
  const known = error as TotpError;
  if (known !== null && known !== undefined && typeof known.userMessage === 'string' && known.userMessage.length > 0) {
    return known.userMessage;
  }
  return '操作失败，请稍后重试';
}

/** 从 URL 中取出 host[:port]，仅用于界面展示。 */
export function hostOf(url: string): string {
  const index = url.indexOf('://');
  const rest = index >= 0 ? url.substring(index + 3) : url;
  const slash = rest.indexOf('/');
  return slash >= 0 ? rest.substring(0, slash) : rest;
}

export function twoDigits(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
