local cartesi = require("cartesi")
local unistd = require("posix.unistd")
local sys_socket = require("posix.sys.socket")
local time = require("posix.time")
local encode_utils = require("cartesi-testlib.encode-utils")

local CARTESI_ROLLUP_ADVANCE_STATE = 0
local CARTESI_ROLLUP_INSPECT_STATE = 1

-- TODO: read hashes

local next_remote_port = 5000

local rolling_machine = {}
rolling_machine.__index = rolling_machine

local function wait_remote_address(remote_addr, remote_port)
    local remote_addrinfo = assert(sys_socket.getaddrinfo(remote_addr, remote_port, {
        family=sys_socket.AF_INET,
        socktype=sys_socket.SOCK_STREAM
    }))
    local fd = assert(sys_socket.socket(sys_socket.AF_INET, sys_socket.SOCK_STREAM, 0))
    -- wait up to 1 second
    local ok, err
    for _=1,250 do
        ok, err = sys_socket.connect(fd, remote_addrinfo[1])
        if ok then break end
        time.nanosleep({ tv_sec = 0, tv_nsec = 4 * 1000 * 1000 })
    end
    unistd.close(fd)
    assert(ok, err)
end

local function spawn_remote_cartesi_machine(dir, remote_port, remote_protocol)
    local remote_pid = assert(unistd.fork())
    local remote_rpc = remote_protocol == 'jsonrpc' and require("cartesi.jsonrpc") or require("cartesi.grpc")
    local remote_bin = remote_protocol == 'jsonrpc' and "jsonrpc-remote-cartesi-machine" or "remote-cartesi-machine"
    local remote_addr = '127.0.0.1'
    local remote_endpoint = remote_addr..':'..remote_port
    local remote_checkin_endpoint = remote_addr..':'..(remote_port+1)
    if remote_pid == 0 then -- child
        assert(unistd.execp(remote_bin, {
            [0] = remote_bin,
            "--log-level=debug",
            "--server-address="..remote_endpoint,
        }))
        unistd._exit(0)
    else -- parent
        wait_remote_address(remote_addr, remote_port)
        local remote = assert(remote_rpc.stub(remote_endpoint, remote_checkin_endpoint))
        local machine = remote.machine(dir, {skip_root_hash_check=true, skip_version_check=true})
        return remote_rpc, remote, machine
    end
end

setmetatable(rolling_machine, {
    __call = function(rolling_machine_mt, dir, remote_protocol, remote_port)
        if not remote_port then
            remote_port = next_remote_port
            next_remote_port = next_remote_port + 2
        end
        remote_protocol = remote_protocol or 'jsonrpc'
        local remote_rpc, remote, machine = spawn_remote_cartesi_machine(dir, remote_port, remote_protocol)
        local config = machine:get_initial_config()
        return setmetatable({
            default_msg_sender = string.rep("\x00", 20),
            epoch_number = 0,
            input_number = 0,
            block_number = 0,
            remote_rpc = remote_rpc,
            remote = remote,
            machine = machine,
            config = config,
            remote_protocol = remote_protocol,
        }, rolling_machine_mt)
    end,
})

function rolling_machine:fork()
    local forked_remote = assert(self.remote_rpc.stub(self.remote.fork()))
    local forked_self = {}
    for k,v in pairs(self) do
        forked_self[k] = v
    end
    forked_self.remote = forked_remote
    forked_self.machine = forked_remote.get_machine()
    return setmetatable(forked_self, rolling_machine)
end

function rolling_machine:swap(forked)
    local keys = {}
    for k in pairs(self) do
        keys[k] = true
    end
    for k in pairs(forked) do
        keys[k] = true
    end
    for k in pairs(keys) do
        self[k], forked[k] = forked[k], self[k]
    end
end

function rolling_machine:destroy()
    if self.machine then
        self.machine:destroy()
        self.machine = nil
    end
    if self.remote then
        self.remote:shutdown()
        self.remote = nil
    end
    setmetatable(self, nil)
end

rolling_machine.__close = rolling_machine.destroy
rolling_machine.__gc = rolling_machine.destroy

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
            string.rep('\x00', 12), -- padding
            encode_utils.encode_erc20_address(input_metadata.msg_sender),
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

local function rolling_machine_advance_state(self, input)
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
    if res.status == "accepted" then
        self.input_number = self.input_number + 1
    end
    return res
end

function rolling_machine:advance_state(input, no_rollback)
    -- Check if we can perform an advance request
    assert(
        self:read_yield_reason() == cartesi.machine.HTIF_YIELD_REASON_RX_ACCEPTED,
        "machine must be yielded with rx accepted to advance state"
    )
    if no_rollback then
        return rolling_machine_advance_state(self, input)
    else
        if self.remote_protocol == 'jsonrpc' then
            -- Create machine state checkpoint
            local checkpoint <close> = self:fork()
            -- Advance state
            local res = rolling_machine_advance_state(self, input)
            if res.status == "rejected" then
                -- Rollback machine state
                self:swap(checkpoint)
            end
            return res
        else -- grpc
            -- Create machine state checkpoint
            self.machine:snapshot()
            -- Advance state
            local res = rolling_machine_advance_state(self, input)
            if res.status == "rejected" then
                -- Rollback machine state
                self.machine:rollback()
            end
            return res
        end
    end
end

local function rolling_machine_inspect_state(self, input)
    -- Write the input metadata and data
    self:write_input_metadata(input.metadata or {})
    self:write_input_payload(input.payload or "")
    -- Tell machine this is an inspect-state request
    self.machine:write_htif_fromhost_data(CARTESI_ROLLUP_INSPECT_STATE)
    -- Reset the Y flag so machine can proceed
    self.machine:reset_iflags_Y()
    -- Run the inspect request
    return self:run_collecting_events()
end

function rolling_machine:inspect_state(input, no_rollback)
    if no_rollback then
        return rolling_machine_inspect_state(self, input)
    else
        if self.remote_protocol == 'jsonrpc' then
            -- Create machine state checkpoint
            local checkpoint <close> = self:fork()
            -- Inspect state
            local res = rolling_machine_inspect_state(self, input)
            -- Rollback machine state
            self:swap(checkpoint)
            return res
        else -- grpc
            -- Create machine state checkpoint
            self.machine:snapshot()
            -- Inspect state
            local res = rolling_machine_inspect_state(self, input)
            -- Rollback machine state
            self.machine:rollback()
            return res
        end
    end
end

return rolling_machine
