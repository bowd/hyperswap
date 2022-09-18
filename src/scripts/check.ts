import { HyperswapApp } from "../app/app";
import { HyperswapContracts, hyperswapFactories } from "../app/contracts";
import { HyperswapChecker } from "../deploy/check";
import { prodConfigs } from "../deploy/config";
import {
  AbacusCore,
  ChainMap,
  ChainName,
  MultiProvider,
  buildContracts,
  getChainToOwnerMap,
  objMap,
} from "@abacus-network/sdk";

// COPY FROM OUTPUT OF DEPLOYMENT SCRIPT OR IMPORT FROM ELSEWHERE
const deploymentAddresses = {};

// SET CONTRACT OWNER ADDRESS HERE
const ownerAddress = "0x123...";

async function check() {
  console.info("Preparing utilities");
  const chainProviders = objMap(prodConfigs, (_, config) => ({
    provider: config.provider,
    confirmations: config.confirmations,
    overrides: config.overrides,
  }));
  const multiProvider = new MultiProvider(chainProviders);

  const contractsMap = buildContracts(
    deploymentAddresses,
    hyperswapFactories
  ) as ChainMap<ChainName, HyperswapContracts>;

  const core = AbacusCore.fromEnvironment("testnet2", multiProvider);
  const app = new HyperswapApp(core, contractsMap, multiProvider);
  const config = core.extendWithConnectionClientConfig(
    getChainToOwnerMap(prodConfigs, ownerAddress)
  );

  console.info("Starting check");
  const hyperswapChecker = new HyperswapChecker(multiProvider, app, config);
  await hyperswapChecker.check();
  hyperswapChecker.expectEmpty();
}

check()
  .then(() => console.info("Check complete"))
  .catch(console.error);
