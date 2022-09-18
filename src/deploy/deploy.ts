import {
  HyperswapContracts,
  HyperswapFactories,
  hyperswapFactories,
} from "../app/contracts";
import { HyperswapCustodian, HyperswapRouter } from "../types";
import { HyperswapConfig } from "./config";
import {
  AbacusCore,
  AbacusRouterDeployer,
  ChainMap,
  ChainName,
  ChainNameToDomainId,
  MultiProvider,
} from "@abacus-network/sdk";

export class HyperswapDeployer<
  Chain extends ChainName
> extends AbacusRouterDeployer<
  Chain,
  HyperswapConfig,
  HyperswapContracts,
  HyperswapFactories
> {
  constructor(
    multiProvider: MultiProvider<Chain>,
    configMap: ChainMap<Chain, HyperswapConfig>,
    protected core: AbacusCore<Chain>
  ) {
    super(multiProvider, configMap, hyperswapFactories, {});
  }

  // Custom contract deployment logic can go here
  // If no custom logic is needed, call deployContract for the router
  async deployContracts(chain: Chain, config: HyperswapConfig) {
    console.log(chain);
    console.log(config);
    const localDomain = ChainNameToDomainId[chain];
    const router = await this.deployContract(chain, "router", []);
    console.log("as1");
    console.log(router.address);
    const hyperswapRouter = (await this.deployContract(
      chain,
      "hyperswapRouter",
      [router.address, localDomain]
    )) as HyperswapRouter;
    console.log("as2");
    const hyperswapCustodian = (await this.deployContract(
      chain,
      "hyperswapCustodian",
      [router.address]
    )) as HyperswapCustodian;
    console.log("as3");
    const signer = this.multiProvider.getChainSigner(chain);

    console.log("here");
    if (chain == "alfajores" || chain == "test1") {
      await router
        .connect(signer)
        .initialize(
          config.abacusConnectionManager,
          "0x0",
          hyperswapRouter.address,
          true
        );
    } else {
      await router
        .connect(signer)
        .initialize(
          config.abacusConnectionManager,
          hyperswapCustodian.address,
          "0x0",
          false
        );
    }

    return {
      router,
      hyperswapCustodian,
      hyperswapRouter,
    };
  }
}
