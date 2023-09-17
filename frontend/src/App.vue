<script setup>
import HelloWorld from './components/HelloWorld.vue'
import TheWelcome from './components/TheWelcome.vue'

import { createWeb3Modal, defaultWagmiConfig } from '@web3modal/wagmi/vue'
import { localhost } from '@wagmi/core/chains'

// 1. Get projectId
const projectId = import.meta.env.VITE_PROJECT_ID
if (!projectId) {
  throw new Error('VITE_PROJECT_ID is not set')
}

// 2. Create wagmiConfig
const chains = [localhost]
const tokens = {
  31337: {
    address: "0xae7f61eCf06C65405560166b259C54031428A9C4"
  }
}
const wagmiConfig = defaultWagmiConfig({ chains, projectId, appName: 'Web3Modal' })

// 3. Create modal
const modal = createWeb3Modal({ wagmiConfig, projectId, chains, tokens: tokens })

</script>

<template>
  <header>
    <!--
    <img alt="Vue logo" class="logo" src="./assets/logo.svg" width="125" height="125" />

    <div class="wrapper">
      <HelloWorld msg="You did it!" />
    </div>
    -->
    <w3m-button />
  </header>

  <main>
    <!-- <TheWelcome /> -->
  </main>
</template>

<style scoped>
</style>
