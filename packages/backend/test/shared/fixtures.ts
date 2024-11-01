import { ethers } from "hardhat";
import { expect } from "chai";

import PairBuild from "../../artifacts/contracts/Pair.sol/Pair.json";
import { TokenPaymentStruct } from "../../typechain-types/contracts/Router";

import {
  AddressLike,
  BaseContract,
  BigNumberish,
  getBigInt,
  parseEther,
  solidityPackedKeccak256,
  ZeroAddress,
} from "ethers";
import { getCreate2Address } from "./utilities";

export async function routerFixture() {
  const [owner, ...users] = await ethers.getSigners();

  const RouterFactory = await ethers.getContractFactory("Router");
  const router = await RouterFactory.deploy();
  await router.initialize(owner);

  const wrappedNativeToken = await router.getWrappedNativeToken();

  let tokensCreated = 0;
  const createToken = async (decimals: BigNumberish) => {
    tokensCreated++;

    return await ethers.deployContract("TestERC20", ["Token" + tokensCreated, "TK-" + tokensCreated, decimals]);
  };

  async function createPair(args: { paymentA?: TokenPaymentStruct; paymentB?: TokenPaymentStruct } = {}) {
    if (!args.paymentA && !args.paymentB) {
      args.paymentA = { token: ZeroAddress, nonce: 0, amount: parseEther("1000") };
      args.paymentB = { token: await createToken(8), nonce: 0, amount: parseEther("10") };
    }

    if (!args.paymentA) {
      args.paymentA = {
        token: args.paymentB?.token == ZeroAddress ? await createToken(8) : ZeroAddress,
        nonce: 0,
        amount: parseEther("10"),
      };
    }

    if (!args.paymentB) {
      args.paymentB = {
        token: args.paymentA.token == ZeroAddress ? await createToken(8) : ZeroAddress,
        nonce: 0,
        amount: parseEther("10"),
      };
    }

    const payments: [TokenPaymentStruct, TokenPaymentStruct] = [args.paymentA, args.paymentB];
    const value = payments.reduce(
      (value, payment) => (payment.token == ZeroAddress ? getBigInt(payment.amount) : value),
      0n,
    );

    let tokens: [string, string] = ["", ""];
    for (let { token, index } of payments.map(({ token }, index) => {
      // Consider native tokens
      if (token == ZeroAddress) {
        token = wrappedNativeToken;
      }

      return { token, index };
    })) {
      if (token instanceof BaseContract) {
        token = await token.getAddress();
      }

      tokens[index] = token.toString();
    }
    const [tokenA, tokenB] = tokens.sort((a, b) => parseInt(a, 16) - parseInt(b, 16));

    const create2Address = getCreate2Address(await router.getAddress(), [tokenA, tokenB], PairBuild.bytecode);

    await expect(router.createPair(...payments, { value }))
      .to.emit(router, "PairCreated")
      .withArgs(tokenA, tokenB, create2Address, 1);

    const paymentsReversed = payments.slice().reverse() as typeof payments;
    const tokensReversed = tokens.slice().reverse() as typeof tokens;

    await expect(router.createPair(...payments, { value })).to.be.revertedWithCustomError(router, "PairExists");
    await expect(router.createPair(...paymentsReversed, { value })).to.be.revertedWithCustomError(router, "PairExists");
    expect(await router.getPair(...tokens)).to.eq(create2Address);
    expect(await router.getPair(...tokensReversed)).to.eq(create2Address);
    expect(await router.allPairs(0)).to.eq(create2Address);
    expect(await router.allPairsLength()).to.eq(1);

    const pair = await ethers.getContractAt("Pair", create2Address);
    expect(await pair.router()).to.eq(await router.getAddress());
    expect(await pair.token0()).to.eq(tokenA);
    expect(await pair.token1()).to.eq(tokenB);
  }

  return { router, createPair, createToken };
}
