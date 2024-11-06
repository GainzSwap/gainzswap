// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Epochs } from "./Epochs.sol";
import { GovernanceV2 } from "../GovernanceV2.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

library DeployGovernanceV2 {
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

		// Deploy the TransparentUpgradeableProxy and initialize the GovernanceV2 contract
		return
			address(
				new TransparentUpgradeableProxy(
					address(new GovernanceV2()),
					proxyAdmin,
					abi.encodeWithSelector(
						GovernanceV2.initialize.selector,
						epochs,
						feeCollector,
						proxyAdmin
					)
				)
			);
	}
}
