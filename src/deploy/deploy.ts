import {
  AbacusCore,
  AbacusRouterDeployer,
  ChainMap,
  ChainName,
  MultiProvider,
} from '@abacus-network/sdk';

import {
  HyperswapContracts,
  HyperswapFactories,
  helloWorldFactories,
} from '../app/contracts';

import { HyperswapConfig } from './config';

export class HyperswapDeployer<
  Chain extends ChainName,
> extends AbacusRouterDeployer<
  Chain,
  HyperswapConfig,
  HyperswapContracts,
  HyperswapFactories
> {
  constructor(
    multiProvider: MultiProvider<Chain>,
    configMap: ChainMap<Chain, HyperswapConfig>,
    protected core: AbacusCore<Chain>,
  ) {
    super(multiProvider, configMap, helloWorldFactories, {});
  }

  // Custom contract deployment logic can go here
  // If no custom logic is needed, call deployContract for the router
  async deployContracts(chain: Chain, config: HyperswapConfig) {
    const router = await this.deployContract(chain, 'router', [
      config.abacusConnectionManager,
    ]);
    return {
      router,
    };
  }
}
