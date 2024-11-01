// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { SwapFactory } from "./abstracts/SwapFactory.sol";
import { OldRouter } from "./abstracts/OldRouter.sol";

import { IRouter } from "./interfaces/IRouter.sol";

import { TokenPayment } from "./libraries/TokenPayments.sol";

import { WEDU } from "./tokens/WEDU.sol";

contract Router is IRouter, SwapFactory, OldRouter {
	error InvalidPaymentsWithNativeCoin();

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

	function _receiveAndWrapNativeCoin()
		private
		returns (TokenPayment memory payment)
	{
		payment.token = getWrappedNativeToken();
		payment.amount = msg.value;

		WEDU(payable(payment.token)).receiveForSpender{ value: msg.value }(
			msg.sender,
			address(this)
		);
	}

	function initialize(address initialOwner) public initializer {
		__Ownable_init(initialOwner);

		RouterStorage storage $ = _getRouterStorage();

		setProxyAdmin(msg.sender);

		setWrappedNativeToken(
			address(
				new TransparentUpgradeableProxy(
					address(new WEDU()),
					$.proxyAdmin,
					abi.encodeWithSignature("initialize()")
				)
			)
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
		if (msg.value > 0) {
			if (paymentA.token == address(0)) {
				paymentA = _receiveAndWrapNativeCoin();
			} else if (paymentB.token == address(0)) {
				paymentB = _receiveAndWrapNativeCoin();
			} else {
				revert InvalidPaymentsWithNativeCoin();
			}
		}

		pairAddress = _createPair(paymentA.token, paymentB.token);

		// TODO mint gToken
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

	function getWrappedNativeToken() public view returns (address) {
		return _getRouterStorage().wNativeToken;
	}
}
