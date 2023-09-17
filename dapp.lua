local rollup = require 'rollup'
local config = require 'config'
local encoding = require 'encoding'
local Wallet = require 'wallet'
local tohex = encoding.tohex

local function deposit_erc20(token, sender, amount)
  print('[dapp] deposit_erc20', tohex(token), tohex(sender), amount)
  local wallet = Wallet.get_or_create(sender)
  wallet:deposit(token, amount)
  return true
end

local function withdraw_erc20(token, sender)
  print('[dapp] withdraw_erc20', tohex(token), tohex(sender))
  local wallet = assert(Wallet.get(sender), 'no wallet')
  local amount = wallet:withdraw_all(token)
  assert(not amount:iszero(), 'no funds')
  rollup.voucher(token, encoding.encode_erc20_transfer(sender, amount))
  return true
end

local function balance_erc20(token, sender)
  print('[dapp] balance_erc20', tohex(token), tohex(sender))
  local wallet = assert(Wallet.get(sender), 'no wallet')
  local balance = wallet:balance(token)
  rollup.report(balance:tobe())
  return true
end

function rollup.advance_state(data, sender)
  local opcode, opdata = data:sub(1,2), data:sub(3)
  if sender == config.PORTAL_ERC20_ADDRESS then -- deposit
    return deposit_erc20(encoding.decode_erc20_deposit(data))
  elseif opcode == 'WD' and #opdata == 20 then -- withdraw
    return withdraw_erc20(opdata, sender)
  else
    error('unknown advance state request')
  end
end

function rollup.inspect_state(data)
  local opcode, opdata = data:sub(1,2), data:sub(3)
  if opcode == 'BL' and #opdata == 40 then -- balance
    return balance_erc20(opdata:sub(21,40), opdata:sub(1,20))
  else
    error('unknown inspect state request')
  end
end

rollup.run()
