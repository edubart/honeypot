local cartesi_rolling_machine = require("cartesi-testlib.rolling-machine")
local encode_utils = require("cartesi-testlib.encode-utils")
local lester = require("cartesi-testlib.lester")
local describe, it, expect = lester.describe, lester.it, lester.expect

math.randomseed(10000)

local ERC20_PORTAL_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0x4340ac4FcdFC5eF8d34930C96BBac2Af1301DF40")
local ERC20_CONTRACT_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0xc6e7DF5E7b4f2A278906862b61205850344D4e7d")
local ERC20_WITHDRAW_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
local MACHINE_STORED_DIR = "snapshot"
local REMOTE_RPC_PROTOCOL = arg[1] or "jsonrpc"

local HONEYPOT_STATUS_SUCCESS = string.char(0)
local HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED = string.char(1)
local HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT = string.char(2)
local HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW = string.char(3)
local HONEYPOT_STATUS_WITHDRAW_NO_FUNDS = string.char(4)
-- local HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED = string.char(5)

local CHANCE_WITHDRAW = 1 / 1000
local CHANCE_INVALID_CONTRACT = 1/20
local CHANCE_TRANSFER_FAILED = 1/20
local CHANCE_EXTRA_DATA = 1/20

local function random_erc20_address()
    return string.pack('I4I8I8', math.random(0) >> 32, math.random(0), math.random(0), math.random(0))
end

local function random_contract_address()
    local valid = math.random() >= CHANCE_INVALID_CONTRACT
    return valid and ERC20_CONTRACT_ADDRESS_ENCODED or random_erc20_address(), valid
end

local function random_erc20_status_byte()
    local sucesss = math.random() >= CHANCE_TRANSFER_FAILED
    return sucesss and '\x01' or '\x00', sucesss
end

local function random_amount_be256()
    local amount = math.random(0, 100000000)
    return string.pack('I16I16', 0, amount), amount
end

local function random_extra_data()
    return math.random() < CHANCE_EXTRA_DATA and string.rep(string.char(math.random(0, 255)), math.random(1, 32)) or ''
end

local function random_advance_state(rolling_machine)
    if math.random() < CHANCE_WITHDRAW then -- withdraw
        -- local msg_sender = ERC20_WITHDRAW_ADDRESS_ENCODED
        -- local extra_data = random_extra_data()
    else -- deposit
        local msg_sender = ERC20_PORTAL_ADDRESS_ENCODED
        local tx_status_byte, tx_status = random_erc20_status_byte()
        local contract, valid_contract = random_contract_address()
        local sender = random_erc20_address()
        local amount_be256, amount = random_amount_be256()
        local extra_data = random_extra_data()
        local expected_status = 'accepted'
        local expected_report_status = HONEYPOT_STATUS_SUCCESS
        if #extra_data ~= 0 then
            expected_status = 'rejected'
            expected_report_status = nil
        elseif not tx_status then
            expected_status = 'rejected'
            expected_report_status = HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED
        elseif not valid_contract then
            expected_status = 'rejected'
            expected_report_status = HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT
        end
        local expected_accepted = expected_status == 'accepted'
        if not expected_accepted then
            return
        end
        local no_rollback = false--expected_accepted
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = msg_sender
            },
            payload = tx_status_byte..contract..sender..amount_be256..extra_data
        }, no_rollback)
        expect.equal(res.status, expected_status)
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        if expected_report_status then
            expect.equal(#res.events.reports, 1)
            expect.equal(res.events.reports[1].payload, expected_report_status)
        else
            expect.equal(#res.events.reports, 0)
        end
    end
end

describe("honeypot", function()
    local rolling_machine <close> = cartesi_rolling_machine(MACHINE_STORED_DIR, REMOTE_RPC_PROTOCOL)

    it("stress", function()
        for i=1,100000 do
            print(i)
            random_advance_state(rolling_machine)
        end
    end)
end)

--[[
issues:
1. Logs stop to be written to console after forking and rolling hundreds of thousands times.
2. After a JSON-RPC protocol error raises a Lua error in my test script,
    the script exits but the jsonrpc server application is still left running,
    despite carefully calling shutdown for all jsonrpc instances after the error.
     --- I suspect the application is exiting before shutdown packet is flushed to the network,
         or that json-rpc remote machine is unable to shutdown after a protocol error.
3. Docker add some connection tracking rules to iptables firewall,
    and after running thousands of requests the connection track table becomes full,
    and iptables decides to drop all packets, this makes the test script freeze, and things starts failing.
    Workaround is to remove iptables rules that Docker creates.
4. Sometimes after running thousands of requests (and forks), jsonrpc gives a
    invalid field error, this happens randomly and is hard to reproduce

    {"id":0,"jsonrpc":"2.0","result":true}
    {"id":0.0,"jsonrpc":"2.0","result":144396667347533824}
5. After running thousands of forks, netstat becomes full of TIME_WAIT requests,
   reaching the maximum number of local TCP ports available of 130k,
   and this is may be a problem if the kernel is not configured to recycle time wait TCP connections.
6. JSON-RPC remote cartesi machine does not work when compiling with -DMG_ENABLE_EPOLL=0 to
  force use of poll() instead of epoll().
]]
