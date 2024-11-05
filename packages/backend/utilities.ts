import { ethers as e } from "hardhat";

export async function getRouterLibraries(ethers: typeof e) {
  return {
    DeployWNTV: await (await ethers.deployContract("DeployWNTV")).getAddress(),
    DeployGovernance: await (
      await (
        await ethers.getContractFactory("DeployGovernance", {
          libraries: {
            DeployGToken: await (await ethers.deployContract("DeployGToken")).getAddress(),
          },
        })
      ).deploy()
    ).getAddress(),
  };
}

import * as fs from "fs";
import * as path from "path";

export async function copyFilesRecursively(src: string, dest: string): Promise<void> {
  // src = path.join(__dirname, src);
  // dest = path.join(__dirname, dest);

  // Create the destination folder if it doesn't exist
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }

  // Read the contents of the source folder
  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      // Recursively copy subdirectory
      await copyFilesRecursively(srcPath, destPath);
    } else if (entry.isFile()) {
      // Copy file
      fs.copyFileSync(srcPath, destPath);
    }
  }
}
