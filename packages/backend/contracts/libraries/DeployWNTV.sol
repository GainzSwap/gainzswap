// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { WNTV } from "../tokens/WNTV.sol";

library DeployWNTV {
	function create(address proxyAdmin) external returns (address) {
		return
			address(
				new TransparentUpgradeableProxy(
					address(new WNTV()),
					proxyAdmin,
					abi.encodeWithSignature("initialize()")
				)
			);
	}
}
