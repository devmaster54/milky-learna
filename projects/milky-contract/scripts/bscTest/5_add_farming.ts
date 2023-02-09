import { ethers } from 'hardhat'
import { BigNumber } from 'ethers'
import * as dotenv from 'dotenv'

async function main() {
  const [_owner] = await ethers.getSigners()
  const masterChef = await ethers.getContractAt(
    'MasterChef',
    process.env.MASTERCHEF_CONTRACT_ADDRESS
      ? process.env.MASTERCHEF_CONTRACT_ADDRESS
      : ''
  )

  // You can get LP token's address after add liquidity
  // test pools for MILKY, MILKY/BNB
  const POOLS = [
    { lpToken: '0x9b4a023aBA77ABfE8a0E354414eD39fA7200Fe88', allocPoint: 2000 },
  ]

  const poolLength = (await masterChef.poolLength()).toNumber()

  console.log('POOL Length', poolLength)
  // Please run one by on by commentting and uncommentting each line
  for (let i = 0; i < POOLS.length; i++) {
    // console.log(POOLS[i])
    const tx = await masterChef.add(POOLS[i].allocPoint, POOLS[i].lpToken, true)
    // const tx = await masterChef.set(i, POOLS[i].allocPoint, false)
    await tx.wait()
    console.log(await masterChef.poolInfo(i))
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
