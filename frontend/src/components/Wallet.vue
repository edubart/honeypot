<script setup lang="ts">
import { ref } from 'vue'
import {
  getAccount,
  waitForTransaction,
} from '@wagmi/core'
import {
  writeErc20,
  readErc20,
  writeCartesiErc20Portal,
  writeCartesiInputBox,
  watchCartesiInputBoxEvent,
} from '../generated'

import { useQuery } from '@urql/vue'
import { computed } from 'vue'
import { graphql } from '../gql'

import { Client, provideClient, cacheExchange, fetchExchange } from '@urql/vue'

const client = new Client({
  url: import.meta.env.VITE_GRAPHQL_URL,
  exchanges: [cacheExchange, fetchExchange],
})

provideClient(client)

const account = getAccount()
const tokens = ref({})
const env = import.meta.env

function tohex(s) {
  return "0x"+Buffer.from(s, 'binary').toString("hex")
}

function fromhex(s) {
  return Buffer.from(s.substr(2), 'hex').toString("binary")
}

async function refresh() {
  const req = await fetch(env.VITE_INSPECT_URL + "/BLC/" + account.address)
  const res = await req.json()
  let tokens_json = JSON.parse(fromhex(res.reports[0].payload))
  let tokens_obj = Object.fromEntries(Object.entries(tokens_json).map(([k, v]) => [k, BigInt(v)]))
  Object.assign(tokens.value, tokens_obj)
}

async function deposit(amount) {
  // retrieve allowance
  const allowance = await readErc20({
      address: env.VITE_DAPP_TOKEN_ADDR,
      functionName: "allowance",
      args: [account.address, env.VITE_ERC20_PORTAL_ADDR],
  })
  console.log('allowance', allowance)

  // increase allowance
  if (amount > allowance) {
    const txIncreaseAllowanceHash = await writeErc20({
        address: env.VITE_DAPP_TOKEN_ADDR,
        functionName: "increaseAllowance",
        args: [env.VITE_ERC20_PORTAL_ADDR, amount],
    })
    console.log('txIncreaseAllowanceHash', txIncreaseAllowanceHash)
    const txIncreaseAllowanceData = await waitForTransaction(txIncreaseAllowanceHash)
    console.log('txIncreaseAllowanceData', txIncreaseAllowanceData)
  }

  // deposit
  const txDepositHash = await writeCartesiErc20Portal({
      address: env.VITE_ERC20_PORTAL_ADDR,
      functionName: "depositERC20Tokens",
      args: [env.VITE_DAPP_TOKEN_ADDR, env.VITE_DAPP_ADDR, 10000, "0x"],
  })
  console.log('txDepositHash', txDepositHash)

  // get input index
  const txInputIndex = await new Promise(function(resolve, reject) {
    watchCartesiInputBoxEvent({
      address: env.VITE_INPUT_BOX_ADDR,
      eventName: 'InputAdded',
    }, function(log) {
      if (log[0].transactionHash == txDepositHash.hash) {
        resolve(log[0].args.inputIndex)
      }
    })
  })
  console.log('txInputIndex', txInputIndex)

  // wait transaction to complete
  const txDepositData = await waitForTransaction(txDepositHash)
  console.log('txDepositData', txDepositData)

  // give a time for the node to process it
  await new Promise(r => setTimeout(r, 10000))
  console.log('waited')

  // query its reports
  const txReport = await client.query(graphql`
query reportsByInput($inputIndex: Int!) {
  input(index: $inputIndex) {
    report(index: 0) {
      payload
    }
  }
}`, {inputIndex: parseInt(txInputIndex)}).toPromise()
  console.log('txReport', txReport)

  // refresh wallet
  refresh()
  console.log('refreshed')
}

async function withdraw_all() {
  const payload = tohex("WTDW" + fromhex(env.VITE_DAPP_TOKEN_ADDR))
  // add input
  const txAddInputHash = await writeCartesiInputBox({
      address: env.VITE_INPUT_BOX_ADDR,
      functionName: "addInput",
      args: [env.VITE_DAPP_ADDR, payload],
  })
  console.log('txAddInputHash', txAddInputHash)
  const txAddInputData = await waitForTransaction(txAddInputHash)
  console.log('txAddInputData', txAddInputData)
}

refresh()
</script>

<template>
  <h1 class="display-5 fw-bold text-body-emphasis">Wallet</h1>
  <table class="table">
    <thead>
      <tr>
        <th scope="col">Token</th>
        <th scope="col">Amount</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="(token,amount) in tokens" :key="token">
        <td>{{token}}</td>
        <td>{{amount}}</td>
      </tr>
    </tbody>
  </table>
  <div class="btn-group" role="group">
    <button type="button" class="btn btn-primary" @click="deposit(BigInt(10000))" >Deposit</button>
    <button type="button" class="btn btn-warning" @click="withdraw_all()" >Withdraw All</button>
  </div>
</template>
