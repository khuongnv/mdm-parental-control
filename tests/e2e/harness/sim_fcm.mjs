import http from 'node:http';
import crypto from 'node:crypto';

function readJsonOrForm(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve({ raw, json: null, form: null });
      const ct = String(req.headers['content-type'] || '').toLowerCase();
      if (ct.includes('application/x-www-form-urlencoded')) {
        const params = new URLSearchParams(raw);
        return resolve({ raw, json: null, form: Object.fromEntries(params.entries()) });
      }
      try {
        return resolve({ raw, json: JSON.parse(raw), form: null });
      } catch (err) {
        return reject(err);
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
  });
  res.end(text);
}

export class SimFcmServer {
  constructor({ projectId = 'mdm-parental-control', requireIssuedToken = true } = {}) {
    this.projectId = projectId;
    this.requireIssuedToken = requireIssuedToken;
    this.server = null;
    this.baseUrl = null;
    this.issuedTokens = new Set();
    this.tokenBehaviors = new Map();
    this.sentMessages = [];
    this.rejectedMessages = [];
    this.tokenSubscribers = new Map();
  }

  async start() {
    if (this.server) return this.baseUrl;
    this.server = http.createServer((req, res) => {
      this._handleRequest(req, res).catch((err) => {
        sendJson(res, 500, { error: { code: 500, message: err.message, status: 'INTERNAL' } });
      });
    });

    await new Promise((resolve) => {
      this.server.listen(0, '127.0.0.1', resolve);
    });
    const addr = this.server.address();
    this.baseUrl = `http://127.0.0.1:${addr.port}`;
    return this.baseUrl;
  }

  async stop() {
    if (!this.server) return;
    const srv = this.server;
    this.server = null;
    await new Promise((resolve) => srv.close(resolve));
  }

  setTokenError(token, status = 404, errorCode = 'UNREGISTERED') {
    if (status == null) {
      this.tokenBehaviors.delete(token);
    } else {
      this.tokenBehaviors.set(token, { status, errorCode });
    }
  }

  onTokenPush(token, handler) {
    if (!this.tokenSubscribers.has(token)) {
      this.tokenSubscribers.set(token, new Set());
    }
    this.tokenSubscribers.get(token).add(handler);
    return () => {
      this.tokenSubscribers.get(token)?.delete(handler);
    };
  }

  getSentMessages() {
    return this.sentMessages.slice();
  }

  getSentToToken(token) {
    return this.sentMessages.filter((entry) => entry.message?.token === token);
  }

  getRejectedMessages() {
    return this.rejectedMessages.slice();
  }

  clear() {
    this.sentMessages.length = 0;
    this.rejectedMessages.length = 0;
  }

  async _handleRequest(req, res) {
    const parsed = new URL(req.url || '/', this.baseUrl || 'http://127.0.0.1');

    // OAuth2 token endpoint
    if (req.method === 'POST' && (parsed.pathname === '/oauth2/v4/token' || parsed.pathname === '/token')) {
      const { json, form } = await readJsonOrForm(req);
      const body = form || json || {};
      const grantType = body.grant_type;
      const assertion = body.assertion;
      if (grantType !== 'urn:ietf:params:oauth:grant-type:jwt-bearer' || !assertion || String(assertion).split('.').length !== 3) {
        return sendJson(res, 400, {
          error: 'invalid_grant',
          error_description: 'Expected jwt-bearer grant with 3-part JWT assertion',
        });
      }
      const token = `ya29.sim-${crypto.randomBytes(12).toString('hex')}`;
      this.issuedTokens.add(token);
      return sendJson(res, 200, {
        access_token: token,
        token_type: 'Bearer',
        expires_in: 3600,
      });
    }

    // FCM HTTP v1 send endpoint
    const fcmMatch = parsed.pathname.match(/^\/v1\/projects\/([^/]+)\/messages:send$/);
    if (req.method === 'POST' && fcmMatch) {
      const projectId = decodeURIComponent(fcmMatch[1]);
      const auth = String(req.headers.authorization || '');
      if (!auth.startsWith('Bearer ')) {
        return sendJson(res, 401, {
          error: { code: 401, message: 'Missing Bearer token', status: 'UNAUTHENTICATED' },
        });
      }
      const bearer = auth.slice('Bearer '.length).trim();
      if (this.requireIssuedToken && !this.issuedTokens.has(bearer)) {
        return sendJson(res, 401, {
          error: { code: 401, message: 'Invalid OAuth2 access token', status: 'UNAUTHENTICATED' },
        });
      }

      let payload;
      try {
        ({ json: payload } = await readJsonOrForm(req));
      } catch {
        return sendJson(res, 400, {
          error: { code: 400, message: 'Malformed JSON body', status: 'INVALID_ARGUMENT' },
        });
      }

      const message = payload?.message;
      if (!message || typeof message !== 'object' || !message.token) {
        this.rejectedMessages.push({ projectId, payload, reason: 'missing_token' });
        return sendJson(res, 400, {
          error: { code: 400, message: 'message.token is required', status: 'INVALID_ARGUMENT' },
        });
      }

      // Strict FCM HTTP v1 rule: message.data values MUST all be strings
      if (message.data !== undefined) {
        if (message.data === null || typeof message.data !== 'object' || Array.isArray(message.data)) {
          this.rejectedMessages.push({ projectId, payload, reason: 'invalid_data_map' });
          return sendJson(res, 400, {
            error: { code: 400, message: 'message.data must be a string-to-string map', status: 'INVALID_ARGUMENT' },
          });
        }
        for (const [k, v] of Object.entries(message.data)) {
          if (typeof v !== 'string') {
            this.rejectedMessages.push({ projectId, payload, reason: `non_string_data:${k}` });
            return sendJson(res, 400, {
              error: {
                code: 400,
                message: `Invalid value at 'message.data[${k}]' (TYPE_STRING): got ${typeof v}`,
                status: 'INVALID_ARGUMENT',
              },
            });
          }
        }
      }

      const behavior = this.tokenBehaviors.get(message.token);
      if (behavior) {
        this.rejectedMessages.push({ projectId, payload, reason: behavior.errorCode });
        return sendJson(res, behavior.status, {
          error: {
            code: behavior.status,
            message: 'Requested entity was not found.',
            status: behavior.status === 410 ? 'GONE' : 'NOT_FOUND',
            details: [
              {
                '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
                errorCode: behavior.errorCode || 'UNREGISTERED',
              },
            ],
          },
        });
      }

      const msgId = `projects/${projectId}/messages/${crypto.randomUUID()}`;
      const record = {
        name: msgId,
        projectId,
        message: structuredClone(message),
        receivedAt: new Date().toISOString(),
      };
      this.sentMessages.push(record);

      const subs = this.tokenSubscribers.get(message.token);
      if (subs) {
        for (const handler of subs) {
          Promise.resolve(handler(structuredClone(message), record)).catch(() => {});
        }
      }

      return sendJson(res, 200, { name: msgId });
    }

    return sendJson(res, 404, { error: { code: 404, message: 'Not found' } });
  }
}
