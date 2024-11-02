import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { routerFixture } from "./shared/fixtures";
import { expect } from "chai";
import { parseEther, ZeroAddress } from "ethers";
import { TokenPaymentStruct } from "../typechain-types/contracts/Router";
import { ethers } from "hardhat";

describe("Router", function () {
  it("allPairsLength", async () => {
    const { router } = await loadFixture(routerFixture);

    expect(await router.allPairsLength()).to.eq(0);
  });

  describe("createPair", function () {
    const nativePayment: TokenPaymentStruct = { token: ZeroAddress, amount: parseEther("0.001"), nonce: 0 };

    it("works:native-ERC20", async () => {
      const { createPair } = await loadFixture(routerFixture);

      await createPair({ paymentA: nativePayment });
    });

    it("works:ERC20-native", async () => {
      const { createPair } = await loadFixture(routerFixture);

      await createPair({ paymentB: nativePayment });
    });

    it("works:ERC20-ERC20", async () => {
      const { createPair, createToken } = await loadFixture(routerFixture);

      const tokenA = await createToken(15);
      const tokenB = await createToken(8);

      await createPair({
        paymentA: { token: tokenA, nonce: 0, amount: parseEther("1000") },
        paymentB: { token: tokenB, nonce: 0, amount: parseEther("0.1") },
      });
    });

    it("check gas", async () => {
      const { router, wrappedNativeToken, owner } = await loadFixture(routerFixture);

      const makePayment = async () => {
        const token = await ethers.deployContract("TestERC20", ["TokenB", "TKB", 18]);
        const tokenPayment: TokenPaymentStruct = { token: token, amount: parseEther("1000"), nonce: 0 };
        await token.mint(owner, tokenPayment.amount);
        await token.approve(router, tokenPayment.amount);

        return tokenPayment;
      };

      const tx = await router.createPair({ ...nativePayment, token: wrappedNativeToken }, await makePayment(), {
        value: nativePayment.amount,
      });
      const receipt = await tx.wait();
      expect(receipt!.gasUsed).to.eq(636373);

      // Subsequently
      const tx2 = await router.createPair({ ...nativePayment, token: wrappedNativeToken }, await makePayment(), {
        value: nativePayment.amount,
      });
      const receipt2 = await tx2.wait();
      expect(receipt2!.gasUsed).to.eq(602203);
    });
  });
});
