'use strict';

const elements = {
  loading: document.querySelector('#loading'),
  content: document.querySelector('#content'),
  academyName: document.querySelector('#academy-name'),
  academyLogo: document.querySelector('#academy-logo'),
  studentName: document.querySelector('#student-name'),
  description: document.querySelector('#description'),
  dueDate: document.querySelector('#due-date'),
  amount: document.querySelector('#amount'),
  status: document.querySelector('#status-box'),
  pay: document.querySelector('#pay-button'),
  refresh: document.querySelector('#refresh-button'),
  pixPanel: document.querySelector('#pix-panel'),
  pixQr: document.querySelector('#pix-qr'),
  pixCode: document.querySelector('#pix-code'),
  copyPix: document.querySelector('#copy-pix'),
  openPix: document.querySelector('#open-pix'),
  pixExpiry: document.querySelector('#pix-expiry'),
};

let token = '';
try {
  token = decodeURIComponent(location.pathname.split('/').filter(Boolean)[1] || '');
} catch (_) {
  token = '';
}
const validToken = /^[A-Za-z0-9_-]{43}$/.test(token);
let charge = null;
let activeRequestId = null;

function requestId() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const value = [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-` +
    `${value.slice(16, 20)}-${value.slice(20)}`;
}

async function post(path, body) {
  const response = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    cache: 'no-store',
    credentials: 'omit',
    referrerPolicy: 'no-referrer',
  });
  const data = await response.json().catch(() => ({ status: 'error' }));
  if (!response.ok) {
    const error = new Error(data.message || 'Não foi possível concluir a operação.');
    error.status = response.status;
    error.data = data;
    throw error;
  }
  return data;
}

function money(value) {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
    .format(Number(value) || 0);
}

function date(value) {
  if (!value) return 'Não informado';
  const [year, month, day] = value.split('-').map(Number);
  return new Intl.DateTimeFormat('pt-BR').format(new Date(year, month - 1, day));
}

function setStatus(message, kind = '') {
  elements.status.textContent = message;
  elements.status.className = `status-box ${kind}`.trim();
}

function render(data) {
  elements.loading.hidden = true;
  elements.content.hidden = false;
  elements.pixPanel.hidden = true;
  elements.pay.hidden = true;
  charge = data;

  if (!data.charge || !data.academy) {
    setStatus('Este link de pagamento não está disponível.', 'error');
    elements.refresh.hidden = true;
    document.querySelector('.summary').hidden = true;
    document.querySelector('.academy').hidden = true;
    return;
  }
  document.querySelector('.summary').hidden = false;
  document.querySelector('.academy').hidden = false;
  elements.refresh.hidden = false;
  elements.academyName.textContent = data.academy.displayName || 'Academia';
  elements.studentName.textContent = data.charge.studentDisplayName || 'Aluno';
  elements.description.textContent = data.charge.description || 'Mensalidade';
  elements.dueDate.textContent = date(data.charge.dueDate);
  elements.amount.textContent = money(data.charge.amount);
  if (data.academy.logoUrl) {
    elements.academyLogo.src = data.academy.logoUrl;
    elements.academyLogo.hidden = false;
  } else {
    elements.academyLogo.hidden = true;
  }

  if (data.status === 'paid') {
    setStatus('Pagamento confirmado. Obrigado!', 'success');
  } else if (data.status === 'cancelled') {
    setStatus('Esta cobrança foi cancelada pela academia.', 'error');
  } else if (data.status === 'open' && data.availableMethods?.length) {
    const methods = data.availableMethods.includes('credit_card') ? 'PIX ou cartão' : 'PIX';
    setStatus(`Pagamento disponível por ${methods}. A cobrança só será criada após o clique abaixo.`);
    elements.pay.hidden = false;
  } else {
    setStatus('Pagamento online temporariamente indisponível. Fale com a academia.', 'error');
  }
}

async function resolveCharge() {
  if (!validToken) return render({ status: 'unavailable' });
  elements.refresh.disabled = true;
  try {
    render(await post('/api/public-pay/resolve', { token }));
  } catch (_) {
    setStatus('Não foi possível atualizar agora. Tente novamente.', 'error');
    elements.loading.hidden = true;
    elements.content.hidden = false;
  } finally {
    elements.refresh.disabled = false;
  }
}

function safeMercadoPagoUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' &&
      (url.hostname === 'mercadopago.com.br' || url.hostname.endsWith('.mercadopago.com.br'));
  } catch (_) {
    return false;
  }
}

async function startCheckout() {
  if (!charge || charge.status !== 'open') return;
  elements.pay.disabled = true;
  elements.pay.textContent = 'Preparando pagamento…';
  activeRequestId ||= requestId();
  try {
    let result;
    for (let attempt = 0; attempt < 5; attempt += 1) {
      try {
        result = await post('/api/public-pay/start', {
          token,
          requestId: activeRequestId,
          method: 'auto',
          expectedVersion: charge.version,
        });
        break;
      } catch (error) {
        if (error.status !== 409 || error.data?.status !== 'processing' || attempt === 4) throw error;
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }
    if (result.checkoutMode === 'checkout_pro' && safeMercadoPagoUrl(result.redirectUrl)) {
      location.assign(result.redirectUrl);
      return;
    }
    if (result.checkoutMode === 'pix' && result.pixCode) {
      elements.pixCode.value = result.pixCode;
      elements.pixPanel.hidden = false;
      if (result.qrCodeBase64) {
        elements.pixQr.src = `data:image/png;base64,${result.qrCodeBase64}`;
        elements.pixQr.hidden = false;
      }
      if (safeMercadoPagoUrl(result.ticketUrl)) {
        elements.openPix.href = result.ticketUrl;
        elements.openPix.hidden = false;
      }
      elements.pixExpiry.textContent = result.expiresAt
        ? `Válido até ${new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(result.expiresAt))}.`
        : '';
      setStatus('PIX criado. Conclua o pagamento no seu banco.');
      elements.pay.hidden = true;
      return;
    }
    throw new Error('Resposta de pagamento inválida.');
  } catch (error) {
    activeRequestId = null;
    setStatus(error.message || 'Não foi possível iniciar o pagamento.', 'error');
    elements.pay.disabled = false;
    elements.pay.textContent = 'Tentar novamente';
  }
}

elements.pay.addEventListener('click', startCheckout);
elements.refresh.addEventListener('click', resolveCharge);
elements.copyPix.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(elements.pixCode.value);
    elements.copyPix.textContent = 'Código copiado';
  } catch (_) {
    elements.pixCode.focus();
    elements.pixCode.select();
    elements.copyPix.textContent = 'Selecione e copie o código';
  }
  setTimeout(() => { elements.copyPix.textContent = 'Copiar código PIX'; }, 1800);
});

resolveCharge();
