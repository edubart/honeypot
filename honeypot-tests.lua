local cartesi = require("cartesi")
local encode_utils = require("cartesi-testlib.encode-utils")
local lester = require("cartesi-testlib.lester")
local describe, it, expect = lester.describe, lester.it, lester.expect

local ERC20_PORTAL_ADDRESS = "0x4340ac4FcdFC5eF8d34930C96BBac2Af1301DF40"
local ERC20_WITHDRAW_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
local ERC20_TOKEN_ADDRESS = "0xc6e7DF5E7b4f2A278906862b61205850344D4e7d"

local ERC20_ALICE_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
local MACHINE_STORED_DIR = "snapshot"
local MACHINE_RUNTIME_CONFIG = { skip_root_hash_check = true }

local ADVANCE_STATUS_SUCCESS = string.char(0)
local ADVANCE_STATUS_INVALID_REQUEST = string.char(1)
local ADVANCE_STATUS_DEPOSIT_INVALID_TOKEN = string.char(2)
local ADVANCE_STATUS_DEPOSIT_BALANCE_OVERFLOW = string.char(3)
local ADVANCE_STATUS_WITHDRAW_NO_FUNDS = string.char(4)
-- local ADVANCE_STATUS_WITHDRAW_VOUCHER_FAILED = string.char(5)

local machine_methods = getmetatable(cartesi.machine).__index

function machine_methods:run_until_yield_or_halt()
    local outputs, reports, progresses
    while true do
        local break_reason = self:run()
        if break_reason == cartesi.BREAK_REASON_HALTED then
            return { break_reason = break_reason, outputs = outputs, reports = reports }
        elseif break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY then
            local _, yield_reason, outputs_hash = self:receive_cmio_request()
            return { break_reason = break_reason, yield_reason = yield_reason, outputs = outputs, reports = reports },
                outputs_hash
        elseif break_reason == cartesi.BREAK_REASON_YIELDED_AUTOMATICALLY then
            local _, yield_reason, data = self:receive_cmio_request()
            if yield_reason == cartesi.CMIO_YIELD_AUTOMATIC_REASON_TX_OUTPUT then
                outputs = outputs or {}
                table.insert(outputs, data)
            elseif yield_reason == cartesi.CMIO_YIELD_AUTOMATIC_REASON_TX_REPORT then
                reports = reports or {}
                table.insert(reports, data)
            elseif yield_reason == cartesi.CMIO_YIELD_AUTOMATIC_REASON_PROGRESS then
                progresses = progresses or {}
                table.insert(progresses, data)
            end
        else
            error("unexpected break reason")
        end
    end
end

function machine_methods:advance_state(input)
    self:send_cmio_response(cartesi.CMIO_YIELD_REASON_ADVANCE_STATE, input or "")
    return self:run_until_yield_or_halt()
end

function machine_methods:inspect_state(query)
    self:send_cmio_response(cartesi.CMIO_YIELD_REASON_INSPECT_STATE, query or "")
    return self:run_until_yield_or_halt()
end

describe("honeypot basic", function()
    local machine <close> = cartesi.machine(MACHINE_STORED_DIR, MACHINE_RUNTIME_CONFIG)

    it("should accept first deposit", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_SUCCESS },
        }
        expect.equal(res, expected_res)
    end)

    it("should accept second deposit", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 2,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_SUCCESS },
        }
        expect.equal(res, expected_res)
    end)

    it("should accept third deposit with 0 amount", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 0,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_SUCCESS },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore deposit with invalid token address", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_ALICE_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 3,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_DEPOSIT_INVALID_TOKEN },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore deposit with invalid sender address", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_ALICE_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 3,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore deposit with invalid payload length", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 2,
                extra_data = "\x00",
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should accept balance inspect", function()
        local res = machine:inspect_state()
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { encode_utils.encode_be256(3) },
        }
        expect.equal(res, expected_res)
    end)

    it("should accept balance inspect with any kind of data", function()
        local res = machine:inspect_state("SOME RANDOM DATA")
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { encode_utils.encode_be256(3) },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore withdraw with invalid payload length", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_WITHDRAW_ADDRESS,
            payload = "\x00",
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should accept withdraw when there is funds", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_WITHDRAW_ADDRESS,
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            outputs = {
                encode_utils.encode_voucher_output({
                    address = ERC20_TOKEN_ADDRESS,
                    value = 0,
                    payload = encode_utils.encode_erc20_transfer({
                        destination_address = ERC20_WITHDRAW_ADDRESS,
                        amount = 3,
                    }),
                }),
            },
            reports = { ADVANCE_STATUS_SUCCESS },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore withdraw when there is no funds", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_WITHDRAW_ADDRESS,
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_WITHDRAW_NO_FUNDS },
        }
        expect.equal(res, expected_res)
    end)

    it("should accept inspect when there is no funds", function()
        local res = machine:inspect_state()
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { encode_utils.encode_be256(0) },
        }
        expect.equal(res, expected_res)
    end)
end)

describe("honeypot edge", function()
    local machine <close> = cartesi.machine(MACHINE_STORED_DIR, MACHINE_RUNTIME_CONFIG)

    it("should ignore empty input", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = "",
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore incomplete deposit input", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_address(ERC20_TOKEN_ADDRESS)
                .. encode_utils.encode_erc20_address(ERC20_ALICE_ADDRESS),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore deposit of an addition overflow", function()
        local overflow_machine <close> = cartesi.machine(MACHINE_STORED_DIR, MACHINE_RUNTIME_CONFIG)

        local res = overflow_machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_SUCCESS },
        }
        expect.equal(res, expected_res)

        res = overflow_machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }))
        expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_DEPOSIT_BALANCE_OVERFLOW },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore input chain id out of supported range", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            chain_id = "0x10000000000000000",
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore input block number out of supported range", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            block_number = "0x10000000000000000",
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore input block timestamp out of supported range", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            block_timestamp = "0x10000000000000000",
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore input index out of supported range", function()
        local res = machine:advance_state(encode_utils.encode_advance_input({
            msg_sender = ERC20_PORTAL_ADDRESS,
            index = "0x10000000000000000",
            payload = encode_utils.encode_erc20_deposit({
                contract_address = ERC20_TOKEN_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }))
        local expected_res = {
            break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
            yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
            reports = { ADVANCE_STATUS_INVALID_REQUEST },
        }
        expect.equal(res, expected_res)
    end)

    it("should ignore input with invalid payload offset", function()
        local payload = encode_utils.encode_erc20_deposit({
            contract_address = ERC20_TOKEN_ADDRESS,
            sender_address = ERC20_ALICE_ADDRESS,
            amount = 1,
        })
        do
            local res = machine:advance_state(encode_utils.encode_advance_input({
                msg_sender = ERC20_PORTAL_ADDRESS,
                payload = payload,
                payload_offset = 0x100 + 32,
            }))
            local expected_res = {
                break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
                yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
                reports = { ADVANCE_STATUS_INVALID_REQUEST },
            }
            expect.equal(res, expected_res)
        end
    end)

    it("should ignore input with invalid payload length", function()
        local payload = encode_utils.encode_erc20_deposit({
            contract_address = ERC20_TOKEN_ADDRESS,
            sender_address = ERC20_ALICE_ADDRESS,
            amount = 1,
        })
        do
            local res = machine:advance_state(encode_utils.encode_advance_input({
                msg_sender = ERC20_PORTAL_ADDRESS,
                payload = payload,
                payload_length = #payload + 13,
            }))
            local expected_res = {
                break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
                yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
                reports = { ADVANCE_STATUS_INVALID_REQUEST },
            }
            expect.equal(res, expected_res)
        end
        do
            local res = machine:advance_state(encode_utils.encode_advance_input({
                msg_sender = ERC20_PORTAL_ADDRESS,
                payload = payload,
                payload_length = #payload + 1,
            }))
            local expected_res = {
                break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
                yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
                reports = { ADVANCE_STATUS_INVALID_REQUEST },
            }
            expect.equal(res, expected_res)
        end
        do
            local res = machine:advance_state(encode_utils.encode_advance_input({
                msg_sender = ERC20_PORTAL_ADDRESS,
                payload = payload,
                payload_length = #payload - 1,
            }))
            local expected_res = {
                break_reason = cartesi.BREAK_REASON_YIELDED_MANUALLY,
                yield_reason = cartesi.CMIO_YIELD_MANUAL_REASON_RX_ACCEPTED,
                reports = { ADVANCE_STATUS_INVALID_REQUEST },
            }
            expect.equal(res, expected_res)
        end
    end)
end)
