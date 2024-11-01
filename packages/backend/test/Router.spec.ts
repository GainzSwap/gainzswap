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
    it("works", async () => {
      const { createPair } = await loadFixture(routerFixture);

      await createPair();
    });

    it("native-token", async () => {
      const { createPair } = await loadFixture(routerFixture);

      await createPair({ paymentA: nativePayment });
    });

    it("native-token:reverse", async () => {
      const { createPair } = await loadFixture(routerFixture);

      await createPair({ paymentB: nativePayment });
    });

    it("check gas", async () => {
      const { router } = await loadFixture(routerFixture);

      const token = await ethers.deployContract("TestERC20", ["TokenB", "TKB", 18]);
      const tokenPayment: TokenPaymentStruct = { token: token, amount: parseEther("1000"), nonce: 0 };

      const tx = await router.createPair(nativePayment, tokenPayment, { value: nativePayment.amount });
      const receipt = await tx.wait();
      expect(receipt!.gasUsed).to.eq(1137218); // Compared to the original version, this is cheaper
    });
  });
});
