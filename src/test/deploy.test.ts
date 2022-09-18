import { HyperswapApp } from "../app/app";
import { HyperswapContracts } from "../app/contracts";
import { HyperswapChecker } from "../deploy/check";
import { HyperswapConfig } from "../deploy/config";
import { HyperswapDeployer } from "../deploy/deploy";
import {
  ChainMap,
  MultiProvider,
  TestChainNames,
  TestCoreApp,
  TestCoreDeployer,
  getChainToOwnerMap,
  getTestMultiProvider,
  testChainConnectionConfigs,
} from "@abacus-network/sdk";
import "@nomiclabs/hardhat-waffle";
import { ethers } from "hardhat";

describe("deploy", async () => {
  let multiProvider: MultiProvider<TestChainNames>;
  let core: TestCoreApp;
  let config: ChainMap<TestChainNames, HyperswapConfig>;
  let deployer: HyperswapDeployer<TestChainNames>;
  let contracts: Record<TestChainNames, HyperswapContracts>;
  let app: HyperswapApp<TestChainNames>;

  before(async () => {
    const [signer] = await ethers.getSigners();
    multiProvider = getTestMultiProvider(signer);

    const coreDeployer = new TestCoreDeployer(multiProvider);
    const coreContractsMaps = await coreDeployer.deploy();
    core = new TestCoreApp(coreContractsMaps, multiProvider);
    config = core.extendWithConnectionClientConfig(
      getChainToOwnerMap(testChainConnectionConfigs, signer.address)
    );
    deployer = new HyperswapDeployer(multiProvider, config, core);
  });

  it("deploys", async () => {
    contracts = await deployer.deploy();
  });

  it("builds app", async () => {
    contracts = await deployer.deploy();
    app = new HyperswapApp(core, contracts, multiProvider);
  });

  it("checks", async () => {
    const checker = new HyperswapChecker(multiProvider, app, config);
    await checker.check();
    checker.expectEmpty();
  });
});
