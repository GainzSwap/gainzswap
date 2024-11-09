import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { routerFixture } from "./shared/fixtures";
import { expect } from "chai";
import { Addressable, AddressLike, parseEther, ZeroAddress } from "ethers";
import { ethers } from "hardhat";
import { hours } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time/duration";
import { GovernanceV2, GTokenV2, RouterV2, TestERC20 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

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
        .stake({ token: tokenA, nonce: 0, amount: stakeAmount }, epochsLocked, [[tokenA], [tokenA, tokenB], []], 0, 0, {
          value: stakeAmount,
        });

      // Assert for native coin staking

      const { attributes: nativeStakingAttr } = await gToken.getBalanceAt(user, 1);

      expect(nativeStakingAttr.rewardPerShare).to.equal(0);
      expect(nativeStakingAttr.epochStaked).to.equal(0);
      expect(nativeStakingAttr.stakeWeight).to.gt(0);
      expect(nativeStakingAttr.epochsLocked).to.equal(epochsLocked);
      expect(nativeStakingAttr.lpDetails.liquidity).to.gt(0);
      expect(nativeStakingAttr.lpDetails.liqValue).to.gt(0);

      // Act for ERC20 staking

      await governance
        .connect(user)
        .stake({ token: tokenB, nonce: 0, amount: stakeAmount }, epochsLocked, [[tokenB], [tokenB, tokenA], []], 0, 0);

      // Assert for ERC20 staking

      const { attributes: erc20StakingAttr } = await gToken.getBalanceAt(user, 2);

      expect(erc20StakingAttr.rewardPerShare).to.equal(0);
      expect(erc20StakingAttr.epochStaked).to.equal(0);
      expect(erc20StakingAttr.stakeWeight).to.gt(0);
      expect(erc20StakingAttr.epochsLocked).to.equal(epochsLocked);
      expect(erc20StakingAttr.lpDetails.liquidity).to.gt(0);
      expect(erc20StakingAttr.lpDetails.liqValue).to.gt(0);
    });

    it("Should calculate liquidity value for tokenA with a 5-hop path to the native token", async () => {
      // Deploy tokens and initialize contracts
      const {
        governance,
        gToken,
        users: [user],
        wrappedNativeToken,
        createToken,
        createPair,
      } = await loadFixture(routerFixture);

      // Deploy tokenA, tokenB, and intermediary tokens
      const tokenA = await createToken(5);
      const tokenB = await createToken(9);
      const intermediate1 = await createToken(2);
      const intermediate2 = await createToken(3);
      const intermediate3 = await createToken(4);
      const intermediate4 = await createToken(5);

      // Create path to native token with 5 hops
      const pathToNative = [tokenA, intermediate1, intermediate2, intermediate3, intermediate4, wrappedNativeToken];

      // Create pairs to link to the path
      let pairsCreated = 0;
      for (const [[token1, amount1], [token2, amount2]] of [
        [
          [tokenA, parseEther("0.05")],
          [tokenB, parseEther("10")],
        ],
        [
          [tokenA, parseEther("0.05")],
          [intermediate1, parseEther("20")],
        ],
        [
          [intermediate1, parseEther("20")],
          [intermediate2, parseEther("30")],
        ],
        [
          [intermediate2, parseEther("30")],
          [intermediate3, parseEther("40")],
        ],
        [
          [intermediate3, parseEther("40")],
          [intermediate4, parseEther("50")],
        ],
        [
          [intermediate4, parseEther("50")],
          [ZeroAddress, parseEther("0.0009")],
        ],
      ] as [[AddressLike, bigint], [AddressLike, bigint]][]) {
        await createPair({
          paymentA: { token: token1, nonce: 0, amount: amount1 },
          paymentB: { token: token2, nonce: 0, amount: amount2 },
          pairsCreated: ++pairsCreated,
        });
      }

      // Approve and stake with the given path
      const payment = { token: wrappedNativeToken, amount: parseEther("0.0001"), nonce: 0 };

      const nativeToTokenAPath = pathToNative.slice().reverse();
      await governance.connect(user).stake(
        payment,
        1080, // Epochs locked
        [nativeToTokenAPath, [...nativeToTokenAPath, tokenB], pathToNative], // Paths for A, B, and to native
        0, // amountOutMinA
        0, // amountOutMinB
        { value: payment.amount },
      );

      // Fetch and assert native liquidity value
      const { attributes: gTokenAttributes } = await gToken.getBalanceAt(user, 1);
      expect(gTokenAttributes.lpDetails.liqValue).to.be.gt(0); // Liquidity value should be greater than zero
      expect(gTokenAttributes.epochsLocked).to.equal(1080); // Correct epochs locked
    });
  });

  describe("claimRewards", function () {
    it("Should allow a user to claim rewards if available", async function () {
      const {
        users: [user],
        governance,
        gainzToken,
        gToken,
        createPair,
      } = await loadFixture(routerFixture);
      const stakeAmount = parseEther("0.05");
      const epochsLocked = 1080;
      const nonce = 1; // assume staking gives us nonce 1
      const rewardAmount = parseEther("0.02");

      // Setup: Mint and approve tokenB for staking
      const [{ token: tokenA }, { token: tokenB }] = await createPair();
      const tokenBcontract = await ethers.getContractAt("TestERC20", tokenB as Addressable);
      await tokenBcontract.mintApprove(user, governance, stakeAmount);

      // Stake to initiate rewards
      await governance
        .connect(user)
        .stake({ token: tokenB, nonce: 0, amount: stakeAmount }, epochsLocked, [[tokenB], [tokenB, tokenA], []], 0, 0);

      // Add rewards to the reserve
      await gainzToken.mint(governance, rewardAmount);
      await governance.updateRewardReserve();

      // Act: Claim rewards
      const userBalanceBefore = await gainzToken.balanceOf(user);
      await governance.connect(user).claimRewards(nonce);
      const userBalanceAfter = await gainzToken.balanceOf(user);

      // Assert: Rewards transferred
      expect(userBalanceAfter - userBalanceBefore).to.equal(rewardAmount - 1n); // Minusing 1 due to precision issues
      expect((await gToken.getBalanceAt(user, nonce + 1)).attributes.rewardPerShare).to.eq(
        await governance.rewardPerShare(),
      );
    });

    // it("Should revert if there are no rewards to claim", async function () {
    //   const [user] = users;
    //   const stakeAmount = parseEther("0.05");
    //   const epochsLocked = 1080;
    //   const nonce = 1;

    //   // Setup: Mint and approve tokenB for staking
    //   const [{ token: tokenA }, { token: tokenB }] = await createPair();
    //   const tokenBcontract = await ethers.getContractAt("TestERC20", tokenB as Addressable);
    //   await tokenBcontract.mintApprove(user, governance, stakeAmount);

    //   // Stake to initiate position
    //   await governance
    //     .connect(user)
    //     .stake(
    //       { token: tokenB, nonce: 0, amount: stakeAmount },
    //       epochsLocked,
    //       [[tokenB], [tokenB, tokenA], []],
    //       0,
    //       0
    //     );

    //   // Act and Assert: Attempt to claim without rewards should revert
    //   await expect(governance.connect(user).claimRewards(nonce)).to.be.revertedWith(
    //     "Governance: No rewards to claim"
    //   );
    // });

    // it("Should decrease the rewards reserve after claiming", async function () {
    //   const [user] = users;
    //   const stakeAmount = parseEther("0.05");
    //   const epochsLocked = 1080;
    //   const nonce = 1;
    //   const rewardAmount = parseEther("0.02");

    //   // Setup: Mint and approve tokenB for staking
    //   const [{ token: tokenA }, { token: tokenB }] = await createPair();
    //   const tokenBcontract = await ethers.getContractAt("TestERC20", tokenB as Addressable);
    //   await tokenBcontract.mintApprove(user, governance, stakeAmount);

    //   // Stake to initiate rewards
    //   await governance
    //     .connect(user)
    //     .stake(
    //       { token: tokenB, nonce: 0, amount: stakeAmount },
    //       epochsLocked,
    //       [[tokenB], [tokenB, tokenA], []],
    //       0,
    //       0
    //     );

    //   // Add rewards to the reserve
    //   await gainzToken.mint(governance.address, rewardAmount);
    //   await governance.updateRewardReserve(rewardAmount);

    //   // Capture the initial rewards reserve
    //   const reserveBefore = await governance.rewardsReserve();

    //   // Act: Claim rewards
    //   await governance.connect(user).claimRewards(nonce);

    //   // Assert: Rewards reserve is reduced correctly
    //   const reserveAfter = await governance.rewardsReserve();
    //   expect(reserveBefore.sub(reserveAfter)).to.equal(rewardAmount);
    // });

    // it("Should update the user's reward attributes after claiming", async function () {
    //   const [user] = users;
    //   const stakeAmount = parseEther("0.05");
    //   const epochsLocked = 1080;
    //   const nonce = 1;
    //   const rewardAmount = parseEther("0.02");

    //   // Setup: Mint and approve tokenB for staking
    //   const [{ token: tokenA }, { token: tokenB }] = await createPair();
    //   const tokenBcontract = await ethers.getContractAt("TestERC20", tokenB as Addressable);
    //   await tokenBcontract.mintApprove(user, governance, stakeAmount);

    //   // Stake to initiate rewards
    //   await governance
    //     .connect(user)
    //     .stake(
    //       { token: tokenB, nonce: 0, amount: stakeAmount },
    //       epochsLocked,
    //       [[tokenB], [tokenB, tokenA], []],
    //       0,
    //       0
    //     );

    //   // Add rewards to the reserve
    //   await gainzToken.mint(governance.address, rewardAmount);
    //   await governance.updateRewardReserve(rewardAmount);

    //   // Act: Claim rewards
    //   await governance.connect(user).claimRewards(nonce);

    //   // Assert: Check user's updated attributes
    //   const { attributes } = await gToken.getBalanceAt(user, nonce);
    //   expect(attributes.rewardPerShare).to.equal(await governance.rewardPerShare());
    //   expect(attributes.lastClaimEpoch).to.equal(await governance.currentEpoch());
    // });

    // it("Should return the correct nonce after claiming rewards", async function () {
    //   const [user] = users;
    //   const stakeAmount = parseEther("0.05");
    //   const epochsLocked = 1080;
    //   const nonce = 1;
    //   const rewardAmount = parseEther("0.02");

    //   // Setup: Mint and approve tokenB for staking
    //   const [{ token: tokenA }, { token: tokenB }] = await createPair();
    //   const tokenBcontract = await ethers.getContractAt("TestERC20", tokenB as Addressable);
    //   await tokenBcontract.mintApprove(user, governance, stakeAmount);

    //   // Stake to initiate rewards
    //   await governance
    //     .connect(user)
    //     .stake(
    //       { token: tokenB, nonce: 0, amount: stakeAmount },
    //       epochsLocked,
    //       [[tokenB], [tokenB, tokenA], []],
    //       0,
    //       0
    //     );

    //   // Add rewards to the reserve
    //   await gainzToken.mint(governance.address, rewardAmount);
    //   await governance.updateRewardReserve(rewardAmount);

    //   // Act: Claim rewards
    //   const returnedNonce = await governance.connect(user).claimRewards(nonce);

    //   // Assert: Returned nonce matches
    //   expect(returnedNonce).to.equal(nonce);
    // });
  });

  describe("unStake", function () {
    async function unStakeFixture() {
      const amountToStake = parseEther("100");
      // Deploy the Governance contract and required tokens
      const {
        governance,
        owner,
        gToken,
        users: [user],
        ...fixture
      } = await routerFixture();

      const [{ token: tokenA }, paymentB] = await fixture.createPair();

      const stakeToken = await ethers.getContractAt("TestERC20", paymentB.token as Addressable);

      // Mint and stake tokens for user
      await stakeToken.mintApprove(user, governance, amountToStake);
      await governance
        .connect(user)
        .stake(
          { ...paymentB, amount: amountToStake },
          1080,
          [[paymentB.token], [paymentB.token, tokenA], [paymentB.token, tokenA]],
          0,
          0,
        );

      // Get the initial nonce used for staking
      const userNonces = await gToken.getNonces(user);
      const nonExistentNonce = userNonces.at(-1)! + 1n; // For testing invalid nonce

      return {
        token: await ethers.getContractAt("TestERC20", paymentB.token as Addressable),
        userNonces,
        nonExistentNonce,
        governance,
        gToken,
        user,
        amountToStake,
        owner,
        ...fixture,
      };
    }

    it("should successfully unstake and transfer rewards when available", async function () {
      const { gainzToken, governance, amountToStake, user, gToken, token } = await loadFixture(unStakeFixture);
      // Simulate reward accumulation
      await gainzToken.mint(governance, amountToStake);
      await governance.updateRewardReserve();

      const userInitialBalance = await gainzToken.balanceOf(user.address);
      const governanceInitialReserve = await governance.rewardsReserve();
      const userInitialTokenBalance = await token.balanceOf(user);

      // Unstake with minimum amounts set to 0
      await governance.connect(user).unStake((await gToken.getNonces(user))[0], 1, 1);
      const userFinalBalance = await gainzToken.balanceOf(user.address);
      const governanceFinalReserve = await governance.rewardsReserve();
      const userFinalTokenBalance = await token.balanceOf(user);

      // Check that rewards were transferred to the user
      expect(userFinalTokenBalance).to.be.gt(userInitialTokenBalance);
      expect(userFinalBalance).to.be.gt(userInitialBalance);
      expect(governanceFinalReserve).to.be.lt(governanceInitialReserve);
    });

    it("should revert if trying to unstake with a non-existent nonce", async function () {
      const { nonExistentNonce, governance, user } = await loadFixture(unStakeFixture);
      await expect(governance.connect(user).unStake(nonExistentNonce, 0, 0)).to.be.revertedWith(
        "No GToken balance found at nonce for user",
      );
    });

    // it("should correctly adjust user attributes after unstaking", async function () {
    //   const initialAttributes = await governance.getUserAttributes(user.address, 0);

    //   // Unstake without minimum amounts
    //   await governance.connect(user).unStake(0, 0, 0);

    //   const finalAttributes = await governance.getUserAttributes(user.address, 0);

    //   // Check that the liquidity in user attributes is now zero
    //   expect(finalAttributes.lpDetails.liquidity).to.equal(0);
    // });

    // it("should burn the GToken upon unstaking", async function () {
    //   // Unstake to trigger GToken burn
    //   await governance.connect(user).unStake(0, 0, 0);

    //   // Check that GToken balance for the user is zero
    //   const gTokenBalance = await governance.getGTokenBalance(user.address, 0);
    //   expect(gTokenBalance).to.equal(0);
    // });

    // it("should correctly handle cases where claimable reward is zero", async function () {
    //   // Attempt to unstake when there are no rewards to claim
    //   const userInitialBalance = await gainzToken.balanceOf(user.address);

    //   await governance.connect(user).unStake(0, 0, 0);

    //   const userFinalBalance = await gainzToken.balanceOf(user.address);
    //   expect(userFinalBalance).to.equal(userInitialBalance);
    // });

    // it("should revert if minimum amount conditions are not met", async function () {
    //   // Set high minimum amounts that should not be met
    //   const amount0Min = ethers.utils.parseEther("200");
    //   const amount1Min = ethers.utils.parseEther("200");

    //   await expect(governance.connect(user).unStake(0, amount0Min, amount1Min)).to.be.revertedWith("SlippageExceeded");
    // });
  });
});
