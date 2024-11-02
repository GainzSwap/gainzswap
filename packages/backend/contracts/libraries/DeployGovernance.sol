// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Epochs } from "./Epochs.sol";
import { Governance } from "../Governance.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

library DeployGovernance {
	function create(
		Epochs.Storage memory epochs,
		address proxyAdmin
	) external returns (address) {
		address caller = msg.sender;

		// Get the owner address from the caller
		(bool success, bytes memory owner) = caller.call(
			abi.encodeWithSignature("owner()")
		);

		// Determine the feeCollector, use the owner if callable, else fallback to caller
		address feeCollector = success && owner.length > 0
			? abi.decode(owner, (address))
			: caller;

		// Deploy the TransparentUpgradeableProxy and initialize the Governance contract
		return
			address(
				new TransparentUpgradeableProxy(
					address(new Governance()),
					proxyAdmin,
					abi.encodeWithSelector(
						Governance.initialize.selector,
						epochs,
						feeCollector,
						proxyAdmin
					)
				)
			);
	}
}
