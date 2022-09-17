import {
  AbacusCore,
  AbacusRouterDeployer,
  ChainMap,
  ChainName,
  MultiProvider,
} from '@abacus-network/sdk';

import {
  HelloWorldContracts,
  HelloWorldFactories,
  helloWorldFactories,
} from '../app/contracts';

import { HyperswapConfig } from './config';

export class HelloWorldDeployer<
  Chain extends ChainName,
> extends AbacusRouterDeployer<
  Chain,
  HyperswapConfg,
  HelloWorldContracts,
  HelloWorldFactories
> {
  constructor(
    multiProvider: MultiProvider<Chain>,
    configMap: ChainMap<Chain, HelloWorldConfig>,
    protected core: AbacusCore<Chain>,
  ) {
    super(multiProvider, configMap, helloWorldFactories, {});
  }

  // Custom contract deployment logic can go here
  // If no custom logic is needed, call deployContract for the router
  async deployContracts(chain: Chain, config: HelloWorldConfig) {
    const router = await this.deployContract(chain, 'HyperswapRouter', [
      config.abacusConnectionManager,
      config.interchainGasPaymaster,
    ]);
    return {
      router,
    };
  }
}
