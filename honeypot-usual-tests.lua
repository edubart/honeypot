local cartesi_rolling_machine = require("rolling-machine")
local encode_utils = require("encode-utils")
local lester = require("lester")
local describe, it, expect = lester.describe, lester.it, lester.expect

local ERC20_PORTAL_ADDRESS = "0x4340ac4FcdFC5eF8d34930C96BBac2Af1301DF40"
local ERC20_CONTRACT_ADDRESS = "0xc6e7DF5E7b4f2A278906862b61205850344D4e7d"
local ERC20_WITHDRAW_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
local ERC20_ALICE_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
local MACHINE_STORED_DIR = ".sunodo/image"

describe("honeypot", function()
    local rolling_machine <close> = cartesi_rolling_machine(MACHINE_STORED_DIR)

    it("should accept first deposit", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        })
        expect.equal(res.status, "accepted")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.truthy(res.events.reports[1].payload:find("^0x00: Deposit processed"))
    end)

    it("should accept second deposit", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 2,
            }),
        })
        expect.equal(res.status, "accepted")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.truthy(res.events.reports[1].payload:find("^0x00: Deposit processed"))
    end)

    it("should reject deposit with failed status", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = false,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 3,
            }),
        })
        -- checks
        expect.equal(res.status, "rejected")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.truthy(res.events.reports[1].payload:find("^0x04: Invalid deposit"))
    end)

    it("should reject deposit with invalid contract address", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = false,
                contract_address = ERC20_ALICE_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 3,
            }),
        })
        -- checks
        expect.equal(res.status, "rejected")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.truthy(res.events.reports[1].payload:find("^0x04: Invalid deposit"))
    end)

    it("should reject deposit with invalid sender address", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_ALICE_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 3,
            }),
        })
        -- checks
        expect.equal(res.status, "rejected")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.truthy(res.events.reports[1].payload:find("^0x03: Invalid input"))
    end)

    it("should accept inspect when there is funds", function()
        local res = rolling_machine:inspect_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_ALICE_ADDRESS),
            },
        })
        -- checks
        expect.equal(res.status, "accepted")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.equal(res.events.reports[1], {
            payload = encode_utils.encode_be256(3, true),
        })
    end)

    it("should accept withdraw when there is funds", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_WITHDRAW_ADDRESS),
            },
        })
        expect.equal(res.status, "accepted")
        expect.equal(#res.events.vouchers, 1)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.truthy(res.events.reports[1].payload:find("^0x01: Voucher issued"))
        expect.equal(res.events.vouchers[1], {
            address = encode_utils.encode_be256(ERC20_CONTRACT_ADDRESS),
            payload = encode_utils.encode_erc20_transfer_voucher({
                destination_address = ERC20_WITHDRAW_ADDRESS,
                amount = 3,
            }),
        })
    end)

    it("should reject withdraw when there is no funds", function()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_WITHDRAW_ADDRESS),
            },
        })
        expect.equal(res.status, "rejected")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.truthy(res.events.reports[1].payload:find("^0x02: No funds"))
    end)

    it("should accept inspect when there is no funds", function()
        local res = rolling_machine:inspect_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_ALICE_ADDRESS),
            },
        })
        expect.equal(res.status, "accepted")
        expect.equal(#res.events.vouchers, 0)
        expect.equal(#res.events.notices, 0)
        expect.equal(#res.events.reports, 1)
        expect.equal(res.events.reports[1].payload, encode_utils.encode_be256(0, true))
    end)
end)
