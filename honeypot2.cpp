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
#include <cerrno> // errno
#include <cstring> // memcpy, memcmp, strerror
#include <cstdio> // fprintf

extern "C" {
#include <unistd.h> // close
#include <fcntl.h> // open
#include <sys/ioctl.h> // ioctl
#include <linux/cartesi/rollup.h>
// #include "rollup.h"
}

// ERC-20 Address
struct erc20_address {
    uint8_t bytes[20];
};

static bool erc20addr_equal(const erc20_address& a, const erc20_address& b) {
    return memcmp(a.bytes, b.bytes, 20) == 0;
}

// Big Endian 256
struct be256 {
    uint8_t bytes[32];
};

static bool be256_equal(const be256& a, const be256& b) {
    return memcmp(a.bytes, b.bytes, 32) == 0;
}

static bool be256_checked_add(be256& res, const be256& a, const be256& b) {
    uint16_t carry = 0;
    for (uint32_t i=0; i < 32; ++i) {
        const uint32_t j = 32 - i - 1;
        const uint16_t aj  = static_cast<uint16_t>(a.bytes[j]);
        const uint16_t bj  = static_cast<uint16_t>(b.bytes[j]);
        const uint16_t tmp = static_cast<uint16_t>(carry + aj + bj);
        carry = tmp >> 8;
        res.bytes[j] = static_cast<uint8_t>(tmp & 0xff);
    }
    return carry == 0;
}

// Rollup

constexpr uint64_t ROLLUP_PAYLOAD_MAX_LENGTH = 2*1024*1024 - 64;

template <typename T>
static bool rollup_write_report(int rollup_fd, const T& payload) {
    rollup_report report{};
    report.payload = { const_cast<uint8_t*>(reinterpret_cast<const uint8_t*>(&payload)), sizeof(payload) };
    if (ioctl(rollup_fd, IOCTL_ROLLUP_WRITE_REPORT, &report) < 0) {
        (void) fprintf(stderr, "[dapp] unable to write rollup report: %s\n", strerror(errno));
        return false;
    }
    return true;
}

template <typename T>
static bool rollup_write_voucher(int rollup_fd, const erc20_address& destination, const T& payload) {
    rollup_voucher voucher{};
    memcpy(voucher.destination, destination.bytes, sizeof(erc20_address));
    voucher.payload = { const_cast<uint8_t*>(reinterpret_cast<const uint8_t*>(&payload)), sizeof(payload) };
    if (ioctl(rollup_fd, IOCTL_ROLLUP_WRITE_VOUCHER, &voucher) < 0) {
        (void) fprintf(stderr, "[dapp] unable to write rollup voucher: %s\n", strerror(errno));
        return false;
    }
    return true;
}

template <typename ADVANCE_STATE, typename INSPECT_STATE>
static bool rollup_process_request(int rollup_fd, bool accept_previous_request, ADVANCE_STATE&& advance_cb, INSPECT_STATE&& inspect_cb) {
    // Finish previous request and wait for the next request
    rollup_finish finish_request{};
    finish_request.accept_previous_request = accept_previous_request;
    if (ioctl(rollup_fd, IOCTL_ROLLUP_FINISH, &finish_request) < 0) {
        (void) fprintf(stderr, "[dapp] unable to perform IOCTL_ROLLUP_FINISH: %s\n", strerror(errno));
        return false;
    }
    // Check if payload length is supported
    const uint64_t payload_length = static_cast<uint64_t>(finish_request.next_request_payload_length);
    if (payload_length > ROLLUP_PAYLOAD_MAX_LENGTH) {
        (void) fprintf(stderr, "[dapp] request payload length of %lu exceeds maximum length of %lu\n", payload_length, ROLLUP_PAYLOAD_MAX_LENGTH);
        return false;
    }
    static uint8_t payload_buffer[ROLLUP_PAYLOAD_MAX_LENGTH]{};
    // Process the request
    if (finish_request.next_request_type == CARTESI_ROLLUP_ADVANCE_STATE) { // Advance state
        rollup_advance_state advance_state_request{};
        advance_state_request.payload = {payload_buffer, payload_length};
        if (ioctl(rollup_fd, IOCTL_ROLLUP_READ_ADVANCE_STATE, &advance_state_request) < 0) {
            (void) fprintf(stderr, "[dapp] unable to perform IOCTL_ROLLUP_READ_ADVANCE_STATE: %s\n", strerror(errno));
            return false;
        }
        // Call advance state handler
        return advance_cb(rollup_fd, advance_state_request);
    } else if(finish_request.next_request_type == CARTESI_ROLLUP_INSPECT_STATE) { // Inspect state
        rollup_inspect_state inspect_state_request{};
        inspect_state_request.payload = {payload_buffer, payload_length};
        if (ioctl(rollup_fd, IOCTL_ROLLUP_READ_INSPECT_STATE, &inspect_state_request) < 0) {
            (void) fprintf(stderr, "[dapp] unable to perform IOCTL_ROLLUP_READ_INSPECT_STATE: %s\n", strerror(errno));
            return false;
        }
        // Call inspect state handler
        return inspect_cb(rollup_fd, inspect_state_request);
    } else {
        (void) fprintf(stderr, "[dapp] invalid request type\n");
        return false;
    }
}

template <typename ADVANCE_STATE, typename INSPECT_STATE>
static int rollup_request_loop(ADVANCE_STATE&& advance_cb, INSPECT_STATE&& inspect_cb) {
    // Open rollup device.
    const int rollup_fd = open("/dev/rollup", O_RDWR);
    if (rollup_fd < 0) {
        // This operation may fail only for machines where the rollup device is not configured correctly.
        (void) fprintf(stderr, "[dapp] unable to open rollup device: %s\n", strerror(errno));
        return false;
    }
    // Previous request has no meaning for the very first request, but rollup device requires that we initialize it as accepted.
    bool accept_previous_request = true;
    // Request loop, should loop forever.
    while (true) {
        accept_previous_request = rollup_process_request(rollup_fd, accept_previous_request, advance_cb, inspect_cb);
    }
    // The following code is unreachable, just here for sanity.
    if (close(rollup_fd) < 0) {
        (void) fprintf(stderr, "[dapp] unable to close rollup device: %s\n", strerror(errno));
        return false;
    }
    return true;
}

// Encodings

enum erc20_deposit_status : uint8_t {
    ERC20_DEPOSIT_FAILED = 0,
    ERC20_DEPOSIT_SUCCESSFUL = 1,
};

struct erc20_deposit_payload {
    uint8_t status;
    erc20_address contract_address;
    erc20_address sender_address;
    be256 amount;
};

struct erc20_transfer_payload {
    uint8_t bytecode[4];
    uint8_t padding[12];
    erc20_address destination;
    be256 amount;
};

static erc20_transfer_payload encode_erc20_transfer(erc20_address destination, be256 amount) {
    erc20_transfer_payload payload{};
    payload.bytecode[0] = 0xa9;
    payload.bytecode[1] = 0x05;
    payload.bytecode[2] = 0x9c;
    payload.bytecode[3] = 0xbb;
    payload.destination = destination;
    payload.amount = amount;
    return payload;
}

// Honeypot

static constexpr erc20_address ERC20_PORTAL_ADDRESS     = {{0x43, 0x40, 0xac, 0x4F, 0xcd, 0xFC, 0x5e, 0xF8, 0xd3, 0x49, 0x30, 0xC9, 0x6B, 0xBa, 0xc2, 0xAf, 0x13, 0x01, 0xDF, 0x40}};
static constexpr erc20_address ERC20_WITHDRAWAL_ADDRESS = {{0x70, 0x99, 0x79, 0x70, 0xC5, 0x18, 0x12, 0xdc, 0x3A, 0x01, 0x0C, 0x7d, 0x01, 0xb5, 0x0e, 0x0d, 0x17, 0xdc, 0x79, 0xC8}};
static constexpr erc20_address ERC20_CONTRACT_ADDRESS   = {{0xc6, 0xe7, 0xDF, 0x5E, 0x7b, 0x4f, 0x2A, 0x27, 0x89, 0x06, 0x86, 0x2b, 0x61, 0x20, 0x58, 0x50, 0x34, 0x4D, 0x4e, 0x7d}};

enum honeypot_status : uint8_t {
    HONEYPOT_STATUS_SUCCESS = 0,
    HONEYPOT_STATUS_INVALID_SENDER,
    HONEYPOT_STATUS_INVALID_PAYLOAD_LENGTH,
    HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED,
    HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT,
    HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW,
    HONEYPOT_STATUS_WITHDRAW_NO_FUNDS,
    HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED,
};

struct honeypot_advance_report {
    honeypot_status code;
};

struct honeypot_inspect_report {
    be256 balance;
};

static be256 honeypot_balance{};

static bool honeypot_deposit_balance(int rollup_fd, const rollup_advance_state& req) {
    // Report an error if the payload length mismatch ERC-20 deposit length
    if (req.payload.length != sizeof(erc20_deposit_payload)) {
        (void) fprintf(stderr, "[dapp] invalid deposit payload length\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_INVALID_PAYLOAD_LENGTH});
        return false;
    }
    erc20_deposit_payload deposit = *reinterpret_cast<const erc20_deposit_payload*>(req.payload.data);
    if (deposit.status != ERC20_DEPOSIT_SUCCESSFUL) {
        (void) fprintf(stderr, "[dapp] deposit erc20 transfer failed\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_TRANSFER_FAILED});
        return false;
    }
    if (!erc20addr_equal(deposit.contract_address, ERC20_CONTRACT_ADDRESS)) {
        (void) fprintf(stderr, "[dapp] invalid deposit contract address\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_INVALID_CONTRACT});
        return false;
    }
    if (!be256_checked_add(honeypot_balance, honeypot_balance, deposit.amount)) {
        (void) fprintf(stderr, "[dapp] deposit balance overflow\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_DEPOSIT_BALANCE_OVERFLOW});
        return false;
    }
    // Report that operation succeed
    (void) fprintf(stderr, "[dapp] successful deposit\n");
    (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_SUCCESS});
    return true;
}

static bool honeypot_withdraw_balance(int rollup_fd, const rollup_advance_state& req) {
    (void) fprintf(stderr, "[dapp] withdraw request\n");
    // Report an error if the withdraw payload is not empty
    if (req.payload.length != 0) {
        (void) fprintf(stderr, "[dapp] invalid withdraw payload length\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_INVALID_PAYLOAD_LENGTH});
        return false;
    }
    // Report an error if the balance is empty
    if (be256_equal(honeypot_balance, be256{})) {
        (void) fprintf(stderr, "[dapp] no funds to withdraw\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_WITHDRAW_NO_FUNDS});
        return false;
    }
    // Issue a voucher with the entire balance
    erc20_transfer_payload transfer_payload = encode_erc20_transfer(ERC20_WITHDRAWAL_ADDRESS, honeypot_balance);
    if (!rollup_write_voucher(rollup_fd, ERC20_CONTRACT_ADDRESS, transfer_payload)) {
        (void) fprintf(stderr, "[dapp] unable to issue withdraw voucher\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_WITHDRAW_VOUCHER_FAILED});
        return false;
    }
    // Set balance to 0
    honeypot_balance = be256{};
    // Report that operation succeed
    (void) fprintf(stderr, "[dapp] successful withdrawal\n");
    (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_SUCCESS});
    return true;
}

static bool honeypot_advance_state(int rollup_fd, const rollup_advance_state& req) {
    const erc20_address sender_address = *reinterpret_cast<const erc20_address*>(req.metadata.msg_sender);
    if (erc20addr_equal(sender_address, ERC20_PORTAL_ADDRESS)) { // Deposit
        return honeypot_deposit_balance(rollup_fd, req);
    } else if (erc20addr_equal(sender_address, ERC20_WITHDRAWAL_ADDRESS)) { // Withdraw
        return honeypot_withdraw_balance(rollup_fd, req);
    } else { // Invalid sender
        (void) fprintf(stderr, "[dapp] invalid advance state request\n");
        (void) rollup_write_report(rollup_fd, honeypot_advance_report{HONEYPOT_STATUS_INVALID_SENDER});
        return false;
    }
}

static bool honeypot_inspect_state(int rollup_fd, const rollup_inspect_state& req) {
    (void) req;
    (void) fprintf(stderr, "[dapp] inspect balance\n");
    return rollup_write_report(rollup_fd, honeypot_inspect_report{honeypot_balance});
}

int main() noexcept {
    return rollup_request_loop(honeypot_advance_state, honeypot_inspect_state) ? 0 : -1;
}
