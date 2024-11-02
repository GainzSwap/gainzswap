import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { routerFixture } from "./shared/fixtures";
import { ethers } from "hardhat";
import { expect } from "chai";

describe("Governance", function () {
  it("deploys governance", async () => {
    const { governance } = await loadFixture(routerFixture);

    const gTokenAddress = await governance.getGToken();
    const gToken = await ethers.getContractAt("GToken", gTokenAddress);

    expect(await gToken.name()).to.eq("GainzSwap Governance Token");
  });
});
