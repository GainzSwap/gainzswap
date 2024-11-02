// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import { SwapFactory } from "./abstracts/SwapFactory.sol";
import { OldRouter } from "./abstracts/OldRouter.sol";

import { IRouter } from "./interfaces/IRouter.sol";
import { IPair } from "./interfaces/IPair.sol";

import { TokenPayment, TokenPayments } from "./libraries/TokenPayments.sol";
import { AMMLibrary } from "./libraries/AMMLibrary.sol";

import { WNTV } from "./tokens/WNTV.sol";

import { Pair } from "./Pair.sol";

import "hardhat/console.sol";

contract Router is IRouter, SwapFactory, OldRouter {
	using TokenPayments for TokenPayment;

	error Expired();

	/// @custom:storage-location erc7201:gainz.Router.storage
	struct RouterStorage {
		address wNativeToken;
		address proxyAdmin;
		address pairsBeacon;
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

		RouterStorage storage $ = _getRouterStorage();

		setProxyAdmin(msg.sender);

		setWrappedNativeToken(
			address(
				new TransparentUpgradeableProxy(
					address(new WNTV()),
					$.proxyAdmin,
					abi.encodeWithSignature("initialize()")
				)
			)
		);
	}

	error AddressSetAllready();

	function setWrappedNativeToken(address wNativeToken) public onlyOwner {
		RouterStorage storage $ = _getRouterStorage();
		if ($.wNativeToken != address(0)) {
			revert AddressSetAllready();
		}

		$.wNativeToken = wNativeToken;

		if ($.wNativeToken == address(0)) {
			$.wNativeToken = _getWEDU();
		}
	}

	function setProxyAdmin(address proxyAdmin) public onlyOwner {
		RouterStorage storage $ = _getRouterStorage();
		if ($.proxyAdmin != address(0)) {
			revert AddressSetAllready();
		}
		$.proxyAdmin = proxyAdmin;

		if ($.proxyAdmin == address(0)) {
			$.proxyAdmin = _getProxyAdmin();
		}

		// Deploy the UpgradeableBeacon contract
		$.pairsBeacon = address(
			new UpgradeableBeacon(address(new Pair()), $.proxyAdmin)
		);
	}

	function createPair(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB
	)
		external
		payable
		override
		canCreatePair
		returns (address pairAddress, TokenPayment memory gToken)
	{
		pairAddress = _createPair(
			paymentA.token,
			paymentB.token,
			_getRouterStorage().pairsBeacon
		);

		(, , , gToken) = this.addLiquidity{ value: msg.value }(
			paymentA,
			paymentB,
			0,
			0,
			msg.sender,
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
		address caller
	) internal returns (uint liquidity) {
		address pair = getPair(paymentA.token, paymentB.token);

		paymentA.receiveTokenFor(caller, pair, nativeTokenAddr);
		paymentB.receiveTokenFor(caller, pair, nativeTokenAddr);

		// Router holds all liquidity and mints GTokens for to address
		liquidity = IPair(pair).mint(address(this));
	}

	function _sendLiquidtyDust(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB,
		uint amountA,
		uint amountB,
		address nativeTokenAddr
	)
		internal
		returns (TokenPayment memory _paymentA, TokenPayment memory _paymentB)
	{
		uint256 dustA = paymentA.amount - amountA;
		uint256 dustB = paymentB.amount - amountB;
		paymentA.amount = amountA;
		paymentB.amount = amountB;
		// refund dusts, if any
		paymentA.sendDust(dustA, nativeTokenAddr);
		paymentB.sendDust(dustB, nativeTokenAddr);

		_paymentA = paymentA;
		_paymentB = paymentB;
	}

	function addLiquidity(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB,
		uint amountAMin,
		uint amountBMin,
		address to,
		uint deadline
	)
		external
		payable
		virtual
		ensure(deadline)
		returns (
			uint amountA,
			uint amountB,
			uint liquidity,
			TokenPayment memory gToken
		)
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

		(paymentA, paymentB) = _sendLiquidtyDust(
			paymentA,
			paymentB,
			amountA,
			amountB,
			nativeTokenAddr
		);

		liquidity = _mintLiquidity(
			paymentA,
			paymentB,
			nativeTokenAddr,
			msg.sender == address(this) ? to : msg.sender
		);
	}

	function getWrappedNativeToken() public view returns (address) {
		return _getRouterStorage().wNativeToken;
	}

	function getPairsBeacon() public view returns (address) {
		return _getRouterStorage().pairsBeacon;
	}
}
