.pragma library

// Pure helpers for the OneCamp bar widget: no QML, no I/O, so they are tested
// with node (tests/model.test.js) exactly as the shell runs them.
//
// The data comes from a OneCamp workspace's public API with a personal token
// scoped attention:read:
//   GET /v1/unread     {data:{total,channels,dms,activity,top:[{kind,name,count,path}]}}
//   GET /v1/attention  {data:{enabled,items:[{source,kind,title,subtitle,url}],counts:{}}}
// /v1/attention exists only in the AI edition; without it the widget shows
// unread messages alone.

var MAX_ROWS = 6

// Text from a workspace is shown as plain text, but tooltips accept markup, so
// strip anything that could be read as a tag or a control character.
function plain(raw) {
  return String(raw === undefined || raw === null ? "" : raw)
    .replace(/[\x00-\x1f\x7f]/g, " ")
    .replace(/</g, "‹")
    .replace(/>/g, "›")
    .replace(/&/g, "＆")
    .trim()
}

// "acme.example.com" or "https://acme.example.com/" -> "https://acme.example.com".
// Plain http only for this machine. Empty string when it is not an address.
function normaliseWorkspace(input) {
  var s = String(input || "").trim()
  if (s === "" || /\s/.test(s)) return ""
  if (!/^[a-z]+:\/\//i.test(s)) s = "https://" + s
  var m = /^(https?):\/\/([^\/\s?#]+)/i.exec(s)
  if (!m) return ""
  var scheme = m[1].toLowerCase(), host = m[2].toLowerCase()
  var local = /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(host)
  if (scheme === "http" && !local) return ""
  if (!/^[a-z0-9.-]+(:\d+)?$/.test(host)) return ""
  if (!local && host.indexOf(".") < 0) return ""
  return scheme + "://" + host
}

// The API lives on the backend host. A workspace's web address and its API
// address differ (onecamp.acme.com -> onecamp-backend.acme.com), so the
// connect script records both; this only joins.
function joinUrl(base, path) {
  var b = String(base || "").replace(/\/+$/, "")
  var p = String(path || "")
  if (b === "") return ""
  if (/^https?:\/\//i.test(p)) return p
  return b + (p.charAt(0) === "/" ? p : "/" + p)
}

function _data(text) {
  var parsed = JSON.parse(String(text || "").trim())
  return parsed && parsed.data !== undefined ? parsed.data : parsed
}

function _count(n) {
  var v = Number(n)
  return isFinite(v) && v > 0 ? Math.floor(v) : 0
}

// Parse /v1/unread. ok:false on anything unreadable, never a throw.
function parseUnread(text) {
  try {
    var d = _data(text) || {}
    var top = Array.isArray(d.top) ? d.top : []
    return {
      ok: true,
      total: _count(d.total),
      channels: _count(d.channels),
      dms: _count(d.dms),
      activity: _count(d.activity),
      top: top.slice(0, MAX_ROWS).map(function(p) {
        return { kind: plain(p.kind), name: plain(p.name), count: _count(p.count), path: String(p.path || "") }
      }).filter(function(p) { return p.count > 0 && p.name !== "" })
    }
  } catch (e) {
    return { ok: false, total: 0, channels: 0, dms: 0, activity: 0, top: [] }
  }
}

// Parse /v1/attention. Only approvals and overdue tasks reach the bar: they
// are the things a person must act on, the rest belongs on Home.
function parseAttention(text) {
  try {
    var d = _data(text) || {}
    var items = Array.isArray(d.items) ? d.items : []
    var keep = items.filter(function(it) { return it && (it.source === "approval" || it.source === "task") })
    return {
      ok: true,
      enabled: d.enabled === true,
      approvals: items.filter(function(it) { return it && it.source === "approval" }).length,
      overdue: items.filter(function(it) { return it && it.source === "task" }).length,
      items: keep.slice(0, MAX_ROWS).map(function(it) {
        var row = { source: plain(it.source), kind: plain(it.kind), title: plain(it.title), subtitle: plain(it.subtitle), url: String(it.url || "") }
        row.meta = rowMeta(row)
        return row
      }).filter(function(it) { return it.title !== "" })
    }
  } catch (e) {
    return { ok: false, enabled: false, approvals: 0, overdue: 0, items: [] }
  }
}

// The short label at the right of a "Waiting for you" row. The API's
// subtitles are sentences ("Waiting for you to approve or deny", "Due Oct 4,
// 10:30 PM · Q4 launch"); a sentence there squeezes the title to nothing.
function rowMeta(row) {
  if (row.source === "approval") return "Approval"
  var due = String(row.subtitle || "").split(" · ")[0]
  return due !== "" ? due : row.kind
}

// What the bar shows beside the mark: unread plus what waits for approval,
// capped so the pill never grows past three characters.
function badgeText(unread, approvals) {
  var n = _count(unread) + _count(approvals)
  if (n === 0) return ""
  return n > 99 ? "99+" : String(n)
}

function _plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

// One line for the tooltip and the panel heading.
function summaryLine(unread, attention) {
  var parts = []
  var u = unread ? _count(unread.total) : 0
  if (u > 0) parts.push(_plural(u, "unread", "unread"))
  if (attention && attention.approvals > 0) parts.push(_plural(attention.approvals, "approval waiting", "approvals waiting"))
  if (attention && attention.overdue > 0) parts.push(_plural(attention.overdue, "task overdue", "tasks overdue"))
  return parts.length ? parts.join(" · ") : "All caught up"
}

// What went wrong, in words a person can act on. code is curl's exit status;
// http is the status the API answered, when it answered.
function errorText(code, http) {
  if (http === 401 || http === 403) return "The token was refused. Reconnect with a token that has attention:read."
  if (http === 404) return "This workspace is older than the bar needs. Ask an admin to update OneCamp to the latest release."
  if (code === 6 || code === 7) return "Cannot reach the workspace. Check the address or your connection."
  if (code === 28) return "The workspace did not answer in time."
  return "Could not read the workspace."
}

// Read ~/.config/onemana/onecamp.conf (WORKSPACE=… and API=… lines, written
// by scripts/connect). Both must be addresses or it is not configured.
function parseConf(text) {
  var out = { workspace: "", api: "" }
  String(text || "").split("\n").forEach(function(line) {
    var m = /^\s*(WORKSPACE|API)\s*=\s*(\S+)\s*$/.exec(line)
    if (!m) return
    var v = normaliseWorkspace(m[2])
    if (m[1] === "WORKSPACE") out.workspace = v
    else out.api = v
  })
  out.ok = out.workspace !== "" && out.api !== ""
  return out
}

// curl is run with -w '\n%{http_code}', so the status is the last line.
function splitStatus(text) {
  var s = String(text || "")
  var i = s.lastIndexOf("\n")
  var code = parseInt(i < 0 ? s : s.slice(i + 1), 10)
  return { body: i < 0 ? "" : s.slice(0, i), http: isFinite(code) ? code : 0 }
}
