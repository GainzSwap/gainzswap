import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { routerFixture } from "./shared/fixtures";
import { expect } from "chai";
import { Addressable, parseEther } from "ethers";
import { ethers } from "hardhat";

describe("Governance", function () {
  it("deploys governance", async () => {
    const { gToken } = await loadFixture(routerFixture);

    expect(await gToken.name()).to.eq("GainzSwap Governance Token");
  });

  describe("stake", function () {
    it("Should mint GToken with correct attributes", async function () {
      const {
        governance,
        gToken,
        users: [user],
        createPair,
      } = await loadFixture(routerFixture);

      const [{ token: tokenA }, { token: tokenB }] = await createPair();

      const epochsLocked = 1080;
      const stakeAmount = parseEther("0.05");

      const tokenBcontract = await ethers.getContractAt("TestERC20", tokenB as Addressable);
      await tokenBcontract.mintApprove(user, governance, stakeAmount);

      // Act for native coin staking

      await governance
        .connect(user)
        .stake(
          { token: tokenA, nonce: 0, amount: stakeAmount },
          epochsLocked,
          [[tokenA], [tokenA, tokenB], []],
          0,
          0,
          {
            value: stakeAmount,
          },
        );

      // Assert for native coin staking

      const { attributes: nativeStakingAttr } = await gToken.getBalanceAt(user, 1);

      expect(nativeStakingAttr.rewardPerShare).to.equal(0);
      expect(nativeStakingAttr.epochStaked).to.equal(0);
      expect(nativeStakingAttr.stakeWeight).to.gt(0);
      expect(nativeStakingAttr.epochsLocked).to.equal(epochsLocked);
      expect(nativeStakingAttr.lpDetails[0].liquidity).to.gt(0);
      expect(nativeStakingAttr.lpDetails[0].liqValue).to.gt(0);

      // Act for ERC20 staking

      await governance
        .connect(user)
        .stake(
          { token: tokenB, nonce: 0, amount: stakeAmount },
          epochsLocked,
          [[tokenB], [tokenB, tokenA], []],
          0,
          0,
        );

      // Assert for ERC20 staking

      const { attributes: erc20StakingAttr } = await gToken.getBalanceAt(user, 2);

      expect(erc20StakingAttr.rewardPerShare).to.equal(0);
      expect(erc20StakingAttr.epochStaked).to.equal(0);
      expect(erc20StakingAttr.stakeWeight).to.gt(0);
      expect(erc20StakingAttr.epochsLocked).to.equal(epochsLocked);
      expect(erc20StakingAttr.lpDetails[0].liquidity).to.gt(0);
      expect(erc20StakingAttr.lpDetails[0].liqValue).to.gt(0);
    });
  });
});
