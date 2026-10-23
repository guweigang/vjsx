// Bounded adapter composition for the locked versions, using their real APIs.
import { HTTP } from '@cordisjs/plugin-http';
import { LarkBot } from '@satorijs/adapter-lark';

// Lark 3.12.6 expects ArrayBuffer message.data, unlike the browser Blob default.
export class LarkBrowserHTTP extends HTTP {
  ws(...args) {
    const socket = super.ws(...args);
    socket.binaryType = 'arraybuffer';
    return socket;
  }
}

// The upstream token refresher uses global timers and does not clear them on
// disposal. Fence in-flight refreshes and release their timers in this scope.
export class LarkBrowserBot extends LarkBot {
  static inject = ['http', 'satori'];
  #disposed = false;
  async refreshToken() {
    if (this.#disposed) return;
    await super.refreshToken();
    if (this.#disposed) clearTimeout(this._refresher);
  }
  dispose() {
    this.#disposed = true;
    clearTimeout(this._refresher);
    super.dispose();
  }
}
