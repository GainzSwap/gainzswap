// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import { SwapFactory } from "./abstracts/SwapFactory.sol";
import { OldRouter } from "./abstracts/OldRouter.sol";

import { IRouter } from "./interfaces/IRouter.sol";
import { IPair } from "./interfaces/IPair.sol";

import { TokenPayment, TokenPayments } from "./libraries/TokenPayments.sol";
import { DeployGovernance } from "./libraries/DeployGovernance.sol";
import { DeployWNTV } from "./libraries/DeployWNTV.sol";
import { AMMLibrary } from "./libraries/AMMLibrary.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { Epochs } from "./libraries/Epochs.sol";

import { WNTV } from "./tokens/WNTV.sol";

import { GovernanceV2 } from "./Governance.sol";
import { PairV2, IERC20 } from "./Pair.sol";

import "./types.sol";

contract RouterV2 is IRouter, SwapFactory, OldRouter {
	using TokenPayments for TokenPayment;
	using Epochs for Epochs.Storage;

	/// @custom:storage-location erc7201:gainz.RouterV2.storage
	struct RouterStorage {
		address wNativeToken;
		address proxyAdmin;
		address pairsBeacon;
		address governance;
		Epochs.Storage epochs;
	}

	// keccak256(abi.encode(uint256(keccak256("gainz.RouterV2.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant ROUTER_STORAGE_LOCATION =
		0xae974aecfb7025a5d7fc4d7e9ba067575060084b22f04fa48d6bbae6c0d48d00;

	function _getRouterStorage()
		private
		pure
		returns (RouterStorage storage $)
	{
		assembly {
			$.slot := ROUTER_STORAGE_LOCATION
		}
	}

	error CreatePairUnauthorized();
	modifier canCreatePair() {
		RouterStorage storage $ = _getRouterStorage();

		if (msg.sender != owner() && msg.sender != $.governance)
			revert CreatePairUnauthorized();
		_;
	}

	function _receiveAndWrapNativeCoin()
		private
		returns (TokenPayment memory payment)
	{
		payment.token = getWrappedNativeToken();
		payment.amount = msg.value;

		WNTV(payable(payment.token)).receiveForSpender{ value: msg.value }(
			msg.sender,
			address(this)
		);
	}

	// **** INITIALIZATION ****

	function initialize(address initialOwner) public initializer {
		__Ownable_init(initialOwner);

		runInit();
	}

	error AddressSetAllready();

	function _setGovernance() internal {
		RouterStorage storage $ = _getRouterStorage();

		$.governance = DeployGovernance.create($.epochs, $.proxyAdmin);
	}

	/// @dev Initialisation for testnet after migration from old code
	function runInit() public onlyOwner {
		RouterStorage storage $ = _getRouterStorage();
		if ($.proxyAdmin != address(0)) {
			revert AddressSetAllready();
		}

		$.proxyAdmin = _getProxyAdmin();

		if ($.proxyAdmin == address(0)) {
			$.proxyAdmin = msg.sender;
		}

		// Deploy the UpgradeableBeacon contract
		$.pairsBeacon = address(
			new UpgradeableBeacon(address(new PairV2()), $.proxyAdmin)
		);

		// set Wrapped Native Token;
		$.wNativeToken = DeployWNTV.create($.proxyAdmin);

		// Copy epochs from old storage
		$.epochs = _getOldEpochsStorage();
		if ($.epochs.epochLength == 0) {
			$.epochs.initialize(24 hours);
		}

		_setGovernance();
	}

	// **** END INITIALIZATION ****

	function createPair(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB
	)
		external
		payable
		override
		canCreatePair
		returns (address pairAddress, uint256 liquidity)
	{
		pairAddress = _createPair(
			paymentA.token,
			paymentB.token,
			_getRouterStorage().pairsBeacon
		);

		(, , liquidity, ) = addLiquidity(
			paymentA,
			paymentB,
			0,
			0,
			block.timestamp + 1
		);
	}

	// **** SWAP ****

	error Expired();

	modifier ensure(uint deadline) {
		if (deadline < block.timestamp) revert Expired();
		_;
	}

	// requires the initial amount to have already been sent to the first pair
	function _swap(
		uint[] memory amounts,
		address[] memory path,
		address _to
	) internal virtual {
		for (uint i; i < path.length - 1; i++) {
			(address input, address output) = (path[i], path[i + 1]);
			(address token0, ) = AMMLibrary.sortTokens(input, output);
			uint amountOut = amounts[i + 1];
			(uint amount0Out, uint amount1Out) = input == token0
				? (uint(0), amountOut)
				: (amountOut, uint(0));
			address to = i < path.length - 2
				? AMMLibrary.pairFor(
					address(this),
					getPairsBeacon(),
					output,
					path[i + 2]
				)
				: _to;
			IPair(
				AMMLibrary.pairFor(
					address(this),
					getPairsBeacon(),
					input,
					output
				)
			).swap(amount0Out, amount1Out, to);
		}
	}

	function swapExactTokensForTokens(
		uint amountIn,
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	)
		external
		payable
		virtual
		ensure(deadline)
		returns (uint[] memory amounts)
	{
		amounts = AMMLibrary.getAmountsOut(
			address(this),
			getPairsBeacon(),
			amountIn,
			path
		);
		require(
			amounts[amounts.length - 1] >= amountOutMin,
			"Router: INSUFFICIENT_OUTPUT_AMOUNT"
		);

		{
			// Send token scope
			address pair = AMMLibrary.pairFor(
				address(this),
				getPairsBeacon(),
				path[0],
				path[1]
			);
			if (msg.value > 0) {
				require(
					msg.value == amountIn,
					"Router: INVALID_AMOUNT_IN_VALUES"
				);
				require(
					path[0] == getWrappedNativeToken(),
					"Router: INVALID_PATH"
				);
				WNTV(getWrappedNativeToken()).receiveFor{ value: msg.value }(
					pair
				);
			} else {
				TransferHelper.safeTransferFrom(
					path[0],
					msg.sender,
					pair,
					amounts[0]
				);
			}
		}
		_swap(amounts, path, to);
	}

	// **** ADD LIQUIDITY ****

	error PairNotListed();
	error InSufficientAAmount();
	error InSufficientBAmount();

	function _addLiquidity(
		address tokenA,
		address tokenB,
		uint amountADesired,
		uint amountBDesired,
		uint amountAMin,
		uint amountBMin
	) internal virtual returns (uint amountA, uint amountB) {
		address pair = getPair(tokenA, tokenB);
		if (pair == address(0)) {
			revert PairNotListed();
		}

		(uint reserveA, uint reserveB, ) = IPair(pair).getReserves();
		if (reserveA == 0 && reserveB == 0) {
			(amountA, amountB) = (amountADesired, amountBDesired);
		} else {
			uint amountBOptimal = AMMLibrary.quote(
				amountADesired,
				reserveA,
				reserveB
			);
			if (amountBOptimal <= amountBDesired) {
				if (amountBOptimal < amountBMin) revert InSufficientBAmount();
				(amountA, amountB) = (amountADesired, amountBOptimal);
			} else {
				uint amountAOptimal = AMMLibrary.quote(
					amountBDesired,
					reserveB,
					reserveA
				);
				assert(amountAOptimal <= amountADesired);
				if (amountAOptimal < amountAMin) revert InSufficientAAmount();
				(amountA, amountB) = (amountAOptimal, amountBDesired);
			}
		}
	}

	function _mintLiquidity(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB
	) internal returns (uint liquidity, address pair) {
		pair = getPair(paymentA.token, paymentB.token);

		// Prepare payment{A,B} for reception
		address wNativeToken = getWrappedNativeToken();
		if (paymentA.token == wNativeToken && msg.value == paymentA.amount) {
			paymentA.token = address(0);
		} else if (
			paymentB.token == wNativeToken && msg.value == paymentB.amount
		) {
			paymentB.token = address(0);
		}

		paymentA.receiveTokenFor(msg.sender, pair, wNativeToken);
		paymentB.receiveTokenFor(msg.sender, pair, wNativeToken);

		liquidity = IPair(pair).mint(msg.sender);
	}

	function addLiquidity(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB,
		uint amountAMin,
		uint amountBMin,
		uint deadline
	)
		public
		payable
		virtual
		ensure(deadline)
		canCreatePair
		returns (uint amountA, uint amountB, uint liquidity, address pair)
	{
		(amountA, amountB) = _addLiquidity(
			paymentA.token,
			paymentB.token,
			paymentA.amount,
			paymentB.amount,
			amountAMin,
			amountBMin
		);

		(liquidity, pair) = _mintLiquidity(paymentA, paymentB);
	}

	// ******* VIEWS *******

	function getWrappedNativeToken() public view returns (address) {
		return _getRouterStorage().wNativeToken;
	}

	function getPairsBeacon() public view returns (address) {
		return _getRouterStorage().pairsBeacon;
	}

	function getGovernance() public view returns (address) {
		return _getRouterStorage().governance;
	}
}
