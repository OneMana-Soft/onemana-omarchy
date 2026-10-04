const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\s*\.pragma library\s*$/m, "")
const Model = {}
vm.createContext(Model)
vm.runInContext(source, Model, { filename: "Model.js" })

test("normaliseWorkspace accepts what people type and refuses plain http elsewhere", () => {
  assert.equal(Model.normaliseWorkspace("onecamp.acme.com"), "https://onecamp.acme.com")
  assert.equal(Model.normaliseWorkspace("https://OneCamp.acme.com/app/home"), "https://onecamp.acme.com")
  assert.equal(Model.normaliseWorkspace("http://localhost:3000"), "http://localhost:3000")
  assert.equal(Model.normaliseWorkspace("http://onecamp.acme.com"), "")
  assert.equal(Model.normaliseWorkspace("not a url"), "")
  assert.equal(Model.normaliseWorkspace(""), "")
})

test("joinUrl joins once and leaves absolute links alone", () => {
  assert.equal(Model.joinUrl("https://a.dev/", "/app/channel/1"), "https://a.dev/app/channel/1")
  assert.equal(Model.joinUrl("https://a.dev", "app/home"), "https://a.dev/app/home")
  assert.equal(Model.joinUrl("https://a.dev", "https://b.dev/x"), "https://b.dev/x")
  assert.equal(Model.joinUrl("", "/x"), "")
})

test("parseUnread reads the API and keeps names plain", () => {
  const u = Model.parseUnread(JSON.stringify({ data: { total: 14, channels: 11, dms: 3, activity: 0, top: [
    { kind: "channel", name: "#launch<b>", count: 9, path: "/app/channel/c3" },
    { kind: "dm", name: "Maya", count: 3, path: "/app/chat/maya" },
    { kind: "channel", name: "#empty", count: 0, path: "/x" },
  ] } }))
  assert.equal(u.ok, true)
  assert.equal(u.total, 14)
  assert.equal(u.top.length, 2)
  assert.equal(u.top[0].name, "#launch‹b›")
  assert.equal(Model.parseUnread("<html>502</html>").ok, false)
})

test("parseAttention keeps only what must be acted on", () => {
  const a = Model.parseAttention(JSON.stringify({ data: { enabled: true, items: [
    { source: "approval", kind: "Approval", title: "Release Captain wants to post in #finance", url: "/app/home" },
    { source: "task", kind: "Overdue task", title: "Rollback drill" },
    { source: "calendar", kind: "Event", title: "Standup" },
  ] } }))
  assert.equal(a.approvals, 1)
  assert.equal(a.overdue, 1)
  assert.equal(a.items.length, 2)
  assert.equal(Model.parseAttention("").ok, false)
})

test("badgeText caps at three characters and is empty when clear", () => {
  assert.equal(Model.badgeText(0, 0), "")
  assert.equal(Model.badgeText(3, 1), "4")
  assert.equal(Model.badgeText(120, 0), "99+")
})

test("summaryLine says what waits, or that nothing does", () => {
  assert.equal(Model.summaryLine({ total: 0 }, { approvals: 0, overdue: 0 }), "All caught up")
  assert.equal(Model.summaryLine({ total: 1 }, { approvals: 2, overdue: 1 }), "1 unread · 2 approvals waiting · 1 task overdue")
  assert.equal(Model.summaryLine({ total: 5 }, null), "5 unread")
})

test("errorText names the fix", () => {
  assert.match(Model.errorText(22, 401), /attention:read/)
  assert.match(Model.errorText(22, 404), /update OneCamp/)
  assert.match(Model.errorText(7, 0), /Cannot reach/)
})

test("parseConf needs both addresses", () => {
  const c = Model.parseConf("WORKSPACE=https://onecamp.acme.com\nAPI=onecamp-backend.acme.com\n")
  assert.equal(c.ok, true)
  assert.equal(c.api, "https://onecamp-backend.acme.com")
  assert.equal(Model.parseConf("WORKSPACE=https://a.dev").ok, false)
  assert.equal(Model.parseConf("").ok, false)
})

test("splitStatus separates the body from curl's status line", () => {
  const ok = Model.splitStatus('{"data":{}}\n200')
  assert.equal(ok.body, '{"data":{}}')
  assert.equal(ok.http, 200)
  const refused = Model.splitStatus("\n401")
  assert.equal(refused.body, "")
  assert.equal(refused.http, 401)
  assert.equal(Model.splitStatus("").http, 0)
})
