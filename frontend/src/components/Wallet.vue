<script setup>
import { prepareWriteContract, writeContract } from '@wagmi/core'
import { IInputBox__factory } from "@cartesi/rollups"

async function deposit() {
  const depositPrep = prepareWriteContract({
      address: process.env.VITE_INPUT_BOX_ADDR,
      abi: IInputBox__factory.abi,
      functionName: "depositERC20Tokens",
      args: ["0x"],
      overrides: {
          value: 10,
      },
  });
  const { depositHash } = await writeContract(depositPrep)
  console.log(depositHash);
}
</script>

<template>
  <h1 class="display-5 fw-bold text-body-emphasis">Wallet</h1>
  <table class="table">
    <thead>
      <tr>
        <th scope="col">#</th>
        <th scope="col">Token</th>
        <th scope="col">Amount</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <th scope="row">1</th>
        <td>Mark</td>
        <td>Otto</td>
      </tr>
      <tr>
        <th scope="row">2</th>
        <td>Jacob</td>
        <td>Thornton</td>
      </tr>
    </tbody>
  </table>
  <button type="button" class="btn btn-primary" @click="deposit" >Deposit</button>
</template>
