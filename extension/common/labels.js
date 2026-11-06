/**
 * 数据层占位名。
 *
 * 导入 / 手动录入时若缺少 issuer、account，会写入一个占位名并落库；
 * 占位名会出现在账户列表里，因此必须随界面语言变化。
 * 由 i18n 在每次切换语言时注入当前语言的文案，解析逻辑只读这里。
 */

export const labels = {
  importIssuer: "导入",
  unnamedAccount: "未命名账户",
  unnamedIssuer: "未命名签发方",
};

export function setLabels(next) {
  Object.assign(labels, next);
}
