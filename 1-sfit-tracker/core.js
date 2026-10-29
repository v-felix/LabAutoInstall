(function (root) {
  "use strict";
  function parseTime(value) {
    const m = typeof value === "string" && value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|[+-](\d{2}):(\d{2}))$/);
    if (!m) throw new Error("Ngày giờ phải là YYYY-MM-DDTHH:mm:ss+07:00 (hoặc Z).");
    const p = m.slice(1, 7).map(Number), d = new Date(0);
    d.setUTCFullYear(p[0], p[1] - 1, p[2]); d.setUTCHours(p[3], p[4], p[5], 0);
    if (d.getUTCFullYear() !== p[0] || d.getUTCMonth() !== p[1] - 1 || d.getUTCDate() !== p[2] ||
        d.getUTCHours() !== p[3] || d.getUTCMinutes() !== p[4] || d.getUTCSeconds() !== p[5] ||
        (m[8] && (+m[8] > 14 || +m[9] > 59 || (+m[8] === 14 && +m[9] !== 0)))) throw new Error("Ngày giờ không hợp lệ.");
    const time = Date.parse(value);
    if (!Number.isFinite(time)) throw new Error("Không đọc được ngày giờ.");
    return time;
  }
  function hostList(values) {
    if (!Array.isArray(values)) throw new Error("Danh sách host phải là array.");
    return [...new Set(values.map(value => {
      if (typeof value !== "string" || value !== value.trim() || !/^[a-zA-Z0-9.-]+$/.test(value)) throw new Error("Chỉ nhập hostname, không dùng URL, wildcard hoặc cổng.");
      const u = new URL("https://" + value);
      if (u.hostname !== value.toLowerCase() || value.includes("..") || value.startsWith(".") || value.endsWith(".")) throw new Error("Hostname không hợp lệ.");
      return u.hostname;
    }))];
  }
  function validate(raw) {
    if (!raw || typeof raw.enabled !== "boolean") throw new Error("enabled phải là boolean.");
    const c = {...raw, startMs: parseTime(raw.startAt), endMs: parseTime(raw.endAt)};
    if (c.endMs <= c.startMs) throw new Error("endAt phải sau startAt.");
    c.allowedHosts = hostList(c.allowedHosts); c.resourceHosts = hostList(c.resourceHosts || []);
    if (!c.allowedHosts.length || !allowedUrl(c.examUrl, c.allowedHosts)) throw new Error("examUrl phải thuộc allowedHosts và dùng HTTP(S), không có username/password.");
    if (!["navigation", "strict"].includes(c.networkMode)) throw new Error("networkMode phải là navigation hoặc strict.");
    for (const k of ["singleExamTab", "autoOpenExam", "hideChatbox"]) if (typeof c[k] !== "boolean") throw new Error(k + " phải là boolean.");
    if (!Number.isInteger(c.maxLogEntries) || c.maxLogEntries < 10 || c.maxLogEntries > 1000) throw new Error("maxLogEntries phải từ 10 đến 1000.");
    return c;
  }
  function phase(c, now = Date.now()) {
    if (!c.enabled) return "DISABLED";
    return now < c.startMs ? "WAITING" : now < c.endMs ? "ACTIVE" : "ENDED";
  }
  function allowedUrl(value, hosts) {
    try { const u = new URL(value); return ["http:", "https:"].includes(u.protocol) && !u.username && !u.password && hosts.includes(u.hostname); }
    catch { return false; }
  }
  function rules(c) {
    const regex = hosts => "^https?://(" + hosts.map(h => h.replace(/\./g, "\\.")).join("|") + ")(:[0-9]+)?/";
    const result = [
      {id:10001, priority:1, action:{type:"redirect", redirect:{extensionPath:"/block.html"}}, condition:{regexFilter:"^https?://", resourceTypes:["main_frame"]}},
      {id:10002, priority:3, action:{type:"allow"}, condition:{regexFilter:regex(c.allowedHosts), resourceTypes:["main_frame"]}}
    ];
    if (c.networkMode === "strict") {
      result.push({id:10003, priority:1, action:{type:"block"}, condition:{regexFilter:"^https?://|^wss?://", excludedResourceTypes:["main_frame"]}});
      result.push({id:10004, priority:3, action:{type:"allow"}, condition:{regexFilter:regex([...new Set([...c.allowedHosts,...c.resourceHosts])]).replace("https?", "(https?|wss?)"), excludedResourceTypes:["main_frame"]}});
    }
    return result;
  }
  const api = {parseTime, validate, phase, allowedUrl, rules}; root.SfitCore = api;
  if (typeof module !== "undefined") module.exports = api;
})(globalThis);
