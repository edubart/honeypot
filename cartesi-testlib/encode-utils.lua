local encode_utils = {}

-- Encode a value into a n-bit big-endian value.
function encode_utils.encode_be(bits, v, trim)
    assert(bits % 8 == 0, "bits must be a multiple of 8")
    local bytes = bits // 8
    local res
    if type(v) == "string" and v:find("^0[xX][0-9a-fA-F]+$") then
        res = v:sub(3):gsub("%x%x", function(bytehex) return string.char(tonumber(bytehex, 16)) end)
    elseif math.type(v) == "integer" then
        res = string.pack(">I8", v):gsub("^\x00+", "")
    else
        error("cannot encode value '" .. tostring(v) .. "' to " .. bits .. " bit big endian")
    end
    if #res < bytes then -- add padding
        res = string.rep("\x00", bytes - #res) .. res
    elseif #res > bytes then
        error("value is too large to be encoded into " .. bits .. " bit big endian")
    end
    if trim then
        res = res:gsub("^\x00+", "")
        if res == "" then res = "\x00" end
    end
    return res
end

function encode_utils.encode_be8(v) return encode_utils.encode_be(8, v) end

function encode_utils.encode_erc20_address(v, trim) return encode_utils.encode_be(160, v, trim) end

function encode_utils.encode_be256(v, trim) return encode_utils.encode_be(256, v, trim) end

function encode_utils.encode_erc20_deposit(deposit)
    return table.concat({
        encode_utils.encode_be8(deposit.successful and 1 or 0),
        encode_utils.encode_erc20_address(deposit.contract_address),
        encode_utils.encode_erc20_address(deposit.sender_address),
        encode_utils.encode_be256(deposit.amount),
        deposit.extra_data,
    })
end

function encode_utils.encode_erc20_transfer_voucher(voucher)
    return table.concat({
        "\169\5\156\187", -- First 4 bytes of "transfer(address,uint256)".
        string.rep('\x00', 12),
        encode_utils.encode_erc20_address(voucher.destination_address),
        encode_utils.encode_be256(voucher.amount),
    })
end

return encode_utils
