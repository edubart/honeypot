local cartesi_rolling_machine = require("cartesi-testlib.rolling-machine")
local encode_utils = require("cartesi-testlib.encode-utils")
local lester = require("luadeps.lester")
local bint256 = require 'luadeps.bint'(256)
local config = require 'config'
local describe, it, expect = lester.describe, lester.it, lester.expect

-- local MACHINE_TO_LOAD = ".sunodo/image"
local MACHINE_TO_LOAD = dofile('./.sunodo/image.config.lua')

local MACHINE_RUNTIME_CONFIG = {skip_root_hash_check = true}
local REMOTE_PROTOCOL = "jsonrpc"

describe("tests", function()
    local rolling_machine <close> = cartesi_rolling_machine(MACHINE_TO_LOAD, MACHINE_RUNTIME_CONFIG, REMOTE_PROTOCOL)
    rolling_machine:run_until_yield_or_halt()

    it("should accept first deposit", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = config.PORTAL_ERC20_ADDRESS,
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = config.TOKEN_ERC20_ADDRESS,
                sender_address = config.ALICE_ERC20_ADDRESS,
                amount = 1,
            }),
        }, true)
        local expected_res = {
            status = "accepted",
            vouchers = {},
            notices = {},
            reports = {{payload="OK"}},
        }
        expect.equal(res, expected_res)
    end)

    it("should accept second deposit", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = config.PORTAL_ERC20_ADDRESS,
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = config.TOKEN_ERC20_ADDRESS,
                sender_address = config.ALICE_ERC20_ADDRESS,
                amount = 2,
            }),
        }, true)
        local expected_res = {
            status = "accepted",
            vouchers = {},
            notices = {},
            reports = {{payload="OK"}},
        }
        expect.equal(res, expected_res)
    end)

    it("should accept third deposit with 0 amount", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = config.PORTAL_ERC20_ADDRESS,
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = config.TOKEN_ERC20_ADDRESS,
                sender_address = config.ALICE_ERC20_ADDRESS,
                amount = 0,
            }),
        }, true)
        local expected_res = {
            status = "accepted",
            vouchers = {},
            notices = {},
            reports = {{payload="OK"}},
        }
        expect.equal(res, expected_res)
    end)

    it("should accept balance inspect", function()
        local res = rolling_machine:inspect_state({
            metadata = {
                msg_sender = config.ALICE_ERC20_ADDRESS,
            },
            payload = "BLCE"..config.ALICE_ERC20_ADDRESS
        }, true)
        local expected_res = {
            status = "accepted",
            vouchers = {},
            notices = {},
            reports = {{payload=config.TOKEN_ERC20_ADDRESS..bint256.tobe(3)}},
        }
        expect.equal(res, expected_res)
    end)

    it("should accept withdraw when there is funds", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = config.ALICE_ERC20_ADDRESS,
            },
            payload = "WTDW"..config.TOKEN_ERC20_ADDRESS
        }, true)
        local expected_res = {
            status = "accepted",
            vouchers = {
                {
                    address = config.TOKEN_ERC20_ADDRESS,
                    payload = encode_utils.encode_erc20_transfer_voucher({
                        destination_address = config.ALICE_ERC20_ADDRESS,
                        amount = 3,
                    }),
                },
            },
            notices = {},
            reports = {{payload="OK"}},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject withdraw when there is no funds", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = config.ALICE_ERC20_ADDRESS,
            },
            payload = "WTDW"..config.TOKEN_ERC20_ADDRESS
        }, true)
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {{payload="ERR:no funds"}},
        }
        expect.equal(res, expected_res)
    end)
end)
