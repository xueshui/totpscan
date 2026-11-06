/**
 * 页面侧内容脚本（按需注入）：
 * 1) 在当前页面 DOM 中自动寻找并识别二维码（BarcodeDetector 优先，jsQR 兜底）；
 * 2) 把动态码写入当前聚焦的输入框；
 * 3) 由登录页同源发起扫码提交（携带会话 Cookie，且不跟随重定向）。
 *
 * 该脚本不会主动发起任何网络请求，只有收到扩展消息时才执行对应动作。
 */

(() => {
  if (globalThis.__TOTPSCAN_CONTENT_READY__) {
    return;
  }
  globalThis.__TOTPSCAN_CONTENT_READY__ = true;

  let lastEditable = null;
  let qrDetector = null;
  let qrDetectorChecked = false;

  const EDITABLE_INPUT_TYPES = new Set([
    "text",
    "search",
    "email",
    "tel",
    "url",
    "number",
    "password",
    "",
  ]);

  function isEditable(element) {
    if (!element || !(element instanceof Element)) {
      return false;
    }
    if (element instanceof HTMLTextAreaElement) {
      return !element.disabled && !element.readOnly;
    }
    if (element instanceof HTMLInputElement) {
      return !element.disabled && !element.readOnly && EDITABLE_INPUT_TYPES.has(element.type);
    }
    return element.isContentEditable === true;
  }

  function isVisible(element) {
    if (!element || !element.isConnected) {
      return false;
    }
    const rects = element.getClientRects();
    return rects.length > 0 && rects[0].width > 0 && rects[0].height > 0;
  }

  document.addEventListener(
    "focusin",
    (event) => {
      const target = event.composedPath ? event.composedPath()[0] : event.target;
      if (isEditable(target)) {
        lastEditable = target;
      }
    },
    true,
  );

  function deepActiveElement() {
    let element = document.activeElement;
    while (element?.shadowRoot?.activeElement) {
      element = element.shadowRoot.activeElement;
    }
    return element;
  }

  function findInputTarget() {
    const active = deepActiveElement();
    if (isEditable(active) && isVisible(active)) {
      return active;
    }
    if (lastEditable && lastEditable.isConnected && isEditable(lastEditable) && isVisible(lastEditable)) {
      return lastEditable;
    }
    return null;
  }

  function setNativeValue(element, value) {
    if (element instanceof HTMLTextAreaElement) {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set;
      if (setter) {
        setter.call(element, value);
        return;
      }
    }
    if (element instanceof HTMLInputElement) {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
      if (setter) {
        setter.call(element, value);
        return;
      }
    }
    element.textContent = value;
  }

  function fillCode(code) {
    if (typeof code !== "string" || !/^[0-9]{6,8}$/.test(code)) {
      return { ok: false, reason: "BAD_CODE" };
    }
    const target = findInputTarget();
    if (!target) {
      return {
        ok: false,
        reason: "NO_FOCUSED_FIELD",
      };
    }
    target.focus({ preventScroll: false });
    setNativeValue(target, code);
    try {
      target.dispatchEvent(
        new InputEvent("input", {
          bubbles: true,
          composed: true,
          inputType: "insertText",
          data: code,
        }),
      );
    } catch {
      target.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    }
    target.dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    try {
      target.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, key: "Unidentified" }));
    } catch {
      // 某些页面不接受合成键盘事件，忽略即可
    }
    if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) {
      const end = target.value.length;
      try {
        target.setSelectionRange(end, end);
      } catch {
        // number 类型不支持 setSelectionRange
      }
    }
    return {
      ok: true,
      tag: target.tagName.toLowerCase(),
      type: target instanceof HTMLInputElement ? target.type : "editable",
      fieldLength: target.value?.length ?? 0,
    };
  }

  async function submitSameOrigin(targetUrl, body) {
    let parsed;
    try {
      parsed = new URL(targetUrl);
    } catch {
      return { ok: false, reason: "BAD_URL" };
    }
    if (parsed.origin !== location.origin) {
      return {
        ok: false,
        reason: "CROSS_ORIGIN",
      };
    }
    let response;
    try {
      response = await fetch(parsed.href, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        credentials: "include",
        cache: "no-store",
        redirect: "manual",
      });
    } catch {
      return { ok: false, reason: "NETWORK_ERROR" };
    }
    let text = "";
    try {
      text = (await response.text()).slice(0, 1000);
    } catch {
      text = "";
    }
    return { ok: true, status: response.status, bodyText: text };
  }

  function collectElements() {
    const found = [];
    const seen = new Set();
    const selector = "img, canvas, svg, video";
    function visit(root) {
      if (!root) {
        return;
      }
      let list;
      try {
        list = root.querySelectorAll(selector);
      } catch {
        return;
      }
      for (const element of list) {
        if (seen.has(element)) {
          continue;
        }
        seen.add(element);
        const rect = element.getBoundingClientRect();
        if (rect.width < 40 || rect.height < 40) {
          continue;
        }
        found.push(element);
        if (found.length >= 60) {
          return;
        }
      }
      const all = root.querySelectorAll("*");
      for (const element of all) {
        if (element.shadowRoot) {
          visit(element.shadowRoot);
        }
      }
    }
    visit(document);
    return found;
  }

  async function getDetector() {
    if (qrDetectorChecked) {
      return qrDetector;
    }
    qrDetectorChecked = true;
    if (typeof globalThis.BarcodeDetector !== "function") {
      return null;
    }
    try {
      const formats = await BarcodeDetector.getSupportedFormats();
      if (Array.isArray(formats) && formats.includes("qr_code")) {
        qrDetector = new BarcodeDetector({ formats: ["qr_code"] });
      }
    } catch {
      qrDetector = null;
    }
    return qrDetector;
  }

  function createCanvas(width, height) {
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    return canvas;
  }

  function loadSvgImage(svg) {
    return new Promise((resolve) => {
      let markup = new XMLSerializer().serializeToString(svg);
      if (!/xmlns=/.test(markup)) {
        markup = markup.replace("<svg", '<svg xmlns="http://www.w3.org/2000/svg"');
      }
      const blob = new Blob([markup], { type: "image/svg+xml;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const image = new Image();
      image.onload = () => {
        URL.revokeObjectURL(url);
        resolve(image);
      };
      image.onerror = () => {
        URL.revokeObjectURL(url);
        resolve(null);
      };
      image.src = url;
    });
  }

  async function elementToImageData(element) {
    let source = element;
    if (element instanceof SVGSVGElement) {
      source = await loadSvgImage(element);
      if (!source) {
        return null;
      }
    }
    let width = 0;
    let height = 0;
    if (source instanceof HTMLImageElement) {
      if (!source.complete || source.naturalWidth === 0) {
        return null;
      }
      width = source.naturalWidth;
      height = source.naturalHeight;
    } else if (source instanceof HTMLVideoElement) {
      if (source.readyState < 2 || source.videoWidth === 0) {
        return null;
      }
      width = source.videoWidth;
      height = source.videoHeight;
    } else if (source instanceof HTMLCanvasElement) {
      width = source.width;
      height = source.height;
    } else {
      return null;
    }
    if (width < 1 || height < 1) {
      return null;
    }
    const maxSide = 1400;
    const scale = Math.min(1, maxSide / Math.max(width, height));
    const canvasWidth = Math.max(1, Math.round(width * scale));
    const canvasHeight = Math.max(1, Math.round(height * scale));
    const canvas = createCanvas(canvasWidth, canvasHeight);
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context) {
      return null;
    }
    try {
      context.drawImage(source, 0, 0, canvasWidth, canvasHeight);
      return {
        imageData: context.getImageData(0, 0, canvasWidth, canvasHeight),
        width: canvasWidth,
        height: canvasHeight,
      };
    } catch {
      // 跨域图片会污染 canvas，无法读取像素
      return null;
    }
  }

  function rotateImageData(imageData, turns) {
    let current = imageData;
    for (let turn = 0; turn < turns; turn += 1) {
      const { width, height, data } = current;
      const rotated = new ImageData(height, width);
      for (let y = 0; y < height; y += 1) {
        for (let x = 0; x < width; x += 1) {
          const sourceIndex = (y * width + x) * 4;
          const targetX = height - 1 - y;
          const targetY = x;
          const targetIndex = (targetY * height + targetX) * 4;
          rotated.data[targetIndex] = data[sourceIndex];
          rotated.data[targetIndex + 1] = data[sourceIndex + 1];
          rotated.data[targetIndex + 2] = data[sourceIndex + 2];
          rotated.data[targetIndex + 3] = data[sourceIndex + 3];
        }
      }
      current = rotated;
    }
    return current;
  }

  function decodeWithJsQr(imageData, width, height) {
    if (typeof globalThis.jsQR !== "function") {
      return [];
    }
    const attempts = [0, 1, 2, 3];
    for (const turns of attempts) {
      const data = turns === 0 ? imageData : rotateImageData(imageData, turns);
      try {
        const result = jsQR(data.data, data.width, data.height, {
          inversionAttempts: "attemptBoth",
        });
        if (result?.data) {
          return [{ text: result.data, source: "jsQR" }];
        }
      } catch {
        // 继续尝试其他方向
      }
    }
    return [];
  }

  async function scanPageQr() {
    const results = [];
    const seen = new Set();
    const elements = collectElements();
    const detector = await getDetector();
    let index = 0;
    for (const element of elements) {
      index += 1;
      let detections = [];
      if (detector) {
        try {
          const found = await detector.detect(element);
          detections = (found ?? []).map((item) => item.rawValue).filter(Boolean);
        } catch {
          detections = [];
        }
      }
      if (detections.length === 0) {
        const image = await elementToImageData(element);
        if (image) {
          detections = decodeWithJsQr(image.imageData, image.width, image.height).map((item) => item.text);
        }
      }
      for (const text of detections) {
        if (!seen.has(text)) {
          seen.add(text);
          results.push({
            text,
            source: element.tagName.toLowerCase(),
            index,
            frameUrl: location.href,
            isTopFrame: window === top,
          });
        }
      }
      if (results.length >= 12) {
        break;
      }
    }
    return results;
  }

  globalThis.__TOTPSCAN_SCAN_PAGE__ = scanPageQr;

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || typeof message.type !== "string") {
      return false;
    }
    if (message.type === "TOTPSCAN_PING") {
      sendResponse({ ok: true, url: location.href, isTopFrame: window === top });
      return false;
    }
    if (message.type === "TOTPSCAN_FILL_CODE") {
      sendResponse(fillCode(message.code));
      return false;
    }
    if (message.type === "TOTPSCAN_SUBMIT") {
      submitSameOrigin(message.url, message.body).then(sendResponse).catch(() => {
        sendResponse({ ok: false, reason: "NETWORK_ERROR" });
      });
      return true;
    }
    return false;
  });
})();
