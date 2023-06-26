local cartesi_rolling_machine = require("cartesi-testlib.rolling-machine")
local encode_utils = require("cartesi-testlib.encode-utils")
local lester = require("cartesi-testlib.lester")
local cartesi = require("cartesi")
local describe, it, expect = lester.describe, lester.it, lester.expect

local ERC20_PORTAL_ADDRESS = "0x4340ac4FcdFC5eF8d34930C96BBac2Af1301DF40"
local ERC20_CONTRACT_ADDRESS = "0xc6e7DF5E7b4f2A278906862b61205850344D4e7d"
local ERC20_WITHDRAW_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
local ERC20_ALICE_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
local MACHINE_STORED_DIR = "snapshot"
local MACHINE_RUNTIME_CONFIG = {
    skip_root_hash_check = true,
    skip_version_check = true,
}
local REMOTE_PROTOCOL = arg[1] or "jsonrpc"

local HONEYPOT_STATUS_SUCCESS = string.char(0)
local HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW = string.char(3)
local HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED = string.char(5)

describe("honeypot", function()
    local inital_rolling_machine <close> =
        cartesi_rolling_machine(MACHINE_STORED_DIR, MACHINE_RUNTIME_CONFIG, REMOTE_PROTOCOL)

    it("should reject empty input", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
            },
            payload = "",
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject incomplete deposit input", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
            },
            payload = "\x01" -- success
                .. encode_utils.encode_erc20_address(ERC20_CONTRACT_ADDRESS)
                .. encode_utils.encode_erc20_address(ERC20_ALICE_ADDRESS),
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject deposit of an addition overflow", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            }),
        })
        local expected_res = {
            status = "accepted",
            vouchers = {},
            notices = {},
            reports = { { payload = HONEYPOT_STATUS_SUCCESS } },
        }
        expect.equal(res, expected_res)

        res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        })
        expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = { { payload = HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW } },
        }
        expect.equal(res, expected_res)
    end)

    it("should reject input number out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
                input_number = "0x10000000000000000",
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject block number out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
                block_number = "0x10000000000000000",
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject epoch number out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
                epoch_number = "0x10000000000000000",
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject timestamp out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
                timestamp = "0x10000000000000000",
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject input with length out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
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
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject input with length out of supported range", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
            },
            payload = {
                offset = 32,
                length = "0x10000000000000000",
                data = encode_utils.encode_erc20_deposit({
                    successful = true,
                    contract_address = ERC20_CONTRACT_ADDRESS,
                    sender_address = ERC20_ALICE_ADDRESS,
                    amount = 1,
                }),
            },
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject deposit with maximum possible data size", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local RX_BUFFER_HEADER_SIZE = 64
        local ERC20_DEPOSIT_MSG_SIZE = 1 + 20 * 2 + 32
        local max_data_size = rolling_machine.config.rollup.rx_buffer.length
            - ERC20_DEPOSIT_MSG_SIZE
            - RX_BUFFER_HEADER_SIZE
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
                extra_data = string.rep("X", max_data_size),
            }),
        })
        local expected_res = {
            status = "rejected",
            vouchers = {},
            notices = {},
            reports = {},
        }
        expect.equal(res, expected_res)
    end)

    it("should reject when voucher write fails", function()
        local rolling_machine <close> = inital_rolling_machine:fork()
        local res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_PORTAL_ADDRESS,
            },
            payload = encode_utils.encode_erc20_deposit({
                successful = true,
                contract_address = ERC20_CONTRACT_ADDRESS,
                sender_address = ERC20_ALICE_ADDRESS,
                amount = 1,
            }),
        })
        local expected_res = {
            status = "accepted",
            vouchers = {},
            notices = {},
            reports = { { payload = HONEYPOT_STATUS_SUCCESS } },
        }
        expect.equal(res, expected_res)

        -- This is a trick to intentionally invalidate a yield automatic when writing a voucher,
        -- so we can trigger HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED code path
        function rolling_machine:run_break_cb(break_reason)
            if
                break_reason == cartesi.BREAK_REASON_YIELDED_AUTOMATICALLY
                and self:read_yield_reason() == cartesi.machine.HTIF_YIELD_REASON_TX_VOUCHER
            then
                self.machine:write_htif_fromhost(0)
            end
        end

        res = rolling_machine:advance_state({
            metadata = {
                msg_sender = ERC20_WITHDRAW_ADDRESS,
            },
        })
        expected_res = {
            status = "rejected",
            vouchers = {
                {
                    address = encode_utils.encode_erc20_address(ERC20_CONTRACT_ADDRESS),
                    payload = encode_utils.encode_erc20_transfer_voucher({
                        destination_address = ERC20_WITHDRAW_ADDRESS,
                        amount = 1,
                    }),
                },
            },
            notices = {},
            reports = { { payload = HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED } },
        }
        expect.equal(res, expected_res)
    end)
end)
