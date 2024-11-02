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
import { Epochs } from "./libraries/Epochs.sol";

import { WNTV } from "./tokens/WNTV.sol";

import { Governance } from "./Governance.sol";
import { Pair } from "./Pair.sol";

import "./types.sol";

contract Router is IRouter, SwapFactory, OldRouter {
	using TokenPayments for TokenPayment;

	error Expired();

	/// @custom:storage-location erc7201:gainz.Router.storage
	struct RouterStorage {
		address wNativeToken;
		address proxyAdmin;
		address pairsBeacon;
		address governance;
		Epochs.Storage epochs;
	}

	// keccak256(abi.encode(uint256(keccak256("gainz.Router.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant ROUTER_STORAGE_LOCATION =
		0xc2c5d756614fe8e1f9e71cd191e82f360807e79b0a9d11a8c961359a3f9d1d00;

	function _getRouterStorage()
		private
		pure
		returns (RouterStorage storage $)
	{
		assembly {
			$.slot := ROUTER_STORAGE_LOCATION
		}
	}

	modifier ensure(uint deadline) {
		if (deadline < block.timestamp) revert Expired();
		_;
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
			new UpgradeableBeacon(address(new Pair()), $.proxyAdmin)
		);

		// set Wrapped Native Token;
		$.wNativeToken = DeployWNTV.create($.proxyAdmin);

		// Copy epochs from old storage
		$.epochs = _getOldEpochsStorage();

		_setGovernance();
	}

	// **** END INITIALIZATION ****

	function createPair(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB,
		address originalCaller
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

		(, , liquidity) = addLiquidity(
			paymentA,
			paymentB,
			0,
			0,
			originalCaller,
			block.timestamp + 1
		);
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

		(uint reserveA, uint reserveB) = AMMLibrary.getReserves(
			pair,
			tokenA,
			tokenB
		);
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
		TokenPayment memory paymentB,
		address nativeTokenAddr,
		address originalCaller
	) internal returns (uint liquidity) {
		address pair = getPair(paymentA.token, paymentB.token);

		paymentA.receiveTokenFor(originalCaller, pair, nativeTokenAddr);
		paymentB.receiveTokenFor(originalCaller, pair, nativeTokenAddr);

		// Governance holds all liquidity and mints GTokens for `originalCaller`
		liquidity = IPair(pair).mint(_getRouterStorage().governance);
	}

	function addLiquidity(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB,
		uint amountAMin,
		uint amountBMin,
		address originalCaller,
		uint deadline
	)
		public
		payable
		virtual
		ensure(deadline)
		canCreatePair
		returns (uint amountA, uint amountB, uint liquidity)
	{
		(amountA, amountB) = _addLiquidity(
			paymentA.token,
			paymentB.token,
			paymentA.amount,
			paymentB.amount,
			amountAMin,
			amountBMin
		);
		address nativeTokenAddr = getWrappedNativeToken();

		liquidity = _mintLiquidity(
			paymentA,
			paymentB,
			nativeTokenAddr,
			originalCaller
		);
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
