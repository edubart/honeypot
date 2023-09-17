import { defineConfig } from '@wagmi/cli'
import { erc, actions } from '@wagmi/cli/plugins'
import { ICartesiDApp__factory, IERC20Portal__factory, IInputBox__factory } from '@cartesi/rollups'

export default defineConfig({
  out: 'src/generated.js',
  contracts: [
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
  plugins: [erc(), actions()]
})
