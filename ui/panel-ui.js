(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.PlipPanelUI = factory();
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function sameList(a, b) {
    const left = a || [];
    const right = b || [];
    if (left.length !== right.length) return false;
    for (let i = 0; i < left.length; i++) {
      if ((left[i].id || "") !== (right[i].id || "") || (left[i].name || "") !== (right[i].name || "")) return false;
    }
    return true;
  }

  function create(opts) {
    const $ = opts.get;
    const send = (name, value) => {
      const api = opts.bridge ? opts.bridge() : null;
      if (api && typeof api[name] === "function") api[name](value);
    };
    const makeEl = opts.makeEl || ((tag) => document.createElement(tag));
    let current = null;
    let menuOpen = false;
    let draggingVolume = false;

    function setSwitch(id, on) {
      $(id).setAttribute("aria-checked", on ? "true" : "false");
    }

    function switchOn(id) {
      return $(id).getAttribute("aria-checked") === "true";
    }

    function toggleSwitch(id, key, action) {
      const next = !switchOn(id);
      setSwitch(id, next);
      if (current) current[key] = next;
      send(action, next);
    }

    function closest(el, selector) {
      let node = el && el.nodeType === 3 ? el.parentNode : el;
      if (!node) return null;
      if (node.closest) return node.closest(selector);
      const cls = selector.startsWith(".") ? selector.slice(1) : "";
      while (node) {
        const className = node.className || "";
        if (cls && String(className).split(/\s+/).includes(cls)) return node;
        if (!cls && node.tag === selector) return node;
        node = node.parentNode || node.parent;
      }
      return null;
    }

    function closeMenu() {
      menuOpen = false;
      $("menu").classList.add("hidden");
    }

    function renderMenu(state) {
      const menu = $("menu");
      menu.replaceChildren();
      for (const pack of state.packs || []) {
        const button = makeEl("button");
        button.type = "button";
        button.dataset.id = pack.id;
        button.textContent = pack.name;
        button.setAttribute("aria-current", pack.id === state.packID ? "true" : "false");
        menu.append(button);
      }
      menu.classList.toggle("hidden", !menuOpen);
    }

    function bind() {
      $("volume").addEventListener("pointerdown", () => { draggingVolume = true; });
      $("volume").addEventListener("input", () => {
        $("percent").textContent = $("volume").value;
        if (current) current.volume = Number($("volume").value) / 100;
        send("setVolume", Number($("volume").value) / 100);
      });
      $("volume").addEventListener("change", () => { draggingVolume = false; });
      $("muted").addEventListener("click", () => toggleSwitch("muted", "muted", "setMuted"));
      $("combo").addEventListener("click", () => toggleSwitch("combo", "combo", "setCombo"));
      $("smart").addEventListener("click", () => toggleSwitch("smart", "smartMute", "setSmartMute"));
      $("login").addEventListener("click", () => toggleSwitch("login", "login", "setLogin"));
      $("pack").addEventListener("click", () => {
        menuOpen = !menuOpen;
        $("menu").classList.toggle("hidden", !menuOpen);
      });
      $("permission").addEventListener("click", () => send("openAccessibility"));
      $("loginOpen").addEventListener("click", () => send("openLogin"));
      $("import").addEventListener("click", () => {
        closeMenu();
        send("importPack");
      });
      $("quit").addEventListener("click", () => send("quit"));
      $("menu").addEventListener("click", (event) => {
        const button = closest(event.target, "button");
        if (!button || !button.dataset || !button.dataset.id) return;
        closeMenu();
        send("selectPack", button.dataset.id);
      });
    }

    function render(state) {
      const next = Object.assign({}, state, { packs: (state.packs || []).slice() });
      const packsChanged = !current || !sameList(current.packs, next.packs) || current.packID !== next.packID;
      current = next;
      $("packName").textContent = next.packName || "无音效";
      if (!draggingVolume) {
        $("volume").value = String(Math.round((next.volume || 0) * 100));
        $("percent").textContent = $("volume").value;
      }
      setSwitch("muted", !!next.muted);
      setSwitch("combo", !!next.combo);
      setSwitch("smart", !!next.smartMute);
      setSwitch("login", !!next.login);
      $("permission").classList.toggle("hidden", next.accessibility !== false);
      $("suppress").textContent = next.suppressReason || "";
      $("suppress").classList.toggle("hidden", !next.suppressReason);
      $("loginMessage").textContent = next.loginMessage || "";
      $("loginMessage").classList.toggle("hidden", !next.loginMessage);
      $("loginOpen").classList.toggle("hidden", !next.loginMessage);
      if (packsChanged) renderMenu(next);
      else $("menu").classList.toggle("hidden", !menuOpen);
      if (opts.onResize) {
        const box = opts.measure ? opts.measure() : null;
        if (box) opts.onResize(box);
      }
    }

    return { bind, render, toggleSwitch, setSwitch, switchOn, sameList };
  }

  return { create, sameList };
});
