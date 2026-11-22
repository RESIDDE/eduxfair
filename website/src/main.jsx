import { StrictMode, Suspense, lazy } from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';
import Home from './pages/Home';
import Legal from './pages/Legal';

// Only /delete-account/ talks to Supabase. Loading it lazily keeps the
// Supabase client out of the bundle every other page downloads.
const DeleteAccount = lazy(() => import('./pages/DeleteAccount'));

// Each HTML entry (/, /privacy/, /terms/, /guidelines/, /delete-account/) names its page.
const root = document.getElementById('root');
const page = root.dataset.page ?? 'home';

createRoot(root).render(
  <StrictMode>
    {page === 'home' ? (
      <Home />
    ) : page === 'delete' ? (
      <Suspense fallback={<div className="min-h-screen bg-black" />}>
        <DeleteAccount />
      </Suspense>
    ) : (
      <Legal page={page} />
    )}
  </StrictMode>,
);
