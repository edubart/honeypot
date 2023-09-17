-- Override error/assert with versions that does not include file line
local orig_error = error
function _G.error(message, level)
  orig_error(message, level or 0)
end
function _G.assert(...)
  if not (...) then
    orig_error(select('#', ...) > 1 and select(2, ...) or "assertion failed!", 0)
  end
  return ...
end

local http = require("socket.http")
local ltn12 = require("ltn12")
local cjson = require("cjson")

local rollup = {}

local rollup_url = assert(os.getenv("ROLLUP_HTTP_SERVER_URL"), "missing ROLLUP_HTTP_SERVER_URL")

local function fromhex(hexdata)
  return hexdata:sub(3):gsub('..', function(x) return string.char(tonumber(x, 16)) end)
end

local function tohex(data)
  return '0x'..data:gsub('.', function(x) return ('%02x'):format(string.byte(x)) end)
end

local function http_post(url, body)
  local request_body = cjson.encode(body)
  local response_body = {}
  local result, code = http.request {
    method = "POST",
    url = url,
    source = ltn12.source.string(request_body),
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = #request_body
    },
    sink = ltn12.sink.table(response_body)
  }
  if not result then
    error("HTTP POST request to "..url.." failed with status "..code)
  end
  return code, table.concat(response_body)
end

function rollup.report(payload)
  local code, response = http_post(rollup_url.."/report", {payload=tohex(payload)})
  if not (code >= 200 and code <= 300) then
    error('invalid status code '..code..' for report: '..response)
  end
end

function rollup.notice(payload)
  local code, response = http_post(rollup_url.."/notice", {payload=tohex(payload)})
  if not (code >= 200 and code <= 300) then
    error('invalid status code '..code..' for notice: '..response)
  end
end

function rollup.voucher(destination, payload)
  local body = {destination=tohex(destination), payload=tohex(payload)}
  local code, response = http_post(rollup_url.."/voucher", body)
  if not (code >= 200 and code <= 300) then
    error('invalid status code '..code..' for voucher: '..response)
  end
end

local function rollup_process_request(response)
  local rollup_request = cjson.decode(response)
  local handler = rollup[rollup_request.request_type]
  local data = rollup_request.data
  local payload = fromhex(data.payload)
  local metadata = data.metadata
  local sender
  if metadata then
    sender = fromhex(metadata.msg_sender)
    metadata.msg_sender = sender
  end
  return handler(payload, sender, metadata) and "accept" or "reject"
end

function rollup.run()
  local finish = {status = "accept"}
  while true do
    local code, response = http_post(rollup_url .. "/finish", finish)
    if code == 200 then
      local function xpcall_err(errmsg)
        errmsg = tostring(errmsg)
        return {errmsg = errmsg, errmsg_with_traceback = debug.traceback(errmsg)}
      end
      local ok, ret = xpcall(rollup_process_request, xpcall_err, response)
      if ok then
        finish.status = ret
      else
        io.stderr:write("request failed: ", ret.errmsg_with_traceback, "\n")
        rollup.report(ret.errmsg)
        finish.status = 'reject'
      end
    elseif code == 202 then
      io.stderr:write("no pending rollup request, trying again\n")
    else
      io.stderr:write("invalid finish response code\n")
    end
  end
end

return rollup
