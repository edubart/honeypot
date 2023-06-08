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
    local inital_rolling_machine <close> = cartesi_rolling_machine(MACHINE_STORED_DIR)
    it("should reject empty input", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = "",
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should reject incomplete deposit input", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = table.concat({
                encode_utils.encode_be8(1),
                encode_utils.encode_be160(ERC20_CONTRACT_ADDRESS),
                encode_utils.encode_be160(ERC20_ALICE_ADDRESS),
            }),
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should reject deposit of an addition overflow", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
            }),
        }, true)
        expect.equal(res.status, "accepted")

        res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should reject input number out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
                input_number = '0x10000000000000000'
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should reject block number out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
                block_number = '0x10000000000000000'
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should reject epoch number out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
                epoch_number = '0x10000000000000000'
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should reject timestamp out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
                timestamp = '0x10000000000000000'
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should reject input with length out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = {
                offset = 32,
                length = rolling_machine.config.rollup.rx_buffer.length - 64 + 1,
                data = encode_utils.encode_erc20_deposit({
                    successful = true,
                    contract_address = ERC20_CONTRACT_ADDRESS,
                    sender_address = ERC20_ALICE_ADDRESS,
                    amount = 1,
                }),
            },
        })
        expect.equal(res.status, "rejected")
    end)

    it("should reject input with length out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = {
                offset = 32,
                length = '0x10000000000000000',
                data = encode_utils.encode_erc20_deposit({
                    successful = true,
                    contract_address = ERC20_CONTRACT_ADDRESS,
                    sender_address = ERC20_ALICE_ADDRESS,
                    amount = 1,
                }),
            },
        }, true)
        expect.equal(res.status, "rejected")
    end)

    it("should accept deposit with maximum possible data size", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local RX_BUFFER_HEADER_SIZE = 64
        local ERC20_DEPOSIT_MSG_SIZE = 1 + 20*2 + 32
        local max_data_size = rolling_machine.config.rollup.rx_buffer.length - ERC20_DEPOSIT_MSG_SIZE - RX_BUFFER_HEADER_SIZE
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = encode_utils.encode_be256(ERC20_PORTAL_ADDRESS),
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
                extra_data = string.rep('X', max_data_size)
            }),
        }, true)
        expect.equal(res.status, "accepted")
    end)
end)
