// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TokenPayment } from "../libraries/TokenPayments.sol";

interface IRouter {
	function createPair(
		TokenPayment calldata paymentA,
		TokenPayment calldata paymentB
	)
		external
		payable
		returns (address pairAddress, TokenPayment memory gToken);

	function getWrappedNativeToken() external view returns (address);
}
