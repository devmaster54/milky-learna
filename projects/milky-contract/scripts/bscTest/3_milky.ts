import { ethers } from 'hardhat'
import { BigNumber } from 'ethers'
import * as dotenv from 'dotenv'

const BN = BigNumber.from

async function main() {
  const [_owner] = await ethers.getSigners()
  const MilkyToken = await ethers.getContractFactory('Milky')
  const milkyToken = await MilkyToken.deploy()
  await milkyToken.deployed()

  await milkyToken.mintTo(
    _owner.address,
    BN(
      process.env.MILKY_INITIAL_SUPPLY
        ? process.env.MILKY_INITIAL_SUPPLY
        : 250000000
    ).mul(BN(10).pow(BN(18)))
  )
  console.log('MilkyToken is deployed to:', milkyToken.address) // 0x37078997d9babfB9C16f35cE5736B5929c959032
  // please run the output of the below log for verification of this contract
  console.log(`npx hardhat verify --network bscTest ${milkyToken.address}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
