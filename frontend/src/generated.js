import {
  getContract,
  readContract,
  writeContract,
  prepareWriteContract,
  watchContractEvent,
} from 'wagmi/actions'

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ERC20
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const erc20ABI = [
  {
    type: 'event',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'spender', type: 'address', indexed: true },
      { name: 'value', type: 'uint256', indexed: false },
    ],
    name: 'Approval',
  },
  {
    type: 'event',
    inputs: [
      { name: 'from', type: 'address', indexed: true },
      { name: 'to', type: 'address', indexed: true },
      { name: 'value', type: 'uint256', indexed: false },
    ],
    name: 'Transfer',
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ type: 'uint256' }],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ type: 'bool' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'decimals',
    outputs: [{ type: 'uint8' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'name',
    outputs: [{ type: 'string' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'symbol',
    outputs: [{ type: 'string' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ type: 'uint256' }],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: 'recipient', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ type: 'bool' }],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: 'sender', type: 'address' },
      { name: 'recipient', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'transferFrom',
    outputs: [{ type: 'bool' }],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'addedValue', type: 'uint256' },
    ],
    name: 'increaseAllowance',
    outputs: [{ type: 'bool' }],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'subtractedValue', type: 'uint256' },
    ],
    name: 'decreaseAllowance',
    outputs: [{ type: 'bool' }],
  },
]

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ERC721
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const erc721ABI = [
  {
    type: 'event',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'spender', type: 'address', indexed: true },
      { name: 'tokenId', type: 'uint256', indexed: true },
    ],
    name: 'Approval',
  },
  {
    type: 'event',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'operator', type: 'address', indexed: true },
      { name: 'approved', type: 'bool', indexed: false },
    ],
    name: 'ApprovalForAll',
  },
  {
    type: 'event',
    inputs: [
      { name: 'from', type: 'address', indexed: true },
      { name: 'to', type: 'address', indexed: true },
      { name: 'tokenId', type: 'uint256', indexed: true },
    ],
    name: 'Transfer',
  },
  {
    stateMutability: 'payable',
    type: 'function',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'tokenId', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    name: 'getApproved',
    outputs: [{ type: 'address' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'operator', type: 'address' },
    ],
    name: 'isApprovedForAll',
    outputs: [{ type: 'bool' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'name',
    outputs: [{ type: 'string' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    name: 'ownerOf',
    outputs: [{ name: 'owner', type: 'address' }],
  },
  {
    stateMutability: 'payable',
    type: 'function',
    inputs: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'tokenId', type: 'uint256' },
    ],
    name: 'safeTransferFrom',
    outputs: [],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'id', type: 'uint256' },
      { name: 'data', type: 'bytes' },
    ],
    name: 'safeTransferFrom',
    outputs: [],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: 'operator', type: 'address' },
      { name: 'approved', type: 'bool' },
    ],
    name: 'setApprovalForAll',
    outputs: [],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'symbol',
    outputs: [{ type: 'string' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [{ name: 'index', type: 'uint256' }],
    name: 'tokenByIndex',
    outputs: [{ type: 'uint256' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'index', type: 'uint256' },
    ],
    name: 'tokenByIndex',
    outputs: [{ name: 'tokenId', type: 'uint256' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    name: 'tokenURI',
    outputs: [{ type: 'string' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ type: 'uint256' }],
  },
  {
    stateMutability: 'payable',
    type: 'function',
    inputs: [
      { name: 'sender', type: 'address' },
      { name: 'recipient', type: 'address' },
      { name: 'tokenId', type: 'uint256' },
    ],
    name: 'transferFrom',
    outputs: [],
  },
]

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// cartesiDapp
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const cartesiDappABI = [
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'newConsensus',
        internalType: 'contract IConsensus',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'NewConsensus',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'voucherId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'VoucherExecuted',
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: '_destination', internalType: 'address', type: 'address' },
      { name: '_payload', internalType: 'bytes', type: 'bytes' },
      {
        name: '_proof',
        internalType: 'struct Proof',
        type: 'tuple',
        components: [
          {
            name: 'validity',
            internalType: 'struct OutputValidityProof',
            type: 'tuple',
            components: [
              {
                name: 'inputIndexWithinEpoch',
                internalType: 'uint64',
                type: 'uint64',
              },
              {
                name: 'outputIndexWithinInput',
                internalType: 'uint64',
                type: 'uint64',
              },
              {
                name: 'outputHashesRootHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'vouchersEpochRootHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'noticesEpochRootHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'machineStateHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'outputHashInOutputHashesSiblings',
                internalType: 'bytes32[]',
                type: 'bytes32[]',
              },
              {
                name: 'outputHashesInEpochSiblings',
                internalType: 'bytes32[]',
                type: 'bytes32[]',
              },
            ],
          },
          { name: 'context', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'executeVoucher',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'getConsensus',
    outputs: [
      { name: '', internalType: 'contract IConsensus', type: 'address' },
    ],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'getTemplateHash',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      {
        name: '_newConsensus',
        internalType: 'contract IConsensus',
        type: 'address',
      },
    ],
    name: 'migrateToConsensus',
    outputs: [],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [
      { name: '_notice', internalType: 'bytes', type: 'bytes' },
      {
        name: '_proof',
        internalType: 'struct Proof',
        type: 'tuple',
        components: [
          {
            name: 'validity',
            internalType: 'struct OutputValidityProof',
            type: 'tuple',
            components: [
              {
                name: 'inputIndexWithinEpoch',
                internalType: 'uint64',
                type: 'uint64',
              },
              {
                name: 'outputIndexWithinInput',
                internalType: 'uint64',
                type: 'uint64',
              },
              {
                name: 'outputHashesRootHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'vouchersEpochRootHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'noticesEpochRootHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'machineStateHash',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'outputHashInOutputHashesSiblings',
                internalType: 'bytes32[]',
                type: 'bytes32[]',
              },
              {
                name: 'outputHashesInEpochSiblings',
                internalType: 'bytes32[]',
                type: 'bytes32[]',
              },
            ],
          },
          { name: 'context', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'validateNotice',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [
      { name: '_inputIndex', internalType: 'uint256', type: 'uint256' },
      {
        name: '_outputIndexWithinInput',
        internalType: 'uint256',
        type: 'uint256',
      },
    ],
    name: 'wasVoucherExecuted',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
  },
]

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// cartesiErc20Portal
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const cartesiErc20PortalABI = [
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: '_token', internalType: 'contract IERC20', type: 'address' },
      { name: '_dapp', internalType: 'address', type: 'address' },
      { name: '_amount', internalType: 'uint256', type: 'uint256' },
      { name: '_execLayerData', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'depositERC20Tokens',
    outputs: [],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [],
    name: 'getInputBox',
    outputs: [
      { name: '', internalType: 'contract IInputBox', type: 'address' },
    ],
  },
]

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// cartesiInputBox
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const cartesiInputBoxABI = [
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'dapp', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'inputIndex',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'sender',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      { name: 'input', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'InputAdded',
  },
  {
    stateMutability: 'nonpayable',
    type: 'function',
    inputs: [
      { name: '_dapp', internalType: 'address', type: 'address' },
      { name: '_input', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'addInput',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [
      { name: '_dapp', internalType: 'address', type: 'address' },
      { name: '_index', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getInputHash',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
  },
  {
    stateMutability: 'view',
    type: 'function',
    inputs: [{ name: '_dapp', internalType: 'address', type: 'address' }],
    name: 'getNumberOfInputs',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
  },
]

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Core
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Wraps __{@link getContract}__ with `abi` set to __{@link erc20ABI}__.
 */
export function getErc20(config) {
  return getContract({ abi: erc20ABI, ...config })
}

/**
 * Wraps __{@link readContract}__ with `abi` set to __{@link erc20ABI}__.
 */
export function readErc20(config) {
  return readContract({ abi: erc20ABI, ...config })
}

/**
 * Wraps __{@link writeContract}__ with `abi` set to __{@link erc20ABI}__.
 */
export function writeErc20(config) {
  return writeContract({ abi: erc20ABI, ...config })
}

/**
 * Wraps __{@link prepareWriteContract}__ with `abi` set to __{@link erc20ABI}__.
 */
export function prepareWriteErc20(config) {
  return prepareWriteContract({ abi: erc20ABI, ...config })
}

/**
 * Wraps __{@link watchContractEvent}__ with `abi` set to __{@link erc20ABI}__.
 */
export function watchErc20Event(config, callback) {
  return watchContractEvent({ abi: erc20ABI, ...config }, callback)
}

/**
 * Wraps __{@link getContract}__ with `abi` set to __{@link erc721ABI}__.
 */
export function getErc721(config) {
  return getContract({ abi: erc721ABI, ...config })
}

/**
 * Wraps __{@link readContract}__ with `abi` set to __{@link erc721ABI}__.
 */
export function readErc721(config) {
  return readContract({ abi: erc721ABI, ...config })
}

/**
 * Wraps __{@link writeContract}__ with `abi` set to __{@link erc721ABI}__.
 */
export function writeErc721(config) {
  return writeContract({ abi: erc721ABI, ...config })
}

/**
 * Wraps __{@link prepareWriteContract}__ with `abi` set to __{@link erc721ABI}__.
 */
export function prepareWriteErc721(config) {
  return prepareWriteContract({ abi: erc721ABI, ...config })
}

/**
 * Wraps __{@link watchContractEvent}__ with `abi` set to __{@link erc721ABI}__.
 */
export function watchErc721Event(config, callback) {
  return watchContractEvent({ abi: erc721ABI, ...config }, callback)
}

/**
 * Wraps __{@link getContract}__ with `abi` set to __{@link cartesiDappABI}__.
 */
export function getCartesiDapp(config) {
  return getContract({ abi: cartesiDappABI, ...config })
}

/**
 * Wraps __{@link readContract}__ with `abi` set to __{@link cartesiDappABI}__.
 */
export function readCartesiDapp(config) {
  return readContract({ abi: cartesiDappABI, ...config })
}

/**
 * Wraps __{@link writeContract}__ with `abi` set to __{@link cartesiDappABI}__.
 */
export function writeCartesiDapp(config) {
  return writeContract({ abi: cartesiDappABI, ...config })
}

/**
 * Wraps __{@link prepareWriteContract}__ with `abi` set to __{@link cartesiDappABI}__.
 */
export function prepareWriteCartesiDapp(config) {
  return prepareWriteContract({ abi: cartesiDappABI, ...config })
}

/**
 * Wraps __{@link watchContractEvent}__ with `abi` set to __{@link cartesiDappABI}__.
 */
export function watchCartesiDappEvent(config, callback) {
  return watchContractEvent({ abi: cartesiDappABI, ...config }, callback)
}

/**
 * Wraps __{@link getContract}__ with `abi` set to __{@link cartesiErc20PortalABI}__.
 */
export function getCartesiErc20Portal(config) {
  return getContract({ abi: cartesiErc20PortalABI, ...config })
}

/**
 * Wraps __{@link readContract}__ with `abi` set to __{@link cartesiErc20PortalABI}__.
 */
export function readCartesiErc20Portal(config) {
  return readContract({ abi: cartesiErc20PortalABI, ...config })
}

/**
 * Wraps __{@link writeContract}__ with `abi` set to __{@link cartesiErc20PortalABI}__.
 */
export function writeCartesiErc20Portal(config) {
  return writeContract({ abi: cartesiErc20PortalABI, ...config })
}

/**
 * Wraps __{@link prepareWriteContract}__ with `abi` set to __{@link cartesiErc20PortalABI}__.
 */
export function prepareWriteCartesiErc20Portal(config) {
  return prepareWriteContract({ abi: cartesiErc20PortalABI, ...config })
}

/**
 * Wraps __{@link getContract}__ with `abi` set to __{@link cartesiInputBoxABI}__.
 */
export function getCartesiInputBox(config) {
  return getContract({ abi: cartesiInputBoxABI, ...config })
}

/**
 * Wraps __{@link readContract}__ with `abi` set to __{@link cartesiInputBoxABI}__.
 */
export function readCartesiInputBox(config) {
  return readContract({ abi: cartesiInputBoxABI, ...config })
}

/**
 * Wraps __{@link writeContract}__ with `abi` set to __{@link cartesiInputBoxABI}__.
 */
export function writeCartesiInputBox(config) {
  return writeContract({ abi: cartesiInputBoxABI, ...config })
}

/**
 * Wraps __{@link prepareWriteContract}__ with `abi` set to __{@link cartesiInputBoxABI}__.
 */
export function prepareWriteCartesiInputBox(config) {
  return prepareWriteContract({ abi: cartesiInputBoxABI, ...config })
}

/**
 * Wraps __{@link watchContractEvent}__ with `abi` set to __{@link cartesiInputBoxABI}__.
 */
export function watchCartesiInputBoxEvent(config, callback) {
  return watchContractEvent({ abi: cartesiInputBoxABI, ...config }, callback)
}
