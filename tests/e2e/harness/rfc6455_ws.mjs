import crypto from 'node:crypto';
import net from 'node:net';
import { EventEmitter } from 'node:events';

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

export const WS_OPEN = 1;
export const WS_CLOSING = 2;
export const WS_CLOSED = 3;

export const OPCODE = {
  CONTINUATION: 0x0,
  TEXT: 0x1,
  BINARY: 0x2,
  CLOSE: 0x8,
  PING: 0x9,
  PONG: 0xa,
};

export function computeAcceptKey(secKey) {
  return crypto
    .createHash('sha1')
    .update(String(secKey).trim() + WS_GUID, 'utf8')
    .digest('base64');
}

export function encodeFrame({ opcode, payload = Buffer.alloc(0), mask = false, fin = true }) {
  const buf = Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload), 'utf8');
  const len = buf.length;
  let headerLen = 2;
  if (len >= 126 && len <= 65535) {
    headerLen += 2;
  } else if (len > 65535) {
    headerLen += 8;
  }
  if (mask) {
    headerLen += 4;
  }

  const out = Buffer.allocUnsafe(headerLen + len);
  out[0] = (fin ? 0x80 : 0x00) | (opcode & 0x0f);
  const maskBit = mask ? 0x80 : 0x00;

  let offset = 2;
  if (len < 126) {
    out[1] = maskBit | len;
  } else if (len <= 65535) {
    out[1] = maskBit | 126;
    out.writeUInt16BE(len, 2);
    offset = 4;
  } else {
    out[1] = maskBit | 127;
    out.writeBigUInt64BE(BigInt(len), 2);
    offset = 10;
  }

  if (mask) {
    const maskKey = crypto.randomBytes(4);
    maskKey.copy(out, offset);
    offset += 4;
    for (let i = 0; i < len; i++) {
      out[offset + i] = buf[i] ^ maskKey[i & 3];
    }
  } else if (len > 0) {
    buf.copy(out, offset);
  }
  return out;
}

export class WsFrameDecoder extends EventEmitter {
  constructor() {
    super();
    this.buffer = Buffer.alloc(0);
    this.fragmentOpcode = null;
    this.fragments = [];
  }

  push(chunk) {
    if (!chunk || chunk.length === 0) return;
    this.buffer = this.buffer.length === 0 ? Buffer.from(chunk) : Buffer.concat([this.buffer, chunk]);

    while (this.buffer.length >= 2) {
      const b0 = this.buffer[0];
      const b1 = this.buffer[1];
      const fin = (b0 & 0x80) !== 0;
      const opcode = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let payloadLen = b1 & 0x7f;
      let offset = 2;

      if (payloadLen === 126) {
        if (this.buffer.length < 4) return;
        payloadLen = this.buffer.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (this.buffer.length < 10) return;
        const bigLen = this.buffer.readBigUInt64BE(2);
        if (bigLen > BigInt(Number.MAX_SAFE_INTEGER)) {
          this.emit('error', new Error('WebSocket frame too large'));
          return;
        }
        payloadLen = Number(bigLen);
        offset = 10;
      }

      const maskLen = masked ? 4 : 0;
      const totalFrameLen = offset + maskLen + payloadLen;
      if (this.buffer.length < totalFrameLen) return;

      let payload = this.buffer.subarray(offset + maskLen, totalFrameLen);
      if (masked) {
        const maskKey = this.buffer.subarray(offset, offset + 4);
        const unmasked = Buffer.allocUnsafe(payloadLen);
        for (let i = 0; i < payloadLen; i++) {
          unmasked[i] = payload[i] ^ maskKey[i & 3];
        }
        payload = unmasked;
      } else {
        payload = Buffer.from(payload);
      }

      this.buffer = this.buffer.subarray(totalFrameLen);

      // Control frames (0x8..0xF) may be interleaved between fragmented data frames
      if (opcode >= 0x8) {
        this.emit('frame', { opcode, payload, fin: true });
        continue;
      }

      if (opcode === OPCODE.CONTINUATION) {
        if (this.fragmentOpcode === null) {
          this.emit('error', new Error('Unexpected continuation frame'));
          return;
        }
        this.fragments.push(payload);
        if (fin) {
          const full = Buffer.concat(this.fragments);
          const origOpcode = this.fragmentOpcode;
          this.fragmentOpcode = null;
          this.fragments = [];
          this.emit('frame', { opcode: origOpcode, payload: full, fin: true });
        }
      } else {
        if (!fin) {
          this.fragmentOpcode = opcode;
          this.fragments = [payload];
        } else {
          this.emit('frame', { opcode, payload, fin: true });
        }
      }
    }
  }
}

export class Rfc6455Socket extends EventEmitter {
  constructor(socket, { isClient = false, initialData = null } = {}) {
    super();
    this.socket = socket;
    this.socket.allowHalfOpen = false;
    this.isClient = isClient;
    this.readyState = WS_OPEN;
    this.decoder = new WsFrameDecoder();
    this.closeCode = null;
    this.closeReason = '';

    this.decoder.on('frame', ({ opcode, payload }) => {
      if (opcode === OPCODE.TEXT) {
        this.emit('message', payload.toString('utf8'), false);
      } else if (opcode === OPCODE.BINARY) {
        this.emit('message', payload, true);
      } else if (opcode === OPCODE.PING) {
        if (this.readyState === WS_OPEN) {
          this._writeFrame(OPCODE.PONG, payload);
        }
        this.emit('ping', payload);
      } else if (opcode === OPCODE.PONG) {
        this.emit('pong', payload);
      } else if (opcode === OPCODE.CLOSE) {
        let code = 1005;
        let reason = '';
        if (payload.length >= 2) {
          code = payload.readUInt16BE(0);
          reason = payload.subarray(2).toString('utf8');
        }
        this.closeCode = code;
        this.closeReason = reason;
        if (this.readyState === WS_OPEN) {
          this.readyState = WS_CLOSING;
          const reply = payload.length >= 2 ? payload.subarray(0, 2) : Buffer.alloc(0);
          this._writeFrame(OPCODE.CLOSE, reply);
        }
        this.readyState = WS_CLOSED;
        this.socket.end();
        this.socket.destroy();
      }
    });

    this.decoder.on('error', (err) => {
      if (this.listenerCount('error') > 0) {
        this.emit('error', err);
      }
      this.terminate();
    });

    socket.on('data', (chunk) => {
      this.decoder.push(chunk);
    });

    socket.on('end', () => {
      if (this.readyState !== WS_CLOSED) {
        this.terminate();
      }
    });

    socket.on('error', (err) => {
      if (this.readyState === WS_OPEN && this.listenerCount('error') > 0) {
        this.emit('error', err);
      }
    });

    socket.on('close', () => {
      if (this.readyState !== WS_CLOSED) {
        this.readyState = WS_CLOSED;
      }
      this.emit('close', this.closeCode ?? 1006, this.closeReason);
    });

    if (initialData && initialData.length > 0) {
      queueMicrotask(() => {
        if (this.readyState === WS_OPEN) {
          this.decoder.push(initialData);
        }
      });
    }
  }

  _writeFrame(opcode, payload, fin = true) {
    if (!this.socket || this.socket.destroyed || !this.socket.writable || this.readyState === WS_CLOSED) return;
    if (this.readyState === WS_CLOSING && opcode !== OPCODE.CLOSE) return;
    const frame = encodeFrame({ opcode, payload, mask: this.isClient, fin });
    try {
      this.socket.write(frame, () => {});
    } catch {
      // Ignore write errors during teardown
    }
  }

  send(data) {
    if (this.readyState !== WS_OPEN) {
      throw new Error(`WebSocket is not open (state=${this.readyState})`);
    }
    if (Buffer.isBuffer(data)) {
      this._writeFrame(OPCODE.BINARY, data);
    } else {
      this._writeFrame(OPCODE.TEXT, Buffer.from(String(data), 'utf8'));
    }
  }

  sendFragmented(text, chunkSize = 16) {
    if (this.readyState !== WS_OPEN) {
      throw new Error(`WebSocket is not open (state=${this.readyState})`);
    }
    const buf = Buffer.from(String(text), 'utf8');
    if (buf.length <= chunkSize) {
      this._writeFrame(OPCODE.TEXT, buf, true);
      return;
    }
    let offset = 0;
    let first = true;
    while (offset < buf.length) {
      const end = Math.min(offset + chunkSize, buf.length);
      const isLast = end >= buf.length;
      const slice = buf.subarray(offset, end);
      this._writeFrame(first ? OPCODE.TEXT : OPCODE.CONTINUATION, slice, isLast);
      first = false;
      offset = end;
    }
  }

  ping(data = '') {
    if (this.readyState !== WS_OPEN) return;
    this._writeFrame(OPCODE.PING, Buffer.isBuffer(data) ? data : Buffer.from(String(data), 'utf8'));
  }

  close(code = 1000, reason = '') {
    if (this.readyState !== WS_OPEN) return;
    this.readyState = WS_CLOSING;
    const reasonBuf = Buffer.from(String(reason), 'utf8');
    const payload = Buffer.allocUnsafe(2 + reasonBuf.length);
    payload.writeUInt16BE(code, 0);
    reasonBuf.copy(payload, 2);
    this._writeFrame(OPCODE.CLOSE, payload);
    setTimeout(() => {
      if (!this.socket.destroyed) {
        this.socket.destroy();
      }
    }, 50).unref();
  }

  terminate() {
    this.readyState = WS_CLOSED;
    if (!this.socket.destroyed) {
      this.socket.destroy();
    }
  }
}

export function attachWebSocketServer(httpServer, { path = null, onConnection }) {
  const clients = new Set();

  const upgradeHandler = (req, socket, head) => {
    const parsed = new URL(req.url || '/', 'http://127.0.0.1');
    if (path && parsed.pathname !== path) {
      socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }

    const secKey = req.headers['sec-websocket-key'];
    const upgradeHeader = String(req.headers.upgrade || '').toLowerCase();
    if (!secKey || upgradeHeader !== 'websocket') {
      socket.write('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }

    const accept = computeAcceptKey(secKey);
    const responseHeaders = [
      'HTTP/1.1 101 Switching Protocols',
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Accept: ${accept}`,
      '',
      '',
    ].join('\r\n');

    socket.write(responseHeaders);
    const ws = new Rfc6455Socket(socket, { isClient: false, initialData: head });
    clients.add(ws);
    ws.on('close', () => clients.delete(ws));
    onConnection(ws, req, parsed);
  };

  httpServer.on('upgrade', upgradeHandler);

  return {
    clients,
    closeAll() {
      for (const ws of clients) {
        ws.terminate();
      }
      clients.clear();
    },
    detach() {
      this.closeAll();
      httpServer.off('upgrade', upgradeHandler);
    },
  };
}

export function connectWebSocket(urlStr, { headers = {}, timeoutMs = 5000 } = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(urlStr);
    const host = parsed.hostname;
    const port = Number(parsed.port || (parsed.protocol === 'wss:' ? 443 : 80));
    const pathAndQuery = `${parsed.pathname || '/'}${parsed.search || ''}`;
    const secKey = crypto.randomBytes(16).toString('base64');
    const expectedAccept = computeAcceptKey(secKey);

    const socket = net.createConnection({ host, port });
    let settled = false;
    let rawHead = Buffer.alloc(0);

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        socket.destroy();
        reject(new Error(`WebSocket connect timeout to ${urlStr}`));
      }
    }, timeoutMs);
    timer.unref();

    socket.on('error', (err) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(err);
      }
    });

    socket.on('connect', () => {
      const reqLines = [
        `GET ${pathAndQuery} HTTP/1.1`,
        `Host: ${host}:${port}`,
        'Upgrade: websocket',
        'Connection: Upgrade',
        `Sec-WebSocket-Key: ${secKey}`,
        'Sec-WebSocket-Version: 13',
      ];
      for (const [k, v] of Object.entries(headers)) {
        reqLines.push(`${k}: ${v}`);
      }
      reqLines.push('', '');
      socket.write(reqLines.join('\r\n'));
    });

    const onHandshakeData = (chunk) => {
      rawHead = rawHead.length === 0 ? Buffer.from(chunk) : Buffer.concat([rawHead, chunk]);
      const markerIdx = rawHead.indexOf('\r\n\r\n');
      if (markerIdx === -1) return;

      socket.off('data', onHandshakeData);
      clearTimeout(timer);

      const headerStr = rawHead.subarray(0, markerIdx).toString('utf8');
      const leftover = rawHead.subarray(markerIdx + 4);
      const lines = headerStr.split('\r\n');
      const statusLine = lines[0] || '';
      if (!statusLine.includes('101')) {
        settled = true;
        socket.destroy();
        reject(new Error(`WebSocket handshake failed: ${statusLine}`));
        return;
      }

      const respHeaders = {};
      for (let i = 1; i < lines.length; i++) {
        const colon = lines[i].indexOf(':');
        if (colon > 0) {
          respHeaders[lines[i].slice(0, colon).trim().toLowerCase()] = lines[i].slice(colon + 1).trim();
        }
      }

      if (respHeaders['sec-websocket-accept'] !== expectedAccept) {
        settled = true;
        socket.destroy();
        reject(new Error('Invalid Sec-WebSocket-Accept header'));
        return;
      }

      settled = true;
      const ws = new Rfc6455Socket(socket, { isClient: true, initialData: leftover });
      resolve(ws);
    };

    socket.on('data', onHandshakeData);
  });
}
