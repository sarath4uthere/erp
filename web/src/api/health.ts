export type HealthState =
  | { kind: 'ok'; status: string; timestamp: string }
  | { kind: 'forbidden' }
  | { kind: 'error'; message: string };

interface HealthPayload {
  status: string;
  timestamp: string;
}

/**
 * Reads the public health endpoint through the same origin. Tokens are never
 * stored here; this call is anonymous by design and carries no credentials.
 */
export async function getHealth(signal?: AbortSignal): Promise<HealthState> {
  let response: Response;

  try {
    response = await fetch('/health', {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
      signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw error;
    }

    return { kind: 'error', message: 'The API could not be reached.' };
  }

  if (response.status === 401 || response.status === 403) {
    return { kind: 'forbidden' };
  }

  if (!response.ok) {
    return { kind: 'error', message: `The API returned status ${response.status}.` };
  }

  try {
    const payload = (await response.json()) as Partial<HealthPayload>;

    if (typeof payload.status !== 'string' || typeof payload.timestamp !== 'string') {
      return { kind: 'error', message: 'The API returned an unexpected payload.' };
    }

    return { kind: 'ok', status: payload.status, timestamp: payload.timestamp };
  } catch {
    return { kind: 'error', message: 'The API returned an unreadable payload.' };
  }
}
