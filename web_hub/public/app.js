function hubToken() {
  return localStorage.getItem('hubToken') || '';
}

function setHubToken() {
  const entered = prompt('Enter the hub token from config/local.env on the server.');
  if (entered && entered.trim()) {
    localStorage.setItem('hubToken', entered.trim());
  }
}

function copyHostAddress() {
  const el = document.getElementById('txt-tailscale-ip');
  if (!el) return;
  const value = el.textContent.trim();
  if (!value || value === 'detecting…') return;
  navigator.clipboard.writeText(value);
}

async function hubPost(url, body, retried) {
  const headers = { 'Content-Type': 'application/json' };
  const token = hubToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify(body || {})
  });
  if (res.status === 401 && !retried) {
    const entered = prompt('This action needs the hub token from config/local.env on the server.');
    if (!entered || !entered.trim()) {
      throw new Error('Hub token required');
    }
    localStorage.setItem('hubToken', entered.trim());
    return hubPost(url, body, true);
  }
  return res;
}

// Register Service Worker for PWA
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/service-worker.js').catch(err => console.log('SW registration failed:', err));
  });
}

// Tab Switching
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    
    btn.classList.add('active');
    const tabName = btn.getAttribute('data-tab');
    const view = document.getElementById(`view-${tabName}`);
    if (view) view.classList.add('active');
  });
});

// Update Telemetry & Status
async function updateStats() {
  try {
    const res = await fetch('/api/stats');
    if (!res.ok) return;
    const data = await res.json();

    // GPU
    if (data.gpu) {
      const g = data.gpu;
      const utilEl = document.getElementById('val-gpu-util');
      const barUtil = document.getElementById('bar-gpu-util');
      const clockEl = document.getElementById('gpu-clock');
      const powerEl = document.getElementById('sub-gpu-power');

      if (utilEl) utilEl.textContent = `${Math.round(g.gpu_util)}%`;
      if (barUtil) barUtil.style.width = `${Math.min(100, Math.max(0, g.gpu_util))}%`;
      if (clockEl) clockEl.textContent = `${Math.round(g.clock_graphics)} MHz`;
      if (powerEl) powerEl.textContent = `Power Draw: ${Math.round(g.power_draw)}W / ${Math.round(g.power_limit)}W`;

      // VRAM
      const vramEl = document.getElementById('val-vram');
      const barVram = document.getElementById('bar-vram');
      const subVram = document.getElementById('sub-vram-pct');
      const vramGb = (g.vram_used / 1024).toFixed(1);
      const totalGb = (g.vram_total / 1024).toFixed(0);
      const vramPct = Math.round((g.vram_used / g.vram_total) * 100);

      if (vramEl) vramEl.textContent = `${vramGb} GB`;
      if (barVram) barVram.style.width = `${vramPct}%`;
      if (subVram) subVram.textContent = `${vramPct}% of ${totalGb} GB &bull; Ultra Headroom`;

      // Temp
      const tempEl = document.getElementById('val-temp');
      const barTemp = document.getElementById('bar-temp');
      const subTemp = document.getElementById('sub-temp-status');
      if (tempEl) tempEl.textContent = `${Math.round(g.temperature)}°C`;
      if (barTemp) {
        const tempPct = Math.min(100, (g.temperature / 90) * 100);
        barTemp.style.width = `${tempPct}%`;
        barTemp.style.background = g.temperature > 75 ? 'var(--accent-amber)' : 'var(--accent-green)';
      }
      if (subTemp) subTemp.textContent = g.temperature < 60 ? 'Optimal & Cool' : 'Gaming Load';
    }

    // CPU & RAM
    const cpuEl = document.getElementById('val-cpu');
    const barCpu = document.getElementById('bar-cpu');
    const subRam = document.getElementById('sub-ram');
    if (cpuEl) cpuEl.textContent = `${Math.round(data.cpu_usage)}%`;
    if (barCpu) barCpu.style.width = `${Math.min(100, data.cpu_usage)}%`;
    if (subRam && data.ram_used_mb && data.ram_total_mb) {
      const ramUsedGb = (data.ram_used_mb / 1024).toFixed(1);
      const ramTotalGb = (data.ram_total_mb / 1024).toFixed(0);
      subRam.textContent = `RAM: ${ramUsedGb} / ${ramTotalGb} GB Used`;
    }

    // Services
    if (data.services) {
      updatePill('pill-display', data.services.display, 'Virtual Display (:0)');
      updatePill('pill-audio', data.services.audio, 'Virtual PulseAudio Sink');
      updatePill('pill-sunshine', data.services.sunshine, 'Sunshine Stream Host');
      updatePill('pill-steam', data.services.steam, 'Steam Engine');
    }

    // Network badge
    if (data.network) {
      const host = data.network.tailscale_ip || '';
      const tsBadge = document.getElementById('tailscale-badge');
      if (tsBadge) tsBadge.textContent = host ? `TS: ${host}` : 'TS: unavailable';
      const tsTxt = document.getElementById('txt-tailscale-ip');
      if (tsTxt) tsTxt.textContent = host || 'unavailable';
      const settingsHost = document.getElementById('settings-tailscale-ip');
      if (settingsHost) settingsHost.textContent = host || 'unavailable';
      const settingsPublic = document.getElementById('settings-public-ip');
      if (settingsPublic) settingsPublic.textContent = data.network.public_ip || 'not configured';
      const publicNote = document.getElementById('public-ip-note');
      if (publicNote) {
        if (data.network.public_ip) {
          publicNote.style.display = 'block';
          publicNote.textContent = `Configured public address: ${data.network.public_ip}`;
        } else {
          publicNote.style.display = 'none';
          publicNote.textContent = '';
        }
      }
    }
  } catch (e) {
    console.warn('Telemetry poll failed:', e);
  }
}

function updatePill(id, isActive, name) {
  const el = document.getElementById(id);
  if (!el) return;
  el.className = `service-pill ${isActive ? 'active' : 'inactive'}`;
  el.innerHTML = `<span class="pulse-dot" style="background: ${isActive ? 'var(--accent-green)' : 'var(--accent-red)'}"></span> ${name} (${isActive ? 'ACTIVE' : 'STOPPED'})`;
}

// Service Controls
async function controlServices(action) {
  const btn = document.getElementById(`btn-${action}-services`) || document.getElementById('btn-restart-services');
  const originalText = btn ? btn.textContent : '';
  if (btn) {
    btn.disabled = true;
    btn.textContent = action === 'stop' ? 'Stopping...' : (action === 'start' ? 'Starting...' : 'Restarting...');
  }
  try {
    const res = await hubPost('/api/services', { action });
    const data = await res.json();
    alert(`Service action [${action}]: ${data.success ? 'Success' : 'Failed'}`);
  } catch (e) {
    alert(`Error: ${e.message}`);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = originalText;
    }
    updateStats();
    loadInstalledGames();
  }
}

// Launch Steam
async function launchSteam() {
  const btn = document.getElementById('btn-launch-steam');
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Launching...';
  }
  try {
    const res = await hubPost('/api/launch_steam', {});
    const data = await res.json();
    alert(data.message || 'Steam Big Picture launched!');
  } catch (e) {
    alert(`Error launching Steam: ${e.message}`);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Launch Steam';
    }
    updateStats();
    loadInstalledGames();
  }
}

// Pair PIN
async function submitPairingPin() {
  const input = document.getElementById('pin-input');
  const resultDiv = document.getElementById('pair-result');
  const pin = input.value.trim();
  if (!pin || pin.length < 4) {
    alert('Please enter the 4-digit PIN shown on your phone in Moonlight.');
    return;
  }

  resultDiv.style.display = 'block';
  resultDiv.style.color = 'var(--neon-cyan)';
  resultDiv.textContent = `Pairing PIN ${pin}...`;

  try {
    const res = await hubPost('/api/pair_pin', { pin });
    const data = await res.json();
    if (data.success) {
      resultDiv.style.color = 'var(--accent-green)';
      resultDiv.textContent = '🎉 Successfully paired! Check Moonlight on your device.';
      input.value = '';
    } else {
      resultDiv.style.color = 'var(--accent-red)';
      resultDiv.textContent = `Pairing response: ${data.message || data.error || 'Check status'}`;
    }
  } catch (e) {
    resultDiv.style.color = 'var(--accent-red)';
    resultDiv.textContent = `Network error: ${e.message}`;
  }
}

// Reset Pairing Session
async function resetPairingSession() {
  const resultDiv = document.getElementById('pair-result');
  resultDiv.style.display = 'block';
  resultDiv.style.color = 'var(--neon-cyan)';
  resultDiv.textContent = 'Resetting Sunshine pairing state...';
  try {
    const res = await hubPost('/api/reset_pairing', {});
    const data = await res.json();
    resultDiv.style.color = 'var(--accent-green)';
    resultDiv.textContent = '✅ Session reset! Now tap the host in Moonlight to get a fresh PIN.';
  } catch (e) {
    resultDiv.style.color = 'var(--accent-red)';
    resultDiv.textContent = `Reset error: ${e.message}`;
  }
}

// Check live pairing state
async function checkPairingState() {
  try {
    const res = await fetch('/api/pair_state');
    const data = await res.json();
    const banner = document.getElementById('live-pairing-banner');
    const deviceName = document.getElementById('detected-device-name');
    if (banner && deviceName) {
      if (data.pairings && data.pairings.length > 0) {
        const client = data.pairings[0];
        deviceName.textContent = `${client.name || 'Client'} (${client.address || 'connected'})`;
        banner.style.display = 'block';
      } else {
        banner.style.display = 'none';
      }
    }
  } catch (e) {
    // silently ignore
  }
}

// Poll telemetry every 2 seconds
setInterval(() => {
  updateStats();
  checkPairingState();
}, 2000);
updateStats();
loadInstalledGames();
checkPairingState();

// Reload games list every 30 seconds (not every poll)
setInterval(() => {
  loadInstalledGames();
}, 30000);


// Load installed games
async function loadInstalledGames() {
  const container = document.getElementById('installed-games-list');
  if (!container) return;
  try {
    const res = await fetch('/api/installed_games');
    const games = await res.json();
    if (!games || games.length === 0) {
      container.innerHTML = '<div style="color: var(--text-dim); font-size: 0.85rem;">No user-installed games found in Steam library.</div>';
      return;
    }
    container.innerHTML = games.map(g => `
      <div style="display: flex; justify-content: space-between; align-items: center; background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.08); padding: 0.75rem 1rem; border-radius: 8px;">
        <div>
          <div style="font-weight: 600; font-size: 0.95rem; color: #fff;">${g.name}</div>
          <div style="font-size: 0.75rem; color: var(--text-dim);">AppID: ${g.appid} &bull; Folder: ${g.installdir}</div>
        </div>
        <button class="btn btn-secondary" style="border-color: rgba(255, 75, 75, 0.4); color: #ff5555; font-size: 0.8rem; padding: 0.35rem 0.75rem;" onclick="uninstallGame('${g.appid}', '${g.name.replace(/'/g, "\\'")}')">
          🗑️ Uninstall Game
        </button>
      </div>
    `).join('');
  } catch (e) {
    container.innerHTML = '<div style="color: var(--accent-red); font-size: 0.85rem;">Failed to load games: ' + e.message + '</div>';
  }
}

async function uninstallGame(appid, name) {
  if (!confirm(`Uninstall "${name}"? This will delete all game files.`)) {
    return;
  }
  try {
    const res = await hubPost('/api/uninstall_game', { appid });
    const data = await res.json();
    if (data.success) {
      loadInstalledGames();
      updateStats();
    } else {
      alert(`Uninstall failed: ${data.output || data.error || 'Unknown error'}`);
    }
  } catch (e) {
    alert(`Network error: ${e.message}`);
  }
}
