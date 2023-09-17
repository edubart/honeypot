local cartesi_rolling_machine = require("cartesi-testlib.rolling-machine")
local encode_utils = require("cartesi-testlib.encode-utils")
local now = require("socket").gettime

local ERC20_PORTAL_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0x4340ac4FcdFC5eF8d34930C96BBac2Af1301DF40")
local ERC20_CONTRACT_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0xc6e7DF5E7b4f2A278906862b61205850344D4e7d")
local ERC20_ALICE_ADDRESS_ENCODED = encode_utils.encode_erc20_address("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
local MACHINE_STORED_DIR = "snapshot"
local MACHINE_RUNTIME_CONFIG = {
    htif = {
        no_console_putchar = true,
    },
    skip_root_hash_check = true,
    skip_version_check = true,
}
local REMOTE_PROTOCOL = "local"

local input = {
    metadata = {
        msg_sender = ERC20_PORTAL_ADDRESS_ENCODED,
    },
    payload = encode_utils.encode_erc20_deposit({
        successful = true,
        contract_address = ERC20_CONTRACT_ADDRESS_ENCODED,
        sender_address = ERC20_ALICE_ADDRESS_ENCODED,
        amount = string.rep("\x00", 32),
    }),
}
local rolling_machine <close> = cartesi_rolling_machine(MACHINE_STORED_DIR, MACHINE_RUNTIME_CONFIG, REMOTE_PROTOCOL)

--bench
for _ = 1, 128 do
    local iterations = 2048
    local start_mcycle = rolling_machine.machine:read_mcycle()
    local start_time = now()
    for _ = 1, iterations do
        local res = rolling_machine:advance_state(input, false)
        assert(res.status == "accepted")
    end
    local elapsed_mcycle = rolling_machine.machine:read_mcycle() - start_mcycle
    local elapsed_time = now() - start_time
    print(string.format("%s %.2f req/s", REMOTE_PROTOCOL, iterations / elapsed_time))
    print(string.format("%s %.2f M mcycle/s", REMOTE_PROTOCOL, elapsed_mcycle / elapsed_time / 1000000))
    print(string.format("%s %.2f mcycle/req", REMOTE_PROTOCOL, elapsed_mcycle / iterations))
    print()
end
