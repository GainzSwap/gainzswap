// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC1155HolderUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { TokenPayment, TokenPayments } from "./libraries/TokenPayments.sol";
import { OracleLibrary } from "./libraries/OracleLibrary.sol";
import { FixedPoint128 } from "./libraries/FixedPoint128.sol";
import { FullMath } from "./libraries/FullMath.sol";
import { Epochs } from "./libraries/Epochs.sol";

import { GTokenV2, GTokenV2Lib } from "./tokens/GToken/GTokenV2.sol";

import { PairV2 } from "./PairV2.sol";
import { RouterV2 } from "./RouterV2.sol";
import { PriceOracle } from "./PriceOracle.sol";

import "./types.sol";

library DeployGTokenV2 {
	function create(
		Epochs.Storage memory epochs,
		address initialOwner,
		address proxyAdmin
	) external returns (address) {
		return
			address(
				new TransparentUpgradeableProxy(
					address(new GTokenV2()),
					proxyAdmin,
					abi.encodeWithSelector(
						GTokenV2.initialize.selector,
						epochs,
						initialOwner
					)
				)
			);
	}
}

/// @title Governance Contract
/// @notice This contract handles the governance process by allowing users to lock LP tokens and mint GTokens.
/// @dev This contract interacts with the GTokens library and manages LP token payments.
contract GovernanceV2 is ERC1155HolderUpgradeable, OwnableUpgradeable {
	using Epochs for Epochs.Storage;
	using GTokenV2Lib for GTokenV2Lib.Attributes;
	using TokenPayments for TokenPayment;
	using TokenPayments for address;

	/// @custom:storage-location erc7201:gainz.GovernanceV2.storage
	struct GovernanceStorage {
		uint256 rewardPerShare;
		uint256 rewardsReserve;
		address protocolFeesCollector;
		// The following values should be immutable
		address gtoken;
		address gainzToken;
		address router;
		address wNativeToken;
		Epochs.Storage epochs;
	}

	// keccak256(abi.encode(uint256(keccak256("gainz.GovernanceV2.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant GOVERNANCE_STORAGE_LOCATION =
		0x8a4dda5430cdcd8aca8f2a075bbbae5f31557dc6b6b93555c9c43f674de00c00;

	function _getGovernanceStorage()
		private
		pure
		returns (GovernanceStorage storage $)
	{
		assembly {
			$.slot := GOVERNANCE_STORAGE_LOCATION
		}
	}

	/// @notice Function to initialize the Governance contract.
	/// @param epochs The epochs storage instance for managing epochs.
	/// @param protocolFeesCollector The address to collect protocol fees.
	function initialize(
		Epochs.Storage memory epochs,
		address protocolFeesCollector,
		address gainzToken,
		address proxyAdmin
	) public initializer {
		address router = msg.sender;
		__Ownable_init(router);

		GovernanceStorage storage $ = _getGovernanceStorage();

		$.epochs = epochs;
		$.gtoken = DeployGTokenV2.create($.epochs, address(this), proxyAdmin);

		$.router = router;
		$.wNativeToken = RouterV2(router).getWrappedNativeToken();
		require(
			$.wNativeToken != address(0),
			"Governance: INVALID_WRAPPED_NATIVE_TOKEN"
		);

		require(
			protocolFeesCollector != address(0),
			"Invalid Protocol Fees collector"
		);
		$.protocolFeesCollector = protocolFeesCollector;

		require(gainzToken != address(0), "Invalid gainzToken");
		$.gainzToken = gainzToken;
	}

	error InvalidPayment(TokenPayment payment, uint256 value);
	error InvalidStakePath(address[] path);

	function _getDesiredToken(
		address[] calldata path,
		TokenPayment calldata stakingPayment,
		uint256 amountOutMin
	) internal returns (TokenPayment memory payment) {
		if (path.length == 0) revert InvalidStakePath(path);

		uint256 amountIn = stakingPayment.amount / 2;

		payment.token = path[path.length - 1];
		payment.amount = payment.token == stakingPayment.token
			? amountIn
			: RouterV2(_getGovernanceStorage().router).swapExactTokensForTokens(
				amountIn,
				amountOutMin,
				path,
				address(this),
				block.timestamp + 1
			)[path.length - 1];
	}

	function _receiveAndApprovePayment(
		TokenPayment memory payment,
		address router
	) internal returns (address wNativeToken) {
		wNativeToken = RouterV2(router).getWrappedNativeToken();
		bool paymentIsNative = payment.token == wNativeToken;

		if (paymentIsNative) payment.token = address(0);
		payment.receiveTokenFor(msg.sender, address(this), wNativeToken);
		if (paymentIsNative) payment.token = wNativeToken;

		// Optimistically approve `router` to spend payment in `_getDesiredToken` call
		payment.approve(router);
	}

	function _computeLiqValue(
		GovernanceStorage storage $,
		TokenPayment memory paymentA,
		TokenPayment memory paymentB,
		address[] calldata pathToNative
	) internal view returns (uint256 value) {
		// Early return if either payment{A,B} is native
		if (paymentA.token == $.wNativeToken) return paymentA.amount;
		if (paymentB.token == $.wNativeToken) return paymentB.amount;

		require( // `pathToNative` has valid length
			pathToNative.length > 1 && // The last token must be native token (i.e the reference token)
				pathToNative[pathToNative.length - 1] == $.wNativeToken && //  The first token must be one of the payments' token
				(pathToNative[0] == paymentA.token ||
					pathToNative[0] == paymentB.token),
			"Governance: INVALID_PATH"
		);

		TokenPayment memory payment = pathToNative[0] == paymentA.token
			? paymentA
			: paymentB;
		PriceOracle priceOracle = PriceOracle(
			OracleLibrary.oracleAddress($.router)
		);

		// Start with payment amount
		value = payment.amount;
		for (uint256 i; i < pathToNative.length - 1; i++) {
			value = priceOracle.consult(
				pathToNative[i],
				pathToNative[i + 1],
				value
			);
		}

		require(value > 0, "Governance: INVALID_COMPUTED_LIQ_VALUE");
	}

	function stake(
		TokenPayment calldata payment,
		uint256 epochsLocked,
		address[][3] calldata paths, // 0 -> pathA, 1 -> pathB, 2 -> pathToNative
		uint256 amountOutMinA,
		uint256 amountOutMinB
	) external payable returns (uint256) {
		if (
			payment.amount == 0 ||
			(msg.value > 0 && payment.amount != msg.value)
		) revert InvalidPayment(payment, msg.value);

		GovernanceStorage storage $ = _getGovernanceStorage();

		if (
			($.rewardPerShare == 0 && $.rewardsReserve > 0) ||
			$.epochs.currentEpoch() <= 30
		) {
			require(
				epochsLocked == GTokenV2Lib.MAX_EPOCHS_LOCK,
				"Governance: First stakers must lock for max epoch"
			);
		}

		LiquidityInfo memory liqInfo;
		{
			_receiveAndApprovePayment(payment, $.router);

			TokenPayment memory paymentA = _getDesiredToken(
				paths[0],
				payment,
				amountOutMinA
			);
			TokenPayment memory paymentB = _getDesiredToken(
				paths[1],
				payment,
				amountOutMinB
			);
			require(
				paymentA.token != paymentB.token,
				"Governance: INVALID_PATH_VALUES"
			);

			if (paymentA.token != payment.token) paymentA.approve($.router);
			if (paymentB.token != payment.token) paymentB.approve($.router);

			// Set liquidity info
			(liqInfo.token0, liqInfo.token1) = paymentA.token < paymentB.token
				? (paymentA.token, paymentB.token)
				: (paymentB.token, paymentA.token);

			(, , liqInfo.liquidity, ) = RouterV2($.router).addLiquidity(
				paymentA,
				paymentB,
				0,
				0,
				block.timestamp + 1
			);

			liqInfo.liqValue = _computeLiqValue(
				$,
				paymentA,
				paymentB,
				paths[2]
			);
		}

		return
			GTokenV2($.gtoken).mintGToken(
				msg.sender,
				$.rewardPerShare,
				epochsLocked,
				$.epochs.currentEpoch(),
				liqInfo
			);
	}

	/// @notice Updates the rewards reserve by adding the specified amount.
	/// @dev Only callable by the contract owner or authorized party.
	/// @param amount The amount to add to the rewards reserve.
	function updateRewardReserve(uint256 amount) external {
		GovernanceStorage storage $ = _getGovernanceStorage();

		require(amount > 0, "Amount must be greater than zero");

		// Transfer the amount of Gainz tokens to the contract
		IERC20($.gainzToken).transferFrom(msg.sender, address(this), amount);

		// Update the rewards reserve
		$.rewardsReserve += amount;

		uint256 totalStakeWeight = GTokenV2($.gtoken).totalStakeWeight();
		if (totalStakeWeight > 0) {
			$.rewardPerShare += FullMath.mulDiv(
				amount,
				FixedPoint128.Q128,
				totalStakeWeight
			);
		}
	}

	function _calculateClaimableReward(
		address user,
		uint256 nonce
	)
		internal
		view
		returns (
			uint256 claimableReward,
			GTokenV2Lib.Attributes memory attributes
		)
	{
		GovernanceStorage storage $ = _getGovernanceStorage();
		attributes = GTokenV2($.gtoken).getBalanceAt(user, nonce).attributes;

		claimableReward = FullMath.mulDiv(
			attributes.stakeWeight,
			$.rewardPerShare - attributes.rewardPerShare,
			FixedPoint128.Q128
		);
	}

	/// @notice Allows a user to claim their accumulated rewards based on their current stake.
	/// @dev This function will transfer the calculated claimable reward to the user,
	/// 	 update the user's reward attributes, and decrease the rewards reserve.
	/// @param nonce The specific nonce representing a unique staking position of the user.
	/// @return Nonce of the updated GToken for the user after claiming the reward.
	function claimRewards(uint256 nonce) external returns (uint256) {
		GovernanceStorage storage $ = _getGovernanceStorage();

		address user = msg.sender;
		(
			uint256 claimableReward,
			GTokenV2Lib.Attributes memory attributes
		) = _calculateClaimableReward(user, nonce);

		require(claimableReward > 0, "Governance: No rewards to claim");

		$.rewardsReserve -= claimableReward;
		attributes.rewardPerShare = $.rewardPerShare;
		attributes.lastClaimEpoch = $.epochs.currentEpoch();

		IERC20($.gainzToken).transfer(user, claimableReward);
		return GTokenV2($.gtoken).update(user, nonce, attributes);
	}

	function unStake(uint256 nonce, uint amount0Min, uint amount1Min) external {
		GovernanceStorage storage $ = _getGovernanceStorage();

		address user = msg.sender;

		// Calculate rewards to be claimed on unstaking
		(
			uint256 claimableReward,
			GTokenV2Lib.Attributes memory attributes
		) = _calculateClaimableReward(user, nonce);

		// Transfer the claimable rewards to the user, if any
		if (claimableReward > 0) {
			$.rewardsReserve -= claimableReward;
			IERC20($.gainzToken).transfer(user, claimableReward);
		}

		// Calculate the amount of LP tokens to return to the user
		uint256 liquidity = attributes.lpDetails.liquidity;
		uint256 liquidityToReturn = attributes.valueToKeep(
			liquidity,
			attributes.epochsElapsed($.epochs.currentEpoch())
		);

		if (liquidityToReturn < liquidity) {
			address[] memory addresses = new address[](2);
			uint256[] memory liquidityPortions = new uint256[](2);

			addresses[0] = user;
			addresses[1] = address(this); // Governance holds the GToken and ecosystem can utilise them later

			liquidityPortions[0] = liquidityToReturn;
			liquidityPortions[1] = liquidity - liquidityToReturn;

			// Update the nonce
			nonce = GTokenV2($.gtoken).split(
				nonce,
				addresses,
				liquidityPortions
			)[0];
			attributes = GTokenV2($.gtoken)
				.getBalanceAt(user, nonce)
				.attributes;

			// Adjust slippage accordingly
			amount0Min = (amount0Min * liquidityToReturn) / liquidity;
			amount1Min = (amount1Min * liquidityToReturn) / liquidity;
		}

		// Transfer LP tokens back to the user

		PairV2(
			PriceOracle(OracleLibrary.oracleAddress($.router)).pairFor(
				attributes.lpDetails.token0,
				attributes.lpDetails.token1
			)
		).approve($.router, attributes.lpDetails.liquidity);

		(uint256 amount0, uint256 amount1) = RouterV2($.router).removeLiquidity(
			attributes.lpDetails.token0,
			attributes.lpDetails.token1,
			attributes.lpDetails.liquidity,
			amount0Min,
			amount1Min,
			address(this),
			block.timestamp + 1
		);

		attributes.lpDetails.token0.sendFungibleToken(amount0, user);
		attributes.lpDetails.token1.sendFungibleToken(amount1, user);

		// Update the user's attributes to reflect the unstake
		// Burn the GToken, setting liquity to 0 and then updating the token burns it
		attributes.lpDetails.liquidity = 0;
		nonce = GTokenV2($.gtoken).update(user, nonce, attributes);
	}

	// ******* VIEWS *******

	function getGToken() external view returns (address) {
		return _getGovernanceStorage().gtoken;
	}

	function rewardsReserve() external view returns (uint256) {
		return _getGovernanceStorage().rewardsReserve;
	}

	function rewardPerShare() external view returns (uint256) {
		return _getGovernanceStorage().rewardPerShare;
	}
}
