import { ethers } from "hardhat";
import { expect } from "chai";

import { getCreate2Address } from "./utilities";

import PairBuild from "../../artifacts/contracts/Pair.sol/Pair.json";

export type CreatePairTokens = [string, string];
export  const TEST_ADDRESSES: CreatePairTokens = [
  "0x1000000000000000000000000000000000000000",
  "0x2000000000000000000000000000000000000000",
];

export async function routerFixture() {
  const RouterFactory = await ethers.getContractFactory("Router");
  const router = await RouterFactory.deploy();

  async function createPair(tokens: CreatePairTokens) {
    const create2Address = getCreate2Address(await router.getAddress(), tokens, PairBuild.bytecode);
    await expect(router.createPair(...tokens))
      .to.emit(router, "PairCreated")
      .withArgs(TEST_ADDRESSES[0], TEST_ADDRESSES[1], create2Address, 1);

    const tokensReversed = tokens.slice().reverse() as CreatePairTokens;

    await expect(router.createPair(...tokens)).to.be.revertedWithCustomError(router, "PairExists");
    await expect(router.createPair(...tokensReversed)).to.be.revertedWithCustomError(router, "PairExists");
    expect(await router.getPair(...tokens)).to.eq(create2Address);
    expect(await router.getPair(...tokensReversed)).to.eq(create2Address);
    expect(await router.allPairs(0)).to.eq(create2Address);
    expect(await router.allPairsLength()).to.eq(1);

    const pair = await ethers.getContractAt("Pair", create2Address);
    expect(await pair.router()).to.eq(await router.getAddress());
    expect(await pair.token0()).to.eq(TEST_ADDRESSES[0])
    expect(await pair.token1()).to.eq(TEST_ADDRESSES[1])
  }

  return { router, createPair };
}
