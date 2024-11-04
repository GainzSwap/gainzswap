// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC1155HolderUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { Epochs } from "./libraries/Epochs.sol";
import { GToken, GTokenLib } from "./tokens/GToken/GToken.sol";
import { TokenPayment, TokenPayments } from "./libraries/TokenPayments.sol";

import { Router } from "./Router.sol";

import "./types.sol";

library DeployGToken {
	function create(
		Epochs.Storage memory epochs,
		address initialOwner,
		address proxyAdmin
	) external returns (address) {
		return
			address(
				new TransparentUpgradeableProxy(
					address(new GToken()),
					proxyAdmin,
					abi.encodeWithSelector(
						GToken.initialize.selector,
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
contract Governance is ERC1155HolderUpgradeable, OwnableUpgradeable {
	using Epochs for Epochs.Storage;
	using TokenPayments for TokenPayment;

	/// @custom:storage-location erc7201:gainz.Governance.storage
	struct GovernanceStorage {
		uint256 rewardPerShare;
		uint256 rewardsReserve;
		address gtoken;
		address router;
		Epochs.Storage epochs;
		address protocolFeesCollector;
	}

	// keccak256(abi.encode(uint256(keccak256("gainz.Governance.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant GOVERNANCE_STORAGE_LOCATION =
		0xc28810daea0501c36ac69c5a41a8621a140281f0a38cc30865bbaf3d9b1add00;

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
		address proxyAdmin
	) public initializer {
		address router = msg.sender;
		__Ownable_init(router);

		GovernanceStorage storage $ = _getGovernanceStorage();

		$.epochs = epochs;
		$.gtoken = DeployGToken.create($.epochs, address(this), proxyAdmin);

		$.router = router;

		require(
			protocolFeesCollector != address(0),
			"Invalid Protocol Fees collector"
		);
		$.protocolFeesCollector = protocolFeesCollector;
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
			: Router(_getGovernanceStorage().router).swapExactTokensForTokens(
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
	) internal {
		address wNativeToken = Router(router).getWrappedNativeToken();
		bool paymentIsNative = payment.token == wNativeToken;

		if (paymentIsNative) payment.token = address(0);
		payment.receiveTokenFor(msg.sender, address(this), wNativeToken);
		if (paymentIsNative) payment.token = wNativeToken;

		// Optimistically approve `router` to spend payment in `_getDesiredToken` call
		payment.approve(router);
	}

	function stake(
		TokenPayment calldata payment,
		uint256 epochsLocked,
		address[] calldata pathA,
		address[] calldata pathB,
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
				epochsLocked == GTokenLib.MAX_EPOCHS_LOCK,
				"Governance: First stakers must lock for max epoch"
			);
		}

		_receiveAndApprovePayment(payment, $.router);

		LiquidityInfo memory liqInfo;
		{
			TokenPayment memory paymentA = _getDesiredToken(
				pathA,
				payment,
				amountOutMinA
			);
			TokenPayment memory paymentB = _getDesiredToken(
				pathB,
				payment,
				amountOutMinB
			);
			require(
				paymentA.token != paymentB.token,
				"Governance: INVALID_PATH_VALUES"
			);

			if (paymentA.token != payment.token) paymentA.approve($.router);
			if (paymentB.token != payment.token) paymentB.approve($.router);

			(, , liqInfo.liquidity, liqInfo.pair) = Router($.router)
				.addLiquidity(paymentA, paymentB, 0, 0, block.timestamp + 1);
		}
		// TODO compute gTokenSupply

		return
			GToken($.gtoken).mintGToken(
				msg.sender,
				$.rewardPerShare,
				epochsLocked,
				$.epochs.currentEpoch(),
				createLiquidityInfoArray(liqInfo)
			);
	}

	// ******* VIEWS *******

	function getGToken() external view returns (address) {
		return _getGovernanceStorage().gtoken;
	}
}
