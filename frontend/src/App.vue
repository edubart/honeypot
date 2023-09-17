<script setup>
import HelloWorld from './components/HelloWorld.vue'
import TheWelcome from './components/TheWelcome.vue'
import Header from './components/Header.vue'
import Wallet from './components/Wallet.vue'

import { createWeb3Modal, defaultWagmiConfig } from '@web3modal/wagmi/vue'
import { localhost } from '@wagmi/core/chains'

// 1. Get projectId
const projectId = import.meta.env.VITE_PROJECT_ID

// 2. Create wagmiConfig
const chains = [localhost]
const tokens = {
  31337: {
    address: import.meta.env.VITE_DAPP_TOKEN
  }
}
const wagmiConfig = defaultWagmiConfig({ chains, projectId, appName: 'Web3Modal' })

// 3. Create modal
const modal = createWeb3Modal({ wagmiConfig, projectId, chains, tokens: tokens })

</script>

<template>
  <Header />

  <main>
    <div class="container">
      <Wallet />
    </div>
  </main>
</template>
