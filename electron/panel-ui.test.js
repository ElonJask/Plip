const assert = require("assert");
const { create, sameList } = require("../ui/panel-ui.js");

class El {
  constructor(tag) {
    this.tag = tag;
    this.attrs = {};
    this.className = "";
    this.textContent = "";
    this.value = "";
    this.type = "";
    this.dataset = {};
    this.children = [];
    this.parent = null;
    this.listeners = {};
    this.classList = {
      toggle: (name, on) => {
        const parts = new Set(this.className.split(/\s+/).filter(Boolean));
        if (on === false) parts.delete(name);
        else if (on === true) parts.add(name);
        else if (parts.has(name)) parts.delete(name);
        else parts.add(name);
        this.className = [...parts].join(" ");
      },
      add: (name) => this.classList.toggle(name, true),
      contains: (name) => this.className.split(/\s+/).includes(name)
    };
  }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return this.attrs[k]; }
  addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
  emit(type, target) {
    const event = { target: target || this, preventDefault() {}, stopPropagation() {} };
    let node = this;
    while (node) {
      for (const fn of node.listeners[type] || []) fn(event);
      node = node.parent;
    }
  }
  click() { this.emit("click"); }
  closest(selector) {
    let node = this;
    const cls = selector.startsWith(".") ? selector.slice(1) : selector;
    while (node) {
      if (node.className.split(/\s+/).includes(cls) || node.tag === selector) return node;
      node = node.parent;
    }
    return null;
  }
  append(...nodes) {
    for (const node of nodes) {
      node.parent = this;
      this.children.push(node);
    }
  }
  replaceChildren() {
    for (const child of this.children) child.parent = null;
    this.children = [];
  }
}

function harness() {
  const nodes = {
    packName: new El("div"),
    volume: new El("input"),
    percent: new El("div"),
    muted: new El("button"),
    combo: new El("button"),
    smart: new El("button"),
    login: new El("button"),
    permission: new El("button"),
    status: new El("div"),
    statusLine: new El("div"),
    loginExtra: new El("div"),
    loginOpen: new El("button"),
    loginMessage: new El("div"),
    menu: new El("div"),
    pack: new El("button"),
    import: new El("button"),
    quit: new El("button")
  };
  const sent = [];
  const ui = create({
    get: (id) => nodes[id],
    bridge: () => new Proxy({}, { get: (_, name) => (value) => sent.push([name, value]) }),
    makeEl: (tag) => new El(tag)
  });
  ui.bind();
  return { nodes, sent, ui };
}

const { nodes, sent, ui } = harness();
const first = {
  packName: "青轴",
  packID: "real-mx-blue",
  packs: [{ id: "real-mx-blue", name: "青轴" }, { id: "real-cream", name: "Cream" }],
  volume: 0.8,
  muted: false,
  combo: true,
  smartMute: true,
  login: false,
  accessibility: true,
  suppressReason: "",
  loginMessage: ""
};
ui.render(first);

assert.strictEqual(nodes.muted.getAttribute("aria-checked"), "false");
assert.strictEqual(nodes.combo.getAttribute("aria-checked"), "true");
nodes.muted.click();
assert.strictEqual(nodes.muted.getAttribute("aria-checked"), "true");
assert.deepStrictEqual(sent[0], ["setMuted", true]);
nodes.import.click();
assert.deepStrictEqual(sent[sent.length - 1], ["importPack", undefined]);

ui.render({
  ...first,
  muted: true,
  combo: false,
  smartMute: false,
  login: true,
  loginMessage: "需要登录项"
});
assert.strictEqual(nodes.muted.getAttribute("aria-checked"), "true");
assert.strictEqual(nodes.combo.getAttribute("aria-checked"), "false");
assert.strictEqual(nodes.login.getAttribute("aria-checked"), "true");
assert.ok(!nodes.loginExtra.classList.contains("hidden"));
assert.strictEqual(nodes.status.textContent, "已静音");
assert.ok(nodes.statusLine.classList.contains("off"));
assert.strictEqual(nodes.loginMessage.textContent, "需要登录项");

const packButton = nodes.menu.children[1];
packButton.click();
assert.deepStrictEqual(sent[sent.length - 1], ["selectPack", "real-cream"]);

ui.render({ ...first, suppressReason: "通话应用正在前台" });
assert.strictEqual(nodes.status.textContent, "通话应用正在前台，已暂停");
ui.render(first);
assert.strictEqual(nodes.status.textContent, "正在监听按键");
assert.ok(!nodes.statusLine.classList.contains("off"));
assert.ok(nodes.loginExtra.classList.contains("hidden"));

nodes.pack.click();
assert.strictEqual(nodes.pack.getAttribute("aria-expanded"), "true");
ui.escape();
assert.strictEqual(nodes.pack.getAttribute("aria-expanded"), "false");
ui.escape();
assert.deepStrictEqual(sent[sent.length - 1], ["hide", undefined]);

assert.ok(sameList([{ id: "a", name: "A" }], [{ id: "a", name: "A" }]));
assert.ok(!sameList([{ id: "a", name: "A" }], [{ id: "b", name: "A" }]));

console.log("panel-ui ok");
