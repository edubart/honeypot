#!/usr/bin/lua5.4

--------------------------------------------------------------------------------
-- Rollup utilities.

local unix = require("unix")
local unix_unsafe = require("unix.unsafe")

local stderr = io.stderr
local ioctl = unix_unsafe.ioctl

local IOCTL_ROLLUP_FINISH <const> = -1072901376
local IOCTL_ROLLUP_READ_ADVANCE_STATE <const> = -1068969216
local IOCTL_ROLLUP_READ_INSPECT_STATE <const> = -1072639232
local IOCTL_ROLLUP_WRITE_VOUCHER <const> = -1070542079
-- local IOCTL_ROLLUP_WRITE_NOTICE <const> = -1072114942
local IOCTL_ROLLUP_WRITE_REPORT <const> = -1072639229
-- local IOCTL_ROLLUP_THROW_EXCEPTION <const> = -1072639228

local ROLLUP_ADVANCE_STATE <const> = 0
local ROLLUP_INSPECT_STATE <const> = 1

local ROLLUP_FINISH_ACCEPT_IOCTL_INPUT <const> = "\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
local ROLLUP_FINISH_REJECT_IOCTL_INPUT <const> = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

local rollup_fd = assert(unix.open("/dev/rollup", unix.O_RDWR))
local input_payload_buflen = 128
local input_payload_bufptr = assert(unix_unsafe.calloc(input_payload_buflen, 1))
local input_payload_bufint = tonumber(("%p"):format(input_payload_bufptr))
local input_payload_file = assert(unix_unsafe.fmemopen(input_payload_bufptr, input_payload_buflen, "r"))
assert(input_payload_file:setvbuf("no"))

local output_payload_buflen = 128
local output_payload_bufptr = assert(unix_unsafe.calloc(output_payload_buflen, 1))
local output_payload_bufint = tonumber(("%p"):format(output_payload_bufptr))
local output_payload_file = assert(unix_unsafe.fmemopen(output_payload_bufptr, output_payload_buflen, "w"))
assert(output_payload_file:setvbuf("no"))

assert(stderr:setvbuf("line"))

local function stderrfln(msg, ...)
    if select("#", ...) ~= 0 then msg = msg:format(...) end
    stderr:write("[dapp] " .. msg .. "\n")
end

local function rollup_pack_output_payload(payload)
    local ok, err = output_payload_file:seek("set")
    if not ok then return ok, err end
    return output_payload_file:write(payload)
end

local function rollup_unpack_input_payload(length)
    assert(input_payload_file:seek("set"))
    return assert(input_payload_file:read(length))
end

local function rollup_write_report(payload)
    local ok, err = rollup_pack_output_payload(payload)
    if not ok then return nil, err end
    local ioctl_input = ("I8I8"):pack(output_payload_bufint, #payload)
    ok, err = ioctl(rollup_fd, IOCTL_ROLLUP_WRITE_REPORT, ioctl_input)
    if not ok then return nil, err end
    return true
end

local function rollup_write_voucher(destination, payload)
    local ok, err = rollup_pack_output_payload(payload)
    if not ok then return nil, err end
    local ioctl_input = ("c20xxxxI8I8I8"):pack(destination, output_payload_bufint, #payload, 0)
    ok, err = ioctl(rollup_fd, IOCTL_ROLLUP_WRITE_VOUCHER, ioctl_input)
    if not ok then return nil, err end
    return true
end

local function rollup_finish_request(accept_previous_request)
    local ioctl_input = accept_previous_request == true and ROLLUP_FINISH_ACCEPT_IOCTL_INPUT
        or ROLLUP_FINISH_REJECT_IOCTL_INPUT
    local _, ioctl_output = assert(ioctl(rollup_fd, IOCTL_ROLLUP_FINISH, ioctl_input))
    return ("xxxxi4i4"):unpack(ioctl_output)
end

local function rollup_read_advance_state(length)
    local ioctl_input = ("c56I8I8"):pack("", input_payload_bufint, input_payload_buflen)
    local _, ioctl_output = assert(ioctl(rollup_fd, IOCTL_ROLLUP_READ_ADVANCE_STATE, ioctl_input))
    return rollup_unpack_input_payload(length), ("c20xxxxI8I8I8I8"):unpack(ioctl_output)
end

local function rollup_read_inspect_state(length)
    local ioctl_input = ("I8I8"):pack(input_payload_bufint, input_payload_buflen)
    assert(ioctl(rollup_fd, IOCTL_ROLLUP_READ_INSPECT_STATE, ioctl_input))
    return rollup_unpack_input_payload(length)
end

local function rollup_process_next_request(accept_previous_request, advance_cb, inspect_cb)
    local request_type, payload_length = rollup_finish_request(accept_previous_request)
    if payload_length > input_payload_buflen then error("payload length is too large") end
    if request_type == ROLLUP_ADVANCE_STATE then
        return advance_cb(rollup_read_advance_state(payload_length))
    elseif request_type == ROLLUP_INSPECT_STATE then
        return inspect_cb(rollup_read_inspect_state(payload_length))
    else
        error("invalid request type")
    end
end

local function rollup_request_loop(advance_cb, inspect_cb)
    local accept_previous_request = true
    while true do
        local ok, err = pcall(rollup_process_next_request, accept_previous_request, advance_cb, inspect_cb)
        if ok then
            accept_previous_request = err
        else
            accept_previous_request = false
            stderrfln("request error: %s", err)
        end
    end
end

--------------------------------------------------------------------------------
-- ERC-20 encoding utilities.

local ERC20_DEPOSIT_LENGTH <const> = 73

local function decode_erc20_deposit(input)
    local status, contract, sender, amount = ("I1c20c20c32"):unpack(input)
    return status == 1, contract, sender, amount
end

local function encode_erc20_transfer(destination, amount)
    return ("c16c20c32"):pack("\xa9\x05\x9c\xbb", destination, amount)
end

--------------------------------------------------------------------------------
-- Honeypot application.

local bint256 = require("bint")(256)
local balance = bint256.zero()

local ERC20_PORTAL_ADDRESS <const>     = "\x43\x40\xac\x4F\xcd\xFC\x5e\xF8\xd3\x49\x30\xC9\x6B\xBa\xc2\xAf\x13\x01\xDF\x40"
local ERC20_CONTRACT_ADDRESS <const>   = "\xc6\xe7\xDF\x5E\x7b\x4f\x2A\x27\x89\x06\x86\x2b\x61\x20\x58\x50\x34\x4D\x4e\x7d"
local ERC20_WITHDRAWAL_ADDRESS <const> = "\x70\x99\x79\x70\xC5\x18\x12\xdc\x3A\x01\x0C\x7d\x01\xb5\x0e\x0d\x17\xdc\x79\xC8"

local HONEYPOT_STATUS_SUCCESS <const> = "\0"
local HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED <const> = "\1"
local HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT <const> = "\2"
local HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW <const> = "\3"
local HONEYPOT_STATUS_WITHDRAW_NO_FUNDS <const> = "\4"
local HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED <const> = "\5"

local function honeypot_deposit(status, contract, sender, amount)
    if not status then
        rollup_write_report(HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED)
        stderrfln("deposit erc20 transfer failed")
        return false
    end
    if contract ~= ERC20_CONTRACT_ADDRESS then
        rollup_write_report(HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT)
        stderrfln("invalid deposit contract address")
        return false
    end
    local new_balance = balance + bint256.frombe(amount)
    if bint256.ult(new_balance, balance) then
        rollup_write_report(HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW)
        stderrfln("deposit balance overflow")
        return false
    end
    balance = new_balance
    rollup_write_report(HONEYPOT_STATUS_SUCCESS)
    stderrfln("successful deposit")
    return true
end

local function honeypot_withdraw()
    if balance:iszero() then
        rollup_write_report(HONEYPOT_STATUS_WITHDRAW_NO_FUNDS)
        stderrfln("no funds to withdraw")
        return false
    end
    local transfer_payload = encode_erc20_transfer(ERC20_WITHDRAWAL_ADDRESS, balance:tobe())
    if not rollup_write_voucher(ERC20_CONTRACT_ADDRESS, transfer_payload) then
        rollup_write_report(HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED)
        stderrfln("unable to issue withdraw voucher")
        return false
    end
    balance = bint256.zero()
    rollup_write_report(HONEYPOT_STATUS_SUCCESS)
    stderrfln("successful withdrawal")
    return true
end

local function honeypot_inspect_balance()
    assert(rollup_write_report(balance:tobe()))
    stderrfln("inspect balance request")
    return true
end

local function honeypot_advance_state(input, sender)
    if sender == ERC20_PORTAL_ADDRESS and #input == ERC20_DEPOSIT_LENGTH then
        return honeypot_deposit(decode_erc20_deposit(input))
    elseif sender == ERC20_WITHDRAWAL_ADDRESS and #input == 0 then
        return honeypot_withdraw()
    else
        stderrfln("invalid advance state request")
        return false
    end
end

local function honeypot_inspect_state(input)
    if #input == 0 then
        return honeypot_inspect_balance()
    else
        stderrfln("invalid inspect state request")
        return false
    end
end

rollup_request_loop(honeypot_advance_state, honeypot_inspect_state)
