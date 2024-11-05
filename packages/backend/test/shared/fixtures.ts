import { ethers } from "hardhat";
import { expect } from "chai";

import { TokenPaymentStruct } from "../../typechain-types/contracts/Router";

import { BaseContract, BigNumberish, getBigInt, parseEther, ZeroAddress } from "ethers";
import { getPairProxyAddress } from "./utilities";
import { getRouterLibraries } from "../../utilities";

export async function routerFixture() {
  const [owner, ...users] = await ethers.getSigners();

  const RouterFactory = await ethers.getContractFactory("RouterV2", {
    libraries: await getRouterLibraries(ethers),
  });
  const router = await RouterFactory.deploy();
  await router.initialize(owner);

  const wrappedNativeToken = await router.getWrappedNativeToken();
  const routerAddress = await router.getAddress();
  const pairsBeacon = await router.getPairsBeacon();

  const governanceAddress = await router.getGovernance();
  const governance = await ethers.getContractAt("GovernanceV2", governanceAddress);
  const gTokenAddress = await governance.getGToken();
  const gToken = await ethers.getContractAt("GTokenV2", gTokenAddress);

  let tokensCreated = 0;
  const createToken = async (decimals: BigNumberish) => {
    tokensCreated++;

    return await ethers.deployContract("TestERC20", ["Token" + tokensCreated, "TK-" + tokensCreated, decimals]);
  };

  async function createPair(args: { paymentA?: TokenPaymentStruct; paymentB?: TokenPaymentStruct } = {}) {
    if (!args.paymentA && !args.paymentB) {
      args.paymentA = { token: wrappedNativeToken, nonce: 0, amount: parseEther("1000") };
      args.paymentB = { token: await createToken(8), nonce: 0, amount: parseEther("10") };
    }

    if (!args.paymentA) {
      args.paymentA = {
        token: args.paymentB?.token == ZeroAddress ? await createToken(12) : wrappedNativeToken,
        nonce: 0,
        amount: parseEther("10"),
      };
    }

    if (!args.paymentB) {
      args.paymentB = {
        token: args.paymentA.token == ZeroAddress ? await createToken(8) : wrappedNativeToken,
        nonce: 0,
        amount: parseEther("10"),
      };
    }

    const payments = [args.paymentA, args.paymentB].map(payment => ({
      ...payment,
      token: payment.token == ZeroAddress ? wrappedNativeToken : payment.token,
    })) as [TokenPaymentStruct, TokenPaymentStruct];

    const value = payments.reduce(
      (value, payment) => (payment.token == wrappedNativeToken ? getBigInt(payment.amount) : value),
      0n,
    );

    let tokens: [string, string] = ["", ""];
    for (let { token, index, amount } of payments.map(({ token, amount }, index) => ({ token, index, amount }))) {
      if (token instanceof BaseContract) {
        token = await token.getAddress();
      }

      const tokenAddr = (tokens[index] = token.toString());

      // Allowance
      if (tokenAddr != wrappedNativeToken) {
        const testToken = await ethers.getContractAt("TestERC20", tokenAddr);
        await testToken.mint(owner, amount);
        await testToken.approve(routerAddress, amount);
      }
    }
    const [tokenA, tokenB] = tokens.sort((a, b) => parseInt(a, 16) - parseInt(b, 16));

    const pairProxy = await getPairProxyAddress(routerAddress, pairsBeacon, [tokenA, tokenB]);

    await expect(router.createPair(...payments, { value }))
      .to.emit(router, "PairCreated")
      .withArgs(tokenA, tokenB, pairProxy, 1);

    const paymentsReversed = payments.slice().reverse() as typeof payments;
    const tokensReversed = tokens.slice().reverse() as typeof tokens;

    await expect(router.createPair(...payments, { value })).to.be.revertedWithCustomError(router, "PairExists");
    await expect(router.createPair(...paymentsReversed, { value })).to.be.revertedWithCustomError(router, "PairExists");
    expect(await router.getPair(...tokens)).to.eq(pairProxy);
    expect(await router.getPair(...tokensReversed)).to.eq(pairProxy);
    expect(await router.allPairs(0)).to.eq(pairProxy);
    expect(await router.allPairsLength()).to.eq(1);

    const pair = await ethers.getContractAt("PairV2", pairProxy);
    expect(await pair.router()).to.eq(routerAddress);
    expect(await pair.token0()).to.eq(tokenA);
    expect(await pair.token1()).to.eq(tokenB);
    expect(await pair.balanceOf(owner)).to.be.gt(0);

    return payments;
  }

  return {
    router,
    governance,
    gToken,
    createPair,
    createToken,
    owner,
    users,
    governanceAddress,
    routerAddress,
    wrappedNativeToken,
  };
}
