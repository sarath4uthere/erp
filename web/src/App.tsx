import { useCallback, useEffect, useState } from 'react';
import { getHealth, type HealthState } from './api/health';

type ViewState = HealthState | { kind: 'loading' };

const modules = [
  { name: 'Master Data', phase: 'Phase 2' },
  { name: 'Inventory', phase: 'Phase 3' },
  { name: 'Purchasing & Sales', phase: 'Phase 4' },
  { name: 'Invoicing & GL', phase: 'Phase 5' },
  { name: 'Reports', phase: 'Phase 6' },
  { name: 'Admin & Security', phase: 'Phase 1' },
] as const;

export default function App() {
  const [state, setState] = useState<ViewState>({ kind: 'loading' });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const controller = new AbortController();

    getHealth(controller.signal)
      .then((next) => {
        if (!controller.signal.aborted) {
          setState(next);
        }
      })
      .catch(() => {
        if (!controller.signal.aborted) {
          setState({ kind: 'error', message: 'The API could not be reached.' });
        }
      });

    return () => controller.abort();
  }, [attempt]);

  const retry = useCallback(() => {
    setState({ kind: 'loading' });
    setAttempt((current) => current + 1);
  }, []);

  return (
    <div className="shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Mini-ERP</p>
          <h1>Foundation online</h1>
        </div>
        <span className="phase-chip">Phase 0</span>
      </header>

      <main>
        <section className="hero" aria-labelledby="foundation-heading">
          <div>
            <h2 id="foundation-heading">Distribution operations, one system.</h2>
            <p className="lede">
              Master data, stock, purchasing, sales, invoicing and the general ledger.
              This deployment is the Phase 0 skeleton: build, test and security gates are wired.
            </p>
          </div>
          <StatusCard state={state} onRetry={retry} />
        </section>

        <section className="modules" aria-labelledby="modules-heading">
          <h2 id="modules-heading">Modules</h2>
          <ul className="module-grid">
            {modules.map((module) => (
              <li key={module.name} className="module-card">
                <span className="module-name">{module.name}</span>
                <span className="module-phase">{module.phase}</span>
              </li>
            ))}
          </ul>
        </section>
      </main>

      <footer>
        <p>Server-driven forms and tables. Contract-first API. Deny-by-default authorization from Phase 1.</p>
      </footer>
    </div>
  );
}

function StatusCard({ state, onRetry }: { state: ViewState; onRetry: () => void }) {
  if (state.kind === 'loading') {
    return (
      <div className="status-card" role="status">
        <span className="dot dot-pending" aria-hidden="true" />
        <span>Checking API…</span>
      </div>
    );
  }

  if (state.kind === 'ok') {
    return (
      <div className="status-card" role="status">
        <span className="dot dot-healthy" aria-hidden="true" />
        <div>
          <strong>API is {state.status}</strong>
          <span className="status-meta">
            Checked {new Date(state.timestamp).toLocaleString()}
          </span>
        </div>
      </div>
    );
  }

  if (state.kind === 'forbidden') {
    return (
      <div className="status-card status-danger" role="alert">
        <span className="dot dot-danger" aria-hidden="true" />
        <div>
          <strong>Access denied</strong>
          <span className="status-meta">You do not have permission to view this.</span>
        </div>
      </div>
    );
  }

  return (
    <div className="status-card status-danger" role="alert">
      <span className="dot dot-danger" aria-hidden="true" />
      <div>
        <strong>API is unavailable</strong>
        <span className="status-meta">{state.message}</span>
        <button type="button" className="retry" onClick={onRetry}>
          Retry
        </button>
      </div>
    </div>
  );
}
