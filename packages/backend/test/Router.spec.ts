import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { routerFixture, TEST_ADDRESSES } from "./shared/fixtures";
import { expect } from "chai";

describe("Router", function () {
  it("allPairsLength", async () => {
    const { router } = await loadFixture(routerFixture);

    expect(await router.allPairsLength()).to.eq(0);
  });

  describe("createPair", function () {
    it("works", async () => {
      const { createPair } = await loadFixture(routerFixture);

      await createPair(TEST_ADDRESSES);
    });

    it("works in reverse", async () => {
      const { createPair } = await loadFixture(routerFixture);

      await createPair(TEST_ADDRESSES.slice().reverse() as [string, string]);
    });

    it("check gas", async () => {
      const { router } = await loadFixture(routerFixture);

      const tx = await router.createPair(...TEST_ADDRESSES);
      const receipt = await tx.wait();
      expect(receipt!.gasUsed).to.eq(1045108); // Compared to the original version, this is cheaper
    });
  });
});
