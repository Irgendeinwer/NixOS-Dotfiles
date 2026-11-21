"use strict";

(() => {
  const ICONS = {
    music: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>',
    sync: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 0 0-15.5-6.36L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 15.5 6.36L21 16"/><path d="M16 16h5v5"/></svg>',
    package: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M16.5 9.4 7.55 4.24"/><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.29 7 12 12 20.71 7"/><line x1="12" y1="22" x2="12" y2="12"/></svg>',
    code: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>',
    globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>'
  };

  const state = {
    config: null,
    status: null,
    timerId: null
  };

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function formatGiB(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "0.0 GiB";
    return (bytes / (1024 ** 3)).toFixed(1) + " GiB";
  }

  function formatUptime(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) return "—";
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (d > 0) return `${d}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  function formatTimestamp(raw) {
    if (!raw) return "—";
    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) return String(raw);
    return parsed.toLocaleString(undefined, {
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    });
  }

  function formatHostForUrl(hostname) {
    if (hostname.includes(":") && !hostname.startsWith("[")) {
      return `[${hostname}]`;
    }
    return hostname;
  }

  function detectNetworkLabel(hostname) {
    if (hostname.endsWith(".local")) return "LAN mDNS";
    if (hostname.endsWith(".internal") || hostname.startsWith("100.")) return "Tailscale";
    if (hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1") return "Loopback";
    return "Direct";
  }

  function barTone(percent) {
    if (percent >= 88) return "crit";
    if (percent >= 72) return "warn";
    return "ok";
  }

  function unitTone(unitInfo) {
    if (!unitInfo) return { tone: "muted", label: "unknown" };
    const active = unitInfo.activeState;
    const sub = unitInfo.subState;
    if (active === "active") {
      return { tone: "ok", label: sub && sub !== "active" ? sub : "active" };
    }
    if (active === "activating" || active === "reloading") {
      return { tone: "warn", label: active };
    }
    if (active === "failed") {
      return { tone: "crit", label: "failed" };
    }
    return { tone: "muted", label: active || "inactive" };
  }

  function resolveServiceLink(svc) {
    const hostname = window.location.hostname || "localhost";
    const urlHost = formatHostForUrl(hostname);
    if (svc.location) {
      return { href: svc.location, display: svc.location };
    }
    if (svc.port) {
      const path = svc.path || "/";
      return {
        href: `${svc.scheme || "http"}://${urlHost}:${svc.port}${path}`,
        display: `${urlHost}:${svc.port}${path}`
      };
    }
    if (svc.url) {
      return { href: svc.url, display: svc.url };
    }
    return null;
  }

  function setBar(fillId, pct, tone) {
    const fill = document.getElementById(fillId);
    if (!fill) return;
    const clamped = Math.max(0, Math.min(100, Number(pct) || 0));
    fill.style.width = `${clamped}%`;
    fill.dataset.tone = tone;
  }

  function renderConnectionPill() {
    const host = window.location.hostname || "junixsrv";
    const proto = window.location.protocol === "https:" ? "HTTPS" : "HTTP";
    const net = detectNetworkLabel(host);
    const pill = document.getElementById("connection-pill");
    if (pill) {
      pill.textContent = `${net} · ${proto} · ${host}`;
      pill.dataset.secure = window.location.protocol === "https:" ? "true" : "false";
    }
  }

  function renderVitals() {
    const data = state.status;
    if (!data) return;

    const hostInfo = data.host || {};
    const genText = hostInfo.generation !== null && hostInfo.generation !== undefined
      ? `Gen #${hostInfo.generation}`
      : "Flake";
    const subtitle = document.getElementById("host-subtitle");
    if (subtitle) {
      subtitle.textContent = `${hostInfo.osName || "NixOS"} · ${genText} · Linux ${hostInfo.kernel || "?"} · up ${formatUptime(hostInfo.uptimeSeconds)}`;
    }

    const loads = Array.isArray(hostInfo.loadAvg) ? hostInfo.loadAvg : [0, 0, 0];
    const cores = hostInfo.cpuCount || 1;
    const loadPct = Math.min(100, ((loads[0] || 0) / cores) * 100);
    document.getElementById("cpu-primary").textContent = `${Number(loads[0] || 0).toFixed(2)}`;
    document.getElementById("cpu-secondary").textContent = `5m ${Number(loads[1] || 0).toFixed(2)} · 15m ${Number(loads[2] || 0).toFixed(2)} · ${cores} threads`;
    setBar("cpu-bar", loadPct, barTone(loadPct));

    const mem = data.memory || {};
    const memPct = Number(mem.percent || 0);
    document.getElementById("mem-primary").textContent = `${formatGiB(mem.usedBytes)} / ${formatGiB(mem.totalBytes)}`;
    const memTag = mem.source === "cgroup" ? "cgroup v2 limit" : "system RAM";
    document.getElementById("mem-secondary").textContent = `${memPct.toFixed(1)}% used · ${memTag}`;
    setBar("mem-bar", memPct, barTone(memPct));

    const disk = data.disk || {};
    const diskPct = Number(disk.percent || 0);
    document.getElementById("disk-primary").textContent = `${formatGiB(disk.usedBytes)} / ${formatGiB(disk.totalBytes)}`;
    document.getElementById("disk-secondary").textContent = `${formatGiB(disk.freeBytes)} free (${diskPct.toFixed(1)}% used)`;
    setBar("disk-bar", diskPct, barTone(diskPct));

    renderNightly(data.nightly);
    renderInfraFooter(data.units || {});
  }

  function renderNightly(nightly) {
    const badge = document.getElementById("nightly-badge");
    const primary = document.getElementById("nightly-primary");
    const secondary = document.getElementById("nightly-secondary");
    const detailsWrap = document.getElementById("nightly-details");
    const summaryList = document.getElementById("nightly-summary-list");

    if (!nightly || !nightly.enabled) {
      badge.textContent = "Disabled";
      badge.dataset.tone = "muted";
      primary.textContent = "Off";
      secondary.textContent = "Nightly auto-builder is disabled";
      detailsWrap.hidden = true;
      return;
    }

    const last = nightly.lastRun;
    if (nightly.running) {
      badge.textContent = "Running";
      badge.dataset.tone = "active";
      primary.textContent = "Update in progress";
    } else if (!last) {
      badge.textContent = "Scheduled";
      badge.dataset.tone = "muted";
      primary.textContent = "Awaiting first run";
    } else if (last.state === "success") {
      badge.textContent = "Updated";
      badge.dataset.tone = "ok";
      primary.textContent = formatTimestamp(last.finishedAt);
    } else if (last.state === "up_to_date") {
      badge.textContent = "Up to date";
      badge.dataset.tone = "info";
      primary.textContent = formatTimestamp(last.finishedAt);
    } else if (last.state === "warning") {
      badge.textContent = "Deferred";
      badge.dataset.tone = "warn";
      primary.textContent = formatTimestamp(last.finishedAt);
    } else {
      badge.textContent = "Failed";
      badge.dataset.tone = "crit";
      primary.textContent = `${last.stage || "error"} (exit ${last.exitCode})`;
    }

    const metaParts = [];
    if (last && last.durationHuman) metaParts.push(`ran ${last.durationHuman}`);
    if (nightly.nextRun) metaParts.push(`next ${formatTimestamp(nightly.nextRun)}`);
    secondary.textContent = metaParts.join(" · ") || "Scheduled overnight";

    summaryList.replaceChildren();
    if (last && Array.isArray(last.summary) && last.summary.length > 0) {
      for (const line of last.summary) {
        summaryList.appendChild(el("li", null, line.replace(/^•\s*/, "")));
      }
      detailsWrap.hidden = false;
    } else {
      detailsWrap.hidden = true;
    }
  }

  function renderServices() {
    const container = document.getElementById("services-root");
    if (!container || !state.config) return;
    container.replaceChildren();

    const units = (state.status && state.status.units) || {};
    const services = Array.isArray(state.config.services) ? [...state.config.services] : [];
    services.sort((a, b) => (a.order - b.order) || a.title.localeCompare(b.title));

    const groups = new Map();
    for (const svc of services) {
      const cat = svc.category || "Services";
      if (!groups.has(cat)) groups.set(cat, []);
      groups.get(cat).push(svc);
    }

    const hostname = window.location.hostname || state.config.hostName || "junixsrv";

    for (const [category, items] of groups.entries()) {
      const section = el("section", "category-section");
      const heading = el("h2", "category-title", category);
      section.appendChild(heading);

      const grid = el("div", "cards-grid");
      for (const svc of items) {
        const link = resolveServiceLink(svc);
        const card = link ? el("a", "service-card") : el("article", "service-card service-card--internal");
        if (link) {
          card.href = link.href;
          card.rel = "noopener";
        }

        const top = el("div", "card-top");
        const iconWrap = el("span", "card-icon");
        const svgMarkup = ICONS[svc.icon] || ICONS.globe;
        const parsedSvg = new DOMParser().parseFromString(svgMarkup, "image/svg+xml").documentElement;
        iconWrap.appendChild(document.importNode(parsedSvg, true));
        top.appendChild(iconWrap);

        const badges = el("div", "card-badges");
        if (svc.badge) {
          badges.appendChild(el("span", "pill pill--subtle", svc.badge));
        }
        if (svc.systemdUnit) {
          const st = unitTone(units[svc.systemdUnit]);
          const unitPill = el("span", "pill pill--unit");
          unitPill.dataset.tone = st.tone;
          unitPill.title = svc.systemdUnit;
          unitPill.appendChild(el("span", "dot"));
          unitPill.appendChild(el("span", null, st.label));
          badges.appendChild(unitPill);
        }
        top.appendChild(badges);
        card.appendChild(top);

        card.appendChild(el("h3", "card-title", svc.title));
        if (svc.description) {
          card.appendChild(el("p", "card-desc", svc.description));
        }

        if (link) {
          const footer = el("div", "card-target");
          footer.appendChild(el("span", "card-target-url", link.display));
          footer.appendChild(el("span", "card-arrow", "↗"));
          card.appendChild(footer);
        } else if (svc.hintCommand) {
          const cmdText = svc.hintCommand.replaceAll("{host}", hostname);
          const hintBox = el("div", "card-hint");
          hintBox.appendChild(el("code", "card-hint-code", cmdText));
          if (navigator.clipboard && window.isSecureContext) {
            const copyBtn = el("button", "copy-btn", "Copy");
            copyBtn.type = "button";
            copyBtn.addEventListener("click", async (ev) => {
              ev.preventDefault();
              ev.stopPropagation();
              try {
                await navigator.clipboard.writeText(cmdText);
                copyBtn.textContent = "Copied";
                setTimeout(() => { copyBtn.textContent = "Copy"; }, 1600);
              } catch {
                copyBtn.textContent = "Error";
              }
            });
            hintBox.appendChild(copyBtn);
          }
          card.appendChild(hintBox);
        }

        grid.appendChild(card);
      }

      section.appendChild(grid);
      container.appendChild(section);
    }
  }

  function renderInfraFooter(units) {
    const wrap = document.getElementById("infra-units");
    if (!wrap || !state.config) return;
    wrap.replaceChildren();
    const list = Array.isArray(state.config.infraUnits) ? state.config.infraUnits : [];
    for (const unitName of list) {
      const st = unitTone(units[unitName]);
      const chip = el("span", "infra-chip");
      chip.dataset.tone = st.tone;
      chip.appendChild(el("span", "dot"));
      chip.appendChild(el("span", "infra-name", unitName.replace(/\.(service|socket)$/, "")));
      chip.appendChild(el("span", "infra-state", st.label));
      wrap.appendChild(chip);
    }
  }

  async function refreshStatus() {
    const statusIndicator = document.getElementById("refresh-state");
    try {
      const res = await fetch("/api/status", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      state.status = await res.json();
      renderVitals();
      renderServices();
      if (statusIndicator) {
        statusIndicator.textContent = "Live";
        statusIndicator.dataset.tone = "ok";
      }
    } catch {
      if (statusIndicator) {
        statusIndicator.textContent = "Offline";
        statusIndicator.dataset.tone = "crit";
      }
    }
  }

  async function init() {
    renderConnectionPill();
    const refreshBtn = document.getElementById("refresh-btn");
    if (refreshBtn) {
      refreshBtn.addEventListener("click", () => { refreshStatus(); });
    }

    try {
      const cfgRes = await fetch("/portal-config.json", { cache: "no-cache" });
      if (cfgRes.ok) {
        state.config = await cfgRes.json();
        const titleEl = document.getElementById("host-title");
        if (titleEl && state.config.hostName) {
          titleEl.textContent = state.config.hostName;
        }
        renderServices();
      }
    } catch {
      // Static config load failed; status poll still runs.
    }

    await refreshStatus();
    state.timerId = window.setInterval(() => {
      if (!document.hidden) refreshStatus();
    }, 15000);
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) refreshStatus();
    });
  }

  document.addEventListener("DOMContentLoaded", init);
})();
