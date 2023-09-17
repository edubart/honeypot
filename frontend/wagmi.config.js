import { defineConfig } from '@wagmi/cli'
import { erc20ABI } from 'wagmi'
import { ICartesiDApp__factory, IERC20Portal__factory, IInputBox__factory } from '@cartesi/rollups'

export default {
  out: 'src/generated.js',
  contracts: [
    {
      name: 'erc20',
      abi: erc20ABI,
    },
    {
      name: 'cartesiDapp',
      abi: ICartesiDApp__factory.abi,
    },
    {
      name: 'cartesiInputBox',
      abi: IInputBox__factory.abi,
    },
    {
      name: 'cartesiErc20Portal',
      abi: IERC20Portal__factory.abi,
    },
  ],
  plugins: []
}
