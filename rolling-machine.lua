local jsonrpc = require("cartesi.jsonrpc")
local cartesi = require("cartesi")
local unistd = require("posix.unistd")
local sys_wait = require("posix.sys.wait")
local time = require("posix.time")
local encode_utils = require("encode-utils")

local CARTESI_ROLLUP_ADVANCE_STATE = 0
local CARTESI_ROLLUP_INSPECT_STATE = 1

-- TODO: read hashes

local next_remote_port = 9000

local rolling_machine = {}
rolling_machine.__index = rolling_machine

local function spawn_remote_cartesi_machine(port)
    local remote_pid = assert(unistd.fork())
    if not port then
        port = next_remote_port
        next_remote_port = next_remote_port + 1
    end
    local remote_address = "127.0.0.1:" .. port
    if remote_pid == 0 then -- child
        -- local fcntl = require 'posix.fcntl'
        -- local devnull_fd = assert(fcntl.open("/dev/null", fcntl.O_RDWR))
        -- assert(unistd.dup2(devnull_fd, unistd.STDOUT_FILENO))
        assert(unistd.execp("jsonrpc-remote-cartesi-machine", {
            [0] = "jsonrpc-remote-cartesi-machine",
            remote_address,
        }))
        unistd._exit(0)
    else -- parent
        time.nanosleep({ tv_sec = 0, tv_nsec = 100 * 1000 * 1000 })
        local remote = assert(jsonrpc.stub(remote_address))
        local function remote_shutdown()
            remote.shutdown()
            sys_wait.wait(remote_pid)
            setmetatable(remote, nil)
        end
        setmetatable(remote, {
            __close = remote_shutdown,
            __gc = remote_shutdown,
        })
        return remote
    end
end

setmetatable(rolling_machine, {
    __call = function(rolling_machine_mt, dir, port)
        local remote = spawn_remote_cartesi_machine(port)
        local machine = remote.machine(dir)
        local config = machine:get_initial_config()
        return setmetatable({
            default_msg_sender = string.rep("\x00", 32),
            epoch_number = 0,
            input_number = 0,
            block_number = 0,
            remote = remote,
            machine = machine,
            config = config,
        }, rolling_machine_mt)
    end,
})

function rolling_machine:__close()
    if self.machine then
        self.machine:destroy()
        self.machine = nil
    end
    if self.remote then
        self.remote:shutdown()
        self.remote = nil
    end
end

-- Write the input metadata into the rollup input_metadata memory range.
function rolling_machine:write_input_metadata(input_metadata)
    input_metadata.msg_sender = input_metadata.msg_sender or self.default_msg_sender
    input_metadata.block_number = input_metadata.block_number or self.block_number
    input_metadata.timestamp = input_metadata.timestamp or os.time()
    input_metadata.epoch_number = input_metadata.epoch_number or self.epoch_number
    input_metadata.input_number = input_metadata.input_number or self.input_number
    self.machine:write_memory(
        self.config.rollup.input_metadata.start,
        table.concat({
            input_metadata.msg_sender,
            encode_utils.encode_be256(input_metadata.block_number),
            encode_utils.encode_be256(input_metadata.timestamp),
            encode_utils.encode_be256(input_metadata.epoch_number),
            encode_utils.encode_be256(input_metadata.input_number),
        })
    )
end

-- Write the input into the rollup rx_buffer memory range.
function rolling_machine:write_input_payload(input)
    if type(input) == 'table' then
        self.machine:write_memory(
            self.config.rollup.rx_buffer.start,
            table.concat({
                encode_utils.encode_be256(input.offset),
                encode_utils.encode_be256(input.length),
                input.data,
            })
        )
    else -- should be string
        local offset = 32
        local length = #input
        self.machine:write_memory(
            self.config.rollup.rx_buffer.start,
            table.concat({
                encode_utils.encode_be256(offset),
                encode_utils.encode_be256(length),
                input,
            })
        )
    end
end

function rolling_machine:read_simple_payload(tx_offset)
    local tx_buffer_start = self.config.rollup.tx_buffer.start + tx_offset
    -- Unpack payload offset and length
    local off_pad, off, len_pad, len = string.unpack("> I16I16 I16I16", self.machine:read_memory(tx_buffer_start, 64))
    -- Validate payload encoding
    assert(off_pad == 0 and len_pad == 0, "invalid payload padding")
    assert(off == tx_offset + 32, "invalid payload offset")
    -- Get payload data itself, skipping offset and length
    return self.machine:read_memory(tx_buffer_start + 64, len)
end

function rolling_machine:read_report() return { payload = self:read_simple_payload(0) } end

function rolling_machine:read_notice() return { payload = self:read_simple_payload(0) } end

function rolling_machine:read_voucher()
    return {
        address = self.machine:read_memory(self.config.rollup.tx_buffer.start, 32),
        payload = self:read_simple_payload(32),
    }
end

function rolling_machine:read_yield_reason()
    if not self.machine:read_iflags_H() and (self.machine:read_iflags_Y() or self.machine:read_iflags_X()) then
        return self.machine:read_htif_tohost_data() >> 32
    end
    return nil
end

function rolling_machine:run_collecting_events()
    local events = {
        vouchers = {},
        notices = {},
        reports = {},
    }
    while true do
        local break_reason = self.machine:run()
        local yield_reason = self:read_yield_reason()
        if break_reason == cartesi.BREAK_REASON_HALTED then
            return { status = "halted", events = events }
        elseif break_reason == cartesi.BREAK_REASON_YIELDED_MANUALLY then
            if yield_reason == cartesi.machine.HTIF_YIELD_REASON_RX_ACCEPTED then
                return { status = "accepted", events = events }
            elseif yield_reason == cartesi.machine.HTIF_YIELD_REASON_RX_REJECTED then
                return { status = "rejected", events = events }
            elseif yield_reason == cartesi.machine.HTIF_YIELD_REASON_TX_EXCEPTION then
                return { status = "exception", exception_payload = self:read_simple_payload(0), events = events }
            else
                error("unexpected yield reason")
            end
        elseif break_reason == cartesi.BREAK_REASON_YIELDED_AUTOMATICALLY then
            if yield_reason == cartesi.machine.HTIF_YIELD_REASON_TX_VOUCHER then
                table.insert(events.vouchers, self:read_voucher())
            elseif yield_reason == cartesi.machine.HTIF_YIELD_REASON_TX_NOTICE then
                table.insert(events.notices, self:read_notice())
            elseif yield_reason == cartesi.machine.HTIF_YIELD_REASON_TX_REPORT then
                table.insert(events.reports, self:read_report())
            end
        -- ignore other reasons (such as HTIF_YIELD_REASON_PROGRESS)
        else
            error("unexpected break reason")
        end
    end
end

function rolling_machine:advance_state(input)
    -- Check if we can perform an advance request
    assert(
        self:read_yield_reason() == cartesi.machine.HTIF_YIELD_REASON_RX_ACCEPTED,
        "machine must be yielded with rx accepted to advance state"
    )
    -- Save machine state
    self.machine:snapshot()
    -- Write the input metadata and data
    self:write_input_metadata(input.metadata or {})
    self:write_input_payload(input.payload or "")
    -- Tell machine this is an advance-state request
    self.machine:write_htif_fromhost_data(CARTESI_ROLLUP_ADVANCE_STATE)
    -- Reset the Y flag so machine can proceed
    self.machine:reset_iflags_Y()
    -- Run the advance request
    local res = self:run_collecting_events()
    -- Restore machine state for rejected requests
    if res.status == "rejected" then
        self.machine:rollback()
    elseif res.status == "accepted" then
        self.input_number = self.input_number + 1
    end
    return res
end

function rolling_machine:inspect_state(input)
    -- Check if we can perform an inspect request
    assert(
        self:read_yield_reason() == cartesi.machine.HTIF_YIELD_REASON_RX_ACCEPTED,
        "machine must be yielded with rx accepted to inspect state"
    )
    -- Save machine state
    self.machine:snapshot()
    -- Write the input metadata and data
    self:write_input_metadata(input.metadata or {})
    self:write_input_payload(input.payload or "")
    -- Tell machine this is an inspect-state request
    self.machine:write_htif_fromhost_data(CARTESI_ROLLUP_INSPECT_STATE)
    -- Reset the Y flag so machine can proceed
    self.machine:reset_iflags_Y()
    -- Run the inspect request
    local res = self:run_collecting_events()
    -- Restore machine state
    self.machine:rollback()
    return res
end

return rolling_machine
