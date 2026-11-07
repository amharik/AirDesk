import { startEndpointPage } from './page';

function showFatal(error: unknown): void {
  const document = window.document;
  const status = document.getElementById('endpoint-status');
  const detail = document.getElementById('endpoint-detail');
  const message = document.getElementById('endpoint-error');
  const indicator = document.getElementById('endpoint-indicator');
  if (status) status.textContent = 'Unavailable';
  if (detail) detail.textContent = 'This display link is incomplete or invalid.';
  if (message) {
    message.textContent =
      error instanceof Error ? error.message : 'The browser endpoint could not be started.';
  }
  if (indicator) indicator.dataset.status = 'failed';
}

try {
  startEndpointPage(window);
} catch (error) {
  showFatal(error);
}
