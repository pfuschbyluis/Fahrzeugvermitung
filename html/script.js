/* ════════════════════════════════════════════════════════════
   MB_Fahrzeugvermitung — UI v2 (Spieler-App, Admin-Menü, HUD)
   ════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  // ────────────────────────────────────────────────
  // UMGEBUNG & HELFER
  // ────────────────────────────────────────────────
  const IN_GAME = typeof window.GetParentResourceName === 'function';

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // Bild-Fallback: zeigt Platzhalter, wenn ein Bild (z. B. defekter Link) nicht lädt
  const IMG_FALLBACK = 'img/placeholder.svg';

  // Bildquelle normalisieren:
  // - https/http Direktlinks bleiben unverändert
  // - nui:// und data:image bleiben erlaubt
  // - lokale Dateinamen ohne Ordner werden automatisch zu img/datei.*
  // - leere Werte fallen auf den Platzhalter zurück
  function normalizeImagePath(p) {
    p = String(p == null ? '' : p).trim();
    if (!p) return IMG_FALLBACK;
    if (/^(https?:\/\/|nui:\/\/|data:image\/)/i.test(p)) return p;
    if (/^img\//i.test(p)) return p;
    if (/^[a-z0-9_\-.]+\.(png|jpe?g|webp|gif|svg)(\?.*)?$/i.test(p)) return `img/${p}`;
    return p;
  }

  // Optionale Pfad-Zuordnung (nur Standalone-Export); im FiveM-Resource werden echte Dateien benutzt.
  function imgSrc(p) {
    p = normalizeImagePath(p);
    const map = window.__IMG_MAP;
    return (map && map[p]) || p;
  }

  const IMG_ONERROR = `onerror="if(!this.dataset.f){this.dataset.f=1;this.src='${imgSrc(IMG_FALLBACK)}'}"`;

  function money(v) {
    return `${Number(v || 0).toLocaleString('de-DE')} €`;
  }

  function formatTimer(totalSeconds) {
    totalSeconds = Math.max(0, Math.floor(totalSeconds));
    const h = Math.floor(totalSeconds / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = totalSeconds % 60;
    const mm = String(m).padStart(2, '0');
    const ss = String(s).padStart(2, '0');
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  function formatDate() {
    const d = new Date();
    const p = (n) => String(n).padStart(2, '0');
    return `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()}`;
  }

  function post(endpoint, body) {
    if (!IN_GAME) {
      return Promise.resolve(Demo.handle(endpoint, body || {}));
    }
    return fetch(`https://${window.GetParentResourceName()}/${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    }).then((r) => (r.ok ? r.json().catch(() => ({})) : {}));
  }

  // Tablet-Uhr
  function updateClock() {
    const d = new Date();
    const el = $('#tablet-clock');
    if (el) el.textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  }
  updateClock();
  setInterval(updateClock, 15000);

  // ────────────────────────────────────────────────
  // TOASTS
  // ────────────────────────────────────────────────
  function toast(msg, type) {
    const stack = $('#toast-stack');
    const t = document.createElement('div');
    t.className = `toast${type === 'success' ? ' toast-success' : type === 'error' ? ' toast-error' : ''}`;
    t.textContent = msg;
    stack.appendChild(t);
    setTimeout(() => {
      t.classList.add('toast-out');
      setTimeout(() => t.remove(), 220);
    }, 3200);
  }

  // ────────────────────────────────────────────────
  // MODAL
  // ────────────────────────────────────────────────
  const modalOverlay = $('#modal-overlay');
  const modalEl = $('#modal');

  function closeModal() {
    modalOverlay.classList.add('hidden');
    modalEl.innerHTML = '';
  }

  /**
   * openModal({ title, bodyHTML, buttons: [{label, cls, onClick, close}] })
   * onClick erhält das Modal-Element; return false verhindert das Schließen.
   */
  function openModal(opts) {
    modalEl.innerHTML = `
      <div class="modal-head">
        <span class="modal-title">${esc(opts.title)}</span>
        <button class="btn btn-icon btn-sm" data-modal-close aria-label="Schließen">
          <svg viewBox="0 0 16 16" class="ico"><path d="M4 4l8 8M12 4l-8 8"/></svg>
        </button>
      </div>
      <div class="modal-body">${opts.bodyHTML || ''}</div>
      <div class="modal-foot"></div>
    `;
    const foot = $('.modal-foot', modalEl);
    (opts.buttons || []).forEach((b) => {
      const btn = document.createElement('button');
      btn.className = `btn ${b.cls || 'btn-secondary'}`;
      btn.textContent = b.label;
      btn.addEventListener('click', () => {
        if (b.onClick && b.onClick(modalEl) === false) return;
        closeModal();
      });
      foot.appendChild(btn);
    });
    $('[data-modal-close]', modalEl).addEventListener('click', closeModal);
    modalOverlay.classList.remove('hidden');
  }

  modalOverlay.addEventListener('click', (e) => {
    if (e.target === modalOverlay) closeModal();
  });

  // ════════════════════════════════════════════════
  // MIET-APP (Spieler)
  // ════════════════════════════════════════════════
  const rentalApp = $('#rental-app');
  let contractViewerApp = $('#contract-viewer-app');

  function ensureContractViewerApp() {
    if (contractViewerApp) return contractViewerApp;

    contractViewerApp = document.createElement('div');
    contractViewerApp.id = 'contract-viewer-app';
    contractViewerApp.className = 'contract-viewer-overlay hidden';
    document.body.appendChild(contractViewerApp);
    bindContractViewerEvents();
    return contractViewerApp;
  }
  const screens = {
    vehicles: $('#screen-vehicles'),
    details: $('#screen-details'),
    contract: $('#screen-contract'),
    signature: $('#screen-signature'),
    success: $('#screen-success'),
  };

  let lastAdminSaveAt = 0;

  const rental = {
    vehicles: [],
    durations: [],
    payments: [],
    selectedVehicle: null,
    selectedDurationIdx: null,
    selectedPaymentId: null,
    playerName: 'Unbekannt',
    signatureDataUrl: null,
    viewerMode: false,
    canShowContract: false,
    currentContractId: null,
  };

  function showScreen(name) {
    Object.values(screens).forEach((s) => s.classList.add('hidden'));
    screens[name].classList.remove('hidden');
  }

  function openRentalApp(data) {
    rental.vehicles = data.vehicles || [];
    rental.durations = data.durations || [];
    rental.payments = data.payments || [];
    rental.selectedVehicle = null;
    rental.selectedDurationIdx = null;
    rental.selectedPaymentId = null;
    rental.viewerMode = false;
    rental.canShowContract = false;
    rental.currentContractId = null;

    $('#location-label').textContent = data.locationLabel || 'Standort';
    renderVehicleGrid();
    showScreen('vehicles');
    rentalApp.classList.remove('hidden');
  }

  function closeAll() {
    // Ignore accidental close right after admin save.
    if (Date.now() - lastAdminSaveAt < 1200 && adminApp && !adminApp.classList.contains('hidden')) {
      return;
    }
    rentalApp.classList.add('hidden');
    if (contractViewerApp) {
      contractViewerApp.classList.add('hidden');
      contractViewerApp.innerHTML = '';
    }
    adminApp.classList.add('hidden');
    closeModal();
  }

  // Screen 1: Fahrzeugauswahl
  function renderVehicleGrid() {
    const grid = $('#vehicle-grid');
    grid.innerHTML = '';

    if (!rental.vehicles.length) {
      grid.innerHTML = '<div class="empty-note">An diesem Standort sind derzeit keine Fahrzeuge verfügbar.</div>';
      return;
    }

    rental.vehicles.forEach((v) => {
      const card = document.createElement('div');
      card.className = 'vehicle-card';
      card.innerHTML = `
        <div class="vehicle-card-img"><img src="${esc(imgSrc(v.image))}" alt="${esc(v.label)}" ${IMG_ONERROR} /></div>
        <div class="vehicle-card-body">
          <div class="vehicle-card-name">${esc(v.label)}</div>
          <div class="vehicle-card-foot">
            <span class="badge">${esc(v.category)}</span>
            <span class="vehicle-card-price">ab ${money(v.price)}</span>
          </div>
        </div>
      `;
      card.addEventListener('click', () => {
        rental.selectedVehicle = v;
        rental.selectedDurationIdx = null;
        rental.selectedPaymentId = null;
        renderDetails();
        showScreen('details');
      });
      grid.appendChild(card);
    });
  }

  // Screen 2: Details
  function renderDetails() {
    const v = rental.selectedVehicle;
    $('#detail-name').textContent = v.label;
    $('#detail-category-sub').textContent = v.category;
    $('#detail-category').textContent = v.category;
    $('#detail-baseprice').textContent = `Grundpreis: ${money(v.price)}`;
    const img = $('#detail-image');
    img.dataset.f = '';
    img.onerror = () => { if (!img.dataset.f) { img.dataset.f = '1'; img.src = imgSrc(IMG_FALLBACK); } };
    img.src = imgSrc(v.image);
    img.alt = v.label;

    const durWrap = $('#duration-options');
    durWrap.innerHTML = '';
    rental.durations.forEach((d, idx) => {
      const tile = document.createElement('div');
      tile.className = 'option-tile';
      tile.innerHTML = `
        <span class="option-tile-label">${esc(d.label)}</span>
        <span class="option-tile-sub">${money(Math.floor(v.price * d.multiplier))}</span>
      `;
      tile.addEventListener('click', () => {
        rental.selectedDurationIdx = idx;
        $$('.option-tile', durWrap).forEach((t) => t.classList.remove('selected'));
        tile.classList.add('selected');
        updateTotal();
      });
      durWrap.appendChild(tile);
    });

    const payWrap = $('#payment-options');
    payWrap.innerHTML = '';
    rental.payments.forEach((p) => {
      const btn = document.createElement('button');
      btn.className = 'seg-item';
      btn.textContent = p.label;
      btn.addEventListener('click', () => {
        rental.selectedPaymentId = p.id;
        $$('.seg-item', payWrap).forEach((b) => b.classList.remove('selected'));
        btn.classList.add('selected');
      });
      payWrap.appendChild(btn);
    });

    updateTotal();
  }

  function updateTotal() {
    const v = rental.selectedVehicle;
    let total = 0;
    if (v && rental.selectedDurationIdx !== null) {
      total = Math.floor(v.price * rental.durations[rental.selectedDurationIdx].multiplier);
    }
    $('#total-price').textContent = money(total);
  }

  function renderStoredContract(contract, allowShow) {
    rental.viewerMode = true;
    rental.canShowContract = allowShow === true;
    rental.currentContractId = contract.id || null;

    let sigHtml = '';
    if (contract.signatureDataUrl) {
      rental.signatureDataUrl = contract.signatureDataUrl;
      sigHtml = `<img src="${esc(contract.signatureDataUrl)}" alt="Unterschrift" />`;
    } else if (contract.tenant || contract.playerName) {
      rental.signatureDataUrl = generateSignatureImage(contract.tenant || contract.playerName);
      sigHtml = `<img src="${rental.signatureDataUrl}" alt="Unterschrift" />`;
    }

    const viewerApp = ensureContractViewerApp();
    viewerApp.innerHTML = `
      <div class="contract-viewer" role="dialog" aria-label="Mietvertrag">
        <div class="contract-paper">
          <div class="contract-head">
            <span class="contract-eyebrow">Fahrzeugmietvertrag</span>
            
          </div>
          <div class="contract-rows">
            <div class="contract-row"><span class="contract-key">Mieter</span><span class="contract-value">${esc(contract.tenant || contract.playerName || rental.playerName || 'Unbekannt')}</span></div>
            <div class="contract-row"><span class="contract-key">Datum</span><span class="contract-value">${esc(contract.date || formatDate())}</span></div>
            <div class="contract-row"><span class="contract-key">Status</span><span class="contract-value status-signed">${esc(contract.status || 'Unterschrieben')}</span></div>
            <div class="contract-divider"></div>
            <div class="contract-row"><span class="contract-key">Fahrzeug</span><span class="contract-value">${esc(contract.vehicleLabel || '—')}</span></div>
            <div class="contract-row"><span class="contract-key">Kennzeichen</span><span class="contract-value">${esc(contract.plate || '—')}</span></div>
            <div class="contract-row"><span class="contract-key">Mietdauer</span><span class="contract-value">${esc(contract.durationLabel || '—')}</span></div>
            <div class="contract-row"><span class="contract-key">Zahlungsart</span><span class="contract-value">${esc(contract.paymentLabel || '—')}</span></div>
            <div class="contract-row"><span class="contract-key">Preis</span><span class="contract-value contract-price">${money(contract.price || 0)}</span></div>
          </div>
          <p class="contract-text">
            Der Mieter verpflichtet sich, das überlassene Fahrzeug pfleglich zu behandeln und
            ausschließlich im Rahmen der geltenden Verkehrsregeln zu nutzen. Nach Ablauf der
            vereinbarten Mietdauer wird das Fahrzeug automatisch durch die Vermietung eingezogen.
            Schäden am Fahrzeug können dem Mieter in Rechnung gestellt werden.
          </p>
          <div class="signature-line">
            <span class="signature-label">Unterschrift</span>
            <div class="signature-preview">${sigHtml}</div>
          </div>
        </div>
        <div class="contract-viewer-actions">
          <button class="btn btn-secondary" data-viewer-close>Schließen</button>
          ${allowShow ? '<button class="btn btn-primary" data-viewer-show>Spieler zeigen</button>' : ''}
        </div>
      </div>
    `;

    rentalApp.classList.add('hidden');
    adminApp.classList.add('hidden');
    viewerApp.classList.remove('hidden');
  }

  function setContractScreenForSigning() {
    rental.viewerMode = false;
    rental.canShowContract = false;
    rental.currentContractId = null;

    const left = $('#btn-contract-left');
    const right = $('#btn-contract-right');
    left.textContent = 'Zurück';
    left.dataset.action = 'back-to-details';
    right.textContent = 'Unterschreiben';
    right.classList.remove('hidden');
    $('.screen-sub', screens.contract).textContent = 'Bitte prüfen und unterschreiben';
  }

  $('#btn-prepare-contract').addEventListener('click', () => {
    if (rental.selectedDurationIdx === null) return toast('Bitte wähle eine Mietdauer aus.', 'error');
    if (rental.selectedPaymentId === null) return toast('Bitte wähle eine Zahlungsmethode aus.', 'error');
    renderContract();
    showScreen('contract');
  });

  // Screen 3: Vertrag
  function renderContract() {
    setContractScreenForSigning();
    const v = rental.selectedVehicle;
    const d = rental.durations[rental.selectedDurationIdx];
    const p = rental.payments.find((x) => x.id === rental.selectedPaymentId);
    const total = Math.floor(v.price * d.multiplier);

    $('#contract-id').textContent = '';
    $('#contract-id').style.display = 'none';
    $('#contract-tenant').textContent = rental.playerName;
    $('#contract-date').textContent = formatDate();
    const st = $('#contract-status');
    st.textContent = 'Unsigniert';
    st.className = 'contract-value status-pending';
    $('#contract-vehicle').textContent = v.label;
    $('#contract-duration').textContent = d.label;
    $('#contract-payment').textContent = p.label;
    $('#contract-price').textContent = money(total);
    $('#signature-preview').innerHTML = '';
    rental.signatureDataUrl = null;
  }

  // Screen 4: automatische Unterschrift
  const SIGNATURE_FONTS = '"Segoe Script", "Brush Script MT", "Lucida Handwriting", cursive';

  function generateSignatureImage(name) {
    const c = document.createElement('canvas');
    let fontSize = 46;
    if (name.length > 18) fontSize = 38;
    if (name.length > 26) fontSize = 32;

    const measure = c.getContext('2d');
    measure.font = `italic ${fontSize}px ${SIGNATURE_FONTS}`;
    const textWidth = measure.measureText(name).width;

    c.width = Math.ceil(textWidth + 70);
    c.height = Math.ceil(fontSize * 2.2);

    const ctx = c.getContext('2d');
    ctx.font = `italic ${fontSize}px ${SIGNATURE_FONTS}`;
    ctx.fillStyle = '#1a2b52';
    ctx.textBaseline = 'middle';
    ctx.save();
    ctx.translate(30, c.height / 2);
    ctx.rotate(-0.045);
    ctx.fillText(name, 0, 0);
    ctx.restore();

    return c.toDataURL('image/png');
  }

  $('#btn-contract-right').addEventListener('click', () => {
    if (rental.viewerMode) {
      if (!rental.currentContractId) return toast('Kein Mietvertrag ausgewählt.', 'error');
      post('showContractToNearest', { contractId: rental.currentContractId }).then((res) => {
        if (res && res.success === false) {
          toast(res.reason || 'Kein Spieler in der Nähe.', 'error');
        } else {
          toast('Mietvertrag wurde gezeigt.', 'success');
        }
      });
      return;
    }

    showScreen('signature');
    const name = rental.playerName || 'Unbekannt';
    $('#signing-name').textContent = name;
    $('#signing-status').textContent = 'Signatur wird erstellt …';

    const sigImg = $('#signing-sig');
    sigImg.classList.remove('sig-reveal');
    sigImg.removeAttribute('src');

    rental.signatureDataUrl = generateSignatureImage(name);

    setTimeout(() => {
      sigImg.src = rental.signatureDataUrl;
      sigImg.classList.add('sig-reveal');
      $('#signing-status').textContent = 'Signiert';
      setTimeout(finalizeContract, 1100);
    }, 450);
  });

  function finalizeContract() {
    $('#signature-preview').innerHTML = `<img src="${rental.signatureDataUrl}" alt="Unterschrift" />`;
    const st = $('#contract-status');
    st.textContent = 'Unterschrieben';
    st.className = 'contract-value status-signed';
    showScreen('contract');

    setTimeout(() => {
      $('#success-text').textContent = 'Dein Fahrzeug wird bereitgestellt …';
      showScreen('success');
      post('signContract', {
        vehicleKey: rental.selectedVehicle.key,
        durationIdx: rental.selectedDurationIdx,
        paymentId: rental.selectedPaymentId,
        signatureDataUrl: rental.signatureDataUrl || '',
      }).then((res) => {
        if (res && res.success === false) {
          $('#success-text').textContent = res.reason || 'Die Anfrage konnte nicht verarbeitet werden.';
        }
      });
    }, 550);
  }

  // Navigation (Zurück / Schließen)
  document.addEventListener('click', (e) => {
    const target = e.target.closest('[data-action]');
    if (!target) return;
    const action = target.dataset.action;
    if (action === 'close') return post('closeUI').then(() => closeAll());
    if (action === 'back-to-vehicles') return showScreen('vehicles');
    if (action === 'back-to-details') {
      if (rental.viewerMode) return post('closeUI').then(() => closeAll());
      return showScreen('details');
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!modalOverlay.classList.contains('hidden')) return closeModal();
    if (contractViewerApp && !contractViewerApp.classList.contains('hidden')) return post('closeUI').then(() => closeAll());
    post('closeUI').then(() => closeAll());
  });

  // ════════════════════════════════════════════════
  // ADMIN-APP
  // ════════════════════════════════════════════════
  const adminApp = $('#admin-app');

  const admin = {
    data: null,        // vollständiger Datensatz vom Server
    fetchedAt: 0,      // Zeitstempel für Restzeit-Countdown
    tab: 'overview',
  };


  function normalizeAdminPayload(payload) {
    payload = payload || {};

    const vehicles = Array.isArray(payload.vehicles) ? payload.vehicles : [];
    const locations = Array.isArray(payload.locations) ? payload.locations : [];
    const durations = Array.isArray(payload.durations) ? payload.durations : [];
    const payments = Array.isArray(payload.payments) ? payload.payments : [];
    const rentals = Array.isArray(payload.rentals) ? payload.rentals : [];

    return {
      vehicles,
      locations,
      durations,
      payments,
      rentals,
      stats: payload.stats || { active: rentals.length, total: 0, revenue: 0, history: [] },
      settings: payload.settings || {},
    };
  }

  function safeRenderAdminTab() {
    try {
      renderAdminTab();
    } catch (err) {
      console.error('[MB_Fahrzeugvermitung] renderAdminTab failed', err);
      const wrap = document.querySelector(`#tab-${admin.tab || 'overview'}`);
      if (wrap) {
        wrap.innerHTML = `
          <div class="tab-head">
            <div class="tab-head-text">
              <span class="tab-title">Fehler</span>
              <span class="tab-sub">Tab konnte nicht geladen werden. Details stehen in F8.</span>
            </div>
          </div>
          <div class="panel">
            <div class="table-empty">${esc(err && err.message ? err.message : 'Unbekannter UI-Fehler')}</div>
          </div>
        `;
      }
    }
  }


  function adminSend(action, data) {
    return post('adminAction', { action, data: data || {} });
  }

  function applyAdminData(data) {
    admin.data = normalizeAdminPayload(data);
    admin.fetchedAt = Date.now();
    safeRenderAdminTab();
  }

  function openAdminApp(data) {
    admin.data = normalizeAdminPayload(data);
    admin.fetchedAt = Date.now();
    admin.tab = admin.tab || 'overview';
    adminApp.classList.remove('hidden');
    rentalApp.classList.add('hidden');
    setAdminTab(admin.tab);
  }

  // Tab-Navigation
  $('#admin-nav').addEventListener('click', (e) => {
    const item = e.target.closest('.admin-nav-item');
    if (item) setAdminTab(item.dataset.tab);
  });

  function setAdminTab(tab) {
    admin.tab = tab || 'overview';
    $$('.admin-nav-item').forEach((i) => i.classList.toggle('active', i.dataset.tab === admin.tab));
    $$('.admin-tab').forEach((t) => t.classList.add('hidden'));

    const target = $(`#tab-${admin.tab}`);
    if (target) target.classList.remove('hidden');

    safeRenderAdminTab();
  }


  function adminDeleteVehicleButton(vehicle) {
    if (!vehicle || !vehicle.key) return '';
    const label = vehicle.label || vehicle.name || vehicle.model || vehicle.key;
    const sourceType = vehicle.source || vehicle.origin || (vehicle.admin ? 'admin' : 'config');
    const locationName = vehicle.locationName || vehicle.location || vehicle.station || rental.currentLocation || '';
    return `<button class="btn btn-danger btn-admin-delete" data-admin-delete-vehicle="${esc(vehicle.key)}" data-vehicle-name="${esc(label)}" data-source-type="${esc(sourceType)}" data-location-name="${esc(locationName)}">Löschen</button>`;
  }



  function keepAdminPanelOpenAfterSave(message) {
    if (message) toast(message, 'success');
    if (adminApp) adminApp.classList.remove('hidden');
    if (rentalApp) rentalApp.classList.add('hidden');
    post('requestAdminData');
    setTimeout(renderAdminDeleteList, 120);
  }

  function renderAdminDeleteList() {
    const list = $('#admin-delete-list');
    if (!list) return;

    const vehicles = [];

    if (Array.isArray((admin.data || {}).vehicles)) {
      (admin.data || {}).vehicles.forEach((v) => vehicles.push(v));
    } else if ((admin.data || {}).vehicles && typeof (admin.data || {}).vehicles === 'object') {
      Object.values((admin.data || {}).vehicles).forEach((group) => {
        if (Array.isArray(group)) group.forEach((v) => vehicles.push(v));
      });
    }

    if (!vehicles.length) {
      list.innerHTML = `<div class="empty-state small">Keine Fahrzeuge vorhanden.</div>`;
      return;
    }

    list.innerHTML = vehicles.map((vehicle) => {
      const label = vehicle.label || vehicle.name || vehicle.model || vehicle.key || 'Fahrzeug';
      const model = vehicle.model || '—';
      const price = vehicle.price || vehicle.basePrice || vehicle.minutePrice || 0;
      return `
        <div class="admin-delete-row">
          <div class="admin-delete-info">
            <strong>${esc(label)}</strong>
            <span>${esc(model)} · ${money(price)}</span>
          </div>
          ${adminDeleteVehicleButton(vehicle)}
        </div>
      `;
    }).join('');
  }



  function renderSettingsTabSafeFallback() {
    const wrap = $('#tab-settings');
    if (!wrap) return;
    wrap.innerHTML = `
      <div class="tab-head">
        <div class="tab-head-text">
          <span class="tab-title">Einstellungen</span>
          <span class="tab-sub">Keine weiteren Einstellungen verfügbar.</span>
        </div>
      </div>
      <div class="panel">
        <div class="table-empty">Hier gibt es aktuell nichts einzustellen.</div>
      </div>
    `;
  }


  function renderAdminTab() {
    if (!admin.data) admin.data = normalizeAdminPayload({});
    if (admin.tab === 'overview') return renderOverview();
    if (admin.tab === 'vehicles') return renderVehiclesTab();
    if (admin.tab === 'locations') return renderLocationsTab();
    if (admin.tab === 'durations') return renderDurationsTab();
    if (admin.tab === 'settings') { try { return renderSettingsTab(); } catch (e) { console.error(e); return renderSettingsTabSafeFallback(); } }

    admin.tab = 'overview';
    return renderOverview();
  }

  function remainingOf(r) {
    const elapsed = Math.floor((Date.now() - admin.fetchedAt) / 1000);
    return Math.max(0, (r.remaining || 0) - elapsed);
  }

  // ── Tab: Übersicht ──
  function renderOverview() {
    const d = admin.data || normalizeAdminPayload({});
    const wrap = $('#tab-overview');

    const rentalRows = (d.rentals || []).map((r) => `
      <tr data-rental-src="${esc(r.src)}">
        <td class="td-strong">${esc(r.player)}</td>
        <td>${esc(r.vehicle)}</td>
        <td><span class="code">${esc(r.plate || '—')}</span></td>
        <td class="td-muted">${esc(r.location)}</td>
        <td class="td-num td-strong" data-remaining>${formatTimer(remainingOf(r))}</td>
        <td>
          <div class="td-actions">
            <button class="btn btn-secondary btn-sm" data-extend="${esc(r.src)}">+15 Min</button>
            <button class="btn btn-danger btn-sm" data-end="${esc(r.src)}">Beenden</button>
          </div>
        </td>
      </tr>
    `).join('');

    const historyRows = (d.stats.history || []).slice(0, 8).map((h) => `
      <tr>
        <td class="td-muted td-num">${esc(h.time)}</td>
        <td class="td-strong">${esc(h.player)}</td>
        <td>${esc(h.vehicle)}</td>
        <td class="td-muted">${esc(h.location)}</td>
        <td class="td-num">${esc(h.minutes)} Min</td>
        <td class="td-num td-strong">${money(h.price)}</td>
      </tr>
    `).join('');

    wrap.innerHTML = `
      <div class="tab-head">
        <div class="tab-head-text">
          <span class="tab-title">Übersicht</span>
          <span class="tab-sub">Aktive Mieten, Statistiken und letzte Vorgänge</span>
        </div>
      </div>

      <div class="stat-grid">
        <div class="stat-card stat-accent"><span class="stat-value">${(d.rentals || []).length}</span><span class="stat-label">Aktive Mieten</span></div>
        <div class="stat-card"><span class="stat-value">${Number(d.stats.total || 0).toLocaleString('de-DE')}</span><span class="stat-label">Mieten gesamt</span></div>
        <div class="stat-card stat-accent"><span class="stat-value">${money(d.stats.revenue)}</span><span class="stat-label">Umsatz gesamt</span></div>
        <div class="stat-card"><span class="stat-value">${(d.vehicles || []).length}</span><span class="stat-label">Fahrzeuge im Katalog</span></div>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Aktive Mieten</span></div>
        ${rentalRows ? `
          <table class="table">
            <thead><tr><th>Spieler</th><th>Fahrzeug</th><th>Kennzeichen</th><th>Standort</th><th>Restzeit</th><th></th></tr></thead>
            <tbody>${rentalRows}</tbody>
          </table>` : '<div class="table-empty">Derzeit sind keine Mieten aktiv.</div>'}
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Letzte Mieten</span></div>
        ${historyRows ? `
          <table class="table">
            <thead><tr><th>Zeitpunkt</th><th>Spieler</th><th>Fahrzeug</th><th>Standort</th><th>Dauer</th><th>Preis</th></tr></thead>
            <tbody>${historyRows}</tbody>
          </table>` : '<div class="table-empty">Noch keine abgeschlossenen Mietvorgänge.</div>'}
      </div>
    `;

    $$('[data-extend]', wrap).forEach((b) => b.addEventListener('click', () => {
      adminSend('extendRental', { src: Number(b.dataset.extend), minutes: 15 });
    }));

    $$('[data-end]', wrap).forEach((b) => b.addEventListener('click', () => {
      const row = b.closest('tr');
      const player = $('.td-strong', row).textContent;
      openModal({
        title: 'Miete beenden',
        bodyHTML: `<p class="modal-warn-text">Die aktive Miete von <strong>${esc(player)}</strong> wird sofort beendet und das Fahrzeug entfernt. Fortfahren?</p>`,
        buttons: [
          { label: 'Abbrechen', cls: 'btn-secondary' },
          { label: 'Miete beenden', cls: 'btn-danger', onClick: () => { adminSend('endRental', { src: Number(b.dataset.end) }); } },
        ],
      });
    }));
  }

  // Restzeiten in der Übersicht sekündlich aktualisieren
  setInterval(() => {
    if (adminApp.classList.contains('hidden') || admin.tab !== 'overview' || !admin.data) return;
    $$('#tab-overview tr[data-rental-src]').forEach((row) => {
      const src = row.dataset.rentalSrc;
      const r = (admin.data.rentals || []).find((x) => String(x.src) === src);
      if (r) $('[data-remaining]', row).textContent = formatTimer(remainingOf(r));
    });
  }, 1000);

  // ── Tab: Fahrzeuge ──
  function renderVehiclesTab() {
    const d = admin.data || normalizeAdminPayload({});
    const wrap = $('#tab-vehicles');

    const rows = (d.vehicles || []).map((v) => `
      <tr>
        <td><div class="veh-thumb"><img src="${esc(imgSrc(v.image))}" alt="" ${IMG_ONERROR} /></div></td>
        <td class="td-strong">${esc(v.label)}</td>
        <td><span class="code">${esc(v.model)}</span></td>
        <td><span class="badge badge-neutral">${esc(v.category)}</span></td>
        <td class="td-num td-strong">${money(v.price)}</td>
        <td>
          <div class="td-actions">
            <button class="btn btn-secondary btn-sm" data-edit="${esc(v.key)}">Bearbeiten</button>
            <button class="btn btn-danger btn-sm" data-delete="${esc(v.key)}">Löschen</button>
          </div>
        </td>
      </tr>
    `).join('');

    wrap.innerHTML = `
      <div class="tab-head">
        <div class="tab-head-text">
          <span class="tab-title">Fahrzeuge</span>
          <span class="tab-sub">Katalog verwalten — neue Fahrzeuge müssen anschließend einem Standort zugewiesen werden</span>
        </div>
        <button class="btn btn-primary" id="btn-add-vehicle">Fahrzeug hinzufügen</button>
      </div>

      <div class="panel">
        ${rows ? `
          <table class="table">
            <thead><tr><th></th><th>Bezeichnung</th><th>Modell</th><th>Kategorie</th><th>Grundpreis</th><th></th></tr></thead>
            <tbody>${rows}</tbody>
          </table>` : '<div class="table-empty">Keine Fahrzeuge im Katalog.</div>'}
      </div>
    `;

    $('#btn-add-vehicle').addEventListener('click', () => openVehicleModal(null));
    $$('[data-edit]', wrap).forEach((b) => b.addEventListener('click', () => {
      const v = d.vehicles.find((x) => x.key === b.dataset.edit);
      if (v) openVehicleModal(v);
    }));
    $$('[data-delete]', wrap).forEach((b) => b.addEventListener('click', () => {
      const v = d.vehicles.find((x) => x.key === b.dataset.delete);
      if (!v) return;
      openModal({
        title: 'Fahrzeug löschen',
        bodyHTML: `<p class="modal-warn-text"><strong>${esc(v.label)}</strong> wird aus dem Katalog und von allen Standorten entfernt. Fortfahren?</p>`,
        buttons: [
          { label: 'Abbrechen', cls: 'btn-secondary' },
          { label: 'Löschen', cls: 'btn-danger', onClick: () => { adminSend('deleteVehicle', { key: v.key }); } },
        ],
      });
    }));
  }

  function openVehicleModal(vehicle) {
    const isNew = !vehicle;
    openModal({
      title: isNew ? 'Fahrzeug hinzufügen' : 'Fahrzeug bearbeiten',
      bodyHTML: `
        <div class="field">
          <label class="field-label" for="vm-label">Bezeichnung</label>
          <input class="input" id="vm-label" value="${esc(vehicle ? vehicle.label : '')}" placeholder="z. B. Devauchee Quail" />
        </div>
        <div class="form-grid">
          <div class="field">
            <label class="field-label" for="vm-model">Spawn-Modell</label>
            <input class="input" id="vm-model" value="${esc(vehicle ? vehicle.model : '')}" placeholder="z. B. quail" ${isNew ? '' : ''} />
          </div>
          <div class="field">
            <label class="field-label" for="vm-price">Grundpreis (€)</label>
            <input class="input" id="vm-price" type="number" min="0" step="1" value="${esc(vehicle ? vehicle.price : '')}" placeholder="250" />
          </div>
        </div>
        <div class="form-grid">
          <div class="field">
            <label class="field-label" for="vm-category">Kategorie</label>
            <input class="input" id="vm-category" value="${esc(vehicle ? vehicle.category : '')}" placeholder="z. B. Sportwagen" />
          </div>
          <div class="field">
            <label class="field-label" for="vm-image">Bild (Link oder Pfad)</label>
            <input class="input" id="vm-image" value="${esc(vehicle ? vehicle.image : '')}" placeholder="https://… oder img/fahrzeug.svg" />
            <span class="field-hint">Direktlink zu einem Bild (https://….png/.jpg/.webp) oder lokale Datei aus html/img/</span>
          </div>
        </div>
        <div class="field">
          <span class="field-label">Bild-Vorschau</span>
          <div class="img-preview" id="vm-preview">
            <img id="vm-preview-img" alt="" />
            <span class="img-preview-note hidden" id="vm-preview-note">Bild konnte nicht geladen werden — Link prüfen.</span>
          </div>
        </div>
      `,
      buttons: [
        { label: 'Abbrechen', cls: 'btn-secondary' },
        {
          label: isNew ? 'Hinzufügen' : 'Speichern',
          cls: 'btn-primary',
          onClick: (m) => {
            const data = {
              key: vehicle ? vehicle.key : null,
              label: $('#vm-label', m).value.trim(),
              model: $('#vm-model', m).value.trim().toLowerCase(),
              price: Math.max(0, Math.floor(Number($('#vm-price', m).value))),
              category: $('#vm-category', m).value.trim() || 'Fahrzeug',
              image: $('#vm-image', m).value.trim() || 'img/placeholder.svg',
            };
            if (!data.label) { toast('Bitte eine Bezeichnung eingeben.', 'error'); return false; }
            if (!data.model) { toast('Bitte ein Spawn-Modell eingeben.', 'error'); return false; }
            if (!Number.isFinite(data.price) || data.price <= 0) { toast('Bitte einen gültigen Preis eingeben.', 'error'); return false; }
            adminSend('saveVehicle', data);
          },
        },
      ],
    });

    // Live-Vorschau des Bildes (Link oder lokaler Pfad)
    const input = $('#vm-image', modalEl);
    const previewImg = $('#vm-preview-img', modalEl);
    const previewNote = $('#vm-preview-note', modalEl);
    let previewTimer = null;

    function updatePreview() {
      const src = input.value.trim();
      previewNote.classList.add('hidden');
      previewImg.classList.remove('hidden');
      previewImg.onerror = () => {
        previewImg.classList.add('hidden');
        previewNote.classList.remove('hidden');
      };
      previewImg.src = imgSrc(src || IMG_FALLBACK);
    }

    input.addEventListener('input', () => {
      clearTimeout(previewTimer);
      previewTimer = setTimeout(updatePreview, 400);
    });
    updatePreview();
  }

  // ── Tab: Standorte ──
  function renderLocationsTab() {
    const d = admin.data || normalizeAdminPayload({});
    const wrap = $('#tab-locations');
    const locations = d.locations || [];

    const rows = locations.map((loc) => {
      const coords = loc.coords || {};
      const source = loc.source || 'admin';
      const canDelete = source !== 'config';
      return `
        <tr>
          <td class="td-strong">${esc(loc.label || loc.name || 'Mietstation')}</td>
          <td><span class="code">${Number(coords.x || 0).toFixed(2)}, ${Number(coords.y || 0).toFixed(2)}, ${Number(coords.z || 0).toFixed(2)}</span></td>
          <td><span class="code">${Number(loc.heading || 0).toFixed(1)}</span></td>
          <td><span class="code">${esc(loc.pedModel || 's_m_m_autoshop_01')}</span></td>
          <td><span class="badge badge-neutral">${source === 'config' ? 'Config' : 'Ingame'}</span></td>
          <td>
            <div class="td-actions">
              <button class="btn btn-secondary btn-sm" data-edit-location="${esc(loc.key)}">Bearbeiten</button>
              ${canDelete ? `<button class="btn btn-danger btn-sm" data-delete-location="${esc(loc.key)}">Löschen</button>` : ''}
            </div>
          </td>
        </tr>
      `;
    }).join('');

    wrap.innerHTML = `
      <div class="tab-head">
        <div class="tab-head-text">
          <span class="tab-title">Miet-Orte</span>
          <span class="tab-sub">Setze Koordinaten. Dort spawnt ein NPC, über den Spieler Fahrzeuge mieten.</span>
        </div>
        <button class="btn btn-primary" id="btn-add-location">Ort hinzufügen</button>
      </div>

      <div class="panel">
        ${rows ? `
          <table class="table">
            <thead>
              <tr><th>Name</th><th>Koordinaten</th><th>Heading</th><th>NPC</th><th>Quelle</th><th></th></tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        ` : '<div class="table-empty">Keine Miet-Orte vorhanden.</div>'}
      </div>
    `;

    $('#btn-add-location').addEventListener('click', () => openLocationModal(null));

    $$('[data-edit-location]', wrap).forEach((b) => b.addEventListener('click', () => {
      const loc = locations.find((x) => x.key === b.dataset.editLocation);
      if (loc) openLocationModal(loc);
    }));

    $$('[data-delete-location]', wrap).forEach((b) => b.addEventListener('click', () => {
      const loc = locations.find((x) => x.key === b.dataset.deleteLocation);
      if (!loc) return;

      openModal({
        title: 'Ort löschen',
        bodyHTML: `<p class="modal-warn-text"><strong>${esc(loc.label || loc.name)}</strong> wird als Miet-Ort entfernt. Fortfahren?</p>`,
        buttons: [
          { label: 'Abbrechen', cls: 'btn-secondary' },
          { label: 'Löschen', cls: 'btn-danger', onClick: () => {
              post('adminDeleteLocation', { key: loc.key }).then(() => {
                toast('Ort gelöscht.', 'success');
                post('requestAdminData');
              });
            }
          },
        ],
      });
    }));
  }

  function openLocationModal(location) {
    const isNew = !location;
    const coords = location && location.coords ? location.coords : {};

    openModal({
      title: isNew ? 'Ort hinzufügen' : 'Ort bearbeiten',
      bodyHTML: `
        <div class="field">
          <label class="field-label" for="lm-name">Name</label>
          <input class="input" id="lm-name" value="${esc(location ? (location.label || location.name || '') : '')}" placeholder="z. B. Flughafen Vermietung" />
        </div>

        <div class="form-grid">
          <div class="field">
            <label class="field-label" for="lm-x">X</label>
            <input class="input" id="lm-x" type="number" step="0.001" value="${esc(coords.x || '')}" />
          </div>
          <div class="field">
            <label class="field-label" for="lm-y">Y</label>
            <input class="input" id="lm-y" type="number" step="0.001" value="${esc(coords.y || '')}" />
          </div>
        </div>

        <div class="form-grid">
          <div class="field">
            <label class="field-label" for="lm-z">Z</label>
            <input class="input" id="lm-z" type="number" step="0.001" value="${esc(coords.z || '')}" />
          </div>
          <div class="field">
            <label class="field-label" for="lm-heading">Heading</label>
            <input class="input" id="lm-heading" type="number" step="0.01" value="${esc(location ? (location.heading || 0) : '')}" />
          </div>
        </div>

        <div class="field">
          <label class="field-label" for="lm-ped">NPC Modell</label>
          <input class="input" id="lm-ped" value="${esc(location ? (location.pedModel || '') : 's_m_m_autoshop_01')}" placeholder="s_m_m_autoshop_01" />
          <span class="field-hint">Ped-Model, z. B. s_m_m_autoshop_01, a_m_y_business_02</span>
        </div>

        <button class="btn btn-secondary btn-block" id="btn-use-current-coords" type="button">Aktuelle Position übernehmen</button>
      `,
      buttons: [
        { label: 'Abbrechen', cls: 'btn-secondary' },
        {
          label: isNew ? 'Ort erstellen' : 'Speichern',
          cls: 'btn-primary',
          onClick: (m) => {
            const data = {
              key: location ? location.key : null,
              name: $('#lm-name', m).value.trim(),
              x: Number($('#lm-x', m).value),
              y: Number($('#lm-y', m).value),
              z: Number($('#lm-z', m).value),
              heading: Number($('#lm-heading', m).value),
              pedModel: $('#lm-ped', m).value.trim() || 's_m_m_autoshop_01'
            };

            if (!data.name) { toast('Bitte einen Namen eingeben.', 'error'); return false; }
            if (![data.x, data.y, data.z].every(Number.isFinite)) { toast('Bitte gültige Koordinaten eingeben.', 'error'); return false; }

            post('adminSaveLocation', data).then(() => {
              toast('Ort gespeichert.', 'success');
              post('requestAdminData');
            });
          },
        },
      ],
    });

    const btn = $('#btn-use-current-coords', modalEl);
    if (btn) {
      btn.addEventListener('click', () => {
        post('getCurrentCoords').then((coords) => {
          if (!coords || coords.success === false) return toast('Koordinaten konnten nicht gelesen werden.', 'error');
          $('#lm-x', modalEl).value = coords.x;
          $('#lm-y', modalEl).value = coords.y;
          $('#lm-z', modalEl).value = coords.z;
          $('#lm-heading', modalEl).value = coords.heading;
          toast('Aktuelle Position übernommen.', 'success');
        });
      });
    }
  }


  function renderDurationsTab() {
    const d = admin.data || normalizeAdminPayload({});
    const wrap = $('#tab-durations');

    const rows = (d.durations || []).map((du) => durationRowHTML(du)).join('');

    wrap.innerHTML = `
      <div class="tab-head">
        <div class="tab-head-text">
          <span class="tab-title">Mietdauern</span>
          <span class="tab-sub">Preis = Grundpreis × Multiplikator (abgerundet)</span>
        </div>
        <button class="btn btn-primary" id="btn-save-durations">Alle speichern</button>
      </div>

      <div class="panel">
        <div class="panel-body" id="duration-rows">${rows}</div>
        <div class="panel-head" style="border-top:1px solid var(--border); border-bottom:none;">
          <button class="btn btn-secondary btn-sm" id="btn-add-duration">Zeile hinzufügen</button>
        </div>
      </div>
    `;

    bindDurationRows(wrap);

    $('#btn-add-duration').addEventListener('click', () => {
      const rowsWrap = $('#duration-rows');
      rowsWrap.insertAdjacentHTML('beforeend', durationRowHTML({ label: '', minutes: 30, multiplier: 1.0 }));
      bindDurationRows(wrap);
    });

    $('#btn-save-durations').addEventListener('click', () => {
      const list = $$('.form-row-inline', wrap).map((row) => ({
        label: $('[data-du-label]', row).value.trim(),
        minutes: Math.max(1, Math.floor(Number($('[data-du-minutes]', row).value))),
        multiplier: Math.max(0.1, Number($('[data-du-mult]', row).value)),
      })).filter((x) => x.label && Number.isFinite(x.minutes) && Number.isFinite(x.multiplier));

      if (!list.length) return toast('Mindestens eine gültige Mietdauer wird benötigt.', 'error');
      adminSend('saveDurations', { list });
    });
  }

  function durationRowHTML(du) {
    return `
      <div class="form-row-inline">
        <div class="field">
          <label class="field-label">Bezeichnung</label>
          <input class="input" data-du-label value="${esc(du.label)}" placeholder="z. B. 30 Minuten" />
        </div>
        <div class="field">
          <label class="field-label">Minuten</label>
          <input class="input" data-du-minutes type="number" min="1" step="1" value="${esc(du.minutes)}" />
        </div>
        <div class="field">
          <label class="field-label">Faktor</label>
          <input class="input" data-du-mult type="number" min="0.1" step="0.1" value="${esc(du.multiplier)}" />
        </div>
        <button class="btn btn-icon" data-du-remove aria-label="Entfernen" style="height:40px;">
          <svg viewBox="0 0 16 16" class="ico"><path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.2a1 1 0 0 0 1 .8h3.8a1 1 0 0 0 1-.8l.6-8.2"/></svg>
        </button>
      </div>
    `;
  }

  function bindDurationRows(wrap) {
    $$('[data-du-remove]', wrap).forEach((b) => {
      if (b.dataset.bound) return;
      b.dataset.bound = '1';
      b.addEventListener('click', () => b.closest('.form-row-inline').remove());
    });
  }

  // ── Tab: Einstellungen ──
  function renderSettingsTab() {
    const s = admin.data.settings || {};
    const wrap = $('#tab-settings');

    wrap.innerHTML = `
      <div class="tab-head">
        <div class="tab-head-text">
          <span class="tab-title">Einstellungen</span>
          <span class="tab-sub">Allgemeines Mietverhalten — Änderungen gelten sofort</span>
        </div>
        <button class="btn btn-primary" id="btn-save-settings">Speichern</button>
      </div>

      <div class="panel">
        <div class="panel-body">
          <div class="form-grid">
            <div class="field">
              <label class="field-label" for="set-cooldown">Cooldown (Minuten)</label>
              <input class="input" id="set-cooldown" type="number" min="0" step="1" value="${esc(s.cooldown)}" />
              <span class="field-hint">Wartezeit zwischen zwei Anmietungen, 0 = deaktiviert</span>
            </div>
            <div class="field">
              <label class="field-label" for="set-max">Max. aktive Mieten pro Spieler</label>
              <input class="input" id="set-max" type="number" min="1" step="1" value="${esc(s.maxActive)}" />
            </div>
            <div class="field">
              <label class="field-label" for="set-warn">Ablauf-Warnung (Sekunden)</label>
              <input class="input" id="set-warn" type="number" min="10" step="5" value="${esc(s.warningTime)}" />
              <span class="field-hint">Vorlaufzeit der Warnung vor Mietende</span>
            </div>
          </div>
        </div>
      </div>
    `;

    $('#btn-save-settings').addEventListener('click', () => {
      const data = {
        cooldown: Math.max(0, Math.floor(Number($('#set-cooldown').value))),
        maxActive: Math.max(1, Math.floor(Number($('#set-max').value))),
        warningTime: Math.max(10, Math.floor(Number($('#set-warn').value))),
      };
      if (![data.cooldown, data.maxActive, data.warningTime].every(Number.isFinite)) {
        return toast('Bitte gültige Zahlen eingeben.', 'error');
      }
      adminSend('saveSettings', data);
    });
  }

  // ════════════════════════════════════════════════
  // MIET-HUD
  // ════════════════════════════════════════════════
  const hud = $('#rental-hud');
  const HUD_WARNING_THRESHOLD = 60;

  function updateRentalHud(data) {
    if (!data.visible) {
      hud.classList.add('hidden');
      return;
    }
    hud.classList.remove('hidden');
    $('#hud-vehicle').textContent = data.vehicleLabel || 'Mietfahrzeug';
    $('#hud-timer').textContent = formatTimer(data.remainingSeconds || 0);

    const pct = data.totalSeconds
      ? Math.max(0, Math.min(100, (data.remainingSeconds / data.totalSeconds) * 100))
      : 0;
    $('#hud-progress-fill').style.width = `${pct}%`;
    hud.classList.toggle('hud-warning', (data.remainingSeconds || 0) <= HUD_WARNING_THRESHOLD);
  }

  function bindContractViewerEvents() {
    const app = ensureContractViewerApp();
    if (app.dataset.bound === '1') return;
    app.dataset.bound = '1';

    app.addEventListener('click', (e) => {
      if (e.target === app || e.target.closest('[data-viewer-close]')) {
        return post('closeUI').then(() => closeAll());
      }

      if (e.target.closest('[data-viewer-show]')) {
        if (!rental.currentContractId) return toast('Kein Mietvertrag ausgewählt.', 'error');
        post('showContractToNearest', { contractId: rental.currentContractId }).then((res) => {
          if (res && res.success === false) {
            toast(res.reason || 'Kein Spieler in der Nähe.', 'error');
          } else {
            toast('Mietvertrag wurde gezeigt.', 'success');
          }
        });
      }
    });
  }

  bindContractViewerEvents();


  document.addEventListener('click', (e) => {
    const deleteBtn = e.target.closest('[data-admin-delete-vehicle]');
    if (!deleteBtn) return;

    const vehicleKey = deleteBtn.dataset.adminDeleteVehicle;
    const vehicleName = deleteBtn.dataset.vehicleName || 'dieses Fahrzeug';
    const sourceType = deleteBtn.dataset.sourceType || 'admin';
    const locationName = deleteBtn.dataset.locationName || '';

    openModal(
      'Fahrzeug löschen?',
      `Soll ${vehicleName} wirklich aus der Vermietung gelöscht werden?`,
      [
        { label: 'Abbrechen', className: 'btn-secondary', action: () => closeModal() },
        {
          label: 'Löschen',
          className: 'btn-danger',
          action: () => {
            closeModal();
            post('adminDeleteVehicle', { vehicleKey, sourceType, locationName }).then((res) => {
              if (res && res.success === false) {
                toast(res.reason || 'Fahrzeug konnte nicht gelöscht werden.', 'error');
              } else {
                toast('Fahrzeug gelöscht.', 'success');
                post('requestAdminData');
              }
            });
          }
        }
      ]
    );
  });


  document.addEventListener('submit', (e) => {
    const form = e.target;
    if (form && (form.closest('#admin-app') || form.id === 'admin-vehicle-form')) {
      e.preventDefault();
      e.stopPropagation();
      return false;
    }
  }, true);

  // ════════════════════════════════════════════════
  // NUI-NACHRICHTEN VOM CLIENT (Lua)
  // ════════════════════════════════════════════════
  window.addEventListener('message', (event) => {
    setTimeout(renderAdminDeleteList, 0);
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {
      case 'openUI':
      case 'openRental':
      case 'rentalOpen':
        openRentalApp(data.data || data.payload || data);
        break;
      case 'forceOpenAdmin':
      case 'openAdmin':
      case 'adminOpen':
      case 'openAdminPanel':
        openAdminApp(data.data || data.payload || data.admin || {});
        break;
      case 'closeUI':         closeAll(); break;
      case 'setPlayerName':
        rental.playerName = data.name || 'Unbekannt';
        $('#contract-tenant').textContent = rental.playerName;
        break;
      case 'rentalDenied':
        showScreen('contract');
        toast(data.reason || 'Die Miete konnte nicht gestartet werden.', 'error');
        break;
      case 'openStoredContract': renderStoredContract(data.contract || {}, data.allowShow === true); break;
      case 'updateRentalHud': updateRentalHud(data); break;
      case 'adminData':       applyAdminData(data.data || data.payload || {}); break;
      case 'adminNotify':     toast(data.message, data.type || 'success'); break;
    }
  });

  // ════════════════════════════════════════════════
  // DEMO-MODUS (nur im Browser, nie in FiveM aktiv)
  // ════════════════════════════════════════════════
  const Demo = {
    data: null,

    init() {
      this.data = {
        vehicles: [
          { key: 'quail',   label: 'Devauchee Quail',      model: 'quail',   price: 250, category: 'Sportwagen', image: 'img/quail.svg' },
          { key: 'faggio2', label: 'Pegassi Faggio Sport', model: 'faggio2', price: 60,  category: 'Roller',     image: 'img/faggio2.svg' },
          { key: 'faggio',  label: 'Faggio',               model: 'faggio',  price: 40,  category: 'Roller',     image: 'img/faggio.svg' },
        ],
        locations: [
          { name: 'flughafen', label: 'Flughafen Vermietung', vehicles: ['quail', 'faggio2', 'faggio'] },
          { name: 'strand',    label: 'Strand Vermietung',    vehicles: ['faggio2', 'faggio'] },
        ],
        durations: [
          { label: '15 Minuten', minutes: 15,  multiplier: 1.0 },
          { label: '30 Minuten', minutes: 30,  multiplier: 1.8 },
          { label: '1 Stunde',   minutes: 60,  multiplier: 3.2 },
          { label: '2 Stunden',  minutes: 120, multiplier: 6.0 },
        ],
        payments: [
          { id: 'cash', label: 'Bar' },
          { id: 'card', label: 'Karte' },
        ],
        settings: { cooldown: 0, maxActive: 1, warningTime: 60 },
        rentals: [
          { src: 3, player: 'Mia Berger',  vehicle: 'Devauchee Quail',      plate: 'MVQK38A1', location: 'Flughafen Vermietung', remaining: 1264 },
          { src: 7, player: 'Jonas Weber', vehicle: 'Pegassi Faggio Sport', plate: 'MV7DK2P0', location: 'Strand Vermietung',    remaining: 322 },
        ],
        stats: {
          total: 148,
          revenue: 61240,
          history: [
            { time: '06.07. 14:32', player: 'Mia Berger',   vehicle: 'Devauchee Quail',      location: 'Flughafen Vermietung', minutes: 30, price: 450 },
            { time: '06.07. 13:58', player: 'Jonas Weber',  vehicle: 'Pegassi Faggio Sport', location: 'Strand Vermietung',    minutes: 15, price: 60 },
            { time: '06.07. 12:41', player: 'Lena Hoffmann', vehicle: 'Faggio',              location: 'Strand Vermietung',    minutes: 60, price: 128 },
            { time: '06.07. 11:15', player: 'Tom Fischer',  vehicle: 'Devauchee Quail',      location: 'Flughafen Vermietung', minutes: 120, price: 1500 },
          ],
        },
      };

      rental.playerName = 'Alex Muster';
      this.buildBar();
      this.openRental();
    },

    adminSnapshot() {
      return JSON.parse(JSON.stringify(this.data));
    },

    openRental() {
      const loc = this.data.locations[0];
      openRentalApp({
        locationLabel: loc.label,
        vehicles: loc.vehicles.map((k) => this.data.vehicles.find((v) => v.key === k)).filter(Boolean),
        durations: this.data.durations,
        payments: this.data.payments,
      });
    },

    handle(endpoint, body) {
      if (endpoint === 'closeUI') return {};
      if (endpoint === 'signContract') {
        setTimeout(() => toast('Demo: Fahrzeug würde jetzt gespawnt werden.', 'success'), 900);
        return { success: true };
      }
      if (endpoint === 'adminAction') {
        this.adminAction(body.action, body.data || {});
        return {};
      }
      return {};
    },

    adminAction(action, data) {
      const d = this.data;

      if (action === 'saveVehicle') {
        if (data.key) {
          const v = d.vehicles.find((x) => x.key === data.key);
          Object.assign(v, data);
        } else {
          let key = data.model;
          let n = 2;
          while (d.vehicles.some((x) => x.key === key)) key = `${data.model}_${n++}`;
          d.vehicles.push({ ...data, key });
        }
        toast('Fahrzeug gespeichert.', 'success');
      }
      if (action === 'deleteVehicle') {
        d.vehicles = d.vehicles.filter((x) => x.key !== data.key);
        d.locations.forEach((l) => { l.vehicles = l.vehicles.filter((k) => k !== data.key); });
        toast('Fahrzeug gelöscht.', 'success');
      }
      if (action === 'setLocationVehicles') {
        const loc = d.locations.find((l) => l.name === data.name);
        if (loc) loc.vehicles = data.keys;
        toast('Standort gespeichert.', 'success');
      }
      if (action === 'saveDurations') {
        d.durations = data.list.sort((a, b) => a.minutes - b.minutes);
        toast('Mietdauern gespeichert.', 'success');
      }
      if (action === 'saveSettings') {
        d.settings = data;
        toast('Einstellungen gespeichert.', 'success');
      }
      if (action === 'endRental') {
        d.rentals = d.rentals.filter((r) => r.src !== data.src);
        toast('Miete beendet, Fahrzeug entfernt.', 'success');
      }
      if (action === 'extendRental') {
        const r = d.rentals.find((x) => x.src === data.src);
        if (r) r.remaining = (r.remaining - Math.floor((Date.now() - admin.fetchedAt) / 1000)) + data.minutes * 60;
        toast(`Miete um ${data.minutes} Minuten verlängert.`, 'success');
      }

      applyAdminData(this.adminSnapshot());
    },

    buildBar() {
      const bar = $('#demo-bar');
      bar.classList.remove('hidden');
      bar.innerHTML = `
        <button data-demo="rental" class="active">Miet-UI</button>
        <button data-demo="admin">Admin-Menü</button>
        <button data-demo="hud">HUD</button>
      `;
      let hudTimer = null;

      bar.addEventListener('click', (e) => {
        const btn = e.target.closest('button');
        if (!btn) return;
        $$('button', bar).forEach((b) => b.classList.toggle('active', b === btn));
        closeAll();
        clearInterval(hudTimer);
        hud.classList.add('hidden');

        if (btn.dataset.demo === 'rental') this.openRental();
        if (btn.dataset.demo === 'admin') openAdminApp(this.adminSnapshot());
        if (btn.dataset.demo === 'hud') {
          let remaining = 312;
          const total = 900;
          const tick = () => updateRentalHud({ visible: true, remainingSeconds: remaining--, totalSeconds: total, vehicleLabel: 'Devauchee Quail' });
          tick();
          hudTimer = setInterval(tick, 1000);
        }
      });
    },
  };

  // MB_FIX_UNIFIED_OPEN_HANDLER
  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    const action = msg.action || msg.type;

    if (action === 'forceOpenAdmin' || action === 'openAdmin' || action === 'adminOpen' || action === 'openAdminPanel') {
      openAdminApp(msg.data || msg.payload || msg.admin || {});
    }

    if (action === 'openRental' || action === 'rentalOpen') {
      openRentalApp(msg.data || msg.payload || msg);
    }
  });

if (!IN_GAME) Demo.init();
})();
