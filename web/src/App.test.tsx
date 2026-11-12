import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import App from './App';

function jsonResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

describe('App', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('shows the API status when the health check succeeds', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ status: 'Healthy', timestamp: '2026-11-12T10:00:00Z' }),
    );
    vi.stubGlobal('fetch', fetchMock);

    render(<App />);

    expect(screen.getByRole('status')).toHaveTextContent('Checking API');
    expect(await screen.findByText(/api is healthy/i)).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      '/health',
      expect.objectContaining({ credentials: 'same-origin' }),
    );
  });

  it('shows a forbidden state for 403 responses', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({}, 403)));

    render(<App />);

    expect(await screen.findByText(/access denied/i)).toBeInTheDocument();
    expect(screen.getByText(/do not have permission/i)).toBeInTheDocument();
  });

  it('shows an unavailable state for server errors', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({}, 503)));

    render(<App />);

    expect(await screen.findByText(/api is unavailable/i)).toBeInTheDocument();
    expect(screen.getByText(/status 503/i)).toBeInTheDocument();
  });

  it('shows an unavailable state when the network fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('network down')));

    render(<App />);

    expect(await screen.findByText(/api is unavailable/i)).toBeInTheDocument();
    expect(screen.getByText(/could not be reached/i)).toBeInTheDocument();
  });

  it('retries the health check', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({}, 500))
      .mockResolvedValueOnce(jsonResponse({ status: 'Healthy', timestamp: '2026-11-12T10:00:00Z' }));
    vi.stubGlobal('fetch', fetchMock);

    const user = userEvent.setup();
    render(<App />);

    expect(await screen.findByText(/api is unavailable/i)).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /retry/i }));

    expect(await screen.findByText(/api is healthy/i)).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
