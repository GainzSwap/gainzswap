// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { SwapFactory } from "./abstracts/SwapFactory.sol";
import { OldRouter } from "./abstracts/OldRouter.sol";

import { IRouter } from "./interfaces/IRouter.sol";
import { IPair } from "./interfaces/IPair.sol";

import { TokenPayment, TokenPayments } from "./libraries/TokenPayments.sol";
import { AMMLibrary } from "./libraries/AMMLibrary.sol";

import { WNTV } from "./tokens/WNTV.sol";

contract Router is IRouter, SwapFactory, OldRouter {
	using TokenPayments for TokenPayment;

	error InvalidPaymentsWithNativeCoin();
	error Expired();

	/// @custom:storage-location erc7201:gainz.Router.storage
	struct RouterStorage {
		address wNativeToken;
		address proxyAdmin;
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

	error AddressSetAlready();

	function setWrappedNativeToken(address wNativeToken) public onlyOwner {
		RouterStorage storage $ = _getRouterStorage();
		if ($.wNativeToken != address(0)) {
			revert AddressSetAlready();
		}

		$.wNativeToken = wNativeToken;

		if ($.wNativeToken == address(0)) {
			$.wNativeToken = _getWEDU();
		}
	}

	function setProxyAdmin(address proxyAdmin) public onlyOwner {
		RouterStorage storage $ = _getRouterStorage();
		if ($.proxyAdmin != address(0)) {
			revert AddressSetAlready();
		}
		$.proxyAdmin = proxyAdmin;

		if ($.proxyAdmin == address(0)) {
			$.proxyAdmin = _getProxyAdmin();
		}
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
		address tokenA = paymentA.token;
		address tokenB = paymentB.token;
		if (msg.value > 0) {
			if (tokenA == address(0)) {
				tokenA = getWrappedNativeToken();
			} else if (tokenB == address(0)) {
				tokenB = getWrappedNativeToken();
			} else {
				revert InvalidPaymentsWithNativeCoin();
			}
		}

		pairAddress = _createPair(tokenA, tokenB);

		(, , , gToken) = this.addLiquidity{ value: msg.value }(
			paymentA,
			paymentB,
			0,
			0,
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
		if (getPair(tokenA, tokenB) == address(0)) {
			revert PairNotListed();
		}
		(uint reserveA, uint reserveB) = AMMLibrary.getReserves(
			address(this),
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
		int8 nativeFlag
	) internal returns (uint liquidity) {
		address pair = AMMLibrary.pairFor(
			address(this),
			paymentA.token,
			paymentB.token
		);
		paymentA.receiveTokenFor(msg.sender, pair, nativeFlag > 0);
		paymentB.receiveTokenFor(msg.sender, pair, nativeFlag < 0);

		// Router holds all liquidity and mints GTokens for to address
		liquidity = IPair(pair).mint(address(this));
	}

	function addLiquidity(
		TokenPayment memory paymentA,
		TokenPayment memory paymentB,
		uint amountADesired,
		uint amountBDesired,
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
		int8 nativeFlag = 0;

		if (msg.value > 0) {
			if (paymentA.token == address(0)) {
				paymentA.token = getWrappedNativeToken();
				nativeFlag = 1;
			} else if (paymentB.token == address(0)) {
				paymentB.token = getWrappedNativeToken();
				nativeFlag = -1;
			} else {
				revert InvalidPaymentsWithNativeCoin();
			}
		}

		(amountA, amountB) = _addLiquidity(
			paymentA.token,
			paymentB.token,
			amountADesired,
			amountBDesired,
			amountAMin,
			amountBMin
		);
		paymentA.amount = amountA;
		paymentB.amount = amountB;

		liquidity = _mintLiquidity(paymentA, paymentB, nativeFlag);

		// refund dust native coin, if any
		if (nativeFlag != 0) {
			uint256 amountNTV = nativeFlag > 0
				? paymentA.amount
				: paymentB.amount;
			if (msg.value > amountNTV) {
				address recipient = msg.sender == address(this)
					? to
					: msg.sender;
				payable(recipient).transfer(msg.value - amountNTV);
			}
		}
	}

	function getWrappedNativeToken() public view returns (address) {
		return _getRouterStorage().wNativeToken;
	}
}
