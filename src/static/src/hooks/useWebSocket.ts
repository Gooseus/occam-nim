import { useRef, useCallback, useEffect } from 'react';

export interface WebSocketOptions {
  url: string;
  onOpen?: () => void;
  onMessage?: (data: unknown) => void;
  onError?: (error: Event) => void;
  onClose?: () => void;
  reconnect?: boolean;
  maxReconnectAttempts?: number;
  reconnectIntervalMs?: number;
}

export interface WebSocketHandle {
  send: (data: unknown) => void;
  close: () => void;
  isConnected: () => boolean;
}

/**
 * Low-level WebSocket hook with optional reconnection support.
 * Returns a handle for sending messages and closing the connection.
 *
 * @param options - WebSocket configuration, or null to disable connection
 */
export function useWebSocket(options: WebSocketOptions | null): WebSocketHandle {
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectAttemptsRef = useRef(0);
  const reconnectTimeoutRef = useRef<number | null>(null);
  const isMountedRef = useRef(true);
  const optionsRef = useRef(options);

  // Keep options ref updated
  optionsRef.current = options;

  // Extract maxReconnectAttempts for use in close callback
  const maxReconnectAttempts = options?.maxReconnectAttempts ?? 5;

  const connect = useCallback(() => {
    const opts = optionsRef.current;
    if (!opts?.url || !isMountedRef.current) return;

    // Clean up existing connection
    if (wsRef.current) {
      wsRef.current.close();
    }

    // Determine protocol
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = opts.url.startsWith('ws')
      ? opts.url
      : `${protocol}//${window.location.host}${opts.url}`;

    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      reconnectAttemptsRef.current = 0;
      opts.onOpen?.();
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        opts.onMessage?.(data);
      } catch {
        // If not JSON, pass raw data
        opts.onMessage?.(event.data);
      }
    };

    ws.onerror = (event) => {
      opts.onError?.(event);
    };

    ws.onclose = () => {
      wsRef.current = null;
      opts.onClose?.();

      // Attempt reconnection if enabled
      if (
        opts.reconnect &&
        isMountedRef.current &&
        reconnectAttemptsRef.current < (opts.maxReconnectAttempts ?? 5)
      ) {
        const delay =
          (opts.reconnectIntervalMs ?? 1000) *
          Math.pow(2, reconnectAttemptsRef.current);
        reconnectAttemptsRef.current++;

        reconnectTimeoutRef.current = window.setTimeout(() => {
          if (isMountedRef.current) {
            connect();
          }
        }, delay);
      }
    };
  }, []);

  // Connect when options are provided
  useEffect(() => {
    isMountedRef.current = true;

    if (options) {
      connect();
    }

    return () => {
      isMountedRef.current = false;
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [options, connect]);

  const send = useCallback((data: unknown) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(typeof data === 'string' ? data : JSON.stringify(data));
    }
  }, []);

  const close = useCallback(() => {
    // Prevent reconnection
    reconnectAttemptsRef.current = maxReconnectAttempts ?? 5;
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
  }, [maxReconnectAttempts]);

  const isConnected = useCallback(() => {
    return wsRef.current?.readyState === WebSocket.OPEN;
  }, []);

  return { send, close, isConnected };
}
