/**
 * 注册域名（PSL 级）推导。
 *
 * 说明：这里使用内置的常用公共后缀表做离线推导，不访问网络、不下载 PSL。
 * 覆盖 ICANN 常见后缀与常见二级后缀（如 com.cn / co.uk）；未收录的后缀按
 * “最后两段”退化，不会把整段主机名当成公共后缀。
 */
const SUFFIX_TEXT: string =
  'com net org edu gov mil int info biz name pro aero coop museum travel jobs mobi asia tel cat ' +
  'io ai app dev xyz online site tech store cloud club space website live top vip ltd group ' +
  'cn com.cn net.cn org.cn gov.cn edu.cn ac.cn ' +
  'hk com.hk net.hk org.hk edu.hk gov.hk idv.hk ' +
  'tw com.tw net.tw org.tw edu.tw gov.tw idv.tw ' +
  'uk co.uk org.uk me.uk ltd.uk plc.uk net.uk ac.uk gov.uk ' +
  'jp co.jp ne.jp or.jp ac.jp go.jp ed.jp gr.jp lg.jp ' +
  'kr co.kr ne.kr or.kr re.kr go.kr ac.kr ' +
  'sg com.sg net.sg org.sg edu.sg gov.sg ' +
  'au com.au net.au org.au edu.au gov.au id.au asn.au ' +
  'nz co.nz net.nz org.nz govt.nz ac.nz geek.nz ' +
  'ca com.ca net.ca org.ca gc.ca ' +
  'in co.in net.in org.in firm.in gen.in ind.in ac.in edu.in gov.in ' +
  'br com.br net.br org.br gov.br edu.br art.br blog.br ' +
  'mx com.mx net.mx org.mx gob.mx edu.mx ' +
  'ar com.ar net.ar org.ar gob.ar edu.ar ' +
  'cl com.cl net.cl org.cl gob.cl ' +
  'za co.za net.za org.za gov.za ac.za web.za ' +
  'tr com.tr net.tr org.tr gov.tr edu.tr ' +
  'ru com.ru net.ru org.ru msk.ru spb.ru ' +
  'ua com.ua net.ua org.ua gov.ua ' +
  'kz com.kz net.kz org.kz gov.kz ' +
  'by com.by net.by org.by gov.by ' +
  'id co.id net.id org.id web.id ac.id go.id ' +
  'my com.my net.my org.my gov.my edu.my ' +
  'th co.th in.th ac.th go.th net.th or.th ' +
  'vn com.vn net.vn org.vn gov.vn edu.vn ' +
  'ph com.ph net.ph org.ph gov.ph edu.ph ' +
  'pk com.pk net.pk org.pk gov.pk edu.pk ' +
  'eg com.eg net.eg org.eg gov.eg edu.eg ' +
  'sa com.sa net.sa org.sa gov.sa edu.sa ' +
  'ae co.ae net.ae org.ae gov.ae ac.ae ' +
  'de fr it es nl be at ch se no fi dk ie pt pl cz gr il co.il org.il ' +
  'eu am az ge md uz ' +
  'me tv cc ws ly to fm gg je im is li lu mt cy ee lv lt sk si hr rs bg ro hu';

const SUFFIXES: Set<string> = new Set<string>(SUFFIX_TEXT.split(' '));

const IPV4 = new RegExp('^[0-9]{1,3}(\\.[0-9]{1,3}){3}$');

export class RegisteredDomain {
  /**
   * 返回 host 的注册域名（PSL 级）。IP 字面量与单标签主机原样返回。
   */
  static of(host: string): string {
    const normalized = host.trim().toLowerCase();
    if (normalized.length === 0) {
      return '';
    }
    if (normalized.startsWith('[') || normalized.indexOf(':') >= 0 || IPV4.test(normalized)) {
      return normalized;
    }
    const labels = normalized.split('.');
    if (labels.length <= 1) {
      return normalized;
    }
    let matched = 0;
    // 最长后缀匹配：从整段主机开始向下找。
    for (let i = 0; i < labels.length; i += 1) {
      const candidate = labels.slice(i).join('.');
      if (SUFFIXES.has(candidate)) {
        matched = labels.length - i;
        break;
      }
    }
    if (matched === 0) {
      // 未收录后缀：按最后两段退化为注册域名。
      return labels.slice(labels.length - 2).join('.');
    }
    if (matched >= labels.length) {
      // 整个主机就是一个公共后缀（如直接输入 "com.cn"），原样返回。
      return normalized;
    }
    return labels.slice(labels.length - matched - 1).join('.');
  }

  /** 主域名标签（注册域名去掉公共后缀），用于相似域名提示。 */
  static baseLabel(domain: string): string {
    const labels = domain.split('.');
    if (labels.length <= 1) {
      return domain;
    }
    for (let i = 0; i < labels.length; i += 1) {
      if (SUFFIXES.has(labels.slice(i).join('.'))) {
        return labels.slice(0, i).join('.');
      }
    }
    return labels.length >= 2 ? labels[labels.length - 2] : domain;
  }

  /**
   * 与非信任域名的相似性提示（只提示，不拦截）。
   *
   * - 主域名相同、公共后缀不同：`example.com` vs `example.org`；
   * - 编辑距离很小：`example` vs `examp1e`。
   */
  static similarTo(domain: string, knownDomains: string[]): string[] {
    const hints: string[] = [];
    const base = RegisteredDomain.baseLabel(domain);
    for (let i = 0; i < knownDomains.length; i += 1) {
      const other = knownDomains[i].toLowerCase();
      if (other.length === 0 || other === domain.toLowerCase()) {
        continue;
      }
      const otherBase = RegisteredDomain.baseLabel(other);
      if (base.length > 0 && base === otherBase) {
        hints.push(`与已信任站点 ${other} 主域名相同、后缀不同`);
        continue;
      }
      if (RegisteredDomain.distance(base, otherBase) <= 1 && base.length >= 3) {
        hints.push(`与已信任站点 ${other} 名称高度相似`);
      }
    }
    return hints;
  }

  private static distance(a: string, b: string): number {
    if (a === b) {
      return 0;
    }
    if (a.length === 0) {
      return b.length;
    }
    if (b.length === 0) {
      return a.length;
    }
    let previous: number[] = [];
    for (let j = 0; j <= b.length; j += 1) {
      previous.push(j);
    }
    for (let i = 1; i <= a.length; i += 1) {
      const current: number[] = [i];
      for (let j = 1; j <= b.length; j += 1) {
        const cost = a.charAt(i - 1) === b.charAt(j - 1) ? 0 : 1;
        const inserted = current[j - 1] + 1;
        const deleted = previous[j] + 1;
        const replaced = previous[j - 1] + cost;
        current.push(Math.min(inserted, Math.min(deleted, replaced)));
      }
      previous = current;
    }
    return previous[b.length];
  }
}
