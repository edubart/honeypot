local cartesi_rolling_machine = require("cartesi-testlib.rolling-machine")
local encode_utils = require("cartesi-testlib.encode-utils")
local lester = require("cartesi-testlib.lester")
local bint256 = require("cartesi-testlib.bint")(256)
local describe, it, expect = lester.describe, lester.it, lester.expect

-- Measure time using gettime() instead of os.clock(), so benchmark include remote process CPU usage.
lester.seconds = require("socket").gettime

local ERC20_PORTAL_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0x4340ac4FcdFC5eF8d34930C96BBac2Af1301DF40")
local ERC20_CONTRACT_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0xc6e7DF5E7b4f2A278906862b61205850344D4e7d")
local ERC20_WITHDRAW_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
local MACHINE_STORED_DIR = "snapshot"

local HONEYPOT_STATUS_SUCCESS = string.char(0)
local HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED = string.char(1)
local HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT = string.char(2)
local HONEYPOT_STATUS_WITHDRAW_NO_FUNDS = string.char(4)

local CHANCE_WITHDRAW = 1 / 100
local CHANCE_INVALID_CONTRACT = 1 / 20
local CHANCE_TRANSFER_FAILED = 1 / 20
local CHANCE_EXTRA_DATA = 1 / 20

-- Returns a random ERC-20 address.
local function random_erc20_address()
    return string.pack(">I4I8I8", math.random(0) >> 32, math.random(0), math.random(0), math.random(0))
end

-- Returns a random boolean.
local function random_boolean(chance) return math.random() >= chance end

-- Returns valid_address or a random ERC-20 address.
local function random_invalid_erc20_address(invalid_chance, valid_address)
    local valid = math.random() >= invalid_chance
    return valid and valid_address or random_erc20_address(), valid
end

-- Returns a random amount between 0 and UINT64_MAX (18446744073709551615).
local function random_amount() return bint256.fromuinteger(math.random(0)) end

-- Returns a random string of length between 0 and max_len.
local function random_string(non_empty_chance, max_len)
    return math.random() < non_empty_chance and string.rep(string.char(math.random(0, 255)), math.random(1, max_len))
        or ""
end

-- Performs a random withdraw request and returns the new balance.
local function random_withdraw_request(rolling_machine, balance)
    -- Generate random withdraw request
    local extra_data = random_string(CHANCE_EXTRA_DATA, 32)
    -- Compute expected response
    local expected_res
    if #extra_data ~= 0 then -- Invalid message
        expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
    elseif bint256.eq(balance, 0) then -- No funds
        expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {
                { payload = HONEYPOT_STATUS_WITHDRAW_NO_FUNDS },
            },
        }
    else -- Success
        expected_res = {
            status = "accepted",
            vouchers = {
                {
                    address = ERC20_CONTRACT_ADDRESS_ENCODED,
                    payload = encode_utils.encode_erc20_transfer_voucher({
                        destination_address = ERC20_WITHDRAW_ADDRESS_ENCODED,
                        amount = balance:tobe(),
                    }),
                },
            },
            notices = {},
            reports = {
                { payload = HONEYPOT_STATUS_SUCCESS },
            },
        }
        balance = bint256(0)
    end
    -- Make the advance request
    local perform_rollback = expected_res.status == "rejected" and rolling_machine.can_rollback
    local res = rolling_machine:advance_state({
        metadata = {
            msg_sender = ERC20_WITHDRAW_ADDRESS_ENCODED,
        },
        payload = extra_data,
    }, perform_rollback)
    -- Check request
    expect.equal(res, expected_res)
    return balance
end

-- Performs a random deposit request and returns the new balance.
local function random_deposit_request(rolling_machine, balance)
    -- Generate a random deposit request
    local tx_status = random_boolean(CHANCE_TRANSFER_FAILED)
    local contract, valid_contract =
        random_invalid_erc20_address(CHANCE_INVALID_CONTRACT, ERC20_CONTRACT_ADDRESS_ENCODED)
    local sender = random_erc20_address()
    local amount = random_amount()
    local extra_data = random_string(CHANCE_EXTRA_DATA, 32)
    -- Compute expected response
    local expected_res
    if #extra_data ~= 0 then -- Invalid message
        expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
    elseif not tx_status then -- Transfer failed
        expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {
                { payload = HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED },
            },
        }
    elseif not valid_contract then -- Invalid contract
        expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {
                { payload = HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT },
            },
        }
    else -- Success
        expected_res = {
            status = "accepted",
            vouchers = {},
            notices = {},
            reports = {
                { payload = HONEYPOT_STATUS_SUCCESS },
            },
        }
        balance = balance + amount
    end
    -- Make the advance request
    local perform_rollback = expected_res.status == "rejected" and rolling_machine.can_rollback
    local res = rolling_machine:advance_state({
        metadata = {
            msg_sender = ERC20_PORTAL_ADDRESS_ENCODED,
        },
        payload = encode_utils.encode_erc20_deposit({
            successful = tx_status,
            contract_address = contract,
            sender_address = sender,
            amount = amount:tobe(),
            extra_data = extra_data,
        }),
    }, perform_rollback)
    -- Check expected advance state results
    expect.equal(res, expected_res)
    return balance
end

-- Performs a random advance state request and returns the new balance.
local function random_advance_state(rolling_machine, balance)
    if math.random() < CHANCE_WITHDRAW then -- withdraw
        balance = random_withdraw_request(rolling_machine, balance)
    else -- deposit
        balance = random_deposit_request(rolling_machine, balance)
    end
    return balance
end

-- Performs a inspect state request and check if its correct.
local function inspect_balance_check(rolling_machine, balance)
    local expected_res = {
        status = "accepted",
        vouchers = {},
        notices = {},
        reports = {
            { payload = balance:tobe() },
        },
    }
    local res = rolling_machine:inspect_state({
        metadata = {
            msg_sender = random_erc20_address(),
        },
    }, rolling_machine.can_rollback)
    expect.equal(res, expected_res)
end

local function perform_tests(remote_protocol, num_iterations)
    local rolling_machine <close> = cartesi_rolling_machine(MACHINE_STORED_DIR, remote_protocol)
    local balance = bint256(0)
    local num_iterations1 = num_iterations // 10
    local num_iterations2 = num_iterations - num_iterations1

    -- Make tests reproducible
    math.randomseed(0)

    describe("honeypot " .. remote_protocol .. " stress", function()
        it("random advance state and inspect state (" .. num_iterations1 .. " iterations)", function()
            for _ = 1, num_iterations1 do
                balance = random_advance_state(rolling_machine, balance)
                inspect_balance_check(rolling_machine, balance)
            end
        end)

        it("random advance state (" .. num_iterations2 .. " iterations)", function()
            local start = lester.seconds()
            for _ = 1, num_iterations2 do
                balance = random_advance_state(rolling_machine, balance)
            end
            local elapsed = lester.seconds() - start
            print(string.format("%s %.2f req/s", remote_protocol, num_iterations2 / elapsed))
            inspect_balance_check(rolling_machine, balance)
        end)
    end)
end

perform_tests("local", 10000)
perform_tests("jsonrpc", 1500)
perform_tests("grpc", 150)

print("Running tests for 1 million requests, this should take a few minutes...")
perform_tests("local", 1000000)
