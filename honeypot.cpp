// Copyright Cartesi and individual authors (see AUTHORS)
// SPDX-License-Identifier: Apache-2.0

#include <cstdint>

#include <cerrno>  // errno
#include <cstdio>  // fprintf/stderr
#include <cstring> // strerror/strlen/memcmp/memcpy

#include <array> // std::array
#include <tuple> // std::ignore

extern "C" {
#include <fcntl.h>    // open
#include <sys/mman.h> // mmap/msync
#include <unistd.h>   // close/lseek

#include <libcmt/abi.h>
#include <libcmt/io.h>
#include <libcmt/rollup.h>
}

#include "honeypot-config.hpp"

////////////////////////////////////////////////////////////////////////////////
// ERC-20 address type.

using erc20_address = cmt_abi_address_t;

// Compare two ERC-20 addresses.
static bool operator==(const erc20_address &a, const erc20_address &b) {
    return memcmp(&a, &b, sizeof(erc20_address)) == 0;
}

////////////////////////////////////////////////////////////////////////////////
// Big Endian 256 type.

using be256 = std::array<uint8_t, 32>;

// Adds `a` and `b` and store in `res`.
// Returns true when there is no arithmetic overflow, false otherwise.
[[nodiscard]]
static bool be256_checked_add(be256 &res, const be256 &a, const be256 &b) {
    uint16_t carry = 0;
    for (size_t i = 0; i < res.size(); ++i) {
        const size_t j = res.size() - i - 1;
        const uint16_t tmp = carry + a[j] + b[j];
        res[j] = static_cast<uint8_t>(tmp);
        carry = tmp >> 8U;
    }
    return carry == 0;
}

////////////////////////////////////////////////////////////////////////////////
// Rollup utilities.

// Emit a report POD into rollup device.
template <typename T>
[[nodiscard]]
static bool rollup_emit_report(cmt_rollup_t *rollup, const T &payload) {
    const cmt_abi_bytes_t payload_bytes = {
        .length = sizeof(T),
        .data = const_cast<T *>(&payload) // NOLINT(cppcoreguidelines-pro-type-const-cast)
    };
    const int err = cmt_rollup_emit_report(rollup, &payload_bytes);
    if (err < 0) {
        std::ignore = fprintf(stderr, "[dapp] unable to emit report: %s\n", strerror(-err));
        return false;
    }
    return true;
}

// Emit a voucher POD into rollup device.
template <typename T>
[[nodiscard]]
static bool rollup_emit_voucher(cmt_rollup_t *rollup, const erc20_address &address, const T &payload) {
    const cmt_abi_bytes_t payload_bytes = {
        .length = sizeof(T),
        .data = const_cast<T *>(&payload) // NOLINT(cppcoreguidelines-pro-type-const-cast)
    };
    const cmt_abi_u256_t wei{}; // Transfer 0 Wei
    const int err = cmt_rollup_emit_voucher(rollup, &address, &wei, &payload_bytes, nullptr);
    if (err < 0) {
        std::ignore = fprintf(stderr, "[dapp] unable to emit voucher: %s\n", strerror(-err));
        return false;
    }
    return true;
}

// Finish last rollup request, wait for next rollup request and process it.
// For every new request, reads an input POD and call backs its respective advance or inspect state handler.
template <typename STATE, typename ADVANCE_STATE, typename INSPECT_STATE>
[[nodiscard]]
static bool rollup_process_next_request(cmt_rollup_t *rollup, STATE *state, bool accept_previous_request,
    ADVANCE_STATE advance_state, INSPECT_STATE inspect_state) {
    // Finish previous request and wait for the next request.
    cmt_rollup_finish_t finish{};
    finish.accept_previous_request = accept_previous_request;
    int err = cmt_rollup_finish(rollup, &finish);
    if (err < 0) {
        std::ignore = fprintf(stderr, "[dapp] unable to perform rollup finish: %s\n", strerror(-err));
        return false;
    }
    // Advance state?
    if (finish.next_request_type == HTIF_YIELD_REASON_ADVANCE) {
        // Read the input.
        cmt_rollup_advance_t advance{};
        err = cmt_rollup_read_advance_state(rollup, &advance);
        if (err < 0) {
            std::ignore = fprintf(stderr, "[dapp] unable to read advance state: %s\n", strerror(-err));
            return false;
        }
        // Call advance state handler.
        return advance_state(rollup, state, advance);
    }
    // Inspect state?
    if (finish.next_request_type == HTIF_YIELD_REASON_INSPECT) {
        // Read the query.
        cmt_rollup_inspect_t inspect{};
        err = cmt_rollup_read_inspect_state(rollup, &inspect);
        if (err < 0) {
            std::ignore = fprintf(stderr, "[dapp] unable to read inspect state: %s\n", strerror(-err));
            return false;
        }
        // Call inspect state handler.
        return inspect_state(rollup, state, inspect);
    }
    // Invalid request
    std::ignore = fprintf(stderr, "[dapp] invalid request type\n");
    return false;
}

// Process rollup requests forever.
template <typename STATE, typename ADVANCE_STATE, typename INSPECT_STATE>
[[noreturn]]
static void rollup_request_loop(cmt_rollup_t *rollup, STATE *state, ADVANCE_STATE advance_state,
    INSPECT_STATE inspect_state) {
    // Rollup device requires that we initialize the first previous request as accepted.
    bool accept_previous_request = true;
    // Request loop, should loop forever.
    while (true) {
        accept_previous_request =
            rollup_process_next_request(rollup, state, accept_previous_request, advance_state, inspect_state);
    }
    // Unreachable code.
}

////////////////////////////////////////////////////////////////////////////////
// ERC-20 encoding utilities.

// Bytecode for solidity 'transfer(address,uint256)' in solidity.
#define TRANSFER_FUNCTION_SELECTOR_BYTES {0xa9, 0x05, 0x9c, 0xbb}

enum erc20_deposit_status : uint8_t {
    ERC20_DEPOSIT_FAILED = 0,
    ERC20_DEPOSIT_SUCCESSFUL = 1,
};

// Payload encoding for ERC-20 deposits.
struct [[gnu::packed]] erc20_deposit_payload {
    uint8_t status;
    erc20_address token_address;
    erc20_address sender_address;
    be256 amount;
};

// Payload encoding for ERC-20 transfers.
struct [[gnu::packed]] erc20_transfer_payload {
    std::array<uint8_t, 16> bytecode;
    erc20_address destination;
    be256 amount;
};

// Encodes a ERC-20 transfer of amount to destination address.
static erc20_transfer_payload encode_erc20_transfer(erc20_address destination, be256 amount) {
    erc20_transfer_payload payload{};

    payload.bytecode = TRANSFER_FUNCTION_SELECTOR_BYTES;
    // The last 12 bytes in bytecode should be zeros.
    payload.destination = destination;
    payload.amount = amount;
    return payload;
}

////////////////////////////////////////////////////////////////////////////////
// DApp state utilities.

// Load dapp state from disk.
template <typename STATE>
[[nodiscard]]
static STATE *dapp_load_state(const char *block_device) {
    // Open the dapp state block device.
    // Note that we open but never close it, we intentionally let the OS do this automatically on exit.
    const int state_fd = open(block_device, O_RDWR);
    if (state_fd < 0) {
        std::ignore = fprintf(stderr, "[dapp] unable to open state block device: %s\n", strerror(errno));
        return nullptr;
    }
    // Check if the block device size is big enough.
    const auto size = lseek(state_fd, 0, SEEK_END);
    if (size < 0) {
        std::ignore = fprintf(stderr, "[dapp] unable to seek state block device: %s\n", strerror(errno));
        close(state_fd);
        return nullptr;
    }
    if (static_cast<size_t>(size) < sizeof(STATE)) {
        std::ignore = fprintf(stderr, "[dapp] state block device size is too small\n");
        close(state_fd);
        return nullptr;
    }
    // Map the state block device to memory.
    // Note that we call mmap() but never call munmap(), we intentionally let the OS automatically do this on exit.
    void *mem = mmap(nullptr, sizeof(STATE), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE, state_fd, 0);
    if (mem == MAP_FAILED) {
        std::ignore = fprintf(stderr, "[dapp] unable to map state block device to memory: %s\n", strerror(errno));
        close(state_fd);
        return nullptr;
    }
    // After the mmap() call, the file descriptor can be closed immediately without invalidating the mapping.
    if (close(state_fd) < 0) {
        std::ignore = fprintf(stderr, "[dapp] unable to close state block device: %s\n", strerror(errno));
        return nullptr;
    }
    return reinterpret_cast<STATE *>(mem); // NOLINT(cppcoreguidelines-pro-type-reinterpret-cast)
}

// Flush dapp state to disk.
template <typename STATE>
static void dapp_flush_state(STATE *state) {
    // Flushes state changes made into memory using mmap(2) back to the filesystem.
    if (msync(state, sizeof(STATE), MS_SYNC) < 0) {
        // Cannot recover from failure here, but report the error if any.
        std::ignore = fprintf(stderr, "[dapp] unable to flush state from memory to disk: %s\n", strerror(errno));
    }
}

////////////////////////////////////////////////////////////////////////////////
// Honeypot application.

static constexpr erc20_address ERC20_PORTAL_ADDRESS = {CONFIG_ERC20_PORTAL_ADDRESS};
static constexpr erc20_address ERC20_WITHDRAWAL_ADDRESS = {CONFIG_ERC20_WITHDRAWAL_ADDRESS};
static constexpr erc20_address ERC20_TOKEN_ADDRESS = {CONFIG_ERC20_TOKEN_ADDRESS};

// Status code sent in as reports for well formed advance requests.
enum honeypot_advance_status : uint8_t {
    HONEYPOT_STATUS_SUCCESS = 0,
    HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED,
    HONEYPOT_STATUS_DEPOSIT_INVALID_TOKEN,
    HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW,
    HONEYPOT_STATUS_WITHDRAW_NO_FUNDS,
    HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED,
    HONEYPOT_STATUS_INVALID_REQUEST
};

// POD for advance inputs.
struct [[gnu::packed]] honeypot_advance_input {
    erc20_deposit_payload deposit{};
};

// POD for inspect queries.
struct [[gnu::packed]] honeypot_inspect_query {
    // No data needed for inspect requests.
};

// POD for advance reports.
struct [[gnu::packed]] honeypot_advance_report {
    honeypot_advance_status status{};
};

// POD for inspect reports.
struct [[gnu::packed]] honeypot_inspect_report {
    be256 balance{};
};

// POD for dapp state.
struct [[gnu::packed]] honeypot_state {
    be256 balance{};
};

// Process a ERC-20 deposit request.
static bool honeypot_deposit(cmt_rollup_t *rollup, honeypot_state *state, const erc20_deposit_payload &deposit) {
    // Consider only successful ERC-20 deposits.
    if (deposit.status != ERC20_DEPOSIT_SUCCESSFUL) {
        std::ignore = fprintf(stderr, "[dapp] deposit erc20 transfer failed\n");
        std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED});
        return false;
    }
    // Check token address.
    if (deposit.token_address != ERC20_TOKEN_ADDRESS) {
        std::ignore = fprintf(stderr, "[dapp] invalid deposit token address\n");
        std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_INVALID_TOKEN});
        return false;
    }
    // Add deposit amount to balance.
    be256 new_balance{};
    if (!be256_checked_add(new_balance, state->balance, deposit.amount)) {
        std::ignore = fprintf(stderr, "[dapp] deposit balance overflow\n");
        std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW});
        return false;
    }
    state->balance = new_balance;
    // Flush dapp state to disk, so we can inspect its state from outside.
    dapp_flush_state(state);
    // Report that operation succeed.
    std::ignore = fprintf(stderr, "[dapp] successful deposit\n");
    std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_SUCCESS});
    return true;
}

// Process a ERC-20 withdraw request.
static bool honeypot_withdraw(cmt_rollup_t *rollup, honeypot_state *state) {
    // Report an error if the balance is empty.
    if (state->balance == be256{}) {
        std::ignore = fprintf(stderr, "[dapp] no funds to withdraw\n");
        std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_WITHDRAW_NO_FUNDS});
        return false;
    }
    // Issue a voucher with the entire balance.
    const erc20_transfer_payload transfer_payload = encode_erc20_transfer(ERC20_WITHDRAWAL_ADDRESS, state->balance);
    if (!rollup_emit_voucher(rollup, ERC20_TOKEN_ADDRESS, transfer_payload)) {
        std::ignore = fprintf(stderr, "[dapp] unable to issue withdraw voucher\n");
        std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED});
        return false;
    }
    // Only zero balance after successful voucher emission.
    state->balance = be256{};
    // Flush dapp state to disk, so we can inspect its state from outside.
    dapp_flush_state(state);
    // Report that operation succeed.
    std::ignore = fprintf(stderr, "[dapp] successful withdrawal\n");
    std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_SUCCESS});
    return true;
}

// Process a inspect balance request.
static bool honeypot_inspect_balance(cmt_rollup_t *rollup, honeypot_state *state) {
    std::ignore = fprintf(stderr, "[dapp] inspect balance request\n");
    return rollup_emit_report(rollup, honeypot_inspect_report{state->balance});
}

// Process advance state requests.
static bool honeypot_advance_state(cmt_rollup_t *rollup, honeypot_state *state, const cmt_rollup_advance &input) {
    // Deposit?
    if (input.msg_sender == ERC20_PORTAL_ADDRESS && input.payload.length == sizeof(erc20_deposit_payload)) {
        erc20_deposit_payload deposit{};
        memcpy(&deposit, input.payload.data, sizeof(erc20_deposit_payload));
        return honeypot_deposit(rollup, state, deposit);
    }
    // Withdraw?
    if (input.msg_sender == ERC20_WITHDRAWAL_ADDRESS && input.payload.length == 0) {
        return honeypot_withdraw(rollup, state);
    }
    // Invalid request.
    std::ignore = fprintf(stderr, "[dapp] invalid advance state request\n");
    std::ignore = rollup_emit_report(rollup, honeypot_advance_report{HONEYPOT_STATUS_INVALID_REQUEST});
    return false;
}

// Process inspect state queries.
static bool honeypot_inspect_state(cmt_rollup_t *rollup, honeypot_state *state, const cmt_rollup_inspect &query) {
    // Inspect balance?
    if (query.payload.length == 0) {
        return honeypot_inspect_balance(rollup, state);
    }
    // Invalid query.
    std::ignore = fprintf(stderr, "[dapp] invalid inspect state query\n");
    return false;
}

// Application main.
int main() {
    cmt_rollup_t rollup{};
    // Load dapp state from disk.
    auto *state = dapp_load_state<honeypot_state>(CONFIG_STATE_BLOCK_DEVICE);
    if (state == nullptr) {
        std::ignore = fprintf(stderr, "[dapp] unable to load dapp state\n");
        return -1;
    }
    // Initialize rollup device.
    const int err = cmt_rollup_init(&rollup);
    if (err != 0) {
        std::ignore = fprintf(stderr, "[dapp] unable to initialize rollup device: %s\n", strerror(-err));
        return -1;
    }
    // Process requests forever.
    rollup_request_loop(&rollup, state, honeypot_advance_state, honeypot_inspect_state);
    // Unreachable code, return is intentionally omitted.
}
