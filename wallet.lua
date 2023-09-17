local bint256 = require 'luadeps.bint'(256)
local Wallet = {}

local wallets = {}
Wallet.wallets = wallets
Wallet.__index = Wallet

function Wallet.create(addr)
  local self = setmetatable({tokens={}}, Wallet)
  wallets[addr] = self
  return self
end

function Wallet.get(addr)
  return wallets[addr]
end

function Wallet.get_or_create(addr)
  return Wallet.get(addr) or Wallet.create(addr)
end

function Wallet:balance(token)
  return self.tokens[token] or bint256.zero()
end

function Wallet:deposit(token, amount)
  if bint256.iszero(amount) then return end
  local cur_balance = self.tokens[token] or bint256.zero()
  local new_balance = cur_balance + amount
  assert(not bint256.ult(new_balance, cur_balance), 'balance overflow')
  self.tokens[token] = new_balance
end

function Wallet:withdraw(token, amount)
  if bint256.iszero(amount) then return end
  local cur_balance = self.tokens[token]
  assert(cur_balance and not bint256.ult(cur_balance, amount), 'not enough funds')
  local new_balance = cur_balance - amount
  if bint256.iszero(new_balance) then
    self.tokens[token] = nil
  else
    self.tokens[token] = new_balance
  end
end

function Wallet:withdraw_all(token)
  local balance = self.tokens[token] or bint256.zero()
  self.tokens[token] = nil
  return balance
end

return Wallet
