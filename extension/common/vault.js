/**
 * 本地加密保险库。
 *
 * 浏览器扩展无法访问系统级 Keystore，这里的缓解方案是：
 * - 密钥只以 AES-GCM 密文写入 chrome.storage.local；
 * - 用于解密的 AES 密钥保存在 IndexedDB，且创建时设置 extractable=false，
 *   扩展代码也无法导出原始密钥字节。
 * 这不能抵御拥有扩展执行上下文权限的攻击者，详见 README「安全局限」。
 */

const DB_NAME = "totpscan-vault";
const STORE_NAME = "keys";
const MASTER_KEY_ID = "master";
const MASTER_KEY_PROMISE = { current: null };

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new Error("VAULT_DB_OPEN_FAILED"));
  });
}

async function readMasterKey() {
  const db = await openDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly");
      const request = tx.objectStore(STORE_NAME).get(MASTER_KEY_ID);
      request.onsuccess = () => resolve(request.result ?? null);
      request.onerror = () => reject(new Error("VAULT_KEY_READ_FAILED"));
    });
  } finally {
    db.close();
  }
}

async function createMasterKey() {
  const key = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
  const db = await openDatabase();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      tx.objectStore(STORE_NAME).put(key, MASTER_KEY_ID);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(new Error("VAULT_KEY_WRITE_FAILED"));
    });
  } finally {
    db.close();
  }
  return key;
}

export async function getMasterKey() {
  if (!MASTER_KEY_PROMISE.current) {
    MASTER_KEY_PROMISE.current = (async () => {
      const existing = await readMasterKey();
      if (existing) {
        return existing;
      }
      return createMasterKey();
    })();
  }
  try {
    return await MASTER_KEY_PROMISE.current;
  } catch (error) {
    MASTER_KEY_PROMISE.current = null;
    throw error;
  }
}

function bytesToBase64(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function base64ToBytes(text) {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/** 加密原始密钥字节，返回可直接持久化的密文对象。 */
export async function encryptSecretBytes(bytes) {
  const key = await getMasterKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, bytes);
  return {
    v: 1,
    iv: bytesToBase64(iv),
    ct: bytesToBase64(new Uint8Array(ciphertext)),
  };
}

export async function decryptSecretBytes(record) {
  if (!record || record.v !== 1 || typeof record.iv !== "string" || typeof record.ct !== "string") {
    throw new Error("VAULT_CIPHERTEXT_INVALID");
  }
  const key = await getMasterKey();
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64ToBytes(record.iv) },
    key,
    base64ToBytes(record.ct),
  );
  return new Uint8Array(plaintext);
}
