local bint256 = require 'luadeps.bint'(256)
local encoding = {}

function encoding.fromhex(s)
  local hexpart = assert(s:match'^0[xX]([0-9a-fA-F]+)$')
  return hexpart:gsub('..', function(x) return string.char(tonumber(x, 16)) end)
end

function encoding.tohex(s)
  return '0x'..s:gsub('.', function(x) return ('%02x'):format(string.byte(x)) end)
end

function encoding.decode_erc20_deposit(payload)
  assert(#payload == 73, 'ERC-20 deposit length is invalid')
  local status, token, sender, amount = ("I1c20c20c32"):unpack(payload)
  assert(status == 1, 'ERC-20 deposit status is not 1')
  return token, sender, bint256.frombe(amount)
end

function encoding.encode_erc20_transfer(destination, amount)
  return ("c16c20c32"):pack("\xa9\x05\x9c\xbb", destination, bint256.tobe(amount))
end

return encoding
