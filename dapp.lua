local cjson = require 'cjson'
local rollup = require 'rollup'
local config = require 'config'
local encoding = require 'encoding'
local Wallet = require 'wallet'
local tohex = encoding.tohex

local function deposit_erc20(token, address, amount)
  print('[dapp] deposit_erc20', tohex(token), tohex(address), amount)
  local wallet = Wallet.get_or_create(address)
  wallet:deposit(token, amount)
  rollup.report(cjson.encode{ok=true})
  return true
end

local function withdraw_erc20(token, address)
  print('[dapp] withdraw_erc20', tohex(token), tohex(address))
  local wallet = assert(Wallet.get(address), 'no wallet')
  local amount = wallet:withdraw_all(token)
  assert(not amount:iszero(), 'no funds')
  rollup.voucher(token, encoding.encode_erc20_transfer(address, amount))
  rollup.report(cjson.encode{ok=true})
  return true
end

local function inspect_balance(address)
  print('[dapp] balance', tohex(address))
  local wallet = assert(Wallet.get(address), 'no wallet')
  local tokens = {}
  for token,amount in pairs(wallet.tokens) do
    tokens[tohex(token)] = tostring(amount)
  end
  rollup.report(cjson.encode({tokens=tokens}))
  return true
end

function rollup.advance_state(data, sender)
  if sender == config.PORTAL_ERC20_ADDRESS then -- deposit
    return deposit_erc20(encoding.decode_erc20_deposit(data))
  else
    local input = cjson.decode(data)
    if input.op == "widthdraw" then -- withdraw
      return withdraw_erc20(encoding.fromhex(input.address), sender)
    end
  end
  error('unknown advance state request')
end

function rollup.inspect_state(data)
  local query = cjson.decode(data)
  if query.op == "balance" then -- balance
    return inspect_balance(encoding.fromhex(query.address))
  end
  error('unknown inspect state request')
end

rollup.run()
