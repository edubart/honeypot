// Copyright Cartesi Pte. Ltd.
//
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use
// this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

#include <cstdint>
#include <cerrno>    // errno
#include <cstdio>    // fprintf
#include <cstring>   // strerror
#include <array>     // std::array
#include <algorithm> // std::copy

extern "C" {
#include <fcntl.h>     // open
#include <unistd.h>    // close
#include <sys/ioctl.h> // ioctl
#include <linux/cartesi/rollup.h>
}

////////////////////////////////////////////////////////////////////////////////
// ERC-20 Address and Big Endian 256 primitives.

using erc20_address = std::array<uint8_t, 20>;
using be256 = std::array<uint8_t, 32>;

// Adds `a` and `b` and store in `res`.
// Returns true when there is no arithmetic overflow, false otherwise.
static bool be256_checked_add(be256 &res, const be256 &a, const be256 &b) {
    uint16_t carry = 0;
    for (uint32_t i = 0; i < static_cast<uint32_t>(res.size()); ++i) {
        const uint32_t j = static_cast<uint32_t>(res.size()) - i - 1;
        const uint16_t aj = static_cast<uint16_t>(a[j]);
        const uint16_t bj = static_cast<uint16_t>(b[j]);
        const uint16_t tmp = static_cast<uint16_t>(carry + aj + bj);
        carry = tmp >> 8;
        res[j] = static_cast<uint8_t>(tmp & 0xff);
    }
    return carry == 0;
}

////////////////////////////////////////////////////////////////////////////////
// Rollup utilities.

struct rollup_advance_input_metadata {
    erc20_address sender;
    uint64_t block_number;
    uint64_t timestamp;
    uint64_t epoch_index;
    uint64_t input_index;
};

// Write a report POD into rollup device.
template <typename T>
static bool rollup_write_report(int rollup_fd, const T &payload) {
    rollup_report report{};
    report.payload = {const_cast<uint8_t *>(reinterpret_cast<const uint8_t *>(&payload)), sizeof(payload)};
    if (ioctl(rollup_fd, IOCTL_ROLLUP_WRITE_REPORT, &report) < 0) {
        (void) fprintf(stderr, "[dapp] unable to write rollup report: %s\n", std::strerror(errno));
        return false;
    }
    return true;
}

// Write a voucher POD into rollup device.
template <typename T>
static bool rollup_write_voucher(int rollup_fd, const erc20_address &destination, const T &payload) {
    rollup_voucher voucher{};
    std::copy(destination.begin(), destination.end(), voucher.destination);
    voucher.payload = {const_cast<uint8_t *>(reinterpret_cast<const uint8_t *>(&payload)), sizeof(payload)};
    if (ioctl(rollup_fd, IOCTL_ROLLUP_WRITE_VOUCHER, &voucher) < 0) {
        (void) fprintf(stderr, "[dapp] unable to write rollup voucher: %s\n", std::strerror(errno));
        return false;
    }
    return true;
}

// Finish last rollup request, wait for next rollup request and process it.
// For every new request, reads an input POD and call backs its respective advance or inspect state handler.
template <typename ADVANCE_INPUT, typename INSPECT_INPUT, typename ADVANCE_STATE, typename INSPECT_STATE>
static bool rollup_process_next_request(int rollup_fd, bool accept_previous_request, ADVANCE_STATE &&advance_cb, INSPECT_STATE &&inspect_cb) {
    // Finish previous request and wait for the next request.
    rollup_finish finish_request{};
    finish_request.accept_previous_request = accept_previous_request;
    if (ioctl(rollup_fd, IOCTL_ROLLUP_FINISH, &finish_request) < 0) {
        (void) fprintf(stderr, "[dapp] unable to perform IOCTL_ROLLUP_FINISH: %s\n", std::strerror(errno));
        return false;
    }
    const uint64_t input_data_length = static_cast<uint64_t>(finish_request.next_request_payload_length);
    if (finish_request.next_request_type == CARTESI_ROLLUP_ADVANCE_STATE) { // Advance state.
        // Check if input payload length is supported.
        if (input_data_length > sizeof(ADVANCE_INPUT)) {
            (void) fprintf(stderr, "[dapp] advance request payload length is too large\n");
            return false;
        }
        // Read the input.
        static ADVANCE_INPUT input_data{};
        rollup_advance_state request{};
        request.payload = {reinterpret_cast<uint8_t *>(&input_data), sizeof(input_data)};
        if (ioctl(rollup_fd, IOCTL_ROLLUP_READ_ADVANCE_STATE, &request) < 0) {
            (void) fprintf(stderr, "[dapp] unable to perform IOCTL_ROLLUP_READ_ADVANCE_STATE: %s\n", std::strerror(errno));
            return false;
        }
        rollup_advance_input_metadata input_metadata{{},
            request.metadata.block_number,
            request.metadata.timestamp,
            request.metadata.epoch_index,
            request.metadata.input_index};
        std::copy(std::begin(request.metadata.msg_sender), std::end(request.metadata.msg_sender), input_metadata.sender.begin());
        // Call advance state handler.
        return advance_cb(rollup_fd, input_metadata, input_data, input_data_length);
    } else if (finish_request.next_request_type == CARTESI_ROLLUP_INSPECT_STATE) { // Inspect state.
        // Check if input payload length is supported.
        if (input_data_length > sizeof(INSPECT_INPUT)) {
            (void) fprintf(stderr, "[dapp] inspect request payload length is too large\n");
            return false;
        }
        // Read the input.
        static INSPECT_INPUT input_data{};
        rollup_inspect_state request{};
        request.payload = {reinterpret_cast<uint8_t *>(&input_data), sizeof(input_data)};
        if (ioctl(rollup_fd, IOCTL_ROLLUP_READ_INSPECT_STATE, &request) < 0) {
            (void) fprintf(stderr, "[dapp] unable to perform IOCTL_ROLLUP_READ_INSPECT_STATE: %s\n", std::strerror(errno));
            return false;
        }
        // Call inspect state handler.
        return inspect_cb(rollup_fd, input_data, input_data_length);
    } else {
        (void) fprintf(stderr, "[dapp] invalid request type\n");
        return false;
    }
}

template <typename ADVANCE_INPUT, typename INSPECT_INPUT, typename ADVANCE_STATE, typename INSPECT_STATE>
static int rollup_request_loop(ADVANCE_STATE &&advance_cb, INSPECT_STATE &&inspect_cb) {
    // Open rollup device.
    const int rollup_fd = open("/dev/rollup", O_RDWR);
    if (rollup_fd < 0) {
        // This operation may fail only for machines where the rollup device is not configured correctly.
        (void) fprintf(stderr, "[dapp] unable to open rollup device: %s\n", std::strerror(errno));
        return false;
    }
    // Rollup device requires that we initialize the first previous request as accepted.
    bool accept_previous_request = true;
    // Request loop, should loop forever.
    while (true) {
        accept_previous_request = rollup_process_next_request<ADVANCE_INPUT, INSPECT_INPUT>(rollup_fd, accept_previous_request, advance_cb, inspect_cb);
    }
    // The following code is unreachable, just here for sanity.
    if (close(rollup_fd) < 0) {
        (void) fprintf(stderr, "[dapp] unable to close rollup device: %s\n", std::strerror(errno));
        return false;
    }
    return true;
}

////////////////////////////////////////////////////////////////////////////////
// ERC-20 encoding utilities.

enum erc20_deposit_status : uint8_t {
    ERC20_DEPOSIT_FAILED = 0,
    ERC20_DEPOSIT_SUCCESSFUL = 1,
};

// Payload encoding for ERC-20 deposits.
struct erc20_deposit_payload {
    uint8_t status;
    erc20_address contract_address;
    erc20_address sender_address;
    be256 amount;
};

// Payload encoding for ERC-20 transfers.
struct erc20_transfer_payload {
    std::array<uint8_t, 16> bytecode;
    erc20_address destination;
    be256 amount;
};

// Encodes a ERC-20 transfer of amount to destination address.
static erc20_transfer_payload encode_erc20_transfer(erc20_address destination, be256 amount) {
    erc20_transfer_payload payload{};
    // Bytecode for solidity 'transfer(address,uint256)' in solidity.
    payload.bytecode = {0xa9, 0x05, 0x9c, 0xbb};
    // The last 12 bytes in bytecode should be zeros.
    payload.destination = destination;
    payload.amount = amount;
    return payload;
}

////////////////////////////////////////////////////////////////////////////////
// Honeypot application.

static constexpr erc20_address ERC20_PORTAL_ADDRESS     = {{0x43, 0x40, 0xac, 0x4F, 0xcd, 0xFC, 0x5e, 0xF8, 0xd3, 0x49, 0x30, 0xC9, 0x6B, 0xBa, 0xc2, 0xAf, 0x13, 0x01, 0xDF, 0x40}};
static constexpr erc20_address ERC20_WITHDRAWAL_ADDRESS = {{0x70, 0x99, 0x79, 0x70, 0xC5, 0x18, 0x12, 0xdc, 0x3A, 0x01, 0x0C, 0x7d, 0x01, 0xb5, 0x0e, 0x0d, 0x17, 0xdc, 0x79, 0xC8}};
static constexpr erc20_address ERC20_CONTRACT_ADDRESS   = {{0xc6, 0xe7, 0xDF, 0x5E, 0x7b, 0x4f, 0x2A, 0x27, 0x89, 0x06, 0x86, 0x2b, 0x61, 0x20, 0x58, 0x50, 0x34, 0x4D, 0x4e, 0x7d}};

// Status code sent in as reports for well formed advance requests.
enum honeypot_advance_status : uint8_t {
    HONEYPOT_STATUS_SUCCESS = 0,
    HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED,
    HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT,
    HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW,
    HONEYPOT_STATUS_WITHDRAW_NO_FUNDS,
    HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED,
};

// POD for advance inputs.
struct honeypot_advance_input {
    erc20_deposit_payload deposit;
};

// POD for inspect inputs.
struct honeypot_inspect_input {
    uint8_t dummy; // Unused, just here because C++ cannot have empty structs.
};

// POD for advance reports.
struct honeypot_advance_report {
    honeypot_advance_status status;
};

// POD for inspect reports.
struct honeypot_inspect_report {
    be256 balance;
};

// State of the honeypot dapp.
static be256 honeypot_balance{};

// Process a ERC-20 deposit request.
static bool honeypot_deposit(int rollup_fd, const erc20_deposit_payload &deposit) {
    // Consider only successful ERC-20 deposits.
    if (deposit.status != ERC20_DEPOSIT_SUCCESSFUL) {
        (void) fprintf(stderr, "[dapp] deposit erc20 transfer failed\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED});
        return false;
    }
    // Check token contract address.
    if (deposit.contract_address != ERC20_CONTRACT_ADDRESS) {
        (void) fprintf(stderr, "[dapp] invalid deposit contract address\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT});
        return false;
    }
    // Add deposit amount to balance.
    if (!be256_checked_add(honeypot_balance, honeypot_balance, deposit.amount)) {
        (void) fprintf(stderr, "[dapp] deposit balance overflow\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW});
        return false;
    }
    // Report that operation succeed.
    (void) fprintf(stderr, "[dapp] successful deposit\n");
    (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_SUCCESS});
    return true;
}

// Process a ERC-20 withdraw request.
static bool honeypot_withdraw(int rollup_fd) {
    (void) fprintf(stderr, "[dapp] withdraw request\n");
    // Report an error if the balance is empty.
    if (honeypot_balance == be256{}) {
        (void) fprintf(stderr, "[dapp] no funds to withdraw\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_WITHDRAW_NO_FUNDS});
        return false;
    }
    // Issue a voucher with the entire balance.
    erc20_transfer_payload transfer_payload = encode_erc20_transfer(ERC20_WITHDRAWAL_ADDRESS, honeypot_balance);
    if (!rollup_write_voucher(rollup_fd, ERC20_CONTRACT_ADDRESS, transfer_payload)) {
        (void) fprintf(stderr, "[dapp] unable to issue withdraw voucher\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED});
        return false;
    }
    // Set balance to 0.
    honeypot_balance = be256{};
    // Report that operation succeed
    (void) fprintf(stderr, "[dapp] successful withdrawal\n");
    (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_SUCCESS});
    return true;
}

// Process a inspect balance request.
static bool honeypot_inspect_balance(int rollup_fd) {
    (void) fprintf(stderr, "[dapp] inspect balance\n");
    return rollup_write_report(rollup_fd, honeypot_inspect_report{honeypot_balance});
}

// Process advance state requests.
static bool honeypot_advance_state(int rollup_fd, const rollup_advance_input_metadata &input_metadata, const honeypot_advance_input &input, uint64_t input_length) {
    if (input_metadata.sender == ERC20_PORTAL_ADDRESS && input_length == sizeof(erc20_deposit_payload)) { // Deposit
        return honeypot_deposit(rollup_fd, input.deposit);
    } else if (input_metadata.sender == ERC20_WITHDRAWAL_ADDRESS && input_length == 0) { // Withdraw
        return honeypot_withdraw(rollup_fd);
    } else { // Invalid request
        (void) fprintf(stderr, "[dapp] invalid advance state request\n");
        return false;
    }
}

// Process inspect state requests.
static bool honeypot_inspect_state(int rollup_fd, const honeypot_inspect_input &input, uint64_t input_length) {
    (void) input;
    if (input_length == 0) { // Inspect balance.
        return honeypot_inspect_balance(rollup_fd);
    } else { // Invalid request.
        (void) fprintf(stderr, "[dapp] invalid inspect state request\n");
        return false;
    }
}

// Application main.
int main() noexcept {
    // Process requests forever.
    return rollup_request_loop<honeypot_advance_input, honeypot_inspect_input>(honeypot_advance_state, honeypot_inspect_state) ? 0 : -1;
}
