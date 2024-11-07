// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import { SFT } from "../abstracts/SFT.sol";
import { WNTV } from "../tokens/WNTV.sol";

import "hardhat/console.sol";

struct TokenPayment {
	address token;
	uint256 amount;
	uint256 nonce;
}

library TokenPayments {
	using Address for address;

	function receiveTokenFor(
		TokenPayment memory payment,
		address from,
		address to,
		address wNTV
	) internal {
		if (payment.token == address(0)) {
			// Wrap native tokens for `to`
			WNTV(payable(wNTV)).receiveFor{ value: payment.amount }(to);
		} else if (payment.nonce == 0) {
			// ERC20 payment
			IERC20(payment.token).transferFrom(from, to, payment.amount);
		} else {
			// SFT payment
			SFT(payment.token).safeTransferFrom(
				from,
				to,
				payment.nonce,
				payment.amount,
				""
			);
		}
	}

	function sendFungibleToken(
		address token,
		uint256 amount,
		address to
	) internal {
		sendToken(TokenPayment({ token: token, amount: amount, nonce: 0 }), to);
	}

	function sendToken(TokenPayment memory payment, address to) internal {
		if (payment.nonce == 0) {
			uint256 beforeNativeBal = address(this).balance;

			// Try to withdraw ETH assuming payment.token is WNTV
			(bool shouldMoveEthBalance, ) = payment.token.call(
				abi.encodeWithSignature("withdraw(uint256)", payment.amount)
			);

			// Checks to ensure balance movements
			if (shouldMoveEthBalance) {
				require(
					(beforeNativeBal + payment.amount) == address(this).balance,
					"Failed to withdraw WNTV"
				);

				payable(to).transfer(payment.amount);
			} else {
				IERC20(payment.token).transfer(to, payment.amount);
			}
		} else {
			// SFT payment
			SFT(payment.token).safeTransferFrom(
				address(this),
				to,
				payment.nonce,
				payment.amount,
				""
			);
		}
	}

	function approve(TokenPayment memory payment, address to) internal {
		if (payment.nonce == 0) {
			// ERC20 approval
			IERC20(payment.token).approve(to, payment.amount);
		} else {
			// SFT approval
			SFT(payment.token).setApprovalForAll(to, true);
		}
	}
}
